#!/usr/bin/env bash
# Test hồi quy (P2, gate kẹt và chậm 02/11): hàng đợi vé của heavy_slot lão hoá ưu tiên — prio hiệu dụng
# = max(0, PRIORITY[prio] − ⌊đã chờ / DEVKIT_SLOT_PRIO_AGE_S⌋), mặc định 450 s; vé chờ lâu không bị đói sau vé mức cao mới đến.
#   0. heavy_slot.py nạp là bản trong CHÍNH checkout chứa test (INSTINCT-057)
#   1. vé interactive đã chờ 1000 s đứng TRƯỚC vé merge mới đến (hai vé cùng est_s: chỉ lão hoá quyết định)
#   2. vé interactive mới chờ 10 s vẫn đứng SAU vé merge (khớp ca 6 của test_gate_slot_classes.sh)
#   3. DEVKIT_SLOT_PRIO_AGE_S=5000 ⇒ chờ 1000 s chưa đủ lão hoá, merge vẫn trước; rác / 0 ⇒ mặc định 450 s, không chia cho 0
# Chỉ gọi hàm thuần queue_order (không khoá, không thư mục slot). Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_SLOT_PRIO_AGE_S DEVKIT_SLOT_PRIORITY SB_HEAVY_SLOT_HELD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"

python3 - "$DEVKIT_DIR" <<'PY'
import os, sys
devkit = sys.argv[1]
sys.path.insert(0, os.path.join(devkit, "bin"))
import heavy_slot as hs
fails = 0
def check(name, cond, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond else f" — {detail}"))
    fails += 0 if cond else 1

loaded = os.path.realpath(hs.__file__)
check("0. heavy_slot.py của checkout chứa test", loaded.startswith(devkit + os.sep), f"nạp {loaded}, checkout {devkit}")

now = 100000.0
t = lambda pid, prio, t0: {"pid": pid, "prio": prio, "est_s": 600.0, "t0": t0}
order = [x["pid"] for x in hs.queue_order([t(2, "merge", now), t(1, "interactive", now - 1000)], now)]
check("1. interactive đã chờ 1000 s đứng trước merge mới đến", order == [1, 2], f"thứ tự {order}")
order = [x["pid"] for x in hs.queue_order([t(1, "interactive", now - 10), t(2, "merge", now)], now)]
check("2. interactive mới chờ 10 s vẫn sau merge", order == [2, 1], f"thứ tự {order}")
os.environ["DEVKIT_SLOT_PRIO_AGE_S"] = "5000"
order = [x["pid"] for x in hs.queue_order([t(2, "merge", now), t(1, "interactive", now - 1000)], now)]
check("3a. DEVKIT_SLOT_PRIO_AGE_S=5000: chờ 1000 s chưa đủ, merge vẫn trước", order == [2, 1], f"thứ tự {order}")
for bad in ("0", "rác"):
    os.environ["DEVKIT_SLOT_PRIO_AGE_S"] = bad
    try:
        order = [x["pid"] for x in hs.queue_order([t(2, "merge", now), t(1, "interactive", now - 1000)], now)]
    except Exception as exc:   # noqa: BLE001 - ca đo chính việc không ném
        order = repr(exc)
    check(f"3b. DEVKIT_SLOT_PRIO_AGE_S={bad!r} ⇒ mặc định 450 s, interactive chờ 1000 s vẫn trước", order == [1, 2], f"thứ tự {order}")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && echo "PASS test_gate_slot_aging" || echo "FAIL test_gate_slot_aging"
exit "$rc"
