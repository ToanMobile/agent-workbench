# Bộ kiểm thử độc lập (oracle) dùng để chấm kết quả sửa lỗi hàm median.
import unittest

from stats_calc import median


class TestStatsCalcOracle(unittest.TestCase):
    def test_even_four_elements(self) -> None:
        self.assertAlmostEqual(median([1, 2, 3, 4]), 2.5)
        self.assertAlmostEqual(median([40, 10, 20, 30]), 25.0)

    def test_even_two_and_six_elements(self) -> None:
        self.assertAlmostEqual(median([10, 20]), 15.0)
        self.assertAlmostEqual(median([9, 1, 5, 3, 7, 11]), 6.0)

    def test_odd_and_negative_elements(self) -> None:
        self.assertAlmostEqual(median([-5, -1, -3]), -3.0)
        self.assertAlmostEqual(median([-4, -2, 0, 2]), -1.0)

    def test_empty_raises(self) -> None:
        with self.assertRaises(ValueError):
            median([])


if __name__ == "__main__":
    unittest.main()
