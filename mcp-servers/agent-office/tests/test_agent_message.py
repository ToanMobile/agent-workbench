"""Nhắn lệnh cho agent super-board từ Agent Office (POST /api/agent-message).

- chỉ nhắn được cho phiên worker super-board (tìm thấy trong log worker), không phải phiên tuỳ ý;
- worker đang chạy (ps thấy --session-id/--resume <sid>): ghi hộp thư, mỗi lệnh một file, hook ack thì "đã đọc";
- worker đã dừng: resume bằng claude --resume với config_dir và cwd của worker; KHÔNG resume khi session còn tiến trình,
  khi thẻ còn worker khác sống (lock inflight) hoặc đang có resume khác của cùng session;
- giới hạn 6 lệnh/phút, 4000 ký tự; lệnh qua tunnel cần mã 6 số gửi qua thông báo trên Mac; lỗi thì không gửi.
"""
import http.client, json, os, shutil, sys, tempfile, time, unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402

SID = "0f8b6a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
OLD_SID = "11111111-2222-4333-8444-555555555555"
STRANGER = "99999999-8888-4777-8666-555555555555"


class FakeProc:
    def __init__(self, rc=None):
        self.rc, self.pid = rc, 4242

    def poll(self):
        return self.rc


class AgentMessageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = os.path.join(self.tmp, "agent-workbench")
        self.wdir = os.path.join(self.repo, "docs", "super-board", "runs", "2026-10-24-agent-workbench-workers")
        os.makedirs(self.wdir)
        self.inflight = os.path.join(self.repo, ".claude", "super-board", "inflight")  # đúng chỗ runner ghi lock
        os.makedirs(self.inflight)
        self.log = os.path.join(self.wdir, "worker-build-323.log")
        with open(self.log, "w") as f:
            f.write("=== dispatch lane=build issue=#323 at 2026-10-24T00:00:00Z ===\nprompt: x\n\n"
                    "account_pool: engine=claude account=finos config_dir=/Users/x/.claude-old\n"
                    '{"type":"system","subtype":"init","cwd":"/old","session_id":"%s"}\n'
                    "=== dispatch lane=build issue=#323 at 2026-10-24T01:00:00Z ===\nprompt: y\n\n"
                    "account_pool: engine=claude account=finos config_dir=/Users/x/.claude-finos\n"
                    "agent_office: session_id=%s\n"
                    '{"type":"system","subtype":"hook_started","session_id":"%s"}\n'
                    '{"type":"system","subtype":"init","cwd":"%s","session_id":"%s"}\n' % (OLD_SID, SID, SID, self.repo, SID))
        self.events = os.path.join(self.tmp, "events.jsonl")
        self.inbox = os.path.join(self.tmp, "inbox")
        cfg = server.deep_merge(server.DEFAULTS, {
            "eventsFile": self.events, "macNotify": False, "repos": ["agent-workbench"], "root": self.tmp,
            "claudeProjectsDir": self.tmp, "runnerLogGlobs": [], "inboxDir": self.inbox,
            "resumeLogDir": os.path.join(self.tmp, "resume"), "claudeBin": "/bin/echo"})
        self.app = server.App(cfg, demo=False)
        self.ps = set()
        self.app._ps_sids = lambda: set(self.ps)
        self.spawned = []
        self.app._spawn = lambda argv, env, cwd, log: self.spawned.append((argv, env, cwd, log)) or FakeProc()
        self.notify = mock.patch.object(server, "mac_notify")
        self.notified = self.notify.start()

    def tearDown(self):
        self.notify.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def inbox_files(self, sid=SID):
        d = os.path.join(self.inbox, sid)
        return sorted(n for n in os.listdir(d) if n.endswith(".json")) if os.path.isdir(d) else []

    def send(self, text="Chạy lại test", sid=SID, remote=False):
        return self.app.agent_message({"sessionId": sid, "text": text}, remote=remote)

    # ---- đang chạy: hộp thư
    def test_running_session_gets_inbox_file_and_event(self):
        self.ps = {SID}
        res = self.send("Dừng sửa file X, sửa file Y token=ghp_" + "a" * 36)
        self.assertEqual((res["ok"], res["mode"]), (True, "inbox"))
        files = self.inbox_files()
        self.assertEqual(len(files), 1)
        with open(os.path.join(self.inbox, SID, files[0])) as f:
            msg = json.load(f)
        self.assertIn("sửa file Y", msg["text"])
        self.assertEqual(oct(os.stat(os.path.join(self.inbox, SID)).st_mode & 0o777), "0o700")
        self.assertEqual(self.spawned, [], "đang chạy thì không resume")
        with open(self.events) as f:
            log = f.read()
        self.assertIn("#323", log)
        self.assertNotIn("ghp_" + "a" * 36, log, "events.jsonl che token")

    def test_ack_from_hook_marks_message_read(self):
        self.ps = {SID}
        mid = self.send()["id"]
        os.makedirs(os.path.join(self.inbox, SID, "acks"))
        with open(os.path.join(self.inbox, SID, "acks", mid), "w") as f:
            f.write("1")
        self.app.poll_messages()
        st = {m["id"]: m["state"] for m in self.app.messages_view()}
        self.assertEqual(st[mid], "read")
        with open(self.events) as f:
            self.assertIn("đã đọc", f.read())

    def test_unread_message_dropped_when_session_stops(self):
        self.ps = {SID}
        mid = self.send()["id"]
        self.ps = set()
        self.app.poll_messages()
        self.assertEqual({m["id"]: m["state"] for m in self.app.messages_view()}[mid], "unread")
        self.assertEqual(self.inbox_files(), [], "lệnh chưa đọc không được giao bất ngờ cho lần chạy sau")

    def test_message_taken_by_hook_is_not_called_unread(self):
        self.ps = {SID}
        mid = self.send()["id"]
        os.unlink(os.path.join(self.inbox, SID, mid + ".json"))  # hook đã nhận, phiên dừng trước khi kịp ghi ack
        self.ps = set()
        self.app.poll_messages()
        self.assertEqual({m["id"]: m["state"] for m in self.app.messages_view()}[mid], "read")

    # ---- đích hợp lệ
    def test_unknown_or_bad_session_refused(self):
        for sid in (STRANGER, "../" + SID, "", None):
            with self.assertRaises(ValueError, msg=sid):
                self.send(sid=sid)
        self.assertFalse(os.path.isdir(self.inbox) and os.listdir(self.inbox))

    # ---- resume
    def test_stopped_session_is_resumed_with_worker_config_and_cwd(self):
        res = self.send("Làm tiếp, sửa test hỏng")
        self.assertEqual((res["ok"], res["mode"]), (True, "resume"))
        argv, env, cwd, log = self.spawned[0]
        self.assertEqual(argv[:4], ["/bin/echo", "--resume", SID, "-p"])
        self.assertTrue(argv[4].endswith("Làm tiếp, sửa test hỏng"))
        self.assertNotIn("--model", argv, "dòng init của log mẫu không có model")
        for flag in ("--dangerously-skip-permissions", "--settings", "--append-system-prompt", "--verbose"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[argv.index("--output-format") + 1], "stream-json")
        self.assertEqual(env["CLAUDE_CONFIG_DIR"], "/Users/x/.claude-finos")
        self.assertTrue(env["AGENT_OFFICE_NONCE"])
        self.assertEqual(env["AGENT_OFFICE_INBOX"], self.inbox, "hook của phiên resume đọc đúng hộp thư server ghi")
        self.assertIn(env["AGENT_OFFICE_NONCE"], argv[argv.index("--append-system-prompt") + 1])
        self.assertEqual(cwd, self.repo)
        self.assertTrue(log.startswith(os.path.join(self.tmp, "resume")))
        self.assertEqual(self.inbox_files(), [])

    def test_resume_without_config_dir_drops_inherited_one_and_finds_local_bin(self):
        with open(self.log) as f:
            body = f.read()
        with open(self.log, "w") as f:
            f.write(body.replace("account_pool: engine=claude account=finos config_dir=/Users/x/.claude-finos\n", ""))
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "/Users/x/.claude-khac", "PATH": "/usr/bin:/bin"}):
            self.send()
        env = self.spawned[0][1]
        self.assertNotIn("CLAUDE_CONFIG_DIR", env, "không có config_dir trong log thì dùng mặc định, không kế thừa của server")
        self.assertIn(os.path.expanduser("~/.local/bin"), env["PATH"].split(os.pathsep))

    def test_events_point_at_the_card_or_nothing(self):
        self.app.project = {"items": [{"id": "ITEM-323", "repo": "agent-workbench", "number": "323"}]}
        self.ps = {SID}
        self.send()
        self.assertEqual(self.app.events[-1]["sel"], {"type": "item", "id": "ITEM-323"})
        self.app.project = {"items": []}
        self.send()
        self.assertIsNone(self.app.events[-1]["sel"])

    def test_resume_text_starting_with_dash_is_not_a_flag(self):
        self.send("--settings {} --dangerously-skip-permissions")
        argv = self.spawned[0][0]
        self.assertFalse(argv[4].startswith("-"), argv[4])
        self.assertEqual(argv.count("--settings"), 1)

    def test_resume_keeps_worker_model(self):
        with open(self.log) as f:
            body = f.read()
        with open(self.log, "w") as f:
            f.write(body.replace('"cwd":"%s"' % self.repo, '"cwd":"%s","model":"claude-sonnet-5-5"' % self.repo))
        self.send()
        argv = self.spawned[0][0]
        self.assertEqual(argv[argv.index("--model") + 1], "claude-sonnet-5-5")

    def test_resume_refused_while_session_still_running_elsewhere(self):
        self.ps = {OLD_SID}  # phiên cũ còn tiến trình (vd. claude --resume OLD_SID do ai đó chạy)
        with self.assertRaises(ValueError):
            self.send(sid=OLD_SID)
        self.assertEqual(self.spawned, [])

    def test_resume_refused_while_card_has_live_worker(self):
        # runner giao lại thẻ cho worker lane khác (log khác): vẫn là thẻ đang có worker sống
        with open(os.path.join(self.inflight, "323"), "w") as f:
            f.write("PID=%d\nLANE=qa\nWORKER_LOG=%s\n" % (os.getpid(), os.path.join(self.wdir, "worker-qa-323.log")))
        with self.assertRaises(ValueError):
            self.send()
        self.assertEqual(self.spawned, [])

    def test_resume_refused_when_card_lock_unreadable(self):
        with open(os.path.join(self.inflight, "323"), "w") as f:
            f.write("PID=khong-phai-so\n")
        with self.assertRaises(ValueError):
            self.send()
        self.assertEqual(self.spawned, [])

    def test_resume_allowed_when_card_lock_pid_dead(self):
        with open(os.path.join(self.inflight, "323"), "w") as f:
            f.write("PID=999999\nLANE=build\n")
        self.assertEqual(self.send()["mode"], "resume")

    def test_second_resume_of_same_session_goes_to_inbox_not_second_process(self):
        self.send("một")
        self.ps = {SID}  # resume đang chạy: ps thấy --resume SID
        res = self.send("hai")
        self.assertEqual(res["mode"], "inbox")
        self.assertEqual(len(self.spawned), 1)

    def test_finished_resume_is_closed_out_before_the_next_resume(self):
        first = self.send("một")["id"]
        self.app.resumes[SID]["proc"].rc = 0  # resume 1 xong trước nhịp poll kế tiếp
        self.send("hai")
        self.app.poll_messages()
        self.assertEqual({m["id"]: m["state"] for m in self.app.messages_view()}[first], "done")

    def test_resume_drops_stale_inbox_files_first(self):
        box = os.path.join(self.inbox, SID)
        os.makedirs(box)
        with open(os.path.join(box, "1700000000000-cu.json"), "w") as f:
            json.dump({"id": "1700000000000-cu", "text": "lệnh cũ từ lần chạy trước"}, f)
        self.assertEqual(self.send()["mode"], "resume")
        self.assertEqual(self.inbox_files(), [], "lệnh cũ không được giao cho lần resume")

    def test_resume_refused_when_own_resume_alive_but_not_in_ps(self):
        self.send("một")
        with self.assertRaises(ValueError):
            self.send("hai")
        self.assertEqual(len(self.spawned), 1)

    def test_resume_refused_when_cwd_gone(self):
        with open(self.log, "a") as f:
            f.write("=== dispatch lane=build issue=#323 at 2026-10-24T02:00:00Z ===\nagent_office: session_id=%s\n"
                    '{"type":"system","subtype":"init","cwd":"/khong/con/nua","session_id":"%s"}\n' % (STRANGER, STRANGER))
        with self.assertRaises(ValueError):
            self.send(sid=STRANGER)
        self.assertEqual(self.spawned, [])

    # ---- giới hạn
    def test_rate_limit_six_per_minute(self):
        self.ps = {SID}
        for i in range(6):
            self.send("lệnh %d" % i)
        with self.assertRaises(server.RateLimited):
            self.send("lệnh 7")
        self.assertEqual(len(self.inbox_files()), 6)

    def test_rejected_requests_count_toward_rate_limit(self):
        for _ in range(6):
            with self.assertRaises(ValueError):
                self.send(sid=STRANGER)
        with self.assertRaises(server.RateLimited):
            self.send()

    def test_remote_requests_do_not_lock_out_the_mac(self):
        self.ps = {SID}
        for _ in range(6):
            self.send(remote=True)
            self.app.pending.clear()  # chỉ thử rate limit, không chạm trần số lệnh chờ mã
        with self.assertRaises(server.RateLimited):
            self.send(remote=True)
        self.assertTrue(self.send(remote=False)["ok"], "người có link QR không khoá được người ngồi ở Mac")

    def test_session_id_with_trailing_newline_refused(self):
        self.ps = {SID}
        with self.assertRaises(ValueError):
            self.send(sid=SID + "\n")
        self.assertFalse(os.path.isdir(self.inbox) and os.listdir(self.inbox))

    def test_length_limit_and_empty(self):
        self.ps = {SID}
        with self.assertRaises(ValueError):
            self.send("x" * 4001)
        with self.assertRaises(ValueError):
            self.send("   ")
        self.assertEqual(self.inbox_files(), [])
        self.assertTrue(self.send("x" * 4000)["ok"])

    # ---- qua tunnel
    def test_tunnel_without_code_does_not_send(self):
        self.ps = {SID}
        res = self.send("lệnh từ điện thoại", remote=True)
        self.assertFalse(res["ok"])
        self.assertTrue(res["needCode"])
        self.assertEqual(self.inbox_files(), [])
        code = self.notified.call_args[0][0]
        self.assertRegex(code, r"\b\d{6}\b")
        self.assertNotIn("code", json.dumps(res).replace("needCode", ""))

    def test_tunnel_wrong_code_three_times_cancels(self):
        self.ps = {SID}
        pid = self.send(remote=True)["pendingId"]
        for _ in range(3):
            with self.assertRaises(ValueError):
                self.app.agent_message({"pendingId": pid, "code": "000000x"}, remote=True)
        with self.assertRaises(ValueError):
            self.app.agent_message({"pendingId": pid, "code": self._code()}, remote=True)
        self.assertEqual(self.inbox_files(), [])

    def test_tunnel_right_code_sends_stored_text(self):
        self.ps = {SID}
        pid = self.send("lệnh gốc", remote=True)["pendingId"]
        res = self.app.agent_message({"pendingId": pid, "code": self._code(), "text": "lệnh tráo"}, remote=True)
        self.assertTrue(res["ok"])
        with open(os.path.join(self.inbox, SID, self.inbox_files()[0])) as f:
            self.assertEqual(json.load(f)["text"], "lệnh gốc")
        with self.assertRaises(ValueError):
            self.app.agent_message({"pendingId": pid, "code": self._code()}, remote=True)  # dùng một lần

    def test_tunnel_code_expires(self):
        self.ps = {SID}
        pid = self.send(remote=True)["pendingId"]
        code = self._code()
        with mock.patch.object(server, "now", return_value=time.time() + 121):
            with self.assertRaises(ValueError):
                self.app.agent_message({"pendingId": pid, "code": code}, remote=True)
        self.assertEqual(self.inbox_files(), [])

    def _code(self):
        import re
        return re.search(r"\b(\d{6})\b", self.notified.call_args[0][0]).group(1)

    def test_card_session_is_latest_dispatch_of_the_card(self):
        self.assertEqual(self.app.card_session("agent-workbench", "323")["sid"], SID)
        self.assertEqual(self.app.card_session("AGENT-WORKBENCH", "323")["lane"], "build")
        for repo, issue in (("agent-workbench", "324"), ("khac", "323"), ("agent-workbench", "../323"), ("agent-workbench", "")):
            self.assertIsNone(self.app.card_session(repo, issue), (repo, issue))

    def test_open_code_requests_are_capped(self):
        self.ps = {SID}
        for _ in range(5):
            self.send(remote=True)
        self.app.msg_times = {}  # bỏ rate limit để thử riêng trần số lệnh chờ mã
        with self.assertRaises(ValueError):
            self.send(remote=True)

    def test_message_state_change_changes_state_version(self):
        self.ps = {SID}
        mid = self.send()["id"]
        self.app.rebuild()
        v1 = json.loads(self.app.state_bytes)["version"]
        os.makedirs(os.path.join(self.inbox, SID, "acks"))
        with open(os.path.join(self.inbox, SID, "acks", mid), "w") as f:
            f.write("1")
        self.app.poll_messages()
        self.app.events = self.app.events[:-1]  # chỉ đổi trạng thái lệnh, không tính sự kiện mới
        self.app.rebuild()
        self.assertNotEqual(json.loads(self.app.state_bytes)["version"], v1, "trang chỉ vẽ lại khi version đổi")

    def test_mac_sends_without_code(self):
        self.ps = {SID}
        self.assertTrue(self.send(remote=False)["ok"])
        self.notified.assert_not_called()


