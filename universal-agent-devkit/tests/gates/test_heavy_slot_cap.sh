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
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD DEVKIT_SLOT_HEAVY_MAX DEVKIT_SLOT_HEAVY_WAIT_S DEVKIT_SLOT_HEAVY_BUDGET_S \
  DEVKIT_SLOT_LOAD_WAIT_S SB_HEAVY_SLOT_WAIT_S DEVKIT_SLOT_ADVISORY_BUDGET_S   # merge gate / stale_rerun đặt vài biến này: test không được lệ thuộc môi trường gọi
# T0052: mặc định 3 slot / ngưỡng tải đến từ bin/capacity.py; ghim máy giả 12 lõi rảnh (heavy_max 3, hold_load 96), bỏ nút của người gọi
unset DEVKIT_CAPACITY DEVKIT_SLOT_LOAD_MAX
export DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0
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

# 9. Không có max_wait (CLI --full, merge gate): chờ hàng đợi bị chặn bởi DEVKIT_SLOT_HEAVY_WAIT_S, KHÔNG phải 3600 s của khoá Unity
#    (review 21/10: merge gate bị SIGTERM sau 3600 s nếu một suite xếp hàng cả giờ); LOAD_WAIT_S=0 (merge gate đã chờ rồi) thì không chờ.
full = [take(label=f"f{i}")[0] for i in range(3)]
os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"] = "0.6"
s, w = take(label="nomax")
check("9a. không max_wait: chờ theo DEVKIT_SLOT_HEAVY_WAIT_S rồi vẫn chạy", s.admitted and 0.5 <= w < 3.0 and s.notes, f"{w:.2f}s")
hs.release_suite(s)
del os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"]
os.environ["DEVKIT_SLOT_LOAD_WAIT_S"] = "0"; os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"] = "0.6"
s, w = take(label="nowait")
check("9b. DEVKIT_SLOT_LOAD_WAIT_S=0 chỉ nói đã chờ TẢI: suite nặng vẫn xếp hàng chờ slot (không bỏ qua trần đúng lúc pool đầy)",
      s.admitted and w >= 0.5, f"{w:.2f}s")
hs.release_suite(s)
del os.environ["DEVKIT_SLOT_LOAD_WAIT_S"]; del os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"]
# 9c. ngân sách chờ hàng đợi là của CẢ TIẾN TRÌNH (như chờ tải): k suite nối nhau không chờ k × giới hạn (review 21/10: 7 × 600 s > SIGTERM 3600 s)
hs._HEAVY_WAIT["spent"] = 0.0
os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"] = "0.8"; os.environ["DEVKIT_SLOT_HEAVY_BUDGET_S"] = "1.0"
t0 = time.monotonic()
ws = [take(label=f"b{i}")[1] for i in range(3)]
total = time.monotonic() - t0
check("9c. 3 suite xếp hàng nối nhau, ngân sách 1 s: tổng chờ ≈ ngân sách, suite sau không chờ nữa", total < 1.6 and ws[0] >= 0.7 and ws[2] < 0.3,
      f"chờ {[round(x, 2) for x in ws]} tổng {total:.2f}s")
# 9d. ngân sách đã cạn nhưng pool còn slot trống: vẫn LẤY slot (hết ngân sách chỉ nghĩa là không chờ, không phải bỏ qua trần)
hs.release_suite(full[0])
s, w = take(label="free-after-budget")
check("9d. ngân sách cạn, pool còn slot: suite lấy slot, không ghi chú, không chờ", s.admitted and w < 0.3 and not s.notes and s.handles, f"{w:.2f}s")
full[0] = s
del os.environ["DEVKIT_SLOT_HEAVY_WAIT_S"]; del os.environ["DEVKIT_SLOT_HEAVY_BUDGET_S"]
for s in full:
    hs.release_suite(s)

# 10. T0052: mặc định đi theo bin/capacity.py (số lõi), biến cũ vẫn thắng, không nạp được capacity thì hằng cũ
# ngưỡng chờ của suite (việc BẮT BUỘC) là hold_load = 8 × lõi, không phải busy_load = 3 × lõi (người dùng 20/10: "dưới 100 thì cho chạy")
check("10a. 12 lõi: heavy_max 3, load_max 96 (capacity hold_load)", hs.heavy_max() == 3 and hs.load_max() == 96.0, f"{hs.heavy_max()} {hs.load_max()}")
os.environ["DEVKIT_CAPACITY_CORES"] = "4"
check("10b. 4 lõi: heavy_max 1, load_max 32 (capacity hold_load)", hs.heavy_max() == 1 and hs.load_max() == 32.0, f"{hs.heavy_max()} {hs.load_max()}")
os.environ["DEVKIT_SLOT_HEAVY_MAX"] = "2"; os.environ["DEVKIT_SLOT_LOAD_MAX"] = "64"
check("10c. DEVKIT_SLOT_HEAVY_MAX / DEVKIT_SLOT_LOAD_MAX vẫn thắng capacity", hs.heavy_max() == 2 and hs.load_max() == 64.0,
      f"{hs.heavy_max()} {hs.load_max()}")
