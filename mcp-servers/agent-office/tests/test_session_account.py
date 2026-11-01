"""Ô tài khoản góc phải trên: /api/state gắn `account` (tên hồ sơ account pool) và `configDir` (tên thư mục) cho từng phiên.

- phiên worker: dòng `account_pool: engine=claude account=<tên> config_dir=<thư mục>` của log worker, theo session id của lần giao;
- phiên không có dòng đó (điều phối): đoán từ thư mục cấu hình chứa transcript (~/.claude-finos → finos, ~/.claude → None);
- không bao giờ lộ đường dẫn đầy đủ, chuỗi lạ trong tên hồ sơ, hay giá trị token/khoá có trong log.
"""
import json, os, shutil, sys, tempfile, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402

SID_A = "45899982-08be-4d74-9056-ae1daa7fa60b"
SID_B = "4f2f677e-4ee0-4042-8006-a82fc0f0d2db"
SID_C = "11111111-2222-4333-8444-555555555555"
SECRET = "-".join(["sk", "ant", "oat01", "Z" * 40])  # khoá giả, dựng lúc chạy
KEY_FIELD = "api" + "Key"  # trường khoá trong dòng init giả
OAUTH = "eyJ" + "q" * 60


def section(lane, issue, sid, account, cfg_dir, inbox=True):
    sid_line = f"agent_office: session_id={sid}\n" if inbox else ""
    return (f"=== dispatch lane={lane} issue=#{issue} at 2026-10-30T09:15:32Z ===\n"
            f"CLAUDE_CODE_OAUTH_TOKEN={OAUTH}\n"
            f"account_pool: engine=claude account={account} config_dir={cfg_dir}\n"
            f"{sid_line}"
            f'{{"type":"system","subtype":"init","session_id":"{sid}","cwd":"/r","model":"m","{KEY_FIELD}":"{SECRET}"}}\n')


class AccountHelpers(unittest.TestCase):
    def test_config_dir_names(self):
        self.assertEqual(server.account_of_config_dir("/Users/alex/.claude-finos"), ("finos", ".claude-finos"))
        self.assertEqual(server.account_of_config_dir("/Users/alex/.claude-finos_team/"), ("finos_team", ".claude-finos_team"))
        self.assertEqual(server.account_of_config_dir("/Users/alex/.claude"), (None, ".claude"))
        self.assertEqual(server.account_of_config_dir("/tmp/random"), (None, None))
        self.assertEqual(server.account_of_config_dir(None), (None, None))

    def test_unsafe_account_names_are_dropped(self):
        self.assertEqual(server.safe_account("max"), "max")
        for bad in ("a=b", "x/y", "", None, "a" * 80, SECRET + "=", "two words"):
            self.assertIsNone(server.safe_account(bad), bad)

    def test_orchestrator_from_transcript_dir(self):
        s = {"id": "x", "file": "/Users/alex/.claude-max/projects/-Volumes-Data-Toan-agent-workbench/x.jsonl"}
        self.assertEqual(server.session_account(s), {"account": "max", "configDir": ".claude-max"})
        s = {"id": "x", "file": "/Users/alex/.claude/projects/-Volumes-Data-Toan-agent-workbench/x.jsonl"}
        self.assertEqual(server.session_account(s), {"account": None, "configDir": ".claude"})
        self.assertEqual(server.session_account({"id": "x", "file": ""}), {"account": None, "configDir": None})

    def test_worker_log_wins_over_transcript_dir(self):
        s = {"id": SID_A, "file": "/Users/alex/.claude/projects/p/x.jsonl"}
        got = server.session_account(s, {SID_A: {"account": "finos", "configDir": ".claude-finos"}})
        self.assertEqual(got, {"account": "finos", "configDir": ".claude-finos"})


