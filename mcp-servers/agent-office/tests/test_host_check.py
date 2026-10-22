"""Host check on every request: DNS rebinding must not read /api/state or write."""
import http.client, os, socket, subprocess, sys, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class HostCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        cls.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(cls.port)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", cls.port), 0.2).close()
                return
            except OSError:
                time.sleep(0.1)
        cls.proc.kill()
        cls.proc.wait(5)
        raise RuntimeError("server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)

    def req(self, method, path, host, headers=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.putrequest(method, path, skip_host=True)
        c.putheader("Host", host)
        for k, v in (headers or {}).items():
            c.putheader(k, v)
        c.putheader("Content-Length", "2")
        c.endheaders(b"{}")
        r = c.getresponse()
        r.read()
        c.close()
        return r.status

    def test_get_state_rejects_foreign_host(self):
        self.assertEqual(self.req("GET", "/api/state", "evil.example:%d" % self.port), 403)

    def test_get_page_rejects_foreign_host(self):
        self.assertEqual(self.req("GET", "/", "evil.example"), 403)

    def test_get_state_allows_local_names(self):
        for h in ("127.0.0.1:%d" % self.port, "localhost:%d" % self.port, "ai-factory.test:%d" % self.port, "ai-factory.localhost:%d" % self.port):
            self.assertEqual(self.req("GET", "/api/state", h), 200, h)

    def test_get_refresh_rejects_foreign_host(self):
        self.assertEqual(self.req("GET", "/api/refresh", "evil.example"), 403)

    def test_host_parsing_is_strict(self):
        p = self.port
        for h in ("[::1]:%d" % p, "LOCALHOST:%d" % p):
            self.assertEqual(self.req("GET", "/api/state", h), 200, h)
        for h in ("127.0.0.1:80@evil.example", "localhost:evil.example", "[::1]evil.example", "localhost.", ""):
            self.assertEqual(self.req("GET", "/api/state", h), 403, h)

    def test_post_rejects_foreign_host(self):
        self.assertEqual(self.req("POST", "/api/move", "evil.example", {"X-Agent-Office": "1"}), 403)

    def test_post_allows_ai_factory_test(self):
        self.assertNotEqual(self.req("POST", "/api/nope", "ai-factory.test:%d" % self.port, {"X-Agent-Office": "1"}), 403)


if __name__ == "__main__":
    unittest.main()
