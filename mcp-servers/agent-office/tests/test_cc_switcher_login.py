"""Nút Đăng nhập lại trên /cc-switcher: server cho phép thao tác login, trang có nút cho tài khoản số liệu cũ."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    with open(os.path.join(HERE, rel), encoding="utf-8") as f:
        return f.read()


class LoginButton(unittest.TestCase):
    def test_server_allows_login_action_only_for_claude_accounts(self):
        src = read("server.py")
        self.assertIn('"login"', re.search(r"CC_ACTIONS = \{([^}]*)\}", src, re.S).group(1))
        self.assertRegex(src, r'action == "login"')

    def test_page_has_login_button_for_stale_accounts(self):
        html = read("web/cc-switcher.html")
        self.assertIn("data-login", html)
        self.assertIn("Đăng nhập lại", html)
        self.assertRegex(html, r"action: 'login'")
