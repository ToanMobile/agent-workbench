# Kiểm thử cơ bản hiện có cho module duration.
import unittest

from duration import parse_duration


class TestParseDurationBasic(unittest.TestCase):
    def test_single_units(self) -> None:
        self.assertEqual(parse_duration("45s"), 45)
        self.assertEqual(parse_duration("15m"), 900)
        self.assertEqual(parse_duration("2h"), 7200)

    def test_rejects_empty(self) -> None:
        with self.assertRaises(ValueError):
            parse_duration("   ")


if __name__ == "__main__":
    unittest.main()
