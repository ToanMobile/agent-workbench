import os
import tempfile
import unittest
from export_worker import ExportQueue


class ExportWorkerOracleTest(unittest.TestCase):
    def test_terminal_completed_always_persists_destination_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            empty_out = os.path.join(tmp, "nested_empty", "empty.csv")
            full_out = os.path.join(tmp, "nested", "full.csv")
            q = ExportQueue()
            q.submit_export("empty", [], empty_out)
            q.submit_export("full", [{"name": "Alice"}], full_out)
            self.assertFalse(os.path.exists(empty_out))
            q.drain()
            self.assertEqual(q.jobs["empty"]["status"], "completed")
            self.assertTrue(os.path.isfile(empty_out), "completed job must persist empty destination file")
            self.assertEqual(q.jobs["full"]["status"], "completed")
            self.assertTrue(os.path.isfile(full_out))
            with open(full_out, encoding="utf-8") as fh:
                self.assertIn("Alice", fh.read())


if __name__ == "__main__":
    unittest.main()
