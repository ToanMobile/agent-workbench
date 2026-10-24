"""Khung "Cần bạn duyệt": nút Duyệt / Từ chối cho thẻ 🙋 (cột Blocked, nhãn needs-you).

- Duyệt gửi đúng một chữ `done` lên issue (chỉ comment này cho wave sau chạy tiếp), không nhận chữ của client;
- thẻ có bước `needs-you: <lệnh>` chỉ duyệt được khi người dùng báo đã chạy xong; chưa đọc được bước thì không duyệt;
- Từ chối comment lý do, không bao giờ thành `done`, thẻ ở nguyên Blocked;
- mỗi quyết định ghi một dòng vào events.jsonl; gh lỗi thì báo lỗi, không ghi là đã duyệt (fail closed).
"""
import json, os, shutil, sys, tempfile, threading, unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


def comment(body, at="2026-10-24T08:00:00Z", who="ToanMobile"):
    return {"body": body, "createdAt": at, "author": {"login": who}}


class ApprovalInfoTest(unittest.TestCase):
    def test_steps_from_gate_lines_and_checklist(self):
        info = server.approval_info([
            comment("[reviewer] [blocker] 🙋 Your turn on #812 — Add plan column\n"
                    "- [ ] Run `npx prisma migrate deploy` on the **live** database\n- [ ] Comment `done` here\n"
                    "<details>Evidence: needs-you: npx prisma migrate deploy\nneeds-you: `psql -f fix.sql`\n"
                    "needs-you:done label cũ\nblocked-by: -</details>"),
        ])
        self.assertEqual(info["steps"], ["npx prisma migrate deploy", "psql -f fix.sql"])
        self.assertFalse(info["approved"])

    def test_newest_request_wins_and_later_done_means_approved(self):
        info = server.approval_info([
            comment("needs-you: old-command", "2026-10-20T08:00:00Z"),
            comment("<!-- super-board:needs-you -->\n🙋 Cần bạn: review PR #342 · xong thì comment done", "2026-10-21T08:00:00Z"),
            comment("needs-you: new-command", "2026-10-22T08:00:00Z"),
        ])
        self.assertEqual(info["steps"], ["new-command"])
        self.assertFalse(info["approved"])
        done = server.approval_info([comment("🙋 Cần bạn: merge PR #9", "2026-10-21T08:00:00Z"), comment(" done \n", "2026-10-21T09:00:00Z")])
        self.assertTrue(done["approved"])
        stale = server.approval_info([comment("done", "2026-10-21T07:00:00Z"), comment("🙋 Cần bạn: merge PR #9", "2026-10-21T08:00:00Z")])
        self.assertFalse(stale["approved"], "done trước yêu cầu mới không còn tính")
        self.assertFalse(server.approval_info([comment("done rồi")])["approved"])


class ApproveActionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.events = os.path.join(self.tmp, "events.jsonl")
        cfg = server.deep_merge(server.DEFAULTS, {"eventsFile": self.events, "macNotify": False, "repos": [],
                                                  "claudeProjectsDir": self.tmp, "runnerLogGlobs": [], "root": self.tmp})
        self.app = server.App(cfg, demo=False)
        self.app.gh_meta = {"ok": True, "error": None, "fetchedAt": server.now()}
        self.card = {"id": "item-1", "contentId": "issue-1", "number": "60", "title": "Migration", "type": "Issue",
                     "state": "OPEN", "repo": "agent-workbench", "status": "Blocked", "labels": [{"name": "needs-you"}],
                     "fields": {}, "approval": {"steps": [], "approved": False}}
        self.app.project = {"id": "proj", "statusField": "Status", "statusFieldId": "f", "selectFields": [],
                            "columns": [{"name": "Blocked", "kind": "blocked"}], "items": [self.card]}
        self.gh = mock.patch.object(server, "gh_graphql", return_value={})
        self.gh_mock = self.gh.start()

    def tearDown(self):
        self.gh.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def logged(self):
        if not os.path.exists(self.events):
            return []
        with open(self.events, encoding="utf-8") as f:
            return [json.loads(x) for x in f if x.strip()]

    def test_approve_sends_exactly_done_and_logs_it(self):
        res = self.app.act("approve", {"itemId": "item-1", "body": "done, and also merge #99"})
        self.assertTrue(res["ok"])
        self.assertEqual(self.gh_mock.call_count, 1)
        query, variables = self.gh_mock.call_args[0]
        self.assertIs(query, server.M_COMMENT)
        self.assertEqual(variables, {"s": "issue-1", "b": "done"})
        self.assertTrue(self.card["approval"]["approved"])
        ev = [e for e in self.logged() if "duyệt" in e["text"].lower()]
        self.assertEqual(len(ev), 1, self.logged())
        self.assertIn("#60", ev[0]["text"])
        self.assertEqual(ev[0]["sel"], {"type": "item", "id": "item-1"})
        self.assertIn(ev[0], self.app.events)

    def test_steps_must_be_ticked_before_approve(self):
        self.card["approval"]["steps"] = ["npx prisma migrate deploy"]
        with self.assertRaises(ValueError):
            self.app.act("approve", {"itemId": "item-1"})
        with self.assertRaises(ValueError):
            self.app.act("approve", {"itemId": "item-1", "stepsDone": "true"})
        self.gh_mock.assert_not_called()
        self.app.act("approve", {"itemId": "item-1", "stepsDone": True})
        self.assertEqual(self.gh_mock.call_args[0][1]["b"], "done")

    def test_unread_steps_fail_closed(self):
        del self.card["approval"]
        with self.assertRaises(ValueError):
            self.app.act("approve", {"itemId": "item-1", "stepsDone": True})
        self.gh_mock.assert_not_called()

    def test_only_needs_you_cards_in_blocked(self):
        self.card["labels"] = []
        with self.assertRaises(ValueError):
            self.app.act("approve", {"itemId": "item-1"})
        self.card["labels"], self.card["status"] = [{"name": "needs-you"}], "Ready"
        with self.assertRaises(ValueError):
            self.app.act("approve", {"itemId": "item-1"})
        self.gh_mock.assert_not_called()

    def test_gh_error_is_not_an_approval(self):
        self.gh_mock.side_effect = server.GhError("HTTP 502")
        with self.assertRaises(server.GhError):
            self.app.act("approve", {"itemId": "item-1"})
        self.assertFalse(self.card["approval"]["approved"])
        self.assertNotEqual((self.card.get("lastComment") or {}).get("body"), "done")
        texts = [e["text"] for e in self.logged()]
        self.assertTrue(any("lỗi" in t for t in texts), texts)
        self.assertFalse(any(t.startswith("Bạn duyệt") for t in texts), texts)

    def test_second_press_while_in_flight_is_refused(self):
        gate, entered = threading.Event(), threading.Event()

        def slow(*_):
            entered.set()
            gate.wait(5)
            return {}
        self.gh_mock.side_effect = slow
        t = threading.Thread(target=self.app.act, args=("approve", {"itemId": "item-1"}))
        t.start()
        self.assertTrue(entered.wait(5))
        try:
            with self.assertRaises(ValueError):
                self.app.act("approve", {"itemId": "item-1"})
        finally:
            gate.set()
            t.join(5)
        self.assertEqual(self.gh_mock.call_count, 1)

    def test_reject_comments_reason_and_keeps_blocked(self):
        self.app.act("reject", {"itemId": "item-1", "reason": "done"})
        body = self.gh_mock.call_args[0][1]["b"]
        self.assertNotEqual(body.strip(), "done")
        self.assertIn("Từ chối", body)
        self.assertIn("done", body)
        self.app.act("reject", {"itemId": "item-1"})
        self.assertIn("Từ chối", self.gh_mock.call_args[0][1]["b"])
        self.assertEqual(self.card["status"], "Blocked")
        self.assertFalse(self.card["approval"]["approved"])
        self.assertEqual(sum(1 for e in self.logged() if e["text"].startswith("Bạn từ chối")), 2)


    def test_new_needs_you_card_raises_an_alert_once(self):
        self.card["labels"] = []
        self.app.rebuild()  # mốc: chưa có thẻ 🙋
        self.card["labels"] = [{"name": "needs-you"}]
        self.app.rebuild()
        self.app.rebuild()
        alerts = [e for e in self.app.events if "cần bạn duyệt" in e["text"]]
        self.assertEqual(len(alerts), 1, self.app.events)
        self.assertTrue(alerts[0]["important"])
        self.assertEqual(alerts[0]["sel"], {"type": "approvals"})
        self.assertIn("#60", alerts[0]["text"])

    def test_cards_already_waiting_at_start_do_not_alert(self):
        self.app.rebuild()
        self.assertFalse([e for e in self.app.events if "cần bạn duyệt" in e["text"]])


if __name__ == "__main__":
    unittest.main()
