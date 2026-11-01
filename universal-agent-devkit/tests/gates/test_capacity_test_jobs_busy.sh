#!/usr/bin/env bash
# Kiểm thử hồi quy (#787): bin/capacity.py chia test_jobs theo số slot pool "gate" đang bận (gate_busy()),
# đếm MỌI marker nguyên tử gate-*.lock.held có PID sống từ bin/heavy_slot.py (chỉ pool "gate", chỉ got[0],
# không ghi khi wait_s == 0, xoá trước _unlock), giữ capacity.py tự đủ bằng stdlib thuần, tuân thủ đúng 4 bước
# ưu tiên chọn b, chịu lỗi OSError trên từng slot lẻ, giữ DEVKIT_TEST_JOBS làm override cao nhất và bảo vệ test cũ.
# Tương thích bash 3.2; tuyệt đối không export DEVKIT_TEST_JOBS_BUSY sang tiến trình con ngoài lệnh đo.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Gỡ mọi biến cấu hình / cờ giữ slot từ môi trường gọi (đặc biệt SB_HEAVY_SLOT_HELD=1 do clean_git_env.sh:44 đặt
# và DEVKIT_CAPACITY=0.75 từ gate-full đêm launchd) trước khi chạy các ca kiểm thử.
for _v in $(compgen -v DEVKIT_CAPACITY 2>/dev/null || true) $(compgen -v DEVKIT_TEST_JOBS 2>/dev/null || true); do
  unset "$_v"
done
unset _v SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD \
  DEVKIT_TEST_JOBS DEVKIT_TEST_JOBS_BUSY DEVKIT_TEST_CORES DEVKIT_GATE_SLOTS \
  DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD SB_HEAVY_SLOT_DIR

TMP="$(mktemp -d)"
HOLDER_PIDS=""
cleanup() {
  for p in $HOLDER_PIDS; do
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done
  chmod -R u+rwX "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

CAP="$DEVKIT_DIR/bin/capacity.py"
HEAVY="$DEVKIT_DIR/bin/heavy_slot.py"
RUNNER="$DEVKIT_DIR/tests/run_impacted.sh"

# Khối kiểm thử Python stdlib cho Ca 1..3, 5..7 (tất định, chờ theo tín hiệu file, không sleep mù)
python3 -I - "$CAP" "$HEAVY" "$RUNNER" "$TMP" <<'PY'
import contextlib
import io
import json
import math
import os
import shutil
import signal
import socket
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
    and not k.startswith("DEVKIT_TEST_JOBS")
    and k not in (
        "SB_HEAVY_SLOT_HELD",
        "DEVKIT_GATE_SLOT_HELD",
        "DEVKIT_SLOT_ADVISORY_HELD",
        "SB_HEAVY_SLOT_DIR",
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


HOLDER_CODE = """
import os, sys, time
bin_dir, ready_path, rel_req, rel_ack = sys.argv[1:5]
sys.path.insert(0, bin_dir)
import heavy_slot
paths = heavy_slot.pool_paths("gate", 3)
h = heavy_slot.acquire_pool("gate", paths, wait_s=5.0)
if h.timed_out or h.fh is None:
    sys.exit(2)
with open(ready_path, "w", encoding="utf-8") as f:
    f.write(f"{os.getpid()} {h.path}\\n")
released = False
deadline = time.monotonic() + 60.0
while time.monotonic() < deadline:
    if not released and rel_req and os.path.exists(rel_req):
        heavy_slot.release_pool(h)
        released = True
        if rel_ack:
            with open(rel_ack, "w", encoding="utf-8") as f:
                f.write("released\\n")
    time.sleep(0.02)
"""


def spawn_gate_holder(ready_path, slots_dir=None, home_dir=None, rel_req="", rel_ack=""):
    """Mở tiến trình con gọi THẬT heavy_slot.acquire_pool('gate', ..., wait_s=5.0) và giữ slot tới khi có tín hiệu."""
    env = dict(BASE_ENV)
    if slots_dir is not None:
        env["SB_HEAVY_SLOT_DIR"] = slots_dir
    if home_dir is not None:
        env["HOME"] = home_dir
    p = subprocess.Popen([sys.executable, "-I", "-c", HOLDER_CODE, BIN_DIR, ready_path, rel_req, rel_ack], env=env)
    deadline = time.monotonic() + 10.0
    while not os.path.exists(ready_path):
        if p.poll() is not None or time.monotonic() >= deadline:
            try:
                p.kill()
                p.wait(timeout=2)
            except Exception:
                pass
            raise RuntimeError(f"holder acquire_pool thất bại hoặc quá hạn ({ready_path})")
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


# ── Ca 1: CORES=12 BUSY=3/2/1 -> 5/8/16; CORES=4 BUSY=3 -> 4; hệ số 0.75 -> 12/6; bác bỏ rác / bool / ≤ 0 ──
for busy_in, want_tj in (("3", "5"), ("2", "8"), ("1", "16")):
    rc1, out1, err1 = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=busy_in)
    rc2, out2, err2 = run_cap("--json", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=busy_in)
    try:
        js = json.loads(out2)
    except ValueError:
        js = {}
    chk(
        rc1 == 0
        and out1.strip() == want_tj
        and rc2 == 0
        and js.get("test_jobs") == int(want_tj)
        and js.get("gate_busy") == int(busy_in),
        f"1a. 12 lõi, DEVKIT_TEST_JOBS_BUSY={busy_in} -> test_jobs={want_tj}, --json khớp cả test_jobs lẫn gate_busy",
        f"tj=({rc1},{out1!r},{err1!r}) json=({js.get('test_jobs')!r},{js.get('gate_busy')!r})",
    )

rc_f4, out_f4, err_f4 = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="4", DEVKIT_TEST_JOBS_BUSY="3")
rc_ld1, out_ld1, _ = run_cap("test_jobs", DEVKIT_CAPACITY="0.75", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY="1")
rc_ld2, out_ld2, _ = run_cap("test_jobs", DEVKIT_CAPACITY="0.75", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY="2")
chk(
    rc_f4 == 0 and out_f4.strip() == "4" and rc_ld1 == 0 and out_ld1.strip() == "12" and rc_ld2 == 0 and out_ld2.strip() == "6",
    "1b. 4 lõi BUSY=3 giữ sàn 4; hệ số 0.75 trên 12 lõi với BUSY=1/2 -> 12/6",
    f"f4={out_f4!r} ld1={out_ld1!r} ld2={out_ld2!r} err={err_f4!r}",
)

