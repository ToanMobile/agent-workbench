"""Số liệu cho bảng chỉ số: sức khoẻ máy và đếm việc trong phiên."""
import os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


class HostStatsTest(unittest.TestCase):
    def test_host_stats_shape(self):
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            for n in ("heavy-1.lock", "unity.lock", "heavy-2.lock", "light-1.lock", "note.txt"):
                open(os.path.join(d, n), "w").close()
            # đang giữ: heavy-1 và unity (việc nặng) + light-1 (việc nhẹ, không tính); heavy-2 bỏ trống
            held = [open(os.path.join(d, n), "a") for n in ("heavy-1.lock", "unity.lock", "light-1.lock")]
            for f in held:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                h = server.host_stats(lock_dir=d)
            finally:
                for f in held:
                    f.close()
        self.assertEqual(len(h["load"]), 3)
        self.assertTrue(all(isinstance(x, float) for x in h["load"]))
        self.assertGreaterEqual(h["cpus"], 1)
        self.assertGreater(h["loadMax"], 0)
        self.assertEqual(h["slotsHeld"], 2)  # chỉ đếm khoá việc nặng đang bị giữ: không đếm file bỏ trống, không đếm pool nhẹ

    def test_bad_load_max_falls_back(self):  # inf/nan làm JSON hỏng (Infinity) và cả trang mất dữ liệu
        for bad in ("inf", "nan", "-5", "abc"):
            old = os.environ.get("DEVKIT_SLOT_LOAD_MAX")
            os.environ["DEVKIT_SLOT_LOAD_MAX"] = bad
            try:
                self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 100.0, bad)
            finally:
                if old is None:
                    os.environ.pop("DEVKIT_SLOT_LOAD_MAX", None)
                else:
                    os.environ["DEVKIT_SLOT_LOAD_MAX"] = old

    def test_lock_dir_env_override(self):  # cùng thư mục khoá với heavy_slot.slot_dir()
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            f = open(os.path.join(d, "heavy-1.lock"), "a")
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            old = os.environ.get("SB_HEAVY_SLOT_DIR")
            os.environ["SB_HEAVY_SLOT_DIR"] = d
            try:
                self.assertEqual(server.host_stats()["slotsHeld"], 1)
            finally:
                f.close()
                if old is None:
                    os.environ.pop("SB_HEAVY_SLOT_DIR", None)
                else:
                    os.environ["SB_HEAVY_SLOT_DIR"] = old

    def test_no_getloadavg_does_not_crash(self):  # máy không có os.getloadavg (Windows): bảng báo 0, server không chết vòng dựng
        saved = os.getloadavg
        del os.getloadavg
        try:
            self.assertEqual(server.host_stats(lock_dir="/nonexistent")["load"], [0.0, 0.0, 0.0])
        finally:
            os.getloadavg = saved

    def test_missing_lock_dir_is_zero(self):
        self.assertEqual(server.host_stats(lock_dir="/nonexistent/agent-office")["slotsHeld"], 0)


class SessionTallyTest(unittest.TestCase):
    def test_counts_moves_done_and_blocked(self):
        kinds = {"Ready": "ready", "Review": "review", "Blocked": "blocked", "Done": "done"}
        prev = {"a": "Ready", "b": "Review", "c": "Review", "d": "Done"}
        cur = {"a": "Review", "b": "Done", "c": "Blocked", "d": "Done", "e": "Ready"}
        t = server.tally_moves(prev, cur, kinds, {"moves": 1, "done": 0, "blocked": 0})
        self.assertEqual(t, {"moves": 4, "done": 1, "blocked": 1})  # e là thẻ mới, không tính là di chuyển


if __name__ == "__main__":
    unittest.main()
