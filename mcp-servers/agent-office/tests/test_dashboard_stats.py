"""Số liệu cho bảng chỉ số: sức khoẻ máy và đếm việc trong phiên."""
import os, sys, tempfile, unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


class HostStatsTest(unittest.TestCase):
    def setUp(self):
        # T0052: ngưỡng tải mặc định đến từ universal-agent-devkit/bin/capacity.py; ghim máy giả 12 lõi (hold_load 96) và bỏ nút của
        # người gọi. patch.dict trả lại nguyên os.environ khi xong, nên không rò sang TestCase khác chạy cùng tiến trình discover.
        patcher = mock.patch.dict(os.environ, {"DEVKIT_CAPACITY_CORES": "12"})
        patcher.start()
        self.addCleanup(patcher.stop)
        for k in ("DEVKIT_CAPACITY", "DEVKIT_CAPACITY_LOAD", "DEVKIT_SLOT_LOAD_MAX"):
            os.environ.pop(k, None)

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
                # T0052: giá trị hỏng về ngưỡng mặc định = capacity hold_load (8 × lõi, 12 lõi: 96), như heavy_slot.load_max
                self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 96.0, bad)
            finally:
                if old is None:
                    os.environ.pop("DEVKIT_SLOT_LOAD_MAX", None)
                else:
                    os.environ["DEVKIT_SLOT_LOAD_MAX"] = old

    def test_load_max_from_capacity(self):  # T0052: ngưỡng gate = hold_load theo số lõi, biến cũ thắng, thiếu capacity thì 100
        self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 96.0)
        os.environ["DEVKIT_CAPACITY_CORES"] = "4"
        self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 32.0)
        os.environ["DEVKIT_SLOT_LOAD_MAX"] = "64"
        self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 64.0)
        del os.environ["DEVKIT_SLOT_LOAD_MAX"]
        with mock.patch.object(server, "_CAPACITY", [None]):  # như repo thiếu universal-agent-devkit/bin/capacity.py
            self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 100.0)

    def test_broken_capacity_falls_back(self):  # capacity.py ném lỗi runtime lúc nạp: bảng chỉ số không chết, hiển thị 100
        with tempfile.TemporaryDirectory() as d:
            bad = os.path.join(d, "capacity.py")
            with open(bad, "w") as f:
                f.write("raise RuntimeError('capacity hỏng lúc nạp')\n")
            with mock.patch.object(server, "CAPACITY_PY", bad), mock.patch.object(server, "_CAPACITY", []), \
                    mock.patch.object(server, "warn") as warned:
                self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 100.0)
                self.assertEqual(warned.call_count, 1)

    def test_capacity_broken_on_call_falls_back(self):  # Antigravity audit 23/10: nạp được nhưng hỏng khi gọi
        # file 0 byte (thiếu hold_load → AttributeError làm host_stats chết), hold_load ném lỗi, hay trả inf/nan/0/âm/chuỗi/bool
        # (inf ra "Infinity" làm hỏng JSON cả trang): bảng hiển thị 100, server không chết
        bodies = ("", "def hold_load():\n    raise RuntimeError('x')\n", "def hold_load():\n    return float('inf')\n",
                  "def hold_load():\n    return float('nan')\n", "def hold_load():\n    return 0\n",
                  "def hold_load():\n    return -5\n", "def hold_load():\n    return 'abc'\n", "def hold_load():\n    return True\n")
        for body in bodies:
            with self.subTest(body=body), tempfile.TemporaryDirectory() as d:
                bad = os.path.join(d, "capacity.py")
                with open(bad, "w") as f:
                    f.write(body)
                with mock.patch.object(server, "CAPACITY_PY", bad), mock.patch.object(server, "_CAPACITY", []), \
                        mock.patch.object(server, "warn") as warned:
                    self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 100.0)
                    self.assertEqual(server.host_stats(lock_dir="/nonexistent")["loadMax"], 100.0)
                    self.assertEqual(warned.call_count, 1)  # một dòng cảnh báo, không lặp mỗi lần bảng làm mới

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
