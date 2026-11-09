"""Profile không dùng gần đây mà token hết hạn: trang nói nhẹ (role status), không báo động (role alert)."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class IdleExpiredMessage(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(HERE, "web", "cc-switcher.html"), encoding="utf-8") as f:
            self.html = f.read()

    def test_page_has_soft_idle_wording(self):
        self.assertIn("chưa dùng gần đây", self.html)
        self.assertIn("bình thường", self.html)

    def test_idle_note_is_status_not_alert(self):
        self.assertRegex(self.html, r"role: soft \? 'status' : 'alert'")
