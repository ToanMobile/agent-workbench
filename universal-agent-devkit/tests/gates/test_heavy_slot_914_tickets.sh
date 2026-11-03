#!/usr/bin/env bash
# Test hồi quy (#914 mục 2, 3, 7): heavy_slot ghép vé, tuổi ưu tiên ghi vào vé, prio không băm được. (Mục 5, 6 sửa test có sẵn: đợt riêng chờ duyệt chéo.)
#   2. _pick_free: vé đứng trước giữ chỗ chỉ số trống NHỎ nhất < n (khớp vé hạng 0 quét từ chỉ số 0); vé này lấy chỉ số nhỏ nhất còn lại
#   3. vé ghi age_s lúc tạo; queue_order dùng age_s của vé, không đọc env của tiến trình đọc
#   7. queue_order không ném TypeError khi prio của vé không băm được (list/dict)
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_SLOT_PRIO_AGE_S DEVKIT_SLOT_PRIORITY SB_HEAVY_SLOT_HELD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
FAILS=0

python3 - "$DEVKIT_DIR" <<'PY'
import os, shutil, sys, tempfile, json
devkit = sys.argv[1]
sys.path.insert(0, os.path.join(devkit, "bin"))
import heavy_slot as hs
fails = 0
def check(name, cond, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond else f" — {detail}"))
    fails += 0 if cond else 1

r = hs._pick_free([0, 1], [{"n": 2}], 2)
check("2a. free [0,1], một vé n=2 đứng trước: vé này lấy 1 (vé trước lấy 0)", r == 1, f"được {r}")
r = hs._pick_free([0, 1, 2, 3], [{"n": 2}, {"n": 4}], 4)
check("2b. free [0..3], vé n=2 và n=4 đứng trước: vé này lấy 2 (0 và 1 là của hai vé trước)", r == 2, f"được {r}")
check("2c. không vé đứng trước: chỉ số nhỏ nhất như cũ", hs._pick_free([1, 2], [], 4) == 1)
check("2d. hết chỗ dư: None", hs._pick_free([0], [{"n": 2}], 2) is None)

now = 100000.0
qdir = tempfile.mkdtemp(prefix="dk-914-")
os.environ["DEVKIT_SLOT_PRIO_AGE_S"] = "450"
name = hs._write_ticket(qdir, "interactive", 600.0, 100.0, "t")
tk = json.load(open(os.path.join(qdir, name)))
check("3a. vé ghi age_s", tk.get("age_s") == 450.0, f"vé {tk}")
a = {"pid": 1, "prio": "interactive", "est_s": 600.0, "t0": now - 1000, "age_s": 450.0}
b = {"pid": 2, "prio": "merge", "est_s": 600.0, "t0": now, "age_s": 450.0}
os.environ["DEVKIT_SLOT_PRIO_AGE_S"] = "5000"
order = [x["pid"] for x in hs.queue_order([b, a], now)]
check("3b. env của tiến trình đọc (5000) không đảo thứ tự: age_s của vé (450) quyết", order == [1, 2], f"thứ tự {order}")
del os.environ["DEVKIT_SLOT_PRIO_AGE_S"]

try:
    order = [x["pid"] for x in hs.queue_order([{"pid": 1, "prio": ["x"], "t0": now}, {"pid": 2, "prio": {"a": 1}, "t0": now}], now)]
except Exception as exc:  # noqa: BLE001 - ca đo chính việc không ném
    order = repr(exc)
check("7. prio không băm được không ném", isinstance(order, list), f"{order}")
try:
    order = [x["pid"] for x in hs.queue_order([{"pid": 1, "prio": "merge", "t0": now, "age_s": 10 ** 400, "est_s": 10 ** 400}, {"pid": 2, "prio": "merge", "t0": 10 ** 400}], now)]
except Exception as exc:  # noqa: BLE001 - ca đo chính việc không ném
    order = repr(exc)
check("7b. số quá lớn trong vé (age_s, est_s, t0) không ném OverflowError", isinstance(order, list), f"{order}")
shutil.rmtree(qdir, ignore_errors=True)
sys.exit(1 if fails else 0)
PY
rc=$?
if [ "$rc" = 0 ] && [ "$FAILS" = 0 ]; then echo "PASS test_heavy_slot_914_tickets"; exit 0; fi
echo "FAIL test_heavy_slot_914_tickets"
exit 1