for junk in ("0", "-2", "abc", "1.5", "9" * 400):
    rc, out, err = run_cap("test_jobs", DEVKIT_CAPACITY_CORES="12", DEVKIT_TEST_JOBS_BUSY=junk)
    chk(
        rc == 0 and out.strip() == "16" and err.strip() != "",
        f"1c. DEVKIT_TEST_JOBS_BUSY={junk[:8]!r} không nguyên ≥ 1 -> cảnh báo stderr, fallback 16",
        f"rc={rc} out={out!r} err={err!r}",
    )

import capacity  # noqa: E402
import heavy_slot  # noqa: E402


def try_tj(*a, **kw):
    try:
        return capacity.test_jobs(*a, **kw)
    except TypeError:
        return None


def try_gb(*a, **kw):
    fn = getattr(capacity, "gate_busy", None)
    return -1 if fn is None else fn(*a, **kw)


chk(
    hasattr(capacity, "gate_busy")
    and try_tj(12, 1.0, 24.0) == 16
    and try_tj(12, 1.0, 0.0, busy=3) == 5
    and try_tj(12, 1.0, 0.0, busy=2) == 8
    and try_tj(12, 1.0, 0.0, busy=1) == 16,
    "1d. chữ ký Python tương thích ngược (3 đối số vị trí = 16; busy=3/2/1 = 5/8/16)",
)

os.environ["DEVKIT_TEST_JOBS_BUSY"] = "3"
try:
    b_int1 = try_tj(12, 1.0, 0.0, busy=1)
    b_zero = try_tj(12, 1.0, 0.0, busy=0)
    b_true = try_tj(12, 1.0, 0.0, busy=True)
    b_false = try_tj(12, 1.0, 0.0, busy=False)
    b_neg = try_tj(12, 1.0, 0.0, busy=-1)
finally:
    os.environ.pop("DEVKIT_TEST_JOBS_BUSY", None)
chk(
    (b_int1, b_zero, b_true, b_false, b_neg) == (16, 5, 5, 5, 5),
    "1e. bác bỏ thật kiểu bool & ≤ 0 (busy=1 -> 16 thắng BUSY=3; busy=0/True/False/-1 bị bác -> rơi xuống BUSY=3 -> 5)",
    f"got={(b_int1, b_zero, b_true, b_false, b_neg)}",
)

