"""Nút "Chạy gate full" (gate_full_runner.py + POST /api/gate-full): lệnh lấy từ plist lịch đêm, hàng đợi FIFO bỏ trùng, lưu qua
khởi động lại, đúng MỘT lượt mỗi lúc (khoá toàn máy), chỉ máy Mac bấm được. KHÔNG BAO GIỜ chạy gate_full.py thật: plist trong thư mục
LaunchAgents giả trỏ tới một gate_full.py giả (ghi lúc bắt đầu / kết thúc, giữ khoá toàn máy giả như bản thật)."""
import datetime as dt
import fcntl
import http.client
import json
import os
import plistlib
import shutil
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import gate_full_runner as gfr  # noqa: E402
import server  # noqa: E402

FAKE = r'''import fcntl, json, os, sys, time
calls = os.environ["FAKE_CALLS"]; repo = sys.argv[sys.argv.index("--repo") + 1]
fd = os.open(os.environ["DEVKIT_GATE_FULL_GLOBAL_LOCK"], os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)  # như gate_full.py: chờ khoá toàn máy
os.ftruncate(fd, 0); os.write(fd, json.dumps({"pid": os.getpid(), "repo": repo}).encode())
with open(calls, "a") as f: f.write("start %s %.3f\n" % (os.path.basename(repo), time.time()))
time.sleep(float(os.environ.get("FAKE_SLEEP", "0.6")))
d = os.environ["DEVKIT_GATE_FULL_LOG_DIR"]; os.makedirs(d, exist_ok=True)
with open(os.path.join(d, "summary-latest.md"), "w") as f:
    f.write("# gate-full\n\n- Kết quả: **XANH**\n- Log: %s/x.log\n" % d)
with open(calls, "a") as f: f.write("end %s %.3f\n" % (os.path.basename(repo), time.time()))
'''


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.la = os.path.join(self.tmp, "LaunchAgents")
        os.makedirs(self.la)
        os.makedirs(os.path.join(self.tmp, "kit"))
        self.fake = os.path.join(self.tmp, "kit", "gate_full.py")
        with open(self.fake, "w") as f:
            f.write(FAKE)
        self.calls = os.path.join(self.tmp, "calls.txt")
        self.glock = os.path.join(self.tmp, "global.lock")
        self.env = mock.patch.dict(os.environ, {"FAKE_CALLS": self.calls, "DEVKIT_GATE_FULL_GLOBAL_LOCK": self.glock})
        self.env.start()
        self.repos = {}
        for name in ("alpha", "beta", "nolịch"):
            p = os.path.join(self.tmp, name)
            os.makedirs(os.path.join(p, ".git"))
            self.repos[name] = p
            if name != "nolịch":
                self.install(name, p)
        self.cfg = {"gateFull": {"launchAgentsDir": self.la, "queueFile": os.path.join(self.tmp, "q.json")}}
        self.g = gfr.GateFull(self.cfg)

    def tearDown(self):
        if self.g.proc:
            self.g.proc.wait(10)
        self.env.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def install(self, name, path):
        log = os.path.join(self.tmp, "logs", name)
        data = {"Label": gfr.LABEL_PREFIX + name, "ProgramArguments": [sys.executable, self.fake, "run", "--repo", path],
                "WorkingDirectory": path, "StartCalendarInterval": {"Hour": 0, "Minute": 0},
                "EnvironmentVariables": {"DEVKIT_GATE_FULL_LOG_DIR": log, "TZ": "Asia/Ho_Chi_Minh"}}
        with open(os.path.join(self.la, gfr.LABEL_PREFIX + name + ".plist"), "wb") as f:
            plistlib.dump(data, f)

    def lines(self):
        try:
            with open(self.calls) as f:
                return [ln.split() for ln in f.read().splitlines()]
        except OSError:
            return []

    def drain(self, timeout=20):
        end = time.time() + timeout
        while time.time() < end:
            self.g.tick(self.repos)
            if not self.g.queue and self.g.proc is None:
                return
            time.sleep(0.05)
        self.fail("hàng chờ không chạy hết")


