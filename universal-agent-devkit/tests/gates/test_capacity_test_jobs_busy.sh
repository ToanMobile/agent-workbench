#!/usr/bin/env bash
# Kiểm thử hồi quy (#787): bin/capacity.py chia test_jobs công bằng theo số slot pool "gate" đang bận
# (gate_busy()), đọc PID trong file khoá KHÔNG dùng flock để không làm hụt acquire_pool(wait_s=0) của
# bin/heavy_slot.py, xoá trắng PID dưới LOCK_EX trong heavy_slot._unlock() khi nhả khoá, giữ DEVKIT_TEST_JOBS
# làm quyền ghi đè cao nhất trong tests/run_impacted.sh, và cô lập tuyệt đối các bài test có sẵn qua SB_HEAVY_SLOT_HELD=1.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Gỡ cờ cô lập mặc định của clean_git_env.sh để kiểm thử trực tiếp cơ chế đếm slot thật của máy / thư mục giả lập
unset SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD _DEVKIT_CHILD_TEST DEVKIT_TEST_JOBS DEVKIT_TEST_JOBS_BUSY DEVKIT_TEST_CORES

TMP="$(mktemp -d)"
HOLDER_PIDS=""
cleanup() {
  for p in $HOLDER_PIDS; do
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

CAP="$DEVKIT_DIR/bin/capacity.py"
HEAVY="$DEVKIT_DIR/bin/heavy_slot.py"
RUNNER="$DEVKIT_DIR/tests/run_impacted.sh"

# Mảnh kiểm thử bằng Python stdlib: kiểm chứng toàn bộ ca 1..5 tất định, không dùng sleep mù
python3 -I - "$CAP" "$HEAVY" "$RUNNER" "$TMP" <<'PY'
import errno
import fcntl
import json
import os
import subprocess
import sys
import threading
import time

CAP, HEAVY, RUNNER, TMP = sys.argv[1:5]
BIN_DIR = os.path.dirname(CAP)
sys.path.insert(0, BIN_DIR)

fails = 0


def chk(cond, name, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond or not why else " — " + str(why)), flush=True)
    if not cond:
        fails += 1


BASE_ENV = {
    k: v for k, v in os.environ.items()
    if not k.startswith("DEVKIT_CAPACITY")
    and k not in (
        "SB_HEAVY_SLOT_HELD",
        "DEVKIT_GATE_SLOT_HELD",
        "_DEVKIT_CHILD_TEST",
        "SB_HEAVY_SLOT_DIR",
        "DEVKIT_TEST_JOBS",
        "DEVKIT_TEST_JOBS_BUSY",
        "DEVKIT_TEST_CORES",
        "DEVKIT_GATE_SLOTS",
    )
}


def run_cap(*args, **env_overrides):
    e = dict(BASE_ENV)
    e.update(env_overrides)
    r = subprocess.run([sys.executable, CAP, *args], capture_output=True, text=True, env=e, timeout=15)
    return r.returncode, r.stdout, r.stderr


def run_jobs(**env_overrides):
    e = dict(BASE_ENV)
    e.update(env_overrides)
    r = subprocess.run(["bash", RUNNER, "--jobs"], capture_output=True, text=True, env=e, timeout=15)
    return r.returncode, r.stdout, r.stderr


def spawn_lock_holder(lock_path, ready_path):
    """Mở tiến trình con giữ LOCK_EX và ghi PID thật vào lock_path như heavy_slot._try_lock_path."""
    code = (
        "import fcntl, os, sys, time\n"
        "lp, rp = sys.argv[1], sys.argv[2]\n"
        "os.makedirs(os.path.dirname(lp), exist_ok=True)\n"
        "fd = os.open(lp, os.O_CREAT | os.O_RDWR, 0o600)\n"
        "fh = os.fdopen(fd, 'r+', encoding='utf-8')\n"
        "fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
        "fh.seek(0); fh.truncate(); fh.write(f'{os.getpid()}\\n'); fh.flush()\n"
        "open(rp, 'w').write('ok')\n"
        "time.sleep(60)\n"
    )
    p = subprocess.Popen([sys.executable, "-c", code, lock_path, ready_path], env=BASE_ENV)
    deadline = time.monotonic() + 10.0
    while not os.path.exists(ready_path):
        if p.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError(f"holder chết hoặc quá hạn trên {lock_path}")
        time.sleep(0.02)
    return p