class WorkerLogAccounts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = os.path.join(self.tmp, "Demo")
        self.runs = os.path.join(self.repo, "docs", "super-board", "runs", "2026-10-30-demo-workers")
        os.makedirs(self.runs)
        self.log = os.path.join(self.runs, "worker-build-696.log")
        with open(self.log, "w") as f:
            f.write(section("build", 696, SID_A, "finos", "/Users/alex/.claude-finos"))
            f.write(section("build", 696, SID_B, "finos_team", "/Users/alex/.claude-finos_team", inbox=False))
        self.cfg = {"root": self.tmp, "repos": ["Demo"], "github": {"owner": "o"}, "activeMinutes": 10, "githubSeconds": 60}
        self.scanner = server.LocalScanner(self.cfg)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_each_dispatch_maps_its_session(self):
        got = self.scanner.session_accounts({"Demo": self.repo})
        self.assertEqual(got[SID_A], {"account": "finos", "configDir": ".claude-finos"})
        self.assertEqual(got[SID_B], {"account": "finos_team", "configDir": ".claude-finos_team"})

    def test_reads_appended_lines_incrementally(self):
        self.scanner.session_accounts({"Demo": self.repo})
        pos = self.scanner.acct_cache[self.log]["pos"]
        with open(self.log, "a") as f:
            f.write(section("review", 678, SID_C, "max", "/Users/alex/.claude-max")[:-1])  # dòng cuối chưa ghi trọn
        got = self.scanner.session_accounts({"Demo": self.repo})
        self.assertEqual(got[SID_C], {"account": "max", "configDir": ".claude-max"})
        self.assertGreater(self.scanner.acct_cache[self.log]["pos"], pos)
        with open(self.log, "a") as f:
            f.write("\n")
        self.assertEqual(self.scanner.session_accounts({"Demo": self.repo})[SID_C]["account"], "max")

    def test_odd_account_value_not_exposed(self):
        with open(self.log, "a") as f:
            f.write(section("qa", 1, SID_C, "tok=" + SECRET, "/Users/alex/" + SECRET))
        got = self.scanner.session_accounts({"Demo": self.repo})
        self.assertNotIn(SID_C, got)

    def test_state_api_exposes_account_without_secrets(self):
        t_now = server.now()
        tick = {"time": "10:00:00", "at": t_now - 5, "counts": {}, "lanes": {"b": {"idle": False, "card": "696"}}, "waiting": 0}
        sess = {"id": SID_A, "file": os.path.join(self.tmp, ".claude", "projects", "p", SID_A + ".jsonl"),
                "cwd": os.path.join(self.repo, ".claude", "worktrees", "issue-696-build"), "branch": "issue-696-build",
                "lastTs": t_now - 2, "texts": [{"ts": t_now - 2, "text": "đang làm"}], "tools": [], "ticks": [],
                "tokensLeft": 1234567, "finishedAt": None, "manifest": None, "subagent": False, "projectDir": "p"}
        orch = dict(sess, id="99999999-8888-4777-8666-555555555555", cwd=self.repo, branch="main",
                    file=os.path.join(self.tmp, ".claude-max", "projects", "p", "o.jsonl"), tokensLeft=999)
        project = {"columns": [{"name": "Building", "kind": "building"}],
                   "items": [{"id": "i696", "number": "696", "title": "t", "repo": "Demo", "repoFull": "o/Demo", "status": "Building",
                              "state": "OPEN", "labels": [], "assignees": [], "fields": {}, "updatedAt": t_now}]}
        st = server.build_state(self.cfg, project, {"ok": True}, [sess, orch], {"ok": True},
                                [("Demo", "/x.log", [tick], None, t_now)], self.scanner)
        by_sid = {w["session"]["id"]: w for w in st["workers"] if w.get("session")}
        lane = by_sid[SID_A]
        self.assertEqual(lane["kind"], "lane")
        self.assertEqual((lane["session"]["account"], lane["session"]["configDir"], lane["session"]["tokensLeft"]),
                         ("finos", ".claude-finos", 1234567))
        o = by_sid[orch["id"]]["session"]
        self.assertEqual((o["account"], o["configDir"], o["tokensLeft"]), ("max", ".claude-max", 999))
        body = json.dumps(st, ensure_ascii=False)
        for leak in (SECRET, OAUTH, "/Users/alex/.claude-finos", "config_dir=", "account_pool"):
            self.assertNotIn(leak, body)


class DemoHasAccounts(unittest.TestCase):
    def test_demo_state_carries_accounts(self):
        cfg = server.deep_merge(server.DEFAULTS, {"root": tempfile.gettempdir()})
        app = server.App(cfg, demo=True)
        app.rebuild()
        st = json.loads(app.state_bytes)
        accs = {w["session"]["account"] for w in st["workers"] if w.get("session")}
        self.assertTrue({"max", "finos", "finos_team"} <= accs, accs)
        for w in st["workers"]:
            if w.get("session"):
                self.assertNotIn("/", w["session"]["configDir"] or "")


if __name__ == "__main__":
    unittest.main()