class LocalRequestTest(unittest.TestCase):
    """Chỉ request từ chính Mac (kết nối loopback, Host trong danh sách, không header tunnel) mới được coi là "từ Mac"."""

    def test_needs_loopback_peer(self):
        allowed = {"127.0.0.1", "localhost", "::1"}
        self.assertTrue(server.local_request({"Host": "localhost:4317"}, "127.0.0.1", allowed))
        self.assertTrue(server.local_request({"Host": "localhost"}, "::1", allowed))
        self.assertFalse(server.local_request({"Host": "127.0.0.1"}, "192.168.1.20", allowed), "máy khác trong LAN giả Host")
        self.assertFalse(server.local_request({"Host": "localhost", "Cf-Ray": "x"}, "127.0.0.1", allowed))
        self.assertFalse(server.local_request({"Host": "evil.example"}, "127.0.0.1", allowed))
        self.assertFalse(server.local_request({"Host": "localhost"}, "khong-phai-ip", allowed))


class HandlerRouteTest(unittest.TestCase):
    """Handler: from_mac quyết định remote; tunnel thiếu X-Agent-Office bị chặn; 429 / 202 đúng mã."""

    def test_handler_marks_tunnel_as_remote_and_maps_codes(self):
        cfg = server.deep_merge(server.DEFAULTS, {"eventsFile": "", "macNotify": False, "repos": []})
        app = server.App(cfg, demo=True)
        seen = []

        def fake(body, remote):
            seen.append(remote)
            if body.get("text") == "rate":
                raise server.RateLimited("chậm lại")
            return {"ok": False, "needCode": True, "pendingId": "p"} if remote else {"ok": True}
        app.agent_message = fake
        tmp = tempfile.mkdtemp()
        key_file = os.path.join(tmp, "remote-key")
        with open(key_file, "w") as f:
            f.write("k" * 43)
        with mock.patch.dict(os.environ, {"AGENT_OFFICE_KEY_FILE": key_file}):
            handler = server.make_handler(app)
        srv = server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        import threading
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            def post(host, extra, body):
                c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1], timeout=5)
                data = json.dumps(body).encode()
                c.putrequest("POST", "/api/agent-message", skip_host=True)
                c.putheader("Host", host)
                for k, v in extra.items():
                    c.putheader(k, v)
                c.putheader("Content-Length", str(len(data)))
                c.endheaders(data)
                r = c.getresponse()
                r.read()
                return r.status
            tunnel = {"Cf-Ray": "x", "X-Agent-Office": "1", "X-Agent-Office-Key": "k" * 43}
            self.assertEqual(post("localhost", {"X-Agent-Office": "1"}, {"text": "a"}), 200)
            self.assertEqual(post("a.trycloudflare.com", tunnel, {"text": "a"}), 202)
            self.assertEqual(seen, [False, True])
            self.assertEqual(post("localhost", {"X-Agent-Office": "1"}, {"text": "rate"}), 429)
            self.assertEqual(post("localhost", {}, {"text": "a"}), 403)
            self.assertEqual(post("a.trycloudflare.com", {"Cf-Ray": "x", "X-Agent-Office": "1"}, {"text": "a"}), 401)
            self.assertEqual(len(seen), 3)
        finally:
            srv.shutdown()
            srv.server_close()
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