def stop_proc(p):
    if p is None:
        return
    try:
        p.terminate()
        p.wait(timeout=5)
    except Exception:
        try:
            p.kill()
            p.wait(timeout=5)
        except Exception:
            pass


# ── Ca 1: 12 lõi với DEVKIT_TEST_JOBS_BUSY=1/2/3/0 -> 16/8/5/16; sàn 4 trên 4 lõi; đồng bộ CLI gate_busy & --json ──
want_12 = [("1", "16", "1"), ("2", "8", "2"), ("3", "5", "3"), ("0", "16", "1")]
for busy_in, want_tj, want_gb in want_12:
    rc1, out1, err1 = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=busy_in)
    rc2, out2, err2 = run_cap("gate_busy", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=busy_in)
    rc3, out3, err3 = run_cap("--json", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=busy_in)
    try:
        js = json.loads(out3)
    except ValueError:
        js = {}
    chk(
        rc1 == 0 and out1.strip() == want_tj and rc2 == 0 and out2.strip() == want_gb and rc3 == 0 and js.get("test_jobs") == int(want_tj),
        f"1a. 12 lõi, DEVKIT_TEST_JOBS_BUSY={busy_in} -> test_jobs={want_tj}, gate_busy={want_gb}, --json khớp",
        f"tj=({rc1},{out1!r},{err1!r}) gb=({rc2},{out2!r},{err2!r}) json={js.get('test_jobs')!r}",
    )

rc, out, err = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="4", DEVKIT_TEST_JOBS_BUSY="3")
chk(rc == 0 and out.strip() == "4", "1b. 4 lõi, DEVKIT_TEST_JOBS_BUSY=3 -> giữ sàn 4", f"rc={rc} out={out!r} err={err!r}")

for junk in ("abc", "-2", "1.5"):
    rc, out, err = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=junk)
    chk(
        rc == 0 and out.strip() == "16" and err.strip() != "",
        f"1c. DEVKIT_TEST_JOBS_BUSY={junk!r} rác -> cảnh báo stderr, fallback 16",
        f"rc={rc} out={out!r} err={err!r}",
    )

# ── Ca 2: Tương thích ngược chữ ký Python capacity.test_jobs, snapshot(), KEYS và chặn bool ──
import capacity  # noqa: E402
import heavy_slot  # noqa: E402


def try_tj(*a, **kw):
    try:
        return capacity.test_jobs(*a, **kw)
    except TypeError:
        return None


chk(
    hasattr(capacity, "gate_busy")
    and try_tj(12, 1.0, 24.0) == 16
    and try_tj(12, 1.0, 0.0, busy=3) == 5
    and try_tj(12, 1.0, 0.0, busy=2) == 8
    and try_tj(12, 1.0, 0.0, busy=1) == 16
    and try_tj(12, 1.0, 0.0, busy=0) == 16,
    "2a. chữ ký Python tương thích ngược (3 đối số vị trí = 16; busy=3/2/1/0 = 5/8/16/16)",
)
chk(
    try_tj(12, 1.0, 0.0, busy=True) == 16 and try_tj(12, 1.0, 0.0, busy=False) == 16,
    "2b. chặn kiểu bool (busy=True/False không bị coi là int 1/0 hợp lệ)",
)

