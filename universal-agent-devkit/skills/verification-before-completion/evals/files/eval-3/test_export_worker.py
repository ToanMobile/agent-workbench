import os
import tempfile
import unittest
from export_worker import ExportQueue


class ExportWorkerTest(unittest.TestCase):
    def test_non_empty_export_writes_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "report.csv")
            q = ExportQueue()
            res = q.submit_export("j1", [{"id": "1", "amount": "50"}], out)
            self.assertEqual(res["http_code"], 200)
            q.drain()
            self.assertEqual(q.jobs["j1"]["status"], "completed")
            self.assertTrue(os.path.isfile(out))

    def test_empty_export_marks_job_completed(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "empty_report.csv")
            q = ExportQueue()
            res = q.submit_export("j2", [], out)
            self.assertEqual(res["http_code"], 200)
            q.drain()
            self.assertEqual(q.jobs["j2"]["status"], "completed")


if __name__ == "__main__":
    unittest.main()
