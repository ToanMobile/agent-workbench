"""#742 review c27d199d, BUG-REV c39f91d4e7 (INSTINCT-002): the "Thử lại" button of /cc-switcher locks at once and for >= 1000 ms,
and load() keeps one request in flight. Runs tests/cc_switcher_retry_test.js (the page's real script, fake DOM / fetch / clock)."""
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


@unittest.skipUnless(shutil.which("node"), "cần node")
class CcSwitcherRetryTest(unittest.TestCase):
    def test_retry_locks_and_single_flight(self):
        r = subprocess.run(["node", os.path.join(HERE, "cc_switcher_retry_test.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
