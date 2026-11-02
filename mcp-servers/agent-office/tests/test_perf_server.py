"""Hiệu năng server (BUG-REV-AO-PERF-2):
- /api/state nén gzip (thật ~480 KB JSON mỗi 3 giây -> ~115 KB), nén một lần cho mỗi lần dựng;
- liệt kê transcript tăng dần: không glob lại ~5000 file / ~3500 thư mục của ~/.claude/projects mỗi 3 giây (~100 ms CPU mỗi vòng).
"""
import gzip
import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


class GzipHelpers(unittest.TestCase):
    def test_gzip_ok(self):
        self.assertTrue(server.gzip_ok("gzip, deflate, br"))
        self.assertTrue(server.gzip_ok("br;q=1.0, gzip;q=0.8"))
        self.assertTrue(server.gzip_ok("*"))
        self.assertFalse(server.gzip_ok("gzip;q=0"))
        self.assertFalse(server.gzip_ok("identity"))
        self.assertFalse(server.gzip_ok(""))
        self.assertFalse(server.gzip_ok(None))

    def test_cache_compresses_once_per_body(self):
        c = server.GzipCache()
        body = json.dumps({"items": [{"title": "việc %d" % i} for i in range(500)]}, ensure_ascii=False).encode()
        a = c.get(body)
        self.assertIs(c.get(body), a, "cùng một state_bytes: dùng lại bản nén, không nén lại")
        self.assertEqual(gzip.decompress(a), body)
        self.assertLess(len(a), len(body) / 3)
        body2 = body + b" "
        self.assertEqual(gzip.decompress(c.get(body2)), body2, "state mới: nén lại")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class GzipHttp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.port = free_port()
        cfg = os.path.join(cls.tmp, "c.json")
        with open(cfg, "w") as f:
            json.dump({"macNotify": False, "eventsFile": os.path.join(cls.tmp, "e.jsonl"), "inboxDir": os.path.join(cls.tmp, "i"),
                       "resumeLogDir": os.path.join(cls.tmp, "r")}, f)
        cls.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--config", cfg, "--port", str(cls.port)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(80):
            try:
                socket.create_connection(("127.0.0.1", cls.port), 0.2).close()
                break
            except OSError:
                time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)

    def get(self, headers):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/state", headers=dict({"Host": "127.0.0.1:%d" % self.port}, **headers))
        r = c.getresponse()
        return r, r.read()

    def test_gzip_when_accepted(self):
        r, body = self.get({"Accept-Encoding": "gzip"})
        self.assertEqual(r.status, 200)
        self.assertEqual(r.getheader("Content-Encoding"), "gzip")
        self.assertIn("Accept-Encoding", r.getheader("Vary") or "")
        self.assertEqual(int(r.getheader("Content-Length")), len(body))
        st = json.loads(gzip.decompress(body))
        self.assertIn("items", st)

    def test_plain_without_accept_encoding(self):
        r, body = self.get({})
        self.assertEqual(r.status, 200)
        self.assertIsNone(r.getheader("Content-Encoding"))
        self.assertIn("items", json.loads(body))


class IncrementalScan(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.proj = os.path.join(self.tmp, "projects")
        self.root = os.path.join(self.tmp, "code")
        os.makedirs(self.root)
        self.pdir = os.path.join(self.proj, server.encode_path(self.root) + "-repo")
        os.makedirs(os.path.join(self.pdir, "sess1", "subagents"))
        self.sc = server.LocalScanner({"claudeProjectsDir": self.proj, "root": self.root, "lookbackMinutes": 60})

    def write(self, rel, mtime=None):
        p = os.path.join(self.pdir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a") as f:
            f.write(json.dumps({"timestamp": "2026-01-01T00:00:00Z", "cwd": self.root}) + "\n")
        if mtime is not None:
            os.utime(p, (mtime, mtime))
        return p

    def files(self):
        return sorted(s["file"] for s in self.sc.scan_sessions()[0])

    def test_matches_glob_and_sees_new_files_between_full_scans(self):
        a = self.write("a.jsonl")
        b = self.write("sess1/subagents/b.jsonl")
        self.write(".hidden/c.jsonl")  # như glob "**": mục ẩn bị bỏ
        self.write("sess1/old.jsonl", mtime=time.time() - 7200)
        self.assertEqual(self.files(), sorted([a, b]))
        time.sleep(0.01)
        n = self.write("sess1/new.jsonl")  # file mới trong thư mục cũ: mtime thư mục đổi -> thấy ngay, không đợi quét đầy đủ
        self.assertEqual(self.files(), sorted([a, b, n]))
        os.remove(a)
        self.assertEqual(self.files(), sorted([b, n]))

    def test_cold_files_not_statted_until_full_scan(self):
        old = self.write("sess1/old.jsonl", mtime=time.time() - 7200)
        self.assertEqual(self.files(), [])
        calls = []
        real = os.stat

        def spy(p, *a, **k):
            calls.append(p)
            return real(p, *a, **k)
        server.os.stat = spy
        try:
            self.files()
        finally:
            server.os.stat = real
        self.assertNotIn(old, calls, "file đã cũ không bị stat lại mỗi vòng")
        os.utime(old, None)  # phiên cũ được resume: ghi nối, thư mục không đổi
        self.assertEqual(self.files(), [], "giữa hai lần quét đầy đủ chưa thấy (trễ tối đa FULL_EVERY)")
        self.sc.last_full -= self.sc.FULL_EVERY
        self.assertEqual(self.files(), [old], "quét đầy đủ thấy phiên cũ vừa ghi")

    def test_removed_directory_dropped_from_cache(self):
        p = self.write("gone/x.jsonl")
        self.assertEqual(self.files(), [p])
        os.remove(p)
        os.rmdir(os.path.dirname(p))
        self.assertEqual(self.files(), [])
        self.sc.last_full -= self.sc.FULL_EVERY
        self.files()
        self.assertFalse([k for k in self.sc.dir_cache if k.endswith("gone")])


if __name__ == "__main__":
    unittest.main()
