"""finos_lua (tài khoản Claude thứ 7): server cho phép chuyển/gán repo, trang không còn giả định 3 tài khoản Claude / 6 tài khoản."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    with open(os.path.join(HERE, rel), encoding="utf-8") as f:
        return f.read()


class FinosLuaSupport(unittest.TestCase):
    def test_server_whitelists_accept_finos_lua(self):
        src = read("server.py")
        claude = re.search(r"CC_CLAUDE_ACCOUNTS = \{([^}]*)\}", src).group(1)
        profiles = re.search(r"CC_PROFILES = \{([^}]*)\}", src).group(1)
        self.assertIn('"finos_lua"', claude)  # repo_assign / repo_add
        self.assertIn('"finos_lua"', profiles)  # switch
        self.assertIn("finos_lua", re.search(r'Repo chỉ gán được tài khoản Claude: ([^"]*)"', src).group(1))

    def test_page_has_no_fixed_three_or_six_accounts(self):
        html = read("web/cc-switcher.html")
        self.assertIn("'finos_lua'", html)  # dự phòng khi state chưa có claudeAccounts
        self.assertNotRegex(html, r"Bảng điều khiển 6 tài khoản")
        self.assertRegex(html, r'<div class="grid g4" id="claude">')  # 4 thẻ Claude, không để 3+1
        self.assertRegex(html, r'<div class="grid g4" id="repoByAcc">')

    def test_destructive_dialog_focuses_cancel_and_frozen_account_is_labelled(self):
        html = read("web/cc-switcher.html")
        self.assertIn("(danger ? d.querySelector('button[value=\"cancel\"]') : ok).focus()", html)  # Enter không xác nhận thao tác nguy hiểm
        self.assertIn("đóng băng 429)", html)  # ô chọn tài khoản cho repo báo tài khoản đang đóng băng


if __name__ == "__main__":
    unittest.main()
