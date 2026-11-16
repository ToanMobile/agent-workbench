#!/usr/bin/env bash
# Test hồi quy (16/11): board đứng vì đĩa dưới sàn WORKTREE_DISK_MIN_GIB bị tính là runaway ("no card reached Done in 240 dispatch
# cycles") — cầu chì lại tự bật dù không có gì để giao. Giống phanh tải (#530): đĩa chưa đủ chỗ và chưa có worker thì im lặng
# không phải runaway. Thêm: runaway_summary với DISPATCH_LOG rỗng từng in "[: 0\n0: integer expression expected" (grep -c in 0 rồi
# `|| echo 0` in thêm một 0). gh/claude là stub, chạy offline.
#  A  dưới sàn đĩa: lane không giao, LOAD_HELD_TICK=1, record_cycle_progress không đếm no-progress.
#  B  đủ chỗ đĩa: lane vẫn giao worker như cũ (không mất việc).
#  C  runaway_summary với DISPATCH_LOG rỗng không in "integer expression".
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-disk-hold.XXXXXX")"
cleanup() { for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/slots"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH"
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX DEVKIT_CAPACITY_LOAD DEVKIT_SPAWN_LOAD
export SB_ZOMBIE_GRACE=0 SB_GLOBAL_SLOT_DIR="$TMP/slots" DEVKIT_SPAWN_LOAD=1000
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
# the disk check runs the kit of the repo under test: point the scratch repo at this checkout's kit
mkdir -p .agents && ln -s "$ROOT/universal-agent-devkit" .agents/devkit
TICK_SEQ=0
cards() {   # cards <status> <n>...
  local st="$1" out="" n; shift
  for n in "$@"; do out="${out:+$out,}{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
  PROJECT_ITEMS_JSON="{\"items\":[$out]}"
}
reset() {
  for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done
  rm -f "$INFLIGHT_DIR"/[0-9]* "$SB_GLOBAL_SLOT_DIR"/*; : > "$TMP/log"; : > "$TMP/writes"; ACTIVE_WORKERS=0
  MAX_WORKERS=5; BUILD_WORKERS=5; QA_WORKERS=5; REVIEW_WORKERS=5; QA=0; REVIEW=0; READY=0
  LOAD_HELD_TICK=0; TICK_SEQ=$(( TICK_SEQ + 1 ))
}
total() { build_workers_count; lane_workers_count qa; lane_workers_count review; echo $((BUILD_COUNT + QA_COUNT + REVIEW_COUNT)); }
tick_qa() { reap_finished_locks; lane_dispatch_tick qa QA; }

# A: dưới sàn đĩa -> không giao, giữ im lặng, không đếm no-progress.
reset; cards QA 1
export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0
tick_qa
[ "$(total)" = 0 ] && grep -q "skip dispatch lane=qa issue=#1 — disk under" "$TMP/log" && ok "A: under the disk floor the lane dispatches nothing (skip logged)" \
  || fail "A: total=$(total) log=$(tr '\n' '|' < "$TMP/log" | cut -c1-200)"
[ "${LOAD_HELD_TICK:-0}" = 1 ] && ok "A: the skip marks the tick as held (LOAD_HELD_TICK=1)" || fail "A: LOAD_HELD_TICK=${LOAD_HELD_TICK:-} after a disk skip, want 1"
NO_PROGRESS_CYCLES=2; PREV_DONE_SIG="9"; NO_PROGRESS_CYCLE_COUNT=0; LANDED_COUNT=0; MQ_WAITING=0; REVIEW=0; RUNAWAY_PAUSE_UNTIL=0; ACTIVE_WORKERS=0
rc=0; record_cycle_progress "9" || rc=$?
[ "$rc" -eq 0 ] && [ "${NO_PROGRESS_CYCLE_COUNT:-0}" = 0 ] && ok "A: a disk-held tick is not a no-progress cycle" \
  || fail "A: no-progress counted (rc=$rc count=${NO_PROGRESS_CYCLE_COUNT:-})"

# B: đủ chỗ -> giao như cũ.
reset; cards QA 1
export WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
tick_qa
[ "$(total)" = 1 ] && [ "${LOAD_HELD_TICK:-0}" = 0 ] && ok "B: with room on the disk the lane still dispatches one worker" \
  || fail "B: total=$(total) held=${LOAD_HELD_TICK:-} log=$(tr '\n' '|' < "$TMP/log" | cut -c1-200)"

# C: runaway_summary với DISPATCH_LOG rỗng.
reset; DISPATCH_COUNT=0; REAP_COUNT=0; LANDED_COUNT=0; DISPATCH_LOG=""
err="$( { runaway_summary; } 2>&1 >/dev/null )"
case "$err" in *"integer expression"*) fail "C: runaway_summary leaked: $err" ;; *) ok "C: runaway_summary with an empty DISPATCH_LOG prints no integer-expression error" ;; esac

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_disk_hold_not_runaway: all passed" || { echo "❌ $FAILS failed"; exit 1; }