class QueueTest(Fixture):
    def test_fifo_dedupe_and_persist(self):
        self.assertEqual(self.g.enqueue("alpha", self.repos)["position"], 1)
        r = self.g.enqueue("alpha", self.repos)
        self.assertTrue(r["already"])
        self.assertEqual(self.g.enqueue("beta", self.repos)["position"], 2)
        self.assertEqual(self.g.queue, ["alpha", "beta"])
        again = gfr.GateFull(self.cfg)  # server khởi động lại
        self.assertEqual(again.queue, ["alpha", "beta"], "hàng chờ phải còn sau khi khởi động lại")

    def test_not_installed_refused(self):
        with self.assertRaises(ValueError) as e:
            self.g.enqueue("nolịch", self.repos)
        self.assertIn("gate-full-schedule.sh install", str(e.exception))
        with self.assertRaises(ValueError):
            self.g.enqueue("không-có", self.repos)

    def test_one_run_at_a_time_in_fifo_order(self):
        self.g.enqueue("beta", self.repos)
        self.g.enqueue("alpha", self.repos)
        self.g.tick(self.repos)
        self.assertEqual(self.g.running["repo"], "beta")
        st = self.g.status(self.repos)["repos"]
        self.assertEqual(st["beta"]["state"], "running")
        self.assertEqual(st["alpha"]["state"], "queued")
        self.assertTrue(self.g.enqueue("beta", self.repos)["already"], "bấm repo đang chạy: chỉ báo trạng thái")
        self.assertEqual(self.g.queue, ["alpha"])
        time.sleep(0.2)
        self.g.tick(self.repos)
        self.assertEqual(self.g.running["repo"], "beta", "lượt kế không mở khi lượt trước chưa xong")
        self.drain()
        ev = self.lines()
        self.assertEqual([e[0] + e[1] for e in ev], ["startbeta", "endbeta", "startalpha", "endalpha"])
        self.assertLessEqual(float(ev[1][2]), float(ev[2][2]), "hai lượt chồng nhau")
        last = self.g.status(self.repos)["repos"]["alpha"]["last"]
        self.assertEqual(last["verdict"], "PASS")
        self.assertTrue([n for n in os.listdir(os.path.join(self.tmp, "logs", "beta")) if n.startswith("manual-")], "log chạy tay")

    def test_waits_while_global_lock_held_by_nightly(self):
        fd = os.open(self.glock, os.O_RDWR | os.O_CREAT)
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.write(fd, json.dumps({"pid": os.getpid(), "repo": "/x/nightly"}).encode())
        try:
            self.g.enqueue("alpha", self.repos)
            self.g.tick(self.repos)
            self.assertIsNone(self.g.proc, "lượt đêm đang giữ khoá toàn máy: không mở lượt mới")
            st = self.g.status(self.repos)
            self.assertTrue(st["busy"])
            self.assertEqual(st["repos"]["alpha"]["state"], "queued")
        finally:
            os.close(fd)
        self.drain()
        self.assertEqual([e[0] + e[1] for e in self.lines()], ["startalpha", "endalpha"])

    def test_cancel_queued_only(self):
        self.g.enqueue("alpha", self.repos)
        self.g.enqueue("beta", self.repos)
        self.g.tick(self.repos)  # alpha chạy
        self.assertEqual(self.g.cancel("beta"), {"ok": True})
        self.assertEqual(gfr.GateFull(self.cfg).queue, [])
        with self.assertRaises(ValueError):
            self.g.cancel("alpha")
        self.drain()

    def test_status_reads_nightly_repo_lock_without_flock(self):
        d = os.path.join(self.repos["alpha"], ".git", "postfix-gate")
        os.makedirs(d)
        with open(os.path.join(d, "gate-full.lock"), "w") as f:
            json.dump({"pid": os.getpid(), "started": "2026-10-31T00:00:05"}, f)
        st = self.g.status(self.repos)["repos"]["alpha"]
        self.assertEqual(st["state"], "running")
        self.assertEqual(st["since"], dt.datetime(2026, 10, 31, 0, 0, 5).timestamp())
        with open(os.path.join(d, "gate-full.lock"), "w") as f:
            json.dump({"pid": 999999, "started": "x"}, f)
        self.assertEqual(self.g.status(self.repos)["repos"]["alpha"]["state"], "idle", "khoá mồ côi (pid chết) không tính là đang chạy")
        nxt = self.g.status(self.repos)["repos"]["alpha"]["next"]
        self.assertEqual(dt.datetime.fromtimestamp(nxt).strftime("%H:%M"), "00:00")


class EndpointTest(Fixture):
    def test_mac_only_and_runs(self):
        cfg = server.deep_merge(server.DEFAULTS, {"eventsFile": "", "macNotify": False, "repos": [], **self.cfg})
        app = server.App(cfg, demo=True)
        app.gate_repo_paths = lambda: self.repos
        self.g = app.gatefull
        key_file = os.path.join(self.tmp, "remote-key")
        with open(key_file, "w") as f:
            f.write("k" * 43)
        with mock.patch.dict(os.environ, {"AGENT_OFFICE_KEY_FILE": key_file}):
            handler = server.make_handler(app)
        srv = server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()

        def post(host, extra, body):
            c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1], timeout=10)
            data = json.dumps(body).encode()
            c.putrequest("POST", "/api/gate-full", skip_host=True)
            c.putheader("Host", host)
            for k, v in extra.items():
                c.putheader(k, v)
            c.putheader("Content-Length", str(len(data)))
            c.endheaders(data)
            r = c.getresponse()
            return r.status, json.loads(r.read() or b"{}")
        try:
            tunnel = {"Cf-Ray": "x", "X-Agent-Office": "1", "X-Agent-Office-Key": "k" * 43}
            self.assertEqual(post("a.trycloudflare.com", tunnel, {"repo": "alpha"})[0], 403, "điện thoại / tunnel không chạy được")
            self.assertEqual(post("localhost", {}, {"repo": "alpha"})[0], 403, "thiếu X-Agent-Office (CSRF)")
            self.assertEqual(post("evil.example", {"X-Agent-Office": "1"}, {"repo": "alpha"})[0], 403, "DNS rebinding")
            self.assertEqual(self.lines(), [])
            code, res = post("localhost", {"X-Agent-Office": "1"}, {"repo": "nolịch"})
            self.assertEqual(code, 400)
            code, res = post("localhost", {"X-Agent-Office": "1"}, {"repo": "alpha"})
            self.assertEqual((code, res.get("ok")), (200, True))
            code, res = post("localhost", {"X-Agent-Office": "1"}, {"repo": "beta"})
            self.assertEqual(res.get("state"), "queued")
            st = json.loads(app.state_bytes)["gateFull"]
            self.assertEqual(st["repos"]["alpha"]["state"], "running")
            self.assertEqual(st["repos"]["beta"]["state"], "queued")
            code, res = post("localhost", {"X-Agent-Office": "1"}, {"repo": "beta", "cancel": True})
            self.assertEqual((code, res.get("ok")), (200, True))
            self.drain()
            self.assertEqual([e[0] + e[1] for e in self.lines()], ["startalpha", "endalpha"])
        finally:
            srv.shutdown()
            srv.server_close()


if __name__ == "__main__":
    unittest.main()