# ── Ca 3: Đếm slot thật trong SB_HEAVY_SLOT_DIR (PID sống, PID chết, khử trùng PID, _unlock xoá PID, không tạo file rác) ──
slots_dir = os.path.join(TMP, "slots")
os.makedirs(slots_dir, exist_ok=True)
h1 = spawn_lock_holder(os.path.join(slots_dir, "gate-1.lock"), os.path.join(TMP, "r1"))
h2 = spawn_lock_holder(os.path.join(slots_dir, "gate-2.lock"), os.path.join(TMP, "r2"))
try:
    rc_gb, out_gb, _ = run_cap("gate_busy", DEVKIT_CAPACITY_CORES="12", SB_HEAVY_SLOT_DIR=slots_dir)
    rc_tj, out_tj, _ = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", SB_HEAVY_SLOT_DIR=slots_dir)
    no_stray = not os.path.exists(os.path.join(slots_dir, "gate-3.lock"))
    chk(
        rc_gb == 0 and out_gb.strip() == "2" and rc_tj == 0 and out_tj.strip() == "8" and no_stray,
        "3a. 2 holder sống trên gate-1..2.lock -> gate_busy=2, test_jobs=8, không tạo rác gate-3.lock",
        f"gb={out_gb!r} tj={out_tj!r} no_stray={no_stray}",
    )

    # Ghi một PID chắc chắn đã thoát vào gate-3.lock -> không được đếm
    dead_proc = subprocess.Popen([sys.executable, "-c", "pass"], env=BASE_ENV)
    dead_proc.wait(timeout=5)
    with open(os.path.join(slots_dir, "gate-3.lock"), "w", encoding="utf-8") as fh:
        fh.write(f"{dead_proc.pid}\n")
    rc_tj2, out_tj2, _ = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", SB_HEAVY_SLOT_DIR=slots_dir)
    chk(rc_tj2 == 0 and out_tj2.strip() == "8", "3b. PID đã chết trong gate-3.lock bị bỏ qua -> vẫn test_jobs=8", f"out={out_tj2!r}")

    # Cùng 1 PID sống nằm ở 2 file khoá -> khử trùng tập hợp còn 1
    dup_dir = os.path.join(TMP, "dup_slots")
    os.makedirs(dup_dir, exist_ok=True)
    for idx in (1, 2):
        with open(os.path.join(dup_dir, f"gate-{idx}.lock"), "w", encoding="utf-8") as fh:
            fh.write(f"{os.getpid()}\n")
    gb_dup = capacity.gate_busy(12, 1.0, slot_dir=dup_dir) if hasattr(capacity, "gate_busy") else -1
    chk(gb_dup == 1, "3c. cùng 1 PID sống trên nhiều file gate-*.lock được khử trùng còn busy=1", f"got={gb_dup}")

    # Tiến trình đang sống gọi heavy_slot.acquire_pool rồi release_pool -> _unlock xoá PID dưới LOCK_EX, không đếm thừa
    rel_dir = os.path.join(TMP, "rel_slots")
    os.environ["SB_HEAVY_SLOT_DIR"] = rel_dir
    try:
        paths = heavy_slot.pool_paths("gate", 3, lock_dir=rel_dir)
        leased = heavy_slot.acquire_pool("gate", paths, wait_s=0)
        during = capacity.gate_busy(12, 1.0, slot_dir=rel_dir) if hasattr(capacity, "gate_busy") else -1
        heavy_slot.release_pool(leased)
        after_body = open(leased.path, encoding="utf-8").read() if leased.path and os.path.exists(leased.path) else ""
        # Đặt thêm 1 holder khác (h1.pid) vào gate-2.lock để phân biệt busy=1 (đã xoá PID tiến trình này) với busy=2 (chưa xoá)
        with open(os.path.join(rel_dir, "gate-2.lock"), "w", encoding="utf-8") as fh:
            fh.write(f"{h1.pid}\n")
        after_with_h1 = capacity.gate_busy(12, 1.0, slot_dir=rel_dir) if hasattr(capacity, "gate_busy") else -1
        chk(
            not leased.timed_out and during == 1 and after_body == "" and after_with_h1 == 1,
            "3d. tiến trình sống sau heavy_slot.release_pool xoá trắng PID dưới LOCK_EX -> không đếm thừa",
            f"during={during} body={after_body!r} after_with_h1={after_with_h1}",
        )
    finally:
        os.environ.pop("SB_HEAVY_SLOT_DIR", None)

    # ── Ca 4: Tích hợp run_impacted.sh --jobs, override DEVKIT_TEST_JOBS, đường dẫn hỏng & chống treo FIFO ──
    rc_ri, out_ri, err_ri = run_jobs(DEVKIT_TEST_CORES="12", SB_HEAVY_SLOT_DIR=slots_dir)
    chk(rc_ri == 0 and out_ri.strip() == "8", "4a. run_impacted.sh --jobs trên 12 lõi + 2 lock sống -> 8", f"rc={rc_ri} out={out_ri!r} err={err_ri!r}")

    rc_ov, out_ov, _ = run_jobs(DEVKIT_TEST_CORES="12", SB_HEAVY_SLOT_DIR=slots_dir, DEVKIT_TEST_JOBS="7")
    chk(rc_ov == 0 and out_ov.strip() == "7", "4b. DEVKIT_TEST_JOBS=7 thắng cả gate_busy (override cao nhất)", f"out={out_ov!r}")

    not_a_dir = os.path.join(TMP, "regular_file")
    open(not_a_dir, "w").write("x")
    dangling = os.path.join(TMP, "dangling_link")
    os.symlink(os.path.join(TMP, "missing_target"), dangling)
    for label, bad_path in (("file thường", not_a_dir), ("symlink đứt", dangling)):
        rc_b1, out_b1, err_b1 = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", SB_HEAVY_SLOT_DIR=bad_path)
        rc_b2, out_b2, _ = run_jobs(DEVKIT_TEST_CORES="12", SB_HEAVY_SLOT_DIR=bad_path)
        chk(
            rc_b1 == 0 and out_b1.strip() == "16" and err_b1.strip() != "" and rc_b2 == 0 and out_b2.strip() == "16",
            f"4c. SB_HEAVY_SLOT_DIR là {label} -> capacity cảnh báo stderr & trả 16, run_impacted --jobs trả 16",
            f"cap=({rc_b1},{out_b1!r},{err_b1!r}) ri=({rc_b2},{out_b2!r})",
        )

    missing_dir = os.path.join(TMP, "never_created_locks")
    rc_m, out_m, err_m = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", SB_HEAVY_SLOT_DIR=missing_dir)
    chk(
        rc_m == 0 and out_m.strip() == "16" and err_m == "" and not os.path.exists(missing_dir),
        "4d. thư mục khoá chưa từng tạo -> trả 16 im lặng, không tự tạo thư mục",
        f"rc={rc_m} out={out_m!r} err={err_m!r}",
    )

    fifo_dir = os.path.join(TMP, "fifo_slots")
    os.makedirs(fifo_dir, exist_ok=True)
    os.mkfifo(os.path.join(fifo_dir, "gate-1.lock"))
    with open(os.path.join(fifo_dir, "gate-2.lock"), "w", encoding="utf-8") as fh:
        fh.write("9" * 60 + "\n")  # kiểm luôn số nguyên khổng lồ không ném OverflowError
    t_fifo = time.monotonic()
    rc_f, out_f, err_f = run_cap("gate_busy", SB_HEAVY_SLOT_DIR=fifo_dir, DEVKIT_GATE_SLOTS="9" * 50)
    dt_fifo = time.monotonic() - t_fifo
    chk(
        rc_f == 0 and out_f.strip() == "1" and dt_fifo < 5.0 and "Traceback" not in err_f,
        "4e. gate-1.lock là FIFO không writer + PID tràn + DEVKIT_GATE_SLOTS khổng lồ -> không treo, không OverflowError",
        f"rc={rc_f} out={out_f!r} dt={dt_fifo:.2f}s err={err_f!r}",
    )

    # ── Ca 5: Chứng minh đọc thuần KHÔNG giữ flock làm hụt acquire_pool(wait_s=0) trên slot trống ──
    race_dir = os.path.join(TMP, "race_slots")
    os.makedirs(race_dir, exist_ok=True)
    r_holder = spawn_lock_holder(os.path.join(race_dir, "gate-1.lock"), os.path.join(TMP, "r_race"))
    stop_flag = threading.Event()
    probe_errors = []

    def reader_loop():
        while not stop_flag.is_set():
            try:
                if hasattr(capacity, "gate_busy"):
                    v = capacity.gate_busy(12, 1.0, slot_dir=race_dir)
                    if v not in (1, 2):
                        probe_errors.append(f"unexpected gate_busy={v}")
            except Exception as exc:  # noqa: BLE001
                probe_errors.append(repr(exc))

    th = threading.Thread(target=reader_loop, daemon=True)
    th.start()
    missed = 0
    os.environ["SB_HEAVY_SLOT_DIR"] = race_dir
    try:
        race_paths = [os.path.join(race_dir, "gate-1.lock"), os.path.join(race_dir, "gate-2.lock")]
        for _ in range(60):
            ph = heavy_slot.acquire_pool("gate", race_paths, wait_s=0)
            if ph.timed_out or ph.fh is None:
                missed += 1
            heavy_slot.release_pool(ph)
    finally:
        stop_flag.set()
        th.join(timeout=3)
        os.environ.pop("SB_HEAVY_SLOT_DIR", None)
        stop_proc(r_holder)
    chk(
        missed == 0 and not probe_errors,
        "5. đọc thuần không giữ flock: 60/60 lần acquire_pool(wait_s=0) trên slot trống thành công khi gate_busy chạy song song",
        f"missed={missed} errors={probe_errors[:3]}",
    )
