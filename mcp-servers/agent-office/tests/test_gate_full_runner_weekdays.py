"""Gate speed v26 mục 6: lịch heavy gate là mảng StartCalendarInterval (Weekday 1 và 4, 00:00) do gate-full-schedule.sh --weekdays ghi.
gate_full_runner phải đọc cả dict (plist cũ) lẫn mảng, tính lần chạy kế đúng thứ, và nút bấm tay luôn chạy (--force). Không chạy
gate_full.py thật: plist trong thư mục LaunchAgents giả trỏ tới script giả chỉ ghi argv."""
import datetime as dt
import os
import plistlib
import shutil
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import gate_full_runner as gfr  # noqa: E402

FAKE = 'import json, os, sys\nopen(os.environ["FAKE_ARGV"], "w").write(json.dumps(sys.argv[1:]))\n'


class WeekdaysTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.la = os.path.join(self.tmp, "LaunchAgents")
        os.makedirs(self.la)
        self.fake = os.path.join(self.tmp, "gate_full.py")
        with open(self.fake, "w") as f:
            f.write(FAKE)
        self.argv_file = os.path.join(self.tmp, "argv.json")
        self.env = mock.patch.dict(os.environ, {"FAKE_ARGV": self.argv_file,
                                                "DEVKIT_GATE_FULL_GLOBAL_LOCK": os.path.join(self.tmp, "global.lock")})
        self.env.start()
        self.repos = {}
        for name, cal in (("arr", [{"Weekday": 1, "Hour": 0, "Minute": 0}, {"Weekday": 4, "Hour": 0, "Minute": 0}]),
                          ("dict", {"Hour": 0, "Minute": 0})):
            p = os.path.join(self.tmp, name)
            os.makedirs(os.path.join(p, ".git"))
            self.repos[name] = p
            data = {"Label": gfr.LABEL_PREFIX + name, "ProgramArguments": [sys.executable, self.fake, "run", "--repo", p],
                    "WorkingDirectory": p, "StartCalendarInterval": cal,
                    "EnvironmentVariables": {"DEVKIT_GATE_FULL_LOG_DIR": os.path.join(self.tmp, "logs", name)}}
            with open(os.path.join(self.la, gfr.LABEL_PREFIX + name + ".plist"), "wb") as f:
                plistlib.dump(data, f)
        self.g = gfr.GateFull({"gateFull": {"launchAgentsDir": self.la, "queueFile": os.path.join(self.tmp, "q.json")}})

    def tearDown(self):
        if self.g.proc:
            self.g.proc.wait(10)
        self.env.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_array_calendar_is_installed_and_status_works(self):
        st = self.g.status(self.repos)["repos"]
        self.assertTrue(st["arr"]["installed"], "plist có StartCalendarInterval là mảng phải được nhận là đã cài")
        self.assertTrue(st["dict"]["installed"])
        nxt = dt.datetime.fromtimestamp(st["arr"]["next"])
        self.assertIn(nxt.isoweekday(), (1, 4), "lần chạy kế của lịch thứ Hai + thứ Năm phải rơi vào thứ Hai hoặc thứ Năm")
        self.assertEqual((nxt.hour, nxt.minute), (0, 0))

    def test_next_run_weekdays(self):
        slots = gfr.calendar_slots([{"Weekday": 1, "Hour": 0, "Minute": 0}, {"Weekday": 4, "Hour": 0, "Minute": 0}])
        tue = dt.datetime(2026, 11, 3, 10, 0)   # thứ Ba
        self.assertEqual(dt.datetime.fromtimestamp(gfr.next_run(0, 0, tue, slots)), dt.datetime(2026, 11, 5, 0, 0))
        fri = dt.datetime(2026, 11, 6, 1, 0)    # thứ Sáu ⇒ thứ Hai tuần sau
        self.assertEqual(dt.datetime.fromtimestamp(gfr.next_run(0, 0, fri, slots)), dt.datetime(2026, 11, 9, 0, 0))
        mon = dt.datetime(2026, 11, 9, 0, 0)    # đúng 00:00 thứ Hai đã qua ⇒ thứ Năm
        self.assertEqual(dt.datetime.fromtimestamp(gfr.next_run(0, 0, mon, slots)), dt.datetime(2026, 11, 12, 0, 0))
        sun = gfr.calendar_slots([{"Weekday": 7, "Hour": 3, "Minute": 0}])   # 7 = Chủ nhật như 0
        self.assertEqual(dt.datetime.fromtimestamp(gfr.next_run(0, 0, tue, sun)), dt.datetime(2026, 11, 8, 3, 0))
        self.assertEqual(dt.datetime.fromtimestamp(gfr.next_run(0, 0, tue)), dt.datetime(2026, 11, 4, 0, 0), "không slots: mỗi ngày như cũ")

    def test_manual_run_forces(self):
        self.g.enqueue("arr", self.repos)
        end = time.time() + 20
        while time.time() < end and not os.path.exists(self.argv_file):
            self.g.tick(self.repos)
            time.sleep(0.05)
        with open(self.argv_file) as f:
            argv = __import__("json").load(f)
        self.assertEqual(argv[-1], "--force", "nút bấm tay phải chạy dù không có commit mới (--force): %r" % argv)
        self.assertEqual(argv.count("--force"), 1)


if __name__ == "__main__":
    unittest.main()
