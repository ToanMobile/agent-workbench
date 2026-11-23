import os
import tempfile
import unittest

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import aaf_supervisor  # noqa: E402


class TestAafSupervisor(unittest.TestCase):
    def test_backoff_caps_at_300s(self):
        self.assertEqual(aaf_supervisor.compute_backoff(0), 15)
        self.assertEqual(aaf_supervisor.compute_backoff(1), 30)
        self.assertEqual(aaf_supervisor.compute_backoff(2), 60)
        self.assertEqual(aaf_supervisor.compute_backoff(5), 300)

    def test_single_instance_flock(self):
        with tempfile.TemporaryDirectory() as td:
            lock_p = os.path.join(td, "sup.lock")
            fd1 = aaf_supervisor.acquire_instance_lock(lock_p)
            self.assertIsNotNone(fd1)
            fd2 = aaf_supervisor.acquire_instance_lock(lock_p)
            self.assertIsNone(fd2)
            os.close(fd1)

    def test_caffeinate_cmd_binds_parent_pid(self):
        cmd = aaf_supervisor.build_caffeinate_cmd(12345)
        self.assertEqual(cmd, ["caffeinate", "-s", "-w", "12345"])

    def test_should_spawn_respects_enabled_and_frozen(self):
        self.assertFalse(aaf_supervisor.should_spawn_repo(enabled=False, has_ready=True, frozen=False))
        self.assertFalse(aaf_supervisor.should_spawn_repo(enabled=True, has_ready=True, frozen=True))
        self.assertFalse(aaf_supervisor.should_spawn_repo(enabled=True, has_ready=False, frozen=False))
        self.assertTrue(aaf_supervisor.should_spawn_repo(enabled=True, has_ready=True, frozen=False))


if __name__ == "__main__":
    unittest.main()
