"""Người 3D dùng chung một Skeleton cho các lưới cùng bộ xương (tests/share_skeleton_test.js)."""
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "cần node")
class ShareSkeletonTest(unittest.TestCase):
    def test_share_skeleton_js(self):
        r = subprocess.run(["node", os.path.join(HERE, "share_skeleton_test.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("share_skeleton_test OK", r.stdout)


if __name__ == "__main__":
    unittest.main()
