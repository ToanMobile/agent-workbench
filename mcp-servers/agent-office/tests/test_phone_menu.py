"""Menu "Điện thoại": máy Mac lấy link + QR của Cloudflare tunnel để quét bằng điện thoại ở mạng khác.

- GET /api/phone chỉ trả lời chính máy Mac: request đi qua tunnel bị 403 kể cả khi có key (key không được lộ qua tunnel);
- tunnel sống -> link = <url tunnel>/#key=<key> và QR SVG; tunnel chết -> live=false, không có key trong body;
- POST /api/phone chạy `ai-factory.sh phone` (chỉ tunnel, không bật board) rồi trả link mới.
"""
import http.client, json, os, shutil, socket, stat, subprocess, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(REPO, "ai-factory.sh")
KEY = "k" * 43
URL = "https://phone-menu-test.trycloudflare.com"
TUNNEL = {"Cf-Connecting-Ip": "203.0.113.7", "Cf-Ray": "8a1b2c3d4e5f-SIN"}


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_port(port, proc):
    for _ in range(80):
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close()
            return
        except OSError:
            time.sleep(0.1)
    proc.kill()
    proc.wait(5)
    raise RuntimeError("server did not start")


def req(port, method, path, host, headers=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
    c.putrequest(method, path, skip_host=True)
    c.putheader("Host", host)
    for k, v in (headers or {}).items():
        c.putheader(k, v)
    c.putheader("Content-Length", "2")
    c.endheaders(b"{}")
    r = c.getresponse()
    body = r.read()
    c.close()
    return r.status, body


class PhoneMenu(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.state = os.path.join(self.tmp, "state")
        os.makedirs(self.state)
        self.key_file = os.path.join(self.state, "remote-key")
        with open(self.key_file, "w") as f:
            f.write(KEY + "\n")
        self.procs = []
        self.port = free_port()
        self.factory = os.path.join(self.tmp, "fake-ai-factory.sh")
        # ai-factory.sh giả cho POST: ghi tunnel.log / tunnel.pid / remote-key như bản thật, bản ghi pid là một tiến trình "cloudflared"
        with open(self.factory, "w") as f:
            f.write(
                "#!/usr/bin/env bash\n"
                '[ "$1" = phone ] || exit 9\n'
                'S="$AGENT_OFFICE_STATE"\n'
                f'printf "%s\\n" "{KEY}" > "$S/remote-key"\n'
                f'echo "INF |  {URL.replace("phone-menu-test", "fresh-one")}  |" > "$S/tunnel.log"\n'
                f'nohup "{sys.executable}" -c "import time; time.sleep(60)" cloudflared >/dev/null 2>&1 &\n'
                'echo $! > "$S/tunnel.pid"\n'
                'echo $! > "$S/started-by-fake"\n'
            )
        os.chmod(self.factory, os.stat(self.factory).st_mode | stat.S_IEXEC)
        env = dict(os.environ, AGENT_OFFICE_KEY_FILE=self.key_file, AGENT_OFFICE_FACTORY_SCRIPT=self.factory)
        p = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(self.port)],
                             env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs.append(p)
        wait_port(self.port, p)

    def tearDown(self):
        pid_file = os.path.join(self.state, "started-by-fake")
        if os.path.exists(pid_file):
            try:
                os.kill(int(open(pid_file).read().strip()), 15)
            except (OSError, ValueError):
                pass
        for p in self.procs:
            if p.poll() is None:
                p.kill()
                p.wait(5)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def live_tunnel(self):
        """Tunnel 'sống': một tiến trình có chữ cloudflared trong argv, url trong tunnel.log."""
        t = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", "cloudflared"])
        self.procs.append(t)
        with open(os.path.join(self.state, "tunnel.pid"), "w") as f:
            f.write(str(t.pid))
        with open(os.path.join(self.state, "tunnel.log"), "w") as f:
            f.write(f"2026-10-23T13:54:01Z INF |  {URL}  |\nINF https://api.trycloudflare.com/tunnel\n")
        return t

    def test_mac_gets_link_and_qr_of_a_live_tunnel(self):
        self.live_tunnel()
        code, body = req(self.port, "GET", "/api/phone", "ai-factory.localhost")
        self.assertEqual(code, 200, body)
        data = json.loads(body)
        self.assertTrue(data["live"])
        self.assertEqual(data["url"], URL)
        self.assertEqual(data["link"], URL + "/#key=" + KEY)
        if shutil.which("qrencode"):
            self.assertIn("<svg", data["svg"])
        else:
            self.assertIsNone(data["svg"])

    def test_phone_info_is_refused_through_the_tunnel_even_with_the_key(self):
        self.live_tunnel()
        code, body = req(self.port, "GET", "/api/phone", "phone-menu-test.trycloudflare.com",
                         dict(TUNNEL, **{"X-Agent-Office-Key": KEY}))
        self.assertEqual(code, 403)
        self.assertNotIn(KEY.encode(), body)

    def test_dead_tunnel_reports_not_live_and_leaks_no_key(self):
        with open(os.path.join(self.state, "tunnel.pid"), "w") as f:
            f.write("999999")
        with open(os.path.join(self.state, "tunnel.log"), "w") as f:
            f.write(f"INF |  {URL}  |\n")
        code, body = req(self.port, "GET", "/api/phone", "ai-factory.localhost")
        self.assertEqual(code, 200, body)
        data = json.loads(body)
        self.assertFalse(data["live"])
        self.assertNotIn(KEY.encode(), body)

    def test_post_from_the_mac_opens_a_new_tunnel(self):
        code, body = req(self.port, "POST", "/api/phone", "ai-factory.localhost", {"X-Agent-Office": "1"})
        self.assertEqual(code, 200, body)
        data = json.loads(body)
        self.assertTrue(data["live"], data)
        self.assertEqual(data["url"], "https://fresh-one.trycloudflare.com")
        self.assertTrue(data["link"].endswith("/#key=" + KEY))

    def test_post_through_the_tunnel_is_refused(self):
        code, _ = req(self.port, "POST", "/api/phone", "x.trycloudflare.com",
                      dict(TUNNEL, **{"X-Agent-Office": "1", "X-Agent-Office-Key": KEY}))
        self.assertEqual(code, 403)
        self.assertFalse(os.path.exists(os.path.join(self.state, "started-by-fake")), "tunnel request started a tunnel")

    # Mỗi nửa của "chỉ máy Mac" phải tự chặn được: cloudflared có thể chuyển tiếp Host local (xem
    # test_remote_key.test_tunnel_with_a_local_host_header_still_needs_the_key), và Host tunnel thì không bao giờ là máy Mac.
    def test_local_host_header_through_the_tunnel_is_refused(self):
        self.live_tunnel()
        tun = dict(TUNNEL, **{"X-Agent-Office-Key": KEY})
        code, body = req(self.port, "GET", "/api/phone", "ai-factory.localhost", tun)
        self.assertEqual(code, 403)
        self.assertNotIn(KEY.encode(), body)
        code, _ = req(self.port, "POST", "/api/phone", "ai-factory.localhost", dict(tun, **{"X-Agent-Office": "1"}))
        self.assertEqual(code, 403)
        self.assertFalse(os.path.exists(os.path.join(self.state, "started-by-fake")), "tunnel request started a tunnel")

    def test_tunnel_host_without_cloudflare_headers_is_refused(self):
        self.live_tunnel()
        code, body = req(self.port, "GET", "/api/phone", "phone-menu-test.trycloudflare.com", {"X-Agent-Office-Key": KEY})
        self.assertEqual(code, 403)
        self.assertNotIn(KEY.encode(), body)


class PhoneMenuBrokenFactory(unittest.TestCase):
    """ai-factory.sh không có (vd. server chạy từ bản chép autostart mà không biết đường dẫn): POST báo lỗi, không im lặng."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        key_file = os.path.join(self.tmp, "remote-key")
        with open(key_file, "w") as f:
            f.write(KEY + "\n")
        self.port = free_port()
        env = dict(os.environ, AGENT_OFFICE_KEY_FILE=key_file,
                   AGENT_OFFICE_FACTORY_SCRIPT=os.path.join(self.tmp, "no-such-ai-factory.sh"))
        self.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(self.port)],
                                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_port(self.port, self.proc)

    def tearDown(self):
        self.proc.kill()
        self.proc.wait(5)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_missing_factory_script_is_reported(self):
        code, body = req(self.port, "POST", "/api/phone", "ai-factory.localhost", {"X-Agent-Office": "1"})
        data = json.loads(body)
        self.assertEqual(code, 502, body)
        self.assertFalse(data["ok"])
        self.assertIn("ai-factory", data["error"])
        self.assertNotIn(KEY, data["error"])


class FactoryPhoneCommand(unittest.TestCase):
    """`ai-factory.sh phone` mở tunnel + key mới nhưng KHÔNG bật board (khác `ai-factory` start)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        root = os.path.join(self.tmp, "repo")
        self.home = os.path.join(self.tmp, "home")
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(os.path.join(root, "universal-agent-devkit/scripts/governance"))
        os.makedirs(os.path.join(root, "mcp-servers/agent-office"))
        os.makedirs(self.bin)
        shutil.copy(SCRIPT, os.path.join(root, "ai-factory.sh"))
        self.marker = os.path.join(self.tmp, "boards-touched")
        with open(os.path.join(root, "universal-agent-devkit/scripts/governance/super_board_all.py"), "w") as f:
            f.write(f"open({self.marker!r}, 'a').write('boards\\n')\n")
        self.port = free_port()
        with open(os.path.join(root, "mcp-servers/agent-office/config.json"), "w") as f:
            f.write('{"port": %d}\n' % self.port)
        # cloudflared giả: in url như bản thật rồi chờ
        cf = os.path.join(self.bin, "cloudflared")
        with open(cf, "w") as f:
            f.write("#!/usr/bin/env bash\necho 'INF |  https://cmd-test.trycloudflare.com  |'\nexec sleep 60\n")
        os.chmod(cf, 0o755)
        self.script = os.path.join(root, "ai-factory.sh")
        self.state = os.path.join(self.home, ".agent-office")
        self.procs = []
        p = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(self.port)],
                             env=dict(os.environ, AGENT_OFFICE_KEY_FILE=os.path.join(self.tmp, "unused-key")),
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs.append(p)
        wait_port(self.port, p)

    def tearDown(self):
        pid_file = os.path.join(self.state, "tunnel.pid")
        if os.path.exists(pid_file):
            try:
                os.kill(int(open(pid_file).read().strip()), 15)
            except (OSError, ValueError):
                pass
        for p in self.procs:
            if p.poll() is None:
                p.kill()
                p.wait(5)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_phone_opens_tunnel_without_touching_boards(self):
        env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"])
        env.pop("AGENT_OFFICE_STATE", None)   # biến của người chạy test trỏ vào state thật: script sẽ giết tunnel thật
        r = subprocess.run(["bash", self.script, "phone"], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("https://cmd-test.trycloudflare.com", r.stdout)
        self.assertTrue(os.path.getsize(os.path.join(self.state, "remote-key")) > 20)
        self.assertFalse(os.path.exists(self.marker), "ai-factory phone started the boards")


if __name__ == "__main__":
    unittest.main()
