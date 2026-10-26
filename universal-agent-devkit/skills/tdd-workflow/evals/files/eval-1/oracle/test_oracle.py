# Bộ kiểm thử độc lập (oracle) dùng để chấm kết quả sửa lỗi hàm slugify.
import unittest

from text_slug import slugify


class TestSlugifyOracle(unittest.TestCase):
    def test_preserves_version_digits(self) -> None:
        self.assertEqual(slugify("Release 2026 v2"), "release-2026-v2")

    def test_preserves_leading_and_inline_numbers(self) -> None:
        self.assertEqual(slugify("Top 10 Python 3.12 Tips!"), "top-10-python-3-12-tips")

    def test_pure_numeric_title(self) -> None:
        self.assertEqual(slugify("  404  "), "404")

    def test_existing_alpha_behavior_intact(self) -> None:
        self.assertEqual(slugify("  Hello --- World!! "), "hello-world")
        self.assertEqual(slugify("   "), "")


if __name__ == "__main__":
    unittest.main()
