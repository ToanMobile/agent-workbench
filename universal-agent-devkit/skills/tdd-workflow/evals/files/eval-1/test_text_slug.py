# Kiểm thử cơ bản hiện có cho module text_slug.
import unittest

from text_slug import slugify


class TestSlugifyBasic(unittest.TestCase):
    def test_simple_words(self) -> None:
        self.assertEqual(slugify("Hello World"), "hello-world")

    def test_punctuation_and_spaces(self) -> None:
        self.assertEqual(slugify("  Clean   Architecture! "), "clean-architecture")


if __name__ == "__main__":
    unittest.main()
