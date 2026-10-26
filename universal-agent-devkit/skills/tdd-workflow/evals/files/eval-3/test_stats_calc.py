# Kiểm thử cơ bản hiện có cho module stats_calc.
import unittest

from stats_calc import median


class TestStatsCalcBasic(unittest.TestCase):
    def test_single_value(self) -> None:
        self.assertEqual(median([7]), 7.0)

    def test_odd_unsorted_values(self) -> None:
        self.assertEqual(median([10, 2, 8, 4, 6]), 6.0)

    def test_empty_raises(self) -> None:
        with self.assertRaises(ValueError):
            median([])


if __name__ == "__main__":
    unittest.main()
