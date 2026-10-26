# Bộ kiểm thử độc lập (oracle) dùng để chấm kết quả sửa lỗi parse_duration.
import unittest

from duration import parse_duration


class TestParseDurationOracle(unittest.TestCase):
    def test_compound_hours_minutes(self) -> None:
        self.assertEqual(parse_duration("1h30m"), 5400)

    def test_compound_all_three_units(self) -> None:
        self.assertEqual(parse_duration("1h5m30s"), 3930)
        self.assertEqual(parse_duration("2m15s"), 135)
        self.assertEqual(parse_duration("1h20s"), 3620)

    def test_single_units_still_work(self) -> None:
        self.assertEqual(parse_duration("0s"), 0)
        self.assertEqual(parse_duration("3h"), 10800)

    def test_invalid_inputs_rejected(self) -> None:
        for bad in ("", "   ", "abc", "10d", "10", "-5m"):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    parse_duration(bad)


if __name__ == "__main__":
    unittest.main()
