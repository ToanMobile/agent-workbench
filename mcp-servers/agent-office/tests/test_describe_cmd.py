import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "cần node")
class DescribeCmdTest(unittest.TestCase):
    def test_describe_cmd_js(self):
        r = subprocess.run(["node", os.path.join(HERE, "describe_cmd_test.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