del os.environ["DEVKIT_SLOT_HEAVY_MAX"]; del os.environ["DEVKIT_SLOT_LOAD_MAX"]
saved_cap = list(hs._CAPACITY)
hs._CAPACITY[:] = [None]   # như kit cũ thiếu bin/capacity.py
check("10d. không có capacity: hằng cũ (3 suite nặng, tải 100)", hs.heavy_max() == 3 and hs.load_max() == 100.0, f"{hs.heavy_max()} {hs.load_max()}")
hs._CAPACITY[:] = saved_cap
os.environ["DEVKIT_CAPACITY_CORES"] = "12"

# 11. capacity.py hỏng lúc nạp (lỗi runtime, không chỉ ImportError): heavy_slot không chết theo, về hằng cũ và báo một dòng stderr
import shutil, subprocess, tempfile
with tempfile.TemporaryDirectory() as d:
    shutil.copy(os.path.join(sys.argv[1], "heavy_slot.py"), d)
    with open(os.path.join(d, "capacity.py"), "w") as f:
        f.write("raise RuntimeError('capacity hỏng lúc nạp')\n")
    r = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import heavy_slot as h; "
                        "print(h.load_max(), h.heavy_max(), h.load_max())", d], capture_output=True, text=True, timeout=30,
                       env={k: v for k, v in os.environ.items() if k not in ("DEVKIT_SLOT_LOAD_MAX", "DEVKIT_SLOT_HEAVY_MAX")})
    check("11. capacity.py ném lỗi lúc nạp: load_max 100, heavy_max 3, không traceback, một dòng cảnh báo",
          r.returncode == 0 and r.stdout.split() == ["100.0", "3", "100.0"] and "Traceback" not in r.stderr
          and r.stderr.count("capacity.py") == 1, f"rc={r.returncode} out={r.stdout!r} err={r.stderr[-300:]!r}")

# 11b. capacity.py nạp được nhưng hỏng khi gọi (Antigravity audit 23/10): file 0 byte / thiếu hàm (AttributeError làm sập gate ở
# acquire_for_suite), hàm ném lỗi, hay trả ngoài miền (0 → pool_paths rỗng = không khoá suite nặng nào, inf/nan/chuỗi/bool/số âm/số lẻ)
# → hằng cũ (tải 100, 3 suite nặng), không traceback
BROKEN = ("", "def hold_load(): return 0\ndef heavy_max(): return 0\n",
          "def hold_load(): return float('inf')\ndef heavy_max(): return True\n",
          "def hold_load(): return float('nan')\ndef heavy_max(): return 2.5\n",
          "def hold_load(): return 'abc'\ndef heavy_max(): return -1\n",
          "def hold_load(): raise RuntimeError('x')\ndef heavy_max(): raise RuntimeError('y')\n")
bad = []
for body in BROKEN:
    with tempfile.TemporaryDirectory() as d:
        shutil.copy(os.path.join(sys.argv[1], "heavy_slot.py"), d)
        with open(os.path.join(d, "capacity.py"), "w") as f:
            f.write(body)
        r = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import heavy_slot as h; "
                            "print(h.load_max(), h.heavy_max(), h.load_max())", d], capture_output=True, text=True, timeout=30,
                           env={k: v for k, v in os.environ.items() if k not in ("DEVKIT_SLOT_LOAD_MAX", "DEVKIT_SLOT_HEAVY_MAX")})
        if not (r.returncode == 0 and r.stdout.split() == ["100.0", "3", "100.0"] and "Traceback" not in r.stderr):
            bad.append(f"{body!r}: rc={r.returncode} out={r.stdout.strip()!r} err={r.stderr.strip()[-160:]!r}")
check("11b. capacity.py rỗng / thiếu hàm / hàm ném lỗi / trả 0, inf, nan, chuỗi, bool, âm, lẻ: load_max 100, heavy_max 3", not bad,
      "; ".join(bad[:3]))

sys.exit(1 if fails else 0)
PY
RC=$?
[ "$RC" -eq 0 ] && echo "✅ test_heavy_slot_cap: all passed" || { echo "❌ test_heavy_slot_cap: failed"; exit 1; }
