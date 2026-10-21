#!/usr/bin/env bash
# Trần số suite nặng chạy cùng lúc (người dùng 21/10: build_workers=10, heavy_slot=3). Suite lớp cpu/gradle/xcode lấy một slot của pool
# "heavy" (mặc định 3, DEVKIT_SLOT_HEAVY_MAX): hết slot thì XẾP HÀNG chờ (không lỗi, không UNTESTED); chờ hết ngân sách (max_wait) thì
# vẫn chạy kèm ghi chú. Suite nhẹ, suite lồng trong suite đã được cho chạy, và suite Unity (khoá riêng) không bị trần này đếm.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/heavy-cap.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
echo 1 > "$TMP/load"
export SB_HEAVY_SLOT_DIR="$TMP/locks" DEVKIT_SLOT_LOAD_FILE="$TMP/load" SB_HEAVY_SLOT_POLL_S=0.1
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD DEVKIT_SLOT_HEAVY_MAX
python3 - "$DEVKIT_DIR/bin" <<'PY'
import os, sys, threading, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs

fails = 0
def check(name, good, detail=""):
    global fails
    print(("✔ " if good else "✖ ") + name + (f" — {detail}" if detail else ""))
    if not good:
        fails += 1

CPU = {"cls": "cpu", "engine": None}
def take(info=CPU, **kw):
    t0 = time.monotonic()
    s = hs.acquire_for_suite(info, **kw)
    return s, time.monotonic() - t0

# 1. mặc định 3 slot: 3 suite nặng vào ngay, không giữ khoá Unity (held False: gate lồng vẫn xin Unity)
held = []
for i in range(3):
    s, w = take(label=f"h{i}")
    held.append(s)
    check(f"1.{i} suite nặng thứ {i + 1} vào ngay (mặc định 3 slot)", w < 0.5 and s.admitted and not s.held and s.advisory, f"{w:.2f}s")

# 2. suite thứ 4 xếp hàng: chờ tới khi có slot trả lại, KHÔNG lỗi
res = {}
def fourth():
    res["s"], res["w"] = take(label="h3")
th = threading.Thread(target=fourth); th.start()
time.sleep(0.8)
check("2a. suite thứ 4 đang xếp hàng (chưa vào)", th.is_alive())
hs.release_suite(held[0])
th.join(5)
check("2b. trả một slot: suite thứ 4 vào, được chạy (không lỗi)", not th.is_alive() and res["s"].admitted and res["w"] >= 0.7,
      f"chờ {res.get('w', -1):.2f}s")
held[0] = res["s"]

# 3. chờ hết ngân sách: vẫn chạy (không UNTESTED), có ghi chú xếp hàng
s, w = take(label="over", max_wait=0.5)
check("3. hết ngân sách chờ: vẫn được chạy kèm ghi chú, chờ ≈ ngân sách", s.admitted and 0.4 <= w < 2.0 and any("hàng" in n or "heavy" in n for n in s.notes),
      f"{w:.2f}s notes={s.notes}")
hs.release_suite(s)

# 4. suite nhẹ và suite không nói lớp: không đếm
for info in ({"cls": "light", "engine": None}, {"engine": None}):
    s, w = take(info, label="light")
    check(f"4. {info} không bị trần đếm (vào ngay khi pool đầy)", w < 0.5 and s.admitted, f"{w:.2f}s")

# 5. suite lồng trong suite đã được cho chạy: không xin slot (tránh bế tắc cha giữ slot chờ con)
os.environ["DEVKIT_SLOT_ADVISORY_HELD"] = "1"
s, w = take(label="nested")
check("5. suite lồng (DEVKIT_SLOT_ADVISORY_HELD=1) không xin slot", w < 0.5 and s.admitted, f"{w:.2f}s")
del os.environ["DEVKIT_SLOT_ADVISORY_HELD"]

# 6. gradle và xcode cũng là suite nặng
for cls in ("gradle", "xcode"):
    s, w = take({"cls": cls, "engine": cls}, label=cls, max_wait=0.3)
    check(f"6. lớp {cls} bị trần đếm (pool đầy: chờ hết ngân sách)", w >= 0.25 and s.admitted, f"{w:.2f}s")
    hs.release_suite(s)

# 7. nhả hết thì suite sau vào ngay
for s in held:
    hs.release_suite(s)
s, w = take(label="after")
check("7. nhả hết slot: suite sau vào ngay", w < 0.5 and s.admitted, f"{w:.2f}s")
hs.release_suite(s)

# 8. DEVKIT_SLOT_HEAVY_MAX đổi được trần
os.environ["DEVKIT_SLOT_HEAVY_MAX"] = "1"
a, _ = take(label="a")
b, wb = take(label="b", max_wait=0.4)
check("8. DEVKIT_SLOT_HEAVY_MAX=1: suite thứ hai phải chờ", wb >= 0.3, f"{wb:.2f}s")
hs.release_suite(a); hs.release_suite(b)
os.environ["DEVKIT_SLOT_HEAVY_MAX"] = "abc"
xs = [take(label=f"x{i}")[0] for i in range(3)]
y, wy = take(label="y", max_wait=0.4)
check("8b. giá trị rác thì dùng mặc định 3", wy >= 0.3 and all(x.admitted for x in xs), f"{wy:.2f}s")
for x in xs + [y]:
    hs.release_suite(x)

sys.exit(1 if fails else 0)
PY
RC=$?
[ "$RC" -eq 0 ] && echo "✅ test_heavy_slot_cap: all passed" || { echo "❌ test_heavy_slot_cap: failed"; exit 1; }
