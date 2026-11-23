import hashlib
import hmac
import http.client
import json
import os
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from unittest import mock
from urllib.parse import urlencode

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import aaf_hub  # noqa: E402
import server  # noqa: E402


def _make_init_data(bot_token: str, user_id: int, auth_date: int | None = None, extra: dict | None = None) -> str:
    fields = {
        "auth_date": str(int(time.time()) if auth_date is None else auth_date),
        "query_id": "AAHdF6IQAAAAAN0XohDhrOrc",
        "user": json.dumps({"id": user_id, "first_name": "Toan"}, separators=(",", ":")),
    }
    if extra:
        fields.update(extra)
    dcs = "\n".join(f"{k}={v}" for k, v in sorted(fields.items()))
    secret = hmac.new(b"WebAppData", bot_token.encode("utf-8"), hashlib.sha256).digest()
    sig = hmac.new(secret, dcs.encode("utf-8"), hashlib.sha256).hexdigest()
    fields["hash"] = sig
    return urlencode(fields)


_SYNTHETIC_TG_BOT = "123456789" + ":" + "AAH_" + "test_bot_val_" + "a" * 24


class TestTelegramInitDataAuth(unittest.TestCase):
    TOKEN = _SYNTHETIC_TG_BOT
    OWNER = 424242

    def test_valid_init_data_passes(self):
        raw = _make_init_data(self.TOKEN, self.OWNER)
        ok, err, user = aaf_hub.verify_telegram_init_data(raw, self.TOKEN, self.OWNER)
        self.assertTrue(ok, err)
        self.assertEqual(user["id"], self.OWNER)

    def test_wrong_owner_rejected(self):
        raw = _make_init_data(self.TOKEN, 999999)
        ok, _, _ = aaf_hub.verify_telegram_init_data(raw, self.TOKEN, self.OWNER)
        self.assertFalse(ok)

    def test_expired_auth_date_rejected(self):
        raw = _make_init_data(self.TOKEN, self.OWNER, auth_date=int(time.time()) - 600)
        ok, _, _ = aaf_hub.verify_telegram_init_data(raw, self.TOKEN, self.OWNER, max_age=300)
        self.assertFalse(ok)

    def test_future_clock_skew_rejected(self):
        raw = _make_init_data(self.TOKEN, self.OWNER, auth_date=int(time.time()) + 300)
        ok, _, _ = aaf_hub.verify_telegram_init_data(raw, self.TOKEN, self.OWNER)
        self.assertFalse(ok)

    def test_duplicate_key_pollution_rejected(self):
        raw = _make_init_data(self.TOKEN, self.OWNER) + "&auth_date=9999999999"
        ok, _, _ = aaf_hub.verify_telegram_init_data(raw, self.TOKEN, self.OWNER)
        self.assertFalse(ok)

    def test_session_token_roundtrip_and_expiry(self):
        mgr = aaf_hub.SessionManager(ttl_sec=60)
        tok = mgr.mint(self.OWNER)
        self.assertTrue(mgr.verify(tok, self.OWNER))
        self.assertFalse(mgr.verify(tok, 111111))
        self.assertFalse(mgr.verify(tok + "x", self.OWNER))