# Tính số kỳ vọng động theo số lõi và hệ số thực của cùng tiến trình (không giả định cứng máy 12 lõi ngoài Ca 1)
real_c = capacity.cores()
real_s = capacity.scale()
want_b1 = max(4, int(math.floor(real_c * 4 * real_s / 3 + 1e-9)))
want_b2 = max(4, int(math.floor(real_c * 4 * real_s / 6 + 1e-9)))

# ── Ca 2: acquire_pool("gate") thật, marker .held nguyên tử, got[1:], tiến trình lặp không chặn wait_s=0, release_pool, SIGKILL, OSError ──
slots_dir = os.path.join(TMP, "slots")
os.makedirs(slots_dir, exist_ok=True)
h1 = h2 = h3 = h_rank2 = None
try:
    rel_req1 = os.path.join(TMP, "rel_req1")
    rel_ack1 = os.path.join(TMP, "rel_ack1")
    h1 = spawn_gate_holder(os.path.join(TMP, "r1"), slots_dir=slots_dir, rel_req=rel_req1, rel_ack=rel_ack1)
    h2 = spawn_gate_holder(os.path.join(TMP, "r2"), slots_dir=slots_dir)

    held_names = sorted(n for n in os.listdir(slots_dir) if n.endswith(".held"))
    rc_gb, out_gb, _ = run_cap("gate_busy", SB_HEAVY_SLOT_DIR=slots_dir)
    rc_tj, out_tj, _ = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=slots_dir)
    rc_js, out_js, _ = run_cap("--json", SB_HEAVY_SLOT_DIR=slots_dir)
    js_live = json.loads(out_js) if rc_js == 0 else {}
    chk(
        held_names == ["gate-1.lock.held", "gate-2.lock.held"]
        and rc_gb == 0
        and out_gb.strip() == "2"
        and rc_tj == 0
        and out_tj.strip() == str(want_b2)
        and js_live.get("gate_busy") == 2
        and js_live.get("test_jobs") == want_b2,
        f"2a. 2 holder acquire_pool('gate') thật (không đặt CORES/LOAD) -> đúng 2 file .held, gate_busy=2, test_jobs={want_b2}",
        f"held={held_names} gb={out_gb!r} tj={out_tj!r} json={js_live}",
    )

    os.environ["SB_HEAVY_SLOT_DIR"] = slots_dir
    try:
        sim_py = try_tj(12, 1.0, 24.0)
    finally:
        os.environ.pop("SB_HEAVY_SLOT_DIR", None)
    rc_sim_c, out_sim_c, _ = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=slots_dir, DEVKIT_CAPACITY_CORES="12")
    rc_sim_l, out_sim_l, _ = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=slots_dir, DEVKIT_CAPACITY_LOAD="0")
    chk(
        sim_py == 16 and rc_sim_c == 0 and out_sim_c.strip() == "16" and rc_sim_l == 0 and out_sim_l.strip() == str(want_b1),
        "2b. luật giả lập bước 3 (cores_arg / DEVKIT_CAPACITY_CORES / DEVKIT_CAPACITY_LOAD) thắng SB_HEAVY_SLOT_DIR đang bận",
        f"sim_py={sim_py} sim_c={out_sim_c!r} sim_l={out_sim_l!r}(want {want_b1})",
    )

    # Khi 3 slot trống và rank >= 1 thăm cả 3 slot: chỉ giữ got[0] -> đúng 1 file .held (got[1:] nhả ra không có marker)
    rank_dir = os.path.join(TMP, "rank_slots")
    qdir = os.path.join(rank_dir, "queue", "gate")
    os.makedirs(qdir, exist_ok=True)
    ahead_ticket = os.path.join(qdir, f"{h2.pid}-ahead.json")
    with open(ahead_ticket, "w", encoding="utf-8") as fh:
        json.dump(
            {"pid": h2.pid, "prio": "merge", "est_s": 1.0, "t0": time.time(), "wait_s": 60.0, "label": "ahead", "cont": False},
            fh,
        )
    os.environ["SB_HEAVY_SLOT_DIR"] = rank_dir
    try:
        r_paths = heavy_slot.pool_paths("gate", 3, lock_dir=rank_dir)
        leased = heavy_slot.acquire_pool("gate", r_paths, wait_s=5.0, prio="interactive")
        os.remove(ahead_ticket)
        probed_locks = sorted(n for n in os.listdir(rank_dir) if n.endswith(".lock"))
        held_only_one = sorted(n for n in os.listdir(rank_dir) if n.endswith(".held"))
        held_body = open(leased.path + ".held", encoding="utf-8").read().strip() if os.path.exists(leased.path + ".held") else ""
        h_rank2 = spawn_gate_holder(os.path.join(TMP, "r_rank2"), slots_dir=rank_dir)
        during_two = try_gb(slot_dir=rank_dir)
        heavy_slot.release_pool(leased)
        held_gone = not os.path.exists(leased.path + ".held")
        lock_still_has_pid = open(leased.path, encoding="utf-8").read().strip() == str(os.getpid())
        after_one = try_gb(slot_dir=rank_dir)
        chk(
            not leased.timed_out
            and probed_locks == ["gate-1.lock", "gate-2.lock", "gate-3.lock"]
            and held_only_one == ["gate-1.lock.held"]
            and held_body == str(os.getpid())
            and during_two == 2
            and held_gone
            and lock_still_has_pid
            and after_one == 1,
            "2c. khi 3 slot trống (rank>=1 thăm cả 3) chỉ ghi đúng 1 file .held; release_pool xoá .held (2->1) và bỏ qua PID cũ trong .lock",
            f"locks={probed_locks} held={held_only_one} body={held_body!r} during={during_two} gone={held_gone} after={after_one}",
        )
    finally:
        os.environ.pop("SB_HEAVY_SLOT_DIR", None)
        stop_proc(h_rank2)
        h_rank2 = None

    # Tiến trình lặp gọi capacity.py test_jobs liên tục trong khi tiến trình khác gọi acquire_pool("gate", wait_s=0) -> luôn lấy được
    race_dir = os.path.join(TMP, "race_slots")
    os.makedirs(race_dir, exist_ok=True)
    r_holder = None
    stop_flag = threading.Event()
    probe_errors = []

    def cli_reader_loop():
        while not stop_flag.is_set():
            try:
                rc_r, out_r, _ = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=race_dir)
                if rc_r != 0 or out_r.strip() not in (str(want_b1), str(want_b2)):
                    probe_errors.append(f"cli rc={rc_r} out={out_r!r}")
                v = try_gb(slot_dir=race_dir)
                if v != 1:
                    probe_errors.append(f"unexpected gate_busy={v}")
            except Exception as exc:  # noqa: BLE001
                probe_errors.append(repr(exc))

    try:
        r_holder = spawn_gate_holder(os.path.join(TMP, "r_race"), slots_dir=race_dir)
        th = threading.Thread(target=cli_reader_loop, daemon=True)
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
                time.sleep(0.002)
        finally:
            os.environ.pop("SB_HEAVY_SLOT_DIR", None)
            stop_flag.set()
            th.join(timeout=5)
    finally:
        stop_proc(r_holder)
    chk(
        missed == 0 and not probe_errors,
        "2d. tiến trình lặp gọi capacity.py test_jobs liên tục không chặn acquire_pool('gate', wait_s=0) (60/60 thành công, gate_busy luôn=1)",
        f"missed={missed} errors={probe_errors[:3]}",
    )

    # Holder nền tự release_pool (tiến trình vẫn sống) -> marker mất, gate_busy=1; kill -9 holder còn lại -> marker còn nhưng PID chết không đếm
    with open(rel_req1, "w", encoding="utf-8") as fh:
        fh.write("go\n")
    deadline = time.monotonic() + 5.0
    while not os.path.exists(rel_ack1) and time.monotonic() < deadline:
        time.sleep(0.02)
    h1_held_path = open(os.path.join(TMP, "r1"), encoding="utf-8").read().split()[1] + ".held"
    h1_alive_after_rel = h1.poll() is None
    h1_held_gone = not os.path.exists(h1_held_path)
    gb_after_h1_rel = try_gb(slot_dir=slots_dir)

    h3 = spawn_gate_holder(os.path.join(TMP, "r3"), slots_dir=slots_dir)
    h3_held_path = open(os.path.join(TMP, "r3"), encoding="utf-8").read().split()[1] + ".held"
    gb_before_kill = try_gb(slot_dir=slots_dir)
    os.kill(h3.pid, signal.SIGKILL)
    h3.wait(timeout=5)
    h3_marker_remains = os.path.exists(h3_held_path)
    gb_after_kill = try_gb(slot_dir=slots_dir)
    h3 = None
    chk(
        h1_alive_after_rel
        and h1_held_gone
        and gb_after_h1_rel == 1
        and gb_before_kill == 2
        and h3_marker_remains
        and gb_after_kill == 1,
        "2e. holder sống gọi release_pool xoá marker (2->1); kill -9 holder khác để lại .held nhưng PID chết không đếm (2->1)",
        f"alive={h1_alive_after_rel} after_rel={gb_after_h1_rel} before_kill={gb_before_kill} marker={h3_marker_remains} after_kill={gb_after_kill}",
    )

    # Chịu lỗi OSError/symlink/socket/FIFO trên từng slot lẻ mà không che khuất PID sống ở slot khác
    err_dir = os.path.join(TMP, "err_slots")
    os.makedirs(err_dir, exist_ok=True)
    os.symlink(os.path.join(err_dir, "missing"), os.path.join(err_dir, "gate-1.lock.held"))
    p_unreadable = os.path.join(err_dir, "gate-2.lock.held")
    with open(p_unreadable, "w", encoding="utf-8") as fh:
        fh.write(f"{os.getpid()}\n")
    if os.geteuid() != 0:
        os.chmod(p_unreadable, 0)
    else:
        os.unlink(p_unreadable)
        os.mkdir(p_unreadable)
    sock_obj = None
    sock_path = os.path.join(err_dir, "gate-3.lock.held")
    try:
        sock_obj = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock_obj.bind(sock_path)
    except OSError:
        if sock_obj is not None:
            sock_obj.close()
            sock_obj = None
        os.mkdir(sock_path)
    os.mkfifo(os.path.join(err_dir, "gate-4.lock.held"))
    with open(os.path.join(err_dir, "gate-5.lock.held"), "w", encoding="utf-8") as fh:
        fh.write("9" * 60 + "\n")
    for idx, pid_val in ((6, os.getpid()), (7, os.getpid()), (8, h1.pid), (9, h2.pid)):
        with open(os.path.join(err_dir, f"gate-{idx}.lock.held"), "w", encoding="utf-8") as fh:
            fh.write(f"{pid_val}\n")
    try:
        err_buf = io.StringIO()
        t_err = time.monotonic()
        with contextlib.redirect_stderr(err_buf):
            gb_err_resilient = try_gb(err_dir)
        dt_err = time.monotonic() - t_err
    finally:
        if sock_obj is not None:
            sock_obj.close()
        if os.path.exists(p_unreadable) and not os.path.isdir(p_unreadable):
            os.chmod(p_unreadable, 0o600)
    chk(
        gb_err_resilient == 3 and dt_err < 5.0 and err_buf.getvalue().strip() != "",
        "2f. lỗi symlink/chmod0/socket/FIFO/PID tràn ở slot 1..5 không treo và không che khuất 3 PID sống khử trùng ở slot 6..9",
        f"resilient={gb_err_resilient} dt={dt_err:.2f}s err={err_buf.getvalue()[:160]!r}",
    )

    # ── Ca 3: Tích hợp run_impacted.sh --jobs, override DEVKIT_TEST_JOBS=7, và SB_HEAVY_SLOT_DIR trỏ tới FILE / symlink ──
    h3 = spawn_gate_holder(os.path.join(TMP, "r3_extra"), slots_dir=slots_dir)
    rc_ri, out_ri, err_ri = run_jobs(SB_HEAVY_SLOT_DIR=slots_dir)
    chk(
        rc_ri == 0 and out_ri.strip() == str(want_b2),
        f"3a. run_impacted.sh --jobs với 2 slot acquire_pool('gate') sống -> {want_b2} (khớp Ca 2)",
        f"rc={rc_ri} out={out_ri!r} err={err_ri!r}",
    )

    rc_ov, out_ov, _ = run_jobs(SB_HEAVY_SLOT_DIR=slots_dir, DEVKIT_TEST_JOBS="7")
    chk(rc_ov == 0 and out_ov.strip() == "7", "3b. DEVKIT_TEST_JOBS=7 thắng cả gate_busy (override cao nhất)", f"out={out_ov!r}")

    not_a_dir = os.path.join(TMP, "regular_file")
    with open(not_a_dir, "w", encoding="utf-8") as fh:
        fh.write("x")
    dangling = os.path.join(TMP, "dangling_link")
    os.symlink(os.path.join(TMP, "missing_target"), dangling)
    for label, bad_path in (("file thường", not_a_dir), ("symlink đứt", dangling)):
        rc_b1, out_b1, err_b1 = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=bad_path)
        rc_b2, out_b2, _ = run_jobs(SB_HEAVY_SLOT_DIR=bad_path)
        chk(
            rc_b1 == 0 and out_b1.strip() == str(want_b1) and err_b1.strip() != "" and rc_b2 == 0 and out_b2.strip() == str(want_b1),
            f"3c. SB_HEAVY_SLOT_DIR trỏ tới {label} -> capacity.py cảnh báo stderr & trả {want_b1} (b=1), run_impacted --jobs trả {want_b1}",
            f"cap=({rc_b1},{out_b1!r},{err_b1!r}) ri=({rc_b2},{out_b2!r})",
        )

    missing_dir = os.path.join(TMP, "never_created_locks")
    rc_m, out_m, err_m = run_cap("test_jobs", SB_HEAVY_SLOT_DIR=missing_dir)
    chk(
        rc_m == 0 and out_m.strip() == str(want_b1) and err_m == "" and not os.path.exists(missing_dir),
        f"3d. thư mục khoá chưa từng tạo -> trả {want_b1} im lặng, không tự tạo thư mục",
        f"rc={rc_m} out={out_m!r} err={err_m!r}",
    )

    # ── Ca 5: Chép RIÊNG bin/capacity.py ra thư mục tạm độc lập (không có heavy_slot.py) -> chạy stdlib thuần không ImportError ──
    iso_bin = os.path.join(TMP, "iso_bin")
    iso_slots1 = os.path.join(TMP, "iso_slots1")
    os.makedirs(iso_bin, exist_ok=True)
    os.makedirs(iso_slots1, exist_ok=True)
    iso_cap = os.path.join(iso_bin, "capacity.py")
    shutil.copy2(CAP, iso_cap)
    with open(os.path.join(iso_slots1, "gate-1.lock.held"), "w", encoding="utf-8") as fh:
        fh.write(f"{os.getpid()}\n")
    e_iso1 = dict(BASE_ENV)
    e_iso1["SB_HEAVY_SLOT_DIR"] = iso_slots1
    r_iso1_gb = subprocess.run([sys.executable, "-I", iso_cap, "gate_busy"], capture_output=True, text=True, env=e_iso1, timeout=15)
    r_iso1_tj = subprocess.run([sys.executable, "-I", iso_cap, "test_jobs"], capture_output=True, text=True, env=e_iso1, timeout=15)
    e_iso2 = dict(BASE_ENV)
    e_iso2["SB_HEAVY_SLOT_DIR"] = slots_dir  # đang có 2 marker sống thật (h2 + h3)
    r_iso2_tj = subprocess.run([sys.executable, "-I", iso_cap, "test_jobs"], capture_output=True, text=True, env=e_iso2, timeout=15)
    chk(
        not os.path.exists(os.path.join(iso_bin, "heavy_slot.py"))
        and r_iso1_gb.returncode == 0
        and r_iso1_gb.stdout.strip() == "1"
        and r_iso1_tj.returncode == 0
        and r_iso1_tj.stdout.strip() == str(want_b1)
        and r_iso1_tj.stderr == ""
        and r_iso2_tj.returncode == 0
        and r_iso2_tj.stdout.strip() == str(want_b2)
        and r_iso2_tj.stderr == "",
        f"5. bản chép lẻ bin/capacity.py (không có heavy_slot.py) chạy stdlib thuần, đếm đúng 1 marker ({want_b1}) và 2 marker ({want_b2})",
        f"iso1=({r_iso1_gb.stdout!r},{r_iso1_tj.stdout!r},{r_iso1_tj.stderr!r}) iso2=({r_iso2_tj.stdout!r},{r_iso2_tj.stderr!r})",
    )

    # ── Ca 6: capacity.slot_dir() == heavy_slot.slot_dir() trên mọi biến thể env; marker ở gate-4.lock.held (vượt gate_max) vẫn được đếm ──
    dir_mismatches = []
    saved_env = {k: os.environ.get(k) for k in ("SB_HEAVY_SLOT_DIR", "HOME")}
    try:
        for h_val in ("/tmp/cap_h", "/tmp/cap_h/"):
            for sb_val in (None, "", "   ", f"  {TMP}/custom_lock_dir  "):
                os.environ["HOME"] = h_val
                if sb_val is None:
                    os.environ.pop("SB_HEAVY_SLOT_DIR", None)
                else:
                    os.environ["SB_HEAVY_SLOT_DIR"] = sb_val
                c_dir = capacity.slot_dir()
                hs_dir = heavy_slot.slot_dir()
                if c_dir != hs_dir:
                    dir_mismatches.append((h_val, sb_val, c_dir, hs_dir))
    finally:
        for k, v in saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    over_dir = os.path.join(TMP, "over_gate_max_slots")
    os.makedirs(over_dir, exist_ok=True)
    with open(os.path.join(over_dir, "gate-1.lock.held"), "w", encoding="utf-8") as fh:
        fh.write(f"{os.getpid()}\n")
    with open(os.path.join(over_dir, "gate-4.lock.held"), "w", encoding="utf-8") as fh:
        fh.write(f"{h2.pid}\n")
    rc_ov4, out_ov4, _ = run_cap("gate_busy", SB_HEAVY_SLOT_DIR=over_dir, DEVKIT_GATE_SLOTS="1")
    chk(
        not dir_mismatches and try_gb(slot_dir=over_dir) == 2 and rc_ov4 == 0 and out_ov4.strip() == "2",
        "6. capacity.slot_dir() trùng khít heavy_slot.slot_dir() ở mọi biến thể env; marker ở gate-4.lock.held (vượt gate_max) vẫn được đếm",
        f"mismatches={dir_mismatches} gb_over={try_gb(slot_dir=over_dir)} cli={out_ov4!r}",
    )

    # ── Ca 7: acquire_pool("gate", ..., wait_s=0) KHÔNG ghi .held; gọi release_pool hai lần không xoá marker của holder khác ──
    probe_dir = os.path.join(TMP, "probe_slots")
    os.makedirs(probe_dir, exist_ok=True)
    h_other = None
    os.environ["SB_HEAVY_SLOT_DIR"] = probe_dir
    try:
        p_paths = heavy_slot.pool_paths("gate", 3, lock_dir=probe_dir)
        ph0 = heavy_slot.acquire_pool("gate", p_paths, wait_s=0)
        ph0_got_lock = (not ph0.timed_out) and (ph0.fh is not None)
        held_during_probe = [n for n in os.listdir(probe_dir) if n.endswith(".held")]
        heavy_slot.release_pool(ph0)
        held_after_probe = [n for n in os.listdir(probe_dir) if n.endswith(".held")]

        # Lấy thật 1 slot (wait_s=5.0), nhả lần 1, cho holder khác chiếm lại đúng slot đó, rồi gọi release_pool lần 2 trên handle cũ
        real_h = heavy_slot.acquire_pool("gate", p_paths, wait_s=5.0)
        first_slot_path = real_h.path
        heavy_slot.release_pool(real_h)
        h_other = spawn_gate_holder(os.path.join(TMP, "r_other7"), slots_dir=probe_dir)
        other_slot_path = open(os.path.join(TMP, "r_other7"), encoding="utf-8").read().split()[1]
        heavy_slot.release_pool(real_h)
        other_held_intact = os.path.exists(other_slot_path + ".held") and try_gb(slot_dir=probe_dir) == 1
        # Tạo thêm 1 holder thứ hai để chắc chắn gate_busy == 2 sau release_pool lần 2 của real_h
        h_other2 = spawn_gate_holder(os.path.join(TMP, "r_other7b"), slots_dir=probe_dir)
        try:
            heavy_slot.release_pool(real_h)
            two_intact = try_gb(slot_dir=probe_dir) == 2
        finally:
            stop_proc(h_other2)
        chk(
            ph0_got_lock
            and ph0.fh is None
            and held_during_probe == []
            and held_after_probe == []
            and first_slot_path == other_slot_path
            and other_held_intact
            and two_intact,
            "7. acquire_pool('gate', wait_s=0) lấy được khoá nhưng không tạo .held cả trong lúc giữ lẫn sau khi nhả; release_pool gọi lặp không xoá .held của holder khác",
            f"got={ph0_got_lock} during={held_during_probe} after={held_after_probe} slot=({first_slot_path},{other_slot_path}) intact=({other_held_intact},{two_intact})",
        )
    finally:
        os.environ.pop("SB_HEAVY_SLOT_DIR", None)
        stop_proc(h_other)
