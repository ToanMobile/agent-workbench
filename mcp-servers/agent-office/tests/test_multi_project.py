"""One Agent Office reads several GitHub Projects (one per repo) and writes back to the card's own Project."""
import os, sys, unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


def fake_project(number, repo, statuses=("Backlog", "Ready", "Done")):
    pid = f"PVT_{number}"
    status = {"id": f"STATUS_{number}", "name": "Status",
              "options": [{"id": f"OPT_{number}_{s}", "name": s, "color": None} for s in statuses]}
    return {
        "id": pid, "statusFieldId": status["id"], "selectFields": [status], "title": f"Board {number}",
        "url": f"https://example.test/projects/{number}", "viewName": None, "viewLayout": None, "viewFilter": None,
        "statusField": "Status",
        "columns": [{"name": s, "kind": "backlog", "ghColor": None} for s in statuses],
        "items": [{"id": f"PVTI_{number}_1", "contentId": f"I_{number}", "number": "1", "title": f"card {number}",
                   "url": None, "type": "Issue", "state": "OPEN", "isDraft": False, "repo": repo, "repoFull": f"o/{repo}",
                   "status": "Ready", "assignees": [], "labels": [], "fields": {}, "updatedAt": 1.0,
                   "lastComment": None, "pid": pid}],
        "totalCount": 1,
    }


CFG = {"owner": "o", "ownerType": "user", "project": 1, "projects": [1, 2, 3]}


class FetchProjects(unittest.TestCase):
    def test_merges_items_of_every_project(self):
        def fp(g):
            n = g["project"]
            return fake_project(n, f"repo{n}", ("Backlog", "Ready", "Done") if n != 3 else ("Backlog", "Review", "Done"))
        with mock.patch.object(server, "fetch_project", side_effect=fp):
            proj = server.fetch_projects(CFG)
        self.assertEqual(sorted(i["repo"] for i in proj["items"]), ["repo1", "repo2", "repo3"])
        self.assertEqual([c["name"] for c in proj["columns"]], ["Backlog", "Ready", "Done", "Review"])
        self.assertEqual(set(proj["parts"]), {"PVT_1", "PVT_2", "PVT_3"})

    def test_one_failing_project_keeps_the_others(self):
        def fp(g):
            if g["project"] == 2:
                raise server.GhError("boom")
            return fake_project(g["project"], f"repo{g['project']}")
        with mock.patch.object(server, "fetch_project", side_effect=fp):
            proj = server.fetch_projects(CFG)
        self.assertEqual(len(proj["items"]), 2)
        self.assertTrue(any("#2" in e for e in proj["partialErrors"]))

    def test_all_failing_raises(self):
        with mock.patch.object(server, "fetch_project", side_effect=server.GhError("boom")):
            with self.assertRaises(server.GhError):
                server.fetch_projects(CFG)

    def test_single_project_config_still_works(self):
        with mock.patch.object(server, "fetch_project", side_effect=lambda g: fake_project(g["project"], "r")):
            proj = server.fetch_projects({"owner": "o", "project": 7})
        self.assertEqual(len(proj["items"]), 1)


class Efficiency(unittest.TestCase):
    def test_projects_are_fetched_in_parallel(self):
        import time

        def slow(g):
            time.sleep(0.3)
            return fake_project(g["project"], f"repo{g['project']}")
        t = time.time()
        with mock.patch.object(server, "fetch_project", side_effect=slow):
            proj = server.fetch_projects({**CFG, "projects": [1, 2, 3, 4, 5, 6]})
        self.assertLess(time.time() - t, 0.9)  # sequential would be 1.8 s
        self.assertEqual([i["repo"] for i in proj["items"]], [f"repo{n}" for n in range(1, 7)])  # order kept

    def test_poll_interval_backs_off_when_board_is_idle_and_resets(self):
        base = 30.0
        self.assertEqual(server.poll_interval(base, 0), base)
        self.assertEqual(server.poll_interval(base, 2), base)
        self.assertEqual(server.poll_interval(base, 4), 60.0)
        self.assertEqual(server.poll_interval(base, 400), 60.0)  # capped at 2x

    def test_fingerprint_changes_only_when_a_card_changes(self):
        a = server.board_fingerprint([fake_project(1, "r")])
        self.assertEqual(a, server.board_fingerprint([fake_project(1, "r")]))
        moved = fake_project(1, "r")
        moved["items"][0]["status"] = "Done"
        self.assertNotEqual(a, server.board_fingerprint([moved]))


class WriteGoesToOwnProject(unittest.TestCase):
    def setUp(self):
        with mock.patch.object(server, "fetch_project", side_effect=lambda g: fake_project(g["project"], f"repo{g['project']}")):
            proj = server.fetch_projects(CFG)
        self.app = object.__new__(server.App)
        self.app.project, self.app.demo, self.app.cfg = proj, False, {"github": CFG}

    def test_move_card_of_project_2_uses_project_2_ids(self):
        calls = []
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: calls.append(v) or {}):
            self.app._set("PVTI_2_1", "Status", "Done")
        self.assertEqual(calls, [{"p": "PVT_2", "i": "PVTI_2_1", "f": "STATUS_2", "o": "OPT_2_Done"}])

    def test_move_to_column_missing_in_that_project_is_refused(self):
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: {}):
            with self.assertRaises(ValueError):
                self.app._set("PVTI_1_1", "Status", "Review")  # only project 3 has Review


