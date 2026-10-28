import unittest
from invoice_tax import compute_tax, invoice_total


class InvoiceTaxTest(unittest.TestCase):
    def test_whole_dollar_tax(self):
        self.assertEqual(compute_tax(100.0, 0.1), 10.0)
        self.assertEqual(invoice_total(100.0, 0.1), 110.0)


if __name__ == "__main__":
    unittest.main()
