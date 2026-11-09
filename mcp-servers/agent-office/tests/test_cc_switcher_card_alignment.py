"""Thẻ tài khoản Claude trên /cc-switcher: các khối cùng loại căn đều giữa các thẻ (đã đo 1280/768 px: toạ độ y bằng nhau).

Đọc <style> và mã dựng thẻ của web/cc-switcher.html (CC_PAGE đổi file để chứng minh test đỏ trên bản cũ).
"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.environ.get("CC_PAGE") or os.path.join(HERE, "web", "cc-switcher.html")


def page():
    with open(PAGE, encoding="utf-8") as f:
        return f.read()


class CardAlignment(unittest.TestCase):
    def test_actions_sit_at_card_bottom(self):
        css = page()
        self.assertRegex(css, r"#claude \.card \{[^}]*display: flex;[^}]*flex-direction: column;")
        self.assertRegex(css, r"\.acc-actions \{[^}]*margin-top: auto;")

    def test_head_has_fixed_height_for_mail_and_badge_on_own_row(self):
        css = page()
        self.assertRegex(css, r"#claude \.acc-head \.acc-mail \{[^}]*min-height: 3em;")
        self.assertRegex(css, r"\.acc-head > \.badge \{ order: 1; \}")

    def test_meter_has_fixed_second_line_so_height_does_not_depend_on_reset_text(self):
        html = page()
        self.assertRegex(html, r"\.meter \.sub \{[^}]*min-height: 1\.5em;")
        self.assertIn("el('div', { class: 'sub', text: extra || '\\u00a0' })", html)

    def test_time_rows_are_always_two_lines_and_weekly_row_always_present(self):
        html = page()
        self.assertRegex(html, r"\.facts dd\.two \{[^}]*min-height: 3em;")
        self.assertRegex(html, r"\['Reset tuần', p\.weeklyResetAtMs \? .*: '—', 'two'\]")
        self.assertRegex(html, r"\['Reset / mở khóa', .*'Chưa có mốc', 'two'\]")

    def test_stale_note_reserves_the_height_of_two_meters(self):
        html = page()
        self.assertRegex(html, r"\.acc-note \{[^}]*min-height: calc\(2 \* 3\.7em \+ 12px\);")
        self.assertIn("class: 'acc-mail acc-note'", html)

    def test_no_null_class_attribute_passed_to_builder(self):
        # el() ghi className = giá trị: null thành chuỗi "null"
        self.assertNotRegex(page(), r"class: [^,}]*\? '[a-z]+' : null")


if __name__ == "__main__":
    unittest.main()