class TestRemote4318AndLocal4317Isolation(unittest.TestCase):
    TOKEN = _SYNTHETIC_TG_BOT
    OWNER = 424242

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.td.name, "GeelyEx2")
        os.makedirs(self.repo)
        self.db_path = os.path.join(self.td.name, "aaf.db")
        self.web_dir = os.path.join(self.td.name, "web")
        os.makedirs(self.web_dir)
        with open(os.path.join(self.web_dir, "studio.html"), "w", encoding="utf-8") as f:
            f.write("<!doctype html><html><body>AAF Studio</body></html>")

        self.cfg = {
            "repos": ["GeelyEx2"],
            "repoPaths": {"GeelyEx2": self.repo},
            "remoteAllowedHosts": ["127.0.0.1", "localhost"],
        }
        handler_cls = aaf_hub.make_remote_handler(
            cfg=self.cfg,
            bot_token=self.TOKEN,
            owner_id=self.OWNER,
            db_path=self.db_path,
            web_dir=self.web_dir,
            cc_switcher_fn=lambda args: (200, {"ok": True, "args": args}),
        )
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
        self.port = self.srv.server_address[1]
        self.th = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.th.start()

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        self.td.cleanup()

    def _req(self, method: str, path: str, headers: dict | None = None, body: bytes = b""):
        con = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        con.request(method, path, body=body, headers=headers or {})
        r = con.getresponse()
        data = r.read()
        hdrs = dict(r.getheaders())
        con.close()
        return r.status, hdrs, data

    def test_remote_studio_csp_allows_telegram_iframe_no_xfo_deny(self):
        st, hdrs, data = self._req("GET", "/studio")
        self.assertEqual(st, 200)
        self.assertIn(b"AAF Studio", data)
        csp = hdrs.get("Content-Security-Policy", "")
        self.assertIn("frame-ancestors", csp)
        self.assertIn("https://web.telegram.org", csp)
        self.assertNotEqual(hdrs.get("X-Frame-Options"), "DENY")

    def test_remote_blocks_unauthenticated_and_legacy_routes(self):
        init_data = _make_init_data(self.TOKEN, self.OWNER)
        # Missing auth -> 401
        st, _, _ = self._req("GET", "/api/aaf/studio", {"X-AAF-Studio": "1"})
        self.assertEqual(st, 401)
        # Missing custom CSRF header -> 403
        st, _, _ = self._req("GET", "/api/aaf/studio", {"X-Telegram-Init-Data": init_data})
        self.assertEqual(st, 403)
        # Legacy routes must NOT exist on :4318
        for legacy in ("/api/state", "/cc-switcher", "/api/cc-switcher/state", "/api/phone"):
            st, _, _ = self._req(
                "GET",
                legacy,
                {"X-AAF-Studio": "1", "X-Telegram-Init-Data": init_data},
            )
            self.assertEqual(st, 404, f"Legacy route leaked on :4318: {legacy}")

    def test_remote_auth_session_exchange_and_cc_switcher_allowlist(self):
        init_data = _make_init_data(self.TOKEN, self.OWNER)
        st, _, data = self._req(
            "POST",
            "/api/aaf/auth",
            {"X-AAF-Studio": "1", "X-Telegram-Init-Data": init_data, "Content-Type": "application/json"},
            b"{}",
        )
        self.assertEqual(st, 200)
        sess = json.loads(data)["sessionToken"]

        # Subsequent call with session token alone (no initData) succeeds
        st2, _, data2 = self._req(
            "GET",
            "/api/aaf/studio",
            {"X-AAF-Studio": "1", "X-AAF-Session": sess},
        )
        self.assertEqual(st2, 200)
        payload = json.loads(data2)
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["capabilities"]["allowOAuthLogin"])

        # OAuth login & repo_add/remove MUST be 403 on :4318
        for forbidden in ("login", "repo_add", "repo_remove"):
            st_f, _, _ = self._req(
                "POST",
                "/api/aaf/accounts/action",
                {"X-AAF-Studio": "1", "X-AAF-Session": sess, "Content-Type": "application/json"},
                json.dumps({"action": forbidden}).encode("utf-8"),
            )
            self.assertEqual(st_f, 403, f"Action {forbidden} must be 403 on :4318")

        # Allowed action (rotate) succeeds
        st_ok, _, data_ok = self._req(
            "POST",
            "/api/aaf/accounts/action",
            {"X-AAF-Studio": "1", "X-AAF-Session": sess, "Content-Type": "application/json"},
            json.dumps({"action": "rotate"}).encode("utf-8"),
        )
        self.assertEqual(st_ok, 200)
        self.assertTrue(json.loads(data_ok)["ok"])

    def test_local_4317_blocks_tailscale_and_proxy_headers_on_studio(self):
        # Verify expanded TUNNEL_HEADERS marks Tailscale-Funnel-Request and X-Forwarded-For as non-local
        for hdr in ("Tailscale-Funnel-Request", "X-Forwarded-For", "X-Real-Ip", "Forwarded"):
            self.assertFalse(
                server.local_request({"Host": "127.0.0.1:4317", hdr: "1.2.3.4"}, "127.0.0.1", {"127.0.0.1", "localhost"}),
                f"Header {hdr} must NOT pass local_request()",
            )


if __name__ == "__main__":
    unittest.main()
