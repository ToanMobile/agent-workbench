#!/usr/bin/env bash
# Test hồi quy (P1, gate kẹt và chậm 02/11): pool gate có vé khác cỡ (n = len(paths) của lượt xin) — hết cảnh slot trống mà không ai lấy.
# Vé đứng sau (hạng r > 0) thăm mọi khoá, rồi ghép tham lam: các vé đứng trước, theo n tăng dần, mỗi vé giữ chỗ chỉ số trống LỚN NHẤT
# < n của nó; còn chỗ dư thì vé này lấy chỗ dư nhỏ nhất.
#   0. heavy_slot.py nạp là bản trong CHÍNH checkout chứa test (INSTINCT-057)
#   a. gate-1, gate-2 bận; hai vé n=2 đứng trước ⇒ vé 4 path (wait 3 s) lấy gate-3 ngay (trước sửa: hết giờ vì hạng 2 ≥ 2 slot trống)
#   b. gate-1, gate-4 bận; vé A n=2 đứng trước ⇒ vé B 4 path lấy gate-3, chừa gate-2 cho A (trước sửa: B lấy gate-2, A đói)
# SB_HEAVY_SLOT_DIR riêng mỗi ca (không đụng ~/.claude/super-board/locks), tải giả; PID của vé đứng trước là tiến trình sleep do test
# tự tạo và tự kill. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_SLOT_PRIORITY DEVKIT_SLOT_PRIO_AGE_S DEVKIT_SLOT_ADVISORY_HELD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-gate-pool-mixed.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
PIDS=""
cleanup() {
  local p
  touch "$TMP"/release.* 2>/dev/null || true
  for p in $PIDS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT
printf '0\n' > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load" SB_HEAVY_SLOT_POLL_S=0.05
FAILS=0
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Giữ khoá flock độc quyền trên file bất kỳ tới khi xuất hiện file tín hiệu nhả hoặc hết thời gian (như test_gate_slot_queue.sh)
hold_flock() {
  local lock_file="$1" ready_file="$2" rel_file="$3" max_s="${4:-30}"
  rm -f "$ready_file" "$rel_file"
  python3 - "$lock_file" "$ready_file" "$rel_file" "$max_s" <<'PY' &
import fcntl, os, sys, time
lock_file, ready_file, rel_file, max_s = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
os.makedirs(os.path.dirname(lock_file), exist_ok=True)
with open(lock_file, "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(ready_file, "w").close()
    end = time.monotonic() + max_s
    while time.monotonic() < end:
        if os.path.exists(rel_file):
            break
        time.sleep(0.03)
PY
  PIDS="$PIDS $!"
  local i=0
  while [ ! -f "$ready_file" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$ready_file" ] || { fail "thiết lập: không giữ được khoá $lock_file"; exit 1; }
}

# Tiến trình sống làm PID cho vé đứng trước (vé của PID chết bị _read_tickets xoá)
spawn_sleeper() { sleep 120 & SLEEPER=$!; PIDS="$PIDS $SLEEPER"; }

# run_case <ca> <thư mục slot> <PID vé trước, cách bởi dấu phẩy>: vé trước prio merge, n=2; lượt xin 4 path, wait 3 s
run_case() {
  SB_HEAVY_SLOT_DIR="$2" python3 - "$DEVKIT_DIR" "$1" "$3" <<'PY'
import fcntl, json, os, sys, time
devkit, case, pids = sys.argv[1], sys.argv[2], [int(p) for p in sys.argv[3].split(",")]
sys.path.insert(0, os.path.join(devkit, "bin"))
import heavy_slot as hs
fails = 0
def check(name, cond, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond else f" — {detail}"))
    fails += 0 if cond else 1

loaded = os.path.realpath(hs.__file__)
check(f"{case}.0 heavy_slot.py của checkout chứa test", loaded.startswith(devkit + os.sep), f"nạp {loaded}, checkout {devkit}")
lock_dir = hs.slot_dir()
qdir = os.path.join(lock_dir, "queue", "gate")
os.makedirs(qdir, exist_ok=True)
for i, pid in enumerate(pids):
    tmp = os.path.join(qdir, f".{pid}-ahead.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"pid": pid, "prio": "merge", "est_s": 600.0, "t0": time.time() - 30 + i, "wait_s": 3600.0,
                   "label": f"ahead{i}", "cont": False, "n": 2}, f)
    os.replace(tmp, os.path.join(qdir, f"{pid}-ahead.json"))

def free(name):
    """Khoá được file đó lúc này (rồi nhả ngay) không."""
    fh = hs._try_lock_path(os.path.join(lock_dir, name))
    hs._unlock(fh)
    return fh is not None

t0 = time.monotonic()
h = hs.acquire_pool("gate", hs.pool_paths("gate", 4, lock_dir=lock_dir), wait_s=3.0, prio="interactive", label=f"ca {case}")
waited = time.monotonic() - t0
got = os.path.basename(h.path) if h.path else ""
held = sorted(n for n in os.listdir(lock_dir) if n.endswith(".held"))
ahead_left = sorted(n for n in os.listdir(qdir) if n.endswith("-ahead.json"))
check(f"{case}.1 vé 4 path lấy gate-3 trong ≤ 1 s", not h.timed_out and got == "gate-3.lock" and waited < 1.0,
      f"timed_out={h.timed_out} lấy={got or '-'} chờ={waited:.2f}s")
check(f"{case}.2 chỉ slot đang giữ có marker .held", held == (["gate-3.lock.held"] if got == "gate-3.lock" else []), f"held={held}")
spare = "gate-4.lock" if case == "a" else "gate-2.lock"
check(f"{case}.3 {spare} vẫn trống cho vé đứng trước", free(spare), f"{spare} bị giữ")
check(f"{case}.4 vé đứng trước không bị xoá", len(ahead_left) == len(pids), f"còn {ahead_left}")
hs.release_pool(h)
sys.exit(1 if fails else 0)
PY
  [ "$?" = 0 ] || FAILS=$((FAILS + 1))
}

# ── a. gate-1, gate-2 bận; hai vé n=2 đứng trước ⇒ gate-3 ──
A="$TMP/slots_a"
hold_flock "$A/gate-1.lock" "$TMP/ready.a1" "$TMP/release.a1"
hold_flock "$A/gate-2.lock" "$TMP/ready.a2" "$TMP/release.a2"
spawn_sleeper; s1=$SLEEPER; spawn_sleeper; s2=$SLEEPER
run_case a "$A" "$s1,$s2"

# ── b. gate-1, gate-4 bận; vé A n=2 đứng trước ⇒ B lấy gate-3, chừa gate-2 ──
B="$TMP/slots_b"
hold_flock "$B/gate-1.lock" "$TMP/ready.b1" "$TMP/release.b1"
hold_flock "$B/gate-4.lock" "$TMP/ready.b4" "$TMP/release.b4"
spawn_sleeper; s3=$SLEEPER
run_case b "$B" "$s3"

if [ "$FAILS" = 0 ]; then echo "PASS test_gate_pool_mixed_size"; exit 0; fi
echo "FAIL test_gate_pool_mixed_size ($FAILS ca)"
exit 1