finally:
    stop_proc(h1)
    stop_proc(h2)

sys.exit(1 if fails else 0)
PY
PY_RC=$?

# ── Ca 6: Bảo vệ tuyệt đối test_capacity.sh và test_run_impacted_order.sh ngay khi giữ 2 khoá sống + DEVKIT_TEST_JOBS_BUSY=3 ──
SLOTS6="$TMP/slots6"
mkdir -p "$SLOTS6"
for idx in 1 2; do
  python3 -c '
import fcntl, os, sys, time
lp, rp = sys.argv[1], sys.argv[2]
fd = os.open(lp, os.O_CREAT | os.O_RDWR, 0o600)
fh = os.fdopen(fd, "r+", encoding="utf-8")
fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
fh.seek(0); fh.truncate(); fh.write(f"{os.getpid()}\n"); fh.flush()
open(rp, "w").write("ok")
time.sleep(60)
' "$SLOTS6/gate-$idx.lock" "$TMP/s6_$idx" &
  HOLDER_PIDS="$HOLDER_PIDS $!"
done
for idx in 1 2; do
  w=0
  while [ ! -f "$TMP/s6_$idx" ] && [ "$w" -lt 200 ]; do
    sleep 0.02
    w=$((w + 1))
  done
done

FAILS=0
if [ "$PY_RC" -ne 0 ]; then
  FAILS=$((FAILS + 1))
