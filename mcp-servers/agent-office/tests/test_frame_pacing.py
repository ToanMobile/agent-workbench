"""Nhịp vẽ 3D hạ khi cảnh đứng yên, trần DPR 1,5 (tests/frame_pacing_test.js)."""
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "cần node")
class FramePacingTest(unittest.TestCase):
    def test_frame_pacing_js(self):
        r = subprocess.run(["node", os.path.join(HERE, "frame_pacing_test.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("frame_pacing_test OK", r.stdout)


if __name__ == "__main__":
    unittest.main()
