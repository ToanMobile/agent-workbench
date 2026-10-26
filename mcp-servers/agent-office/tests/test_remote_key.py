"""Remote access through a Cloudflare quick tunnel needs the per-run secret key; the Mac itself does not."""
import http.client, os, socket, subprocess, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = "k" * 43  # same length as secrets.token_urlsafe(32)
TUNNEL = {"Cf-Connecting-Ip": "203.0.113.7", "Cf-Ray": "8a1b2c3d4e5f-SIN"}


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def start(key_file):
    port = free_port()
    env = dict(os.environ, AGENT_OFFICE_KEY_FILE=key_file)
    proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(port)],
                            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close()
            return proc, port
        except OSError:
            time.sleep(0.1)
    proc.kill()
    proc.wait(5)
    raise RuntimeError("server did not start")


def req(port, method, path, host, headers=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.putrequest(method, path, skip_host=True)
    c.putheader("Host", host)
    for k, v in (headers or {}).items():
        c.putheader(k, v)
    # a body only on POST: the server answers a GET without reading it and closes with bytes unread, which sends a RST that can
    # cut the page off ("Connection reset by peer" in 17-27 of 900 GETs at 3 threads, 0 of 900 without the body; #430)
    body = b"{}" if method == "POST" else None
    if body:
        c.putheader("Content-Length", str(len(body)))
    c.endheaders(body)
    r = c.getresponse()
    r.read()
    c.close()
    return r.status


class RemoteKey(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.key_file = os.path.join(cls.tmp.name, "remote-key")
        with open(cls.key_file, "w") as f:
            f.write(KEY + "\n")
        cls.proc, cls.port = start(cls.key_file)

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)
        cls.tmp.cleanup()

    def test_tunnel_api_without_key_is_refused(self):
        self.assertEqual(req(self.port, "GET", "/api/state", "abc-def.trycloudflare.com", TUNNEL), 401)

    def test_tunnel_api_with_wrong_key_is_refused(self):
        h = dict(TUNNEL, **{"X-Agent-Office-Key": "x" * 43})
        self.assertEqual(req(self.port, "GET", "/api/state", "abc-def.trycloudflare.com", h), 401)

    def test_tunnel_api_with_key_is_served(self):
        h = dict(TUNNEL, **{"X-Agent-Office-Key": KEY})
        self.assertEqual(req(self.port, "GET", "/api/state", "abc-def.trycloudflare.com", h), 200)

    def test_tunnel_page_itself_loads_without_key(self):  # the page carries no data; it reads the key from the QR link
        self.assertEqual(req(self.port, "GET", "/", "abc-def.trycloudflare.com", TUNNEL), 200)

    def test_tunnel_refresh_and_writes_need_the_key(self):
        self.assertEqual(req(self.port, "GET", "/api/refresh", "abc-def.trycloudflare.com", TUNNEL), 401)
        no_key = dict(TUNNEL, **{"X-Agent-Office": "1"})
        self.assertEqual(req(self.port, "POST", "/api/nope", "abc-def.trycloudflare.com", no_key), 401)
        with_key = dict(no_key, **{"X-Agent-Office-Key": KEY})
        self.assertNotIn(req(self.port, "POST", "/api/nope", "abc-def.trycloudflare.com", with_key), (401, 403))

    def test_tunnel_with_a_local_host_header_still_needs_the_key(self):
        self.assertEqual(req(self.port, "GET", "/api/state", "127.0.0.1:%d" % self.port, TUNNEL), 401)

    def test_the_mac_itself_needs_no_key(self):
        self.assertEqual(req(self.port, "GET", "/api/state", "127.0.0.1:%d" % self.port), 200)
        self.assertEqual(req(self.port, "GET", "/api/state", "ai-factory.localhost:%d" % self.port), 200)

    def test_other_foreign_hosts_stay_blocked(self):
        self.assertEqual(req(self.port, "GET", "/api/state", "evil.example", TUNNEL), 403)


class RemoteOffWithoutKey(unittest.TestCase):
    def test_tunnel_host_is_refused_when_no_key_file_exists(self):
        with tempfile.TemporaryDirectory() as d:
            proc, port = start(os.path.join(d, "missing-key"))
            try:
                self.assertEqual(req(port, "GET", "/", "abc-def.trycloudflare.com", TUNNEL), 403)
                h = dict(TUNNEL, **{"X-Agent-Office-Key": KEY})
                self.assertEqual(req(port, "GET", "/api/state", "abc-def.trycloudflare.com", h), 403)
            finally:
                proc.terminate()
                proc.wait(5)


if __name__ == "__main__":
    unittest.main()