class NewCardsAndBulkMove(unittest.TestCase):
    def setUp(self):
        with mock.patch.object(server, "fetch_project", side_effect=lambda g: fake_project(g["project"], f"repo{g['project']}")):
            proj = server.fetch_projects(CFG)
        self.app = object.__new__(server.App)
        self.app.project, self.app.demo, self.app.cfg = proj, False, {"github": CFG}
        self.app.gh_meta, self.app.lock, self.app.user_moves = {"ok": True}, __import__("threading").RLock(), {}
        self.app.refresh_evt = __import__("threading").Event()
        self.app.rebuild = lambda: None

    def test_new_draft_card_lands_in_backlog_not_no_status(self):
        calls = []

        def gql(q, v):
            calls.append(v)
            return {"addProjectV2DraftIssue": {"projectItem": {"id": "NEW"}}}
        with mock.patch.object(server, "gh_graphql", side_effect=gql):
            self.app.act("create", {"title": "t"})
        self.assertEqual(calls[-1]["o"], "OPT_1_Backlog")
        self.assertEqual(self.app.project["items"][-1]["status"], "Backlog")

    def test_move_all_moves_every_card_of_a_column_to_ready(self):
        for it in self.app.project["items"]:
            it["status"] = server.NO_STATUS
        calls = []
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: calls.append(v) or {}):
            r = self.app.act("move-all", {"from": server.NO_STATUS, "to": "Ready"})
        self.assertEqual((r["moved"], r["failedCount"]), (3, 0))
        self.assertEqual({c["o"] for c in calls}, {"OPT_1_Ready", "OPT_2_Ready", "OPT_3_Ready"})
        self.assertTrue(all(i["status"] == "Ready" for i in self.app.project["items"]))

    def test_move_all_can_be_limited_to_one_repo(self):
        for it in self.app.project["items"]:
            it["status"] = "Backlog"
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: {}):
            r = self.app.act("move-all", {"from": "Backlog", "to": "Ready", "repo": "repo2"})
        self.assertEqual(r["moved"], 1)
        self.assertEqual({i["repo"]: i["status"] for i in self.app.project["items"]},
                         {"repo1": "Backlog", "repo2": "Ready", "repo3": "Backlog"})

    def test_move_all_reports_cards_whose_project_lacks_the_column(self):
        for it in self.app.project["items"]:
            it["status"] = "Backlog"
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: {}):
            r = self.app.act("move-all", {"from": "Backlog", "to": "Review"})  # no project has Review here
        self.assertEqual((r["moved"], r["failedCount"]), (0, 3))

    def test_cards_without_status_are_set_to_backlog_once(self):
        it = self.app.project["items"][0]
        it["status"] = server.NO_STATUS
        self.app.project["columns"].append({"name": server.NO_STATUS, "kind": "backlog", "ghColor": None, "noStatus": True})
        self.app.backfilled = set()
        calls = []
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: calls.append(v) or {}):
            self.app.backfill_backlog(self.app.project)
            self.app.backfill_backlog(self.app.project)
        self.assertEqual([c["o"] for c in calls], ["OPT_1_Backlog"])
        self.assertEqual(it["status"], "Backlog")
        self.assertFalse(any(c.get("noStatus") for c in self.app.project["columns"]))

    def _no_status(self, state="OPEN"):
        it = self.app.project["items"][0]
        it["status"], it["state"] = server.NO_STATUS, state
        self.app.backfilled = set()
        return it

    def test_closed_cards_without_status_are_left_alone(self):
        it = self._no_status("CLOSED")
        calls = []
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: calls.append(v) or {}):
            self.app.backfill_backlog(self.app.project)
        self.assertEqual(calls, [])
        self.assertEqual(it["status"], server.NO_STATUS)

    def test_a_transient_github_error_is_retried_on_the_next_poll(self):
        it = self._no_status()
        with mock.patch.object(server, "gh_graphql", side_effect=server.GhError("HTTP 502")):
            self.app.backfill_backlog(self.app.project)
        with mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: {}):
            self.app.backfill_backlog(self.app.project)
        self.assertEqual(it["status"], "Backlog")

    def test_backfill_writes_at_most_a_few_cards_per_poll(self):
        for it in self.app.project["items"]:
            it["status"], it["state"] = server.NO_STATUS, "OPEN"
        self.app.backfilled = set()
        calls = []
        with mock.patch.object(server, "BACKFILL_PER_POLL", 2), \
                mock.patch.object(server, "gh_graphql", side_effect=lambda q, v: calls.append(v) or {}):
            self.app.backfill_backlog(self.app.project)
        self.assertEqual(len(calls), 2)

    def test_move_all_reports_github_errors_in_friendly_words(self):
        for it in self.app.project["items"]:
            it["status"] = "Backlog"
        with mock.patch.object(server, "gh_graphql", side_effect=server.GhError("raw gh stderr")), \
                mock.patch.object(server, "friendly", side_effect=lambda m: "FRIENDLY"):
            r = self.app.act("move-all", {"from": "Backlog", "to": "Ready"})
        self.assertEqual(r["failedCount"], 3)
        self.assertTrue(all("FRIENDLY" in f for f in r["failed"]), r["failed"])


if __name__ == "__main__":
    unittest.main()
