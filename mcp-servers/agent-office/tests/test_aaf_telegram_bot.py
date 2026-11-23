import os
import tempfile
import unittest

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import aaf_telegram_bot  # noqa: E402


class TestAafTelegramBot(unittest.TestCase):
    def test_conflict_token_hash_guard_detects_cc_switcher_collision(self):
        with tempfile.TemporaryDirectory() as td:
            cc_env = os.path.join(td, "cc.env")
            same_val = "11111111" + ":" + "AAH_" + "same_" + "x" * 28
            other_val = "22222222" + ":" + "AAH_" + "other_" + "y" * 27
            with open(cc_env, "w", encoding="utf-8") as f:
                f.write("TELEGRAM_BOT_TOKEN=" + same_val + "\n")
            os.chmod(cc_env, 0o600)
            self.assertTrue(
                aaf_telegram_bot.token_conflicts_with_cc_switcher(same_val, cc_env_path=cc_env)
            )
            self.assertFalse(
                aaf_telegram_bot.token_conflicts_with_cc_switcher(other_val, cc_env_path=cc_env)
            )

    def test_parse_prompt_command_prefix_and_missing_repo(self):
        repos = ["GeelyEx2", "OfficeReader", "Goods-Triple-Shelf-Match-3D"]
        repo, body = aaf_telegram_bot.parse_repo_prompt("geely: Fix Bluetooth reconnect", repos)
        self.assertEqual(repo, "GeelyEx2")
        self.assertEqual(body, "Fix Bluetooth reconnect")

        repo2, body2 = aaf_telegram_bot.parse_repo_prompt("or: Chặn crash PDF", repos)
        self.assertEqual(repo2, "OfficeReader")
        self.assertEqual(body2, "Chặn crash PDF")

        repo3, body3 = aaf_telegram_bot.parse_repo_prompt("Sửa lỗi màn hình chính", repos)
        self.assertIsNone(repo3)
        self.assertEqual(body3, "Sửa lỗi màn hình chính")

    def test_update_authorization_checks_owner_and_chat_for_message_and_callback(self):
        msg_ok = {"message": {"from": {"id": 100}, "chat": {"id": -500}, "text": "/status"}}
        msg_bad_user = {"message": {"from": {"id": 999}, "chat": {"id": -500}, "text": "/status"}}
        cb_ok = {"callback_query": {"from": {"id": 100}, "message": {"chat": {"id": -500}}, "data": "r:GeelyEx2"}}
        cb_bad = {"callback_query": {"from": {"id": 999}, "message": {"chat": {"id": -500}}, "data": "r:GeelyEx2"}}

        self.assertTrue(aaf_telegram_bot.is_authorized_update(msg_ok, owner_id=100, allowed_chats={100, -500}))
        self.assertFalse(aaf_telegram_bot.is_authorized_update(msg_bad_user, owner_id=100, allowed_chats={100, -500}))
        self.assertTrue(aaf_telegram_bot.is_authorized_update(cb_ok, owner_id=100, allowed_chats={100, -500}))
        self.assertFalse(aaf_telegram_bot.is_authorized_update(cb_bad, owner_id=100, allowed_chats={100, -500}))

    def test_live_pinned_debounce_and_hash_dedup(self):
        # Too soon (< 15s) -> skip
        self.assertFalse(aaf_telegram_bot.should_edit_pinned("hello", last_hash="old", last_edit_ts=100.0, now_ts=110.0))
        # Identical hash -> skip even after 15s
        h = aaf_telegram_bot.text_hash("hello")
        self.assertFalse(aaf_telegram_bot.should_edit_pinned("hello", last_hash=h, last_edit_ts=100.0, now_ts=200.0))
        # Changed content and >= 15s -> edit
        self.assertTrue(aaf_telegram_bot.should_edit_pinned("hello 2", last_hash=h, last_edit_ts=100.0, now_ts=120.0))

    def test_html_formatting_escapes_special_chars_and_redacts_tokens(self):
        tok = "123456789" + ":" + "AAH_" + "secret_val_" + "z" * 24
        txt = aaf_telegram_bot.format_safe_html(f"Repo <Humans-vs.-UFOs> & val={tok}")
        self.assertIn("&lt;Humans-vs.-UFOs&gt;", txt)
        self.assertIn("&amp;", txt)
        self.assertNotIn("AAH_secret_val", txt)


if __name__ == "__main__":
    unittest.main()
