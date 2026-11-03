#!/usr/bin/env bash
# #914 mục 1: run_suite_on_base (merge gate kiểm "đỏ sẵn trên base" sau REJECT) phải
#   a. xin slot pool gate (heavy_slot.acquire_pool) trước khi chạy suite — không chạy dư một việc nặng ngoài pool sau khi lane_lock P5 nhả slot lane
#   b. dùng trần theo suite: 900 s × SUITE_TIMEOUT_FACTOR của id (REG-DK-ALL-GATES-01 ×2), không cứng 900 s
#   c. hết giờ chờ slot ⇒ exit 2 (không chạy được), không chạy suite
# Trích chính hàm từ gate (như test_merge_gate_verify_log_outside.sh); trần gốc đổi được bằng SB_BASE_SUITE_TIMEOUT_S để test chạy nhanh.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-base-suite-pool.XXXXXX")"
HOLDER=""
cleanup() { touch "$TMP/release" 2>/dev/null; [ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" DEVKIT_GATE_SLOTS=1 SB_HEAVY_SLOT_POLL_S=0.05 SB_REPO_PATH="$ROOT"
unset SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOT_WAIT_S
mkdir -p "$SB_HEAVY_SLOT_DIR" "$TMP/scratch"

sed -n '/^run_suite_on_base() {/,/^}/p' "$GATE" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { echo "✖ không trích được run_suite_on_base"; exit 1; }
SCRATCH="$TMP/scratch"; HERE="$ROOT/.claude/bin"
. "$TMP/fn.sh"

hold_gate1() {  # giữ flock gate-1.lock tới khi có file release
  rm -f "$TMP/ready" "$TMP/release"
  python3 - "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/ready" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
lock, ready, rel = sys.argv[1:4]
with open(lock, "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(ready, "w").close()
    end = time.monotonic() + 30
    while time.monotonic() < end and not os.path.exists(rel):
        time.sleep(0.03)
PY
  HOLDER=$!
  local i=0
  while [ ! -f "$TMP/ready" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$TMP/ready" ] || { echo "✖ không giữ được gate-1.lock"; exit 1; }
}

# a. pool gate đầy: suite chỉ được chạy sau khi nhả
hold_gate1
( run_suite_on_base "echo ran > $TMP/ran" REG-X; echo $? > "$TMP/rc-a" ) &
BG=$!
sleep 1.5
if [ ! -f "$TMP/ran" ]; then ok "a.1 pool gate đầy: suite base chưa chạy"; else fail "a.1 suite base chạy khi pool gate đầy (ngoài pool)"; fi
touch "$TMP/release"
wait "$BG"
if [ -f "$TMP/ran" ] && [ "$(cat "$TMP/rc-a" 2>/dev/null)" = 0 ]; then ok "a.2 pool nhả: suite base chạy xong exit 0"; else fail "a.2 sau khi nhả (rc=$(cat "$TMP/rc-a" 2>/dev/null))"; fi
wait "$HOLDER" 2>/dev/null; HOLDER=""

# b. trần theo suite: gốc 1 s; sleep 1.5 quá giờ với id thường (124), ×2 cho REG-DK-ALL-GATES-01 thì xong (0)
export SB_BASE_SUITE_TIMEOUT_S=2
run_suite_on_base "sleep 2.5" REG-X; rc=$?
if [ "$rc" = 124 ]; then ok "b.1 id thường: trần 2 s ⇒ 124"; else fail "b.1 id thường rc=$rc (muốn 124)"; fi
run_suite_on_base "sleep 2.5" REG-DK-ALL-GATES-01; rc=$?
if [ "$rc" = 0 ]; then ok "b.2 REG-DK-ALL-GATES-01: trần ×2 ⇒ 0"; else fail "b.2 REG-DK-ALL-GATES-01 rc=$rc (muốn 0)"; fi
# d. exception không bắt được KHÔNG được ra exit 1 ("đỏ trên base" ⇒ PR đỏ lọt merge): trần nan ⇒ về 900 s, suite xanh ra 0
SB_BASE_SUITE_TIMEOUT_S=nan run_suite_on_base "true" REG-X; rc=$?
if [ "$rc" = 0 ]; then ok "d.1 trần nan ⇒ dùng 900 s, suite xanh exit 0"; else fail "d.1 trần nan rc=$rc (muốn 0, không phải 1)"; fi
unset SB_BASE_SUITE_TIMEOUT_S

# c. hết giờ chờ slot ⇒ exit 2, suite không chạy
hold_gate1
DEVKIT_GATE_SLOT_WAIT_S=1 run_suite_on_base "echo ran > $TMP/ran2" REG-X; rc=$?
if [ "$rc" = 75 ] && [ ! -f "$TMP/ran2" ]; then ok "c. chờ slot hết giờ ⇒ exit 75 (bận, khác 1 và 2), suite không chạy"; else fail "c. rc=$rc (muốn 75, suite không chạy)"; fi

echo
if [ "$FAILS" -eq 0 ]; then echo "test_merge_gate_base_suite_pool: PASS"; exit 0; fi
echo "test_merge_gate_base_suite_pool: FAIL ($FAILS)"; exit 1