finally:
    stop_proc(h1)
    stop_proc(h2)
    stop_proc(h3)

with open(os.path.join(TMP, "want_b2.txt"), "w", encoding="utf-8") as fh:
    fh.write(f"{want_b2}\n")

sys.exit(1 if fails else 0)
PY
PY_RC=$?

FAILS=0
if [ "$PY_RC" -ne 0 ]; then
  FAILS=$((FAILS + 1))
fi

# ── Ca 4: Giữ 2 slot thật qua acquire_pool("gate") trong thư mục khoá MẶC ĐỊNH giả (HOME tạm) rồi chạy test_capacity.sh & test_run_impacted_order.sh ──
FAKE_HOME="$TMP/fake_home"
mkdir -p "$FAKE_HOME"
for idx in 1 2; do
  HOME="$FAKE_HOME" python3 -I - "$DEVKIT_DIR/bin" "$TMP/s4_$idx" <<'PYH' &
import os, sys, time
bin_dir, ready_path = sys.argv[1], sys.argv[2]
sys.path.insert(0, bin_dir)
import heavy_slot
h = heavy_slot.acquire_pool("gate", heavy_slot.pool_paths("gate", 3), wait_s=5.0)
if h.timed_out or h.fh is None:
    sys.exit(2)
with open(ready_path, "w", encoding="utf-8") as f:
    f.write(f"{os.getpid()} {h.path}\n")
