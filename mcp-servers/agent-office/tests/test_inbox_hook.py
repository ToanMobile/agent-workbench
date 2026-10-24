"""Hook PostToolUse của worker: đọc hộp thư lệnh Agent Office của đúng session rồi giao cho agent.

- hộp thư rỗng / không có thư mục: không in gì, exit 0, nhanh;
- có lệnh: in additionalContext mang nonce, xoá file lệnh, ghi ack cho server;
- sai session (hoặc sid không hợp lệ) không đọc được hộp thư của session khác;
- file lệnh hỏng: bỏ, ghi log, không làm hỏng tool call (exit 0);
- tool call trong subagent (stdin có agent_id) không nhận lệnh — lệnh để dành cho luồng chính;
- thiếu nonce (worker không do runner có hộp thư bật) thì không giao (fail closed);
- hai hook chạy song song chỉ một hook nhận một lệnh.
"""
import json, os, shutil, subprocess, sys, tempfile, threading, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(HERE, "inbox_hook.py")
SID = "0f8b6a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
OTHER = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
NONCE = "n0nce-test-123"


class InboxHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.inbox = os.path.join(self.tmp, "inbox")
        self.log = os.path.join(self.tmp, "inbox-hook.log")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def drop(self, sid, mid, text, raw=None):
        d = os.path.join(self.inbox, sid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, mid + ".json"), "w", encoding="utf-8") as f:
            f.write(raw if raw is not None else json.dumps({"id": mid, "text": text, "ts": time.time()}))

    def run_hook(self, payload, nonce=NONCE):
        env = {"PATH": os.environ.get("PATH", ""), "AGENT_OFFICE_INBOX": self.inbox, "AGENT_OFFICE_HOOK_LOG": self.log}
        if nonce:
            env["AGENT_OFFICE_NONCE"] = nonce
        stdin = payload if isinstance(payload, str) else json.dumps(payload)
        t = time.monotonic()
        p = subprocess.run([sys.executable, "-I", "-S", HOOK], input=stdin, capture_output=True, text=True, env=env, timeout=20)
        return p, time.monotonic() - t

    def ctx(self, p):
        return json.loads(p.stdout)["hookSpecificOutput"]["additionalContext"]

    def event(self, sid=SID, **kw):
        return dict({"session_id": sid, "hook_event_name": "PostToolUse", "tool_name": "Bash"}, **kw)

    def test_empty_inbox_prints_nothing_and_is_fast(self):
        p, dt = self.run_hook(self.event())
        self.assertEqual(p.returncode, 0)
        self.assertEqual(p.stdout, "")
        os.makedirs(os.path.join(self.inbox, SID))
        best = min(self.run_hook(self.event())[1] for _ in range(3))
        self.assertLess(best, 0.5, "hook hộp thư rỗng phải nhanh (đo cả khởi động python)")

    def test_message_delivered_once_with_nonce_and_acked(self):
        self.drop(SID, "m1", "Chạy lại test rồi báo kết quả")
        p, _ = self.run_hook(self.event())
        self.assertEqual(p.returncode, 0, p.stderr)
        c = self.ctx(p)
        self.assertIn(NONCE, c)
        self.assertIn("Chạy lại test rồi báo kết quả", c)
        self.assertEqual(json.loads(p.stdout)["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertFalse(os.path.exists(os.path.join(self.inbox, SID, "m1.json")))
        self.assertTrue(os.path.exists(os.path.join(self.inbox, SID, "acks", "m1")))
        again, _ = self.run_hook(self.event())
        self.assertEqual(again.stdout, "", "lệnh chỉ giao một lần")

    def test_messages_in_order(self):
        self.drop(SID, "1730000000000-a", "một")
        self.drop(SID, "1730000000001-b", "hai")
        c = self.ctx(self.run_hook(self.event())[0])
        self.assertLess(c.index("một"), c.index("hai"))

    def test_wrong_session_does_not_read_other_inbox(self):
        self.drop(OTHER, "m1", "lệnh của session khác")
        p, _ = self.run_hook(self.event(SID))
        self.assertEqual(p.stdout, "")
        self.assertTrue(os.path.exists(os.path.join(self.inbox, OTHER, "m1.json")))
        for bad in ("../" + OTHER, OTHER + "/..", "", None, 5):
            p, _ = self.run_hook(self.event(bad))
            self.assertEqual((p.returncode, p.stdout), (0, ""), bad)
        self.assertTrue(os.path.exists(os.path.join(self.inbox, OTHER, "m1.json")))

    def test_corrupt_file_skipped_logged_and_tool_call_unharmed(self):
        self.drop(SID, "bad", None, raw="{không phải json")
        self.drop(SID, "good", "lệnh tốt")
        p, _ = self.run_hook(self.event())
        self.assertEqual(p.returncode, 0)
        c = self.ctx(p)
        self.assertIn("lệnh tốt", c)
        self.assertFalse(os.path.exists(os.path.join(self.inbox, SID, "bad.json")))
        with open(self.log, encoding="utf-8") as f:
            self.assertIn("bad", f.read())
        for junk in ("", "not json", "[1,2]"):
            p, _ = self.run_hook(junk)
            self.assertEqual((p.returncode, p.stdout), (0, ""), junk)

    def test_ack_failure_still_delivers_and_is_not_logged_as_dropped(self):
        self.drop(SID, "m1", "lệnh vẫn phải tới")
        with open(os.path.join(self.inbox, SID, "acks"), "w") as f:
            f.write("chặn: acks là file nên không tạo được thư mục ack")
        p, _ = self.run_hook(self.event())
        self.assertIn("lệnh vẫn phải tới", self.ctx(p))
        with open(self.log, encoding="utf-8") as f:
            self.assertNotIn("bỏ lệnh hỏng", f.read())

    def test_session_id_with_newline_rejected(self):
        os.makedirs(os.path.join(self.inbox, SID + "\n"))
        self.drop(SID + "\n", "m1", "không được giao")
        p, _ = self.run_hook(self.event(SID + "\n"))
        self.assertEqual((p.returncode, p.stdout), (0, ""))

    def test_fifo_or_symlink_in_inbox_does_not_hang(self):
        d = os.path.join(self.inbox, SID)
        os.makedirs(d)
        os.mkfifo(os.path.join(d, "1730000000000-fifo.json"))  # open() một FIFO không ai ghi sẽ treo hook (INSTINCT-062)
        os.symlink("/etc/hosts", os.path.join(d, "1730000000001-link.json"))
        self.drop(SID, "1730000000002-ok", "lệnh thật")
        p, dt = self.run_hook(self.event())
        self.assertIn("lệnh thật", self.ctx(p))
        self.assertNotIn("localhost", self.ctx(p), "không đọc file qua symlink")
        self.assertLess(dt, 5)

    def test_settings_json_uses_this_python_not_bare_python3(self):
        sys.path.insert(0, HERE)
        import inbox_hook
        cmd = json.loads(inbox_hook.settings_json("/x/inbox_hook.py"))["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
        self.assertTrue(cmd.startswith("'%s' -I -S " % sys.executable), cmd)

    def test_subagent_tool_call_leaves_message_for_main_thread(self):
        self.drop(SID, "m1", "lệnh cho luồng chính")
        p, _ = self.run_hook(self.event(agent_id="aebce6f00b827450d", agent_type="general-purpose"))
        self.assertEqual(p.stdout, "")
        self.assertTrue(os.path.exists(os.path.join(self.inbox, SID, "m1.json")))
        self.assertIn("lệnh cho luồng chính", self.ctx(self.run_hook(self.event())[0]))

    def test_missing_nonce_fails_closed(self):
        self.drop(SID, "m1", "lệnh")
        p, _ = self.run_hook(self.event(), nonce="")
        self.assertEqual((p.returncode, p.stdout), (0, ""))
        self.assertTrue(os.path.exists(os.path.join(self.inbox, SID, "m1.json")), "không nonce thì để nguyên lệnh")

    def test_parallel_hooks_deliver_each_message_once(self):
        for i in range(6):
            self.drop(SID, f"17300000000{i:02d}-m{i}", f"lệnh-{i}")
        outs = []

        def go():
            outs.append(self.run_hook(self.event())[0].stdout)
        ts = [threading.Thread(target=go) for _ in range(4)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        joined = "".join(outs)
        for i in range(6):
            self.assertEqual(joined.count(f"lệnh-{i}"), 1, f"lệnh-{i}")


if __name__ == "__main__":
    unittest.main()
