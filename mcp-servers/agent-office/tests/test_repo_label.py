import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "cần node")
class RepoLabelTest(unittest.TestCase):
    def test_repo_label_js(self):
        r = subprocess.run(["node", os.path.join(HERE, "repo_label_test.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
