"""Thanh nút một hàng + menu ⋯ + ô tài khoản góc phải trên, đo trong Chromium thật (tests/ui_toolbar_account.js).

Cần node, playwright-core (biến PLAYWRIGHT_CORE trỏ tới thư mục gói, hoặc cài được bằng require) và Chromium của Playwright;
thiếu thứ nào thì bỏ qua (CI không có trình duyệt), có đủ thì một lỗi bố cục là test đỏ.
"""
import os, shutil, subprocess, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(HERE, "tests", "ui_toolbar_account.js")


def playwright_ok():
    node = shutil.which("node")
    if not node:
        return False
    r = subprocess.run([node, SCRIPT, "--probe"], capture_output=True, cwd=HERE)
    return r.returncode == 0


@unittest.skipUnless(playwright_ok(), "không có node + playwright-core + Chromium: bỏ qua đo giao diện trong trình duyệt")
class ToolbarAndAccountUI(unittest.TestCase):
    def test_layout_in_real_browser(self):
        r = subprocess.run(["node", SCRIPT], capture_output=True, text=True, cwd=HERE, timeout=900)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-6000:])
        self.assertIn("UI OK", r.stdout)


if __name__ == "__main__":
    unittest.main()


class ToolbarMarkupStatic(unittest.TestCase):
    """Chạy cả khi không có trình duyệt: các thao tác cũ, phím tắt và menu ⋯ vẫn có trong index.html."""

    @classmethod
    def setUpClass(cls):
        import re
        with open(os.path.join(HERE, "web", "index.html"), encoding="utf-8") as f:
            cls.html = f.read()
        cls.re = re
        cls.bar = re.search(r'<div class="controls panel" role="toolbar"[^>]*>(.*?)\n</div>', cls.html, re.S).group(1)
        cls.menu = re.search(r'<div class="more-menu panel" id="moreMenu" role="menu"[^>]*>(.*?)\n</div>', cls.html, re.S).group(1)

    def test_every_former_action_still_exists(self):
        for bid in ("btnApprove", "btnAgents", "btnFit", "btnZoom", "btnRail", "btnBoard", "btnAdd", "btnEvents", "btnDash", "btnMore"):
            self.assertIn(f'id="{bid}"', self.bar, bid)
        for bid in ("btnNext", "btnDesk", "btnTheme", "btnPhone", "btnRefresh"):
            self.assertRegex(self.menu, rf'role="menuitem(checkbox)?"[^>]*id="{bid}"', bid)

    def test_mobile_menu_mirrors_hidden_toolbar_buttons(self):
        for bid in ("btnEvents", "btnDash", "btnAgents", "btnRail", "btnFit", "btnZoom", "btnApprove"):
            self.assertIn(f'data-for="{bid}"', self.menu, bid)

    def test_shortcuts_kept(self):
        m = self.re.search(r"const SHORTCUTS = \{(.*?)\};", self.html)
        keys = dict(self.re.findall(r"(\w): '#(\w+)'", m.group(1)))
        self.assertEqual(keys, {"w": "btnAgents", "e": "btnEvents", "f": "btnFit", "z": "btnZoom", "b": "btnBoard", "a": "btnAdd",
                                "n": "btnNext", "t": "btnTheme", "r": "btnRail", "d": "btnDesk"})

    def test_no_more_khac_and_no_zoom_name_clash(self):
        self.assertNotIn("Khác", self.bar)
        self.assertNotIn("Thu gọn", self.html)
        self.assertNotRegex(self.bar, r'id="btnZoom"[^>]*>Phóng to<')
        self.assertIn('aria-label="Phóng to"', self.html)  # chỉ nút + của khung zoom mang tên này

    def test_toggles_use_fixed_labels(self):
        for bad in ("'Dạng 3D'", "'Ẩn danh sách'", "'Ca ngày' : 'Ca đêm'", "textContent = open ? 'Thu gọn'"):
            self.assertNotIn(bad, self.html)
        self.assertIn("$('#btnBoard').setAttribute('aria-pressed'", self.html)

    def test_account_chip_markup(self):
        self.assertRegex(self.html, r'<button type="button" class="acct panel empty" id="acctChip" aria-haspopup="dialog" aria-expanded="false" aria-controls="acctPop">')
        self.assertIn('id="acctPop" role="dialog"', self.html)
        self.assertIn("Chưa có phiên", self.html)
