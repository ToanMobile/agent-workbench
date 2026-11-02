import unittest
from invoice_tax import compute_tax, invoice_total


class InvoiceTaxOracleTest(unittest.TestCase):
    def test_zero_and_fractional_rounding(self):
        self.assertEqual(compute_tax(0.0, 0.08), 0.0)
        self.assertEqual(compute_tax(19.99, 0.08), 1.6)
        self.assertEqual(compute_tax(33.33, 0.075), 2.5)
        self.assertEqual(invoice_total(33.33, 0.075), 35.83)

    def test_negative_inputs_rejected(self):
        with self.assertRaises(ValueError):
            compute_tax(-1.0, 0.08)
        with self.assertRaises(ValueError):
            compute_tax(10.0, -0.05)


if __name__ == "__main__":
    unittest.main()