fi

if SB_HEAVY_SLOT_DIR="$SLOTS6" DEVKIT_TEST_JOBS_BUSY=3 bash "$DEVKIT_DIR/tests/gates/test_capacity.sh" >"$TMP/cap.out" 2>&1; then
  echo "✔ 6a. test_capacity.sh vẫn PASS khi SB_HEAVY_SLOT_DIR đang giữ 2 lock sống + DEVKIT_TEST_JOBS_BUSY=3"
else
  echo "✖ 6a. test_capacity.sh bị rò trạng thái slot bận:"
  tail -n 20 "$TMP/cap.out"
  FAILS=$((FAILS + 1))
fi

if SB_HEAVY_SLOT_DIR="$SLOTS6" DEVKIT_TEST_JOBS_BUSY=3 bash "$DEVKIT_DIR/tests/verification/test_run_impacted_order.sh" >"$TMP/order.out" 2>&1; then
  echo "✔ 6b. test_run_impacted_order.sh vẫn PASS khi SB_HEAVY_SLOT_DIR đang giữ 2 lock sống + DEVKIT_TEST_JOBS_BUSY=3"
else
  echo "✖ 6b. test_run_impacted_order.sh bị rò trạng thái slot bận:"
  tail -n 20 "$TMP/order.out"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -ne 0 ]; then
  echo "❌ test_capacity_test_jobs_busy: $FAILS nhóm kiểm thử THẤT BẠI"
  exit 1
fi
echo "✅ test_capacity_test_jobs_busy: tất cả PASS"