time.sleep(60)
PYH
  HOLDER_PIDS="$HOLDER_PIDS $!"
done

HOLDERS_OK=1
for idx in 1 2; do
  w=0
  while [ ! -f "$TMP/s4_$idx" ] && [ "$w" -lt 250 ]; do
    sleep 0.02
    w=$((w + 1))
  done
  if [ ! -f "$TMP/s4_$idx" ]; then
    echo "✖ 4. tiền điều kiện: holder $idx trên thư mục khoá mặc định (HOME tạm) không sẵn sàng"
    HOLDERS_OK=0
    FAILS=$((FAILS + 1))
  fi
done

if [ "$HOLDERS_OK" -eq 1 ] && [ -f "$TMP/want_b2.txt" ]; then
  WANT_B2="$(tr -d '[:space:]' <"$TMP/want_b2.txt")"
  GOT_DEF_GB="$(HOME="$FAKE_HOME" python3 "$CAP" gate_busy 2>&1)"
  GOT_DEF_TJ="$(HOME="$FAKE_HOME" python3 "$CAP" test_jobs 2>&1)"
  GOT_DEF_RI="$(HOME="$FAKE_HOME" bash "$RUNNER" --jobs 2>&1)"
  if [ "$GOT_DEF_GB" = "2" ] && [ "$GOT_DEF_TJ" = "$WANT_B2" ] && [ "$GOT_DEF_RI" = "$WANT_B2" ]; then
    echo "✔ 4a. thư mục khoá mặc định (~/.claude/super-board/locks trên HOME tạm): gate_busy=2, test_jobs=$WANT_B2, run_impacted --jobs=$WANT_B2"
  else
    echo "✖ 4a. thư mục khoá mặc định sai giá trị: gate_busy='$GOT_DEF_GB' test_jobs='$GOT_DEF_TJ' run_impacted='$GOT_DEF_RI' (muốn 2 / $WANT_B2 / $WANT_B2)"
    FAILS=$((FAILS + 1))
  fi

  if HOME="$FAKE_HOME" bash "$DEVKIT_DIR/tests/gates/test_capacity.sh" >"$TMP/cap.out" 2>&1; then
    echo "✔ 4b. test_capacity.sh vẫn PASS khi thư mục khoá mặc định trên HOME tạm đang giữ 2 slot thật"
  else
    echo "✖ 4b. test_capacity.sh bị rò trạng thái slot bận từ thư mục khoá mặc định:"
    tail -n 20 "$TMP/cap.out"
    FAILS=$((FAILS + 1))
  fi

  if HOME="$FAKE_HOME" bash "$DEVKIT_DIR/tests/verification/test_run_impacted_order.sh" >"$TMP/order.out" 2>&1; then
    echo "✔ 4c. test_run_impacted_order.sh vẫn PASS khi thư mục khoá mặc định trên HOME tạm đang giữ 2 slot thật"
  else
    echo "✖ 4c. test_run_impacted_order.sh bị rò trạng thái slot bận từ thư mục khoá mặc định:"
    tail -n 20 "$TMP/order.out"
    FAILS=$((FAILS + 1))
  fi
fi

if [ "$FAILS" -ne 0 ]; then
  echo "❌ test_capacity_test_jobs_busy: $FAILS nhóm kiểm thử THẤT BẠI"
  exit 1
fi
echo "✅ test_capacity_test_jobs_busy: tất cả PASS"
