"""Bảng điều khiển CC Switcher (chuyển từ Telegram sang /cc-switcher): trang, API trạng thái và thao tác; chỉ máy Mac dùng được."""
import http.client, json, os, secrets, shutil, socket, subprocess, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CCS_BIN = os.path.join(os.path.dirname(HERE), "cc-switcher-mcp", "bin", "cc-switcher-mcp.js")
KEY = secrets.token_urlsafe(32)  # key giả, sinh lúc chạy
TUNNEL = {"Cf-Connecting-Ip": "203.0.113.7", "Cf-Ray": "8a1b2c3d4e5f-SIN"}
SECRET = "AAH" + secrets.token_hex(16)  # token Telegram giả, sinh lúc chạy


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@unittest.skipUnless(shutil.which("node") and os.path.isfile(CCS_BIN), "cần node và cc-switcher-mcp")
class CcSwitcherPanel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.state = os.path.join(cls.tmp.name, "cc-switch")
        os.makedirs(cls.state)
        with open(os.path.join(cls.state, "settings.json"), "w") as f:
            json.dump({"currentProviderClaude": "finos"}, f)
        with open(os.path.join(cls.state, "repos.json"), "w") as f:   # không đụng 6 repo thật trên máy
            json.dump({"custom": [], "hidden": [], "defaults": False}, f)
        cls.repo = os.path.join(cls.tmp.name, "code", "demo-repo")
        os.makedirs(os.path.join(cls.repo, ".git"))
        os.makedirs(os.path.join(cls.repo, ".claude"))
        with open(os.path.join(cls.repo, ".claude", "settings.local.json"), "w") as f:
            json.dump({"hooks": {"Stop": []}}, f)
        with open(os.path.join(cls.state, "telegram.env"), "w") as f:
            f.write(f"TELEGRAM_BOT_TOKEN=123456789:{SECRET}\nTELEGRAM_CHAT_ID=55667788\n")
        cls.key_file = os.path.join(cls.tmp.name, "remote-key")
        with open(cls.key_file, "w") as f:
            f.write(KEY + "\n")
        cls.port = free_port()
        env = dict(os.environ, AGENT_OFFICE_KEY_FILE=cls.key_file, AGENT_OFFICE_CC_SWITCHER=CCS_BIN,
                   AGENT_OFFICE_CC_SWITCHER_STATE_DIR=cls.state)
        env.pop("TELEGRAM_BOT_TOKEN", None)
        env.pop("TELEGRAM_CHAT_ID", None)
        cls.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py"), "--demo", "--port", str(cls.port)],
                                    env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(80):
            try:
                socket.create_connection(("127.0.0.1", cls.port), 0.2).close()
                return
            except OSError:
                time.sleep(0.1)
        cls.proc.kill()
        raise RuntimeError("server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(5)
        cls.tmp.cleanup()

    def req(self, method, path, host="ai-factory.localhost:4317", headers=None, body=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
        c.putrequest(method, path, skip_host=True)
        c.putheader("Host", host)
        for k, v in (headers or {}).items():
            c.putheader(k, v)
        data = json.dumps(body).encode() if body is not None else (b"{}" if method == "POST" else None)
        if data is not None:
            c.putheader("Content-Type", "application/json")
            c.putheader("Content-Length", str(len(data)))
        c.endheaders(data)
        r = c.getresponse()
        raw = r.read()
        c.close()
        return r.status, raw

    def post(self, body, **kw):
        h = {"X-Agent-Office": "1", **kw.pop("headers", {})}
        return self.req("POST", "/api/cc-switcher/action", headers=h, body=body, **kw)

    def test_page_served_on_ai_factory_localhost(self):
        for path in ("/cc-switcher", "/cc-switcher/"):
            code, raw = self.req("GET", path)
            self.assertEqual(code, 200, path)
            html = raw.decode("utf-8")
            self.assertIn("<title>CC Switcher", html)
            self.assertIn("/api/cc-switcher/state", html)
            self.assertIn("Repo ↔ Tài khoản", html)
        code, raw = self.req("GET", "/")
        self.assertEqual(code, 200)
        self.assertIn('id="btnCcs"', raw.decode("utf-8"))  # nút mở trang từ Xưởng agent

    def test_state_has_six_accounts_and_no_secrets(self):
        code, raw = self.req("GET", "/api/cc-switcher/state")
        self.assertEqual(code, 200, raw[:300])
        st = json.loads(raw)
        self.assertTrue(st["ok"])
        self.assertEqual(len(st["profiles"]), 6)
        self.assertEqual(st["activeProfileId"], "finos")
        self.assertTrue(st["health"]["telegram"]["configured"])
        text = raw.decode("utf-8")
        self.assertNotIn(SECRET, text)
        self.assertNotIn("55667788", text)

    def test_switch_cooldown_and_validation(self):
        code, raw = self.post({"action": "switch", "target": "grok"})
        self.assertEqual(code, 200, raw[:300])
        res = json.loads(raw)
        self.assertTrue(res["ok"])
        self.assertEqual(res["state"]["activeProfileId"], "grok")
        code, raw = self.post({"action": "cooldown", "minutes": 5})
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(raw)["state"]["antiBan"]["cooldownMinutes"], 5)
        for bad in ({"action": "rm"}, {"action": "switch", "target": "../x"}, {"action": "cooldown", "minutes": "5"},
                    {"action": "cooldown", "minutes": 99999}, {"action": "balance", "mode": "all_finos"}):
            code, _ = self.post(bad)
            self.assertEqual(code, 400, bad)
        self.post({"action": "switch", "target": "finos", "force": True})
        self.post({"action": "cooldown", "minutes": 15})

    def test_writes_need_header_and_come_from_mac_only(self):
        code, _ = self.req("POST", "/api/cc-switcher/action", body={"action": "rotate"})  # thiếu X-Agent-Office
        self.assertEqual(code, 403)
        # qua tunnel, kể cả đúng key: không đọc, không ghi
        h = {**TUNNEL, "X-Agent-Office-Key": KEY}
        code, _ = self.req("GET", "/api/cc-switcher/state", host="abc.trycloudflare.com", headers=h)
        self.assertEqual(code, 403)
        code, _ = self.post({"action": "rotate"}, host="abc.trycloudflare.com", headers=h)
        self.assertEqual(code, 403)
        code, _ = self.req("GET", "/cc-switcher", host="abc.trycloudflare.com", headers=h)
        self.assertEqual(code, 403)
        # DNS rebinding: Host lạ bị chặn
        code, _ = self.req("GET", "/api/cc-switcher/state", host="evil.example")
        self.assertEqual(code, 403)
        st = json.loads(self.req("GET", "/api/cc-switcher/state")[1])
        self.assertEqual(st["activeProfileId"], "finos")


    def settings(self):
        with open(os.path.join(self.repo, ".claude", "settings.local.json")) as f:
            return json.load(f)

    def test_repo_account_table_assign_add_remove(self):
        code, raw = self.post({"action": "repo_add", "repo": self.repo, "account": "finos", "name": "Demo Repo"})
        self.assertEqual(code, 200, raw[:300])
        res = json.loads(raw)
        rows = res["state"]["repoAssignments"]
        self.assertEqual([(r["name"], r["path"], r["account"]) for r in rows], [("Demo Repo", self.repo, "finos")])
        row = rows[0]
        for k in ("group", "effective", "differs", "worktrees", "lastUsedAtMs", "lastUsedAccount", "pinnedInFile"):
            self.assertIn(k, row)
        self.assertEqual(row["effective"]["kind"], "assigned")
        self.assertEqual(res["state"]["claudeAccounts"], ["finos", "finos_team", "max"])

        code, raw = self.post({"action": "repo_assign", "repo": self.repo, "account": "max"})
        self.assertEqual(code, 200, raw[:300])
        self.assertEqual(self.settings(), {"hooks": {"Stop": []}, "account": "max"})
        st = json.loads(self.req("GET", "/api/cc-switcher/state")[1])
        self.assertEqual(st["repoAssignments"][0]["account"], "max")

        for bad in ({"action": "repo_assign", "repo": self.repo, "account": "grok"},
                    {"action": "repo_assign", "repo": "relative/path", "account": "finos"},
                    {"action": "repo_assign", "repo": self.repo + "\n--force", "account": "finos"},
                    {"action": "repo_assign", "repo": "/etc", "account": "finos"},
                    {"action": "repo_add", "repo": self.repo, "account": "finos", "name": "--x"},
                    {"action": "repo_remove"}):
            code, _ = self.post(bad)
            self.assertEqual(code, 400, bad)
        self.assertEqual(self.settings()["account"], "max")

        # ghi repo cũng phải có header và chỉ từ máy Mac
        code, _ = self.req("POST", "/api/cc-switcher/action", body={"action": "repo_remove", "repo": self.repo})
        self.assertEqual(code, 403)
        code, _ = self.post({"action": "repo_remove", "repo": self.repo}, host="abc.trycloudflare.com",
                            headers={**TUNNEL, "X-Agent-Office-Key": KEY})
        self.assertEqual(code, 403)
        self.assertEqual(self.settings()["account"], "max")

        code, raw = self.post({"action": "repo_remove", "repo": self.repo})
        self.assertEqual(code, 200, raw[:300])
        self.assertEqual(json.loads(raw)["state"]["repoAssignments"], [])
        self.assertEqual(self.settings(), {"hooks": {"Stop": []}})


if __name__ == "__main__":
    unittest.main()
