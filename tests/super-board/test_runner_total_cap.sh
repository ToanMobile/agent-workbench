#!/usr/bin/env bash
# Test: một trần worker duy nhất, cộng một phanh tải cho mọi lane (#530).
#  - max_workers (mặc định 5) = tổng worker build + qa + review của MỌI repo trên máy, đếm qua thư mục slot dùng chung;
#  - mọi lane dùng chung trần đó và chung ngưỡng DEVKIT_SPAWN_LOAD (ở đây ghim 36);
#  - dưới ngưỡng: tải không cho vượt trần slot; vượt ngưỡng: hoãn spawn, log holding spawn load1=X > N;
#  - config không còn build_workers / qa_workers / review_workers / build_load_max / global_max_workers / gate_max.
# Chạy offline: runner source ở lib mode, gh/claude là stub.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-total-cap.XXXXXX")"
cleanup() { for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/slots"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX DEVKIT_CAPACITY_LOAD DEVKIT_SPAWN_LOAD
export SB_ZOMBIE_GRACE=0 SB_GLOBAL_SLOT_DIR="$TMP/slots"
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
load() { export DEVKIT_CAPACITY_LOAD="$1"; TICK_SEQ=$(( ${TICK_SEQ:-0} + 1 )); }
unset_load() { unset DEVKIT_CAPACITY_LOAD; TICK_SEQ=$(( ${TICK_SEQ:-0} + 1 )); }
cards() {   # cards <status> <n>...
  local st="$1" out="" n; shift
  for n in "$@"; do out="${out:+$out,}{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
  PROJECT_ITEMS_JSON="{\"items\":[$out]}"
}
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
FOREIGN=""
reset() {
  for p in $BUILD_PID $QA_PID $REVIEW_PID ${BUILD_EXTRA:-} ${QA_EXTRA:-} ${REVIEW_EXTRA:-} $FOREIGN; do kill "${p%%:*}" 2>/dev/null; wait "${p%%:*}" 2>/dev/null; done
  BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; FOREIGN=""
  rm -f "$INFLIGHT_DIR"/[0-9]* "$SB_GLOBAL_SLOT_DIR"/*; : > "$TMP/log"; : > "$TMP/writes"; ACTIVE_WORKERS=0
  MAX_WORKERS=5; BUILD_WORKERS=5; QA_WORKERS=5; REVIEW_WORKERS=5; QA=0; REVIEW=0; READY=0
  LOAD_HELD_TICK=0
}
total() { build_workers_count; lane_workers_count qa; lane_workers_count review; echo $((BUILD_COUNT + QA_COUNT + REVIEW_COUNT)); }
tick_qa() { reap_finished_locks; lane_dispatch_tick qa QA; }
tick_review() { reap_finished_locks; lane_dispatch_tick review Review; }
foreign_workers() {   # n worker của repo KHÁC: chỉ có file slot trong thư mục chung
  local i pid
  for i in $(seq 1 "$1"); do sleep 300 >/dev/null 2>&1 & pid=$!; FOREIGN="$FOREIGN $pid"; printf 'other-repo:%s\n' "$i" > "$SB_GLOBAL_SLOT_DIR/$pid"; done
}

# ── 1. cấu hình: mặc định 5, không còn khoá CPU / lane
body=$(sed -n '/^if \[ "${SB_LIB_ONLY:-0}" != "1" \]; then/,$p' "$RUNNER")
grep -q "max_workers 5" <<<"$body" && ok "max_workers defaults to 5" || fail "max_workers default is not 5"
grep -qE 'build_load_max|BUILD_LOAD_MAX|resolve_lane_workers|resolve_build_workers' <<<"$body" && fail "runner still reads CPU-load / per-lane worker config" || ok "runner no longer reads build_load_max / build_workers / qa_workers / review_workers"
grep -qE '^BUILD_WORKERS="?\$MAX_WORKERS' <<<"$body" && ok "lane caps equal max_workers" || fail "lane caps are not tied to max_workers"
grep -qE 'global_max_workers|GLOBAL_MAX|gate_max' <<<"$body" && fail "a second worker cap is still read" || ok "max_workers is the only worker cap (no global_max_workers / gate_max)"

# Ngưỡng AC ghim 36 (12 lõi). Không đọc busy_load của máy đang chạy.
export DEVKIT_SPAWN_LOAD=36

# ── 2. QA + Review + Build chung một trần 5 (tải 0 cũng không cho vượt)
reset; load 0
cards QA 1 2 3 4 5 6; for i in 1 2 3 4 5 6 7; do tick_qa; done
[ "$(total)" = 5 ] && ok "load 0, 6 QA cards: exactly 5 testers, the 6th waits" || fail "QA alone gave $(total) workers (want 5)"
cards Review 7 8; QA=0; REVIEW=2; tick_review; tick_review
[ "$(total)" = 5 ] && [ "$REVIEW_COUNT" = 0 ] && ok "QA holds 5 slots: Review cannot start (one shared cap)" || fail "total $(total), review=$REVIEW_COUNT"

# ── 3. 2 qa + 1 review + 2 build = 5: lane nào cũng bị chặn
reset; load 0
cards QA 1 2; tick_qa; tick_qa
cards Review 3; tick_review
sleep 300 >/dev/null 2>&1 & BUILD_PID=$!; BUILD_ISSUE=4; sleep 300 >/dev/null 2>&1 & BUILD_EXTRA="$!:5"
[ "$(total)" = 5 ] && ok "2 qa + 1 review + 2 build = 5 running" || fail "setup gave $(total)"
cards QA 1 2 6; tick_qa; cards Review 3 7; tick_review
[ "$(total)" = 5 ] && ok "at 5 total: neither QA nor Review adds a worker" || fail "total after extra ticks: $(total)"
READY=3; build_slot_free; rc=$?
[ "$rc" -ne 0 ] && [ "${BUILD_FREE:-0}" = 0 ] && ok "at 5 total: the build lane does not start another" || fail "build started at the cap (rc=$rc)"

# ── 4. phanh tải: một ngưỡng cho build, qa và review
reset; load 40
cards QA 1 2 3; tick_qa
[ "$(total)" = 0 ] && grep -q "holding spawn load1=40 > 36" "$TMP/log" && ok "load 40 holds QA and logs the threshold" || fail "load 40 did not hold QA ($(total)): $(tr '\n' '|' < "$TMP/log")"
reset; load 40
cards Review 1; tick_review
[ "$(total)" = 0 ] && grep -q "holding spawn load1=40 > 36" "$TMP/log" && ok "load 40 holds Review" || fail "load 40 did not hold Review ($(total))"
reset; READY=2; load 40; build_slot_free; rc=$?
[ "$rc" -ne 0 ] && [ "${BUILD_FREE:-0}" = 0 ] && grep -q "holding spawn load1=40 > 36" "$TMP/log" && ok "load 40 holds build" || fail "load 40 did not hold build (rc=$rc BUILD_FREE=${BUILD_FREE:-})"
reset; load 30
cards QA 1; tick_qa
[ "$(total)" = 1 ] && ok "load 30 still spawns QA" || fail "load 30 held QA: $(total)"
reset; load 30
cards Review 1; tick_review
[ "$(total)" = 1 ] && ok "load 30 still spawns Review" || fail "load 30 held Review: $(total)"
reset; READY=2; load 30; build_slot_free; rc=$?
[ "$rc" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && ok "load 30: build lane starts" || fail "load 30 held build (rc=$rc)"
reset; load 36.5
cards QA 1; tick_qa
[ "$(total)" = 0 ] && grep -q "holding spawn load1=36.5 > 36" "$TMP/log" && ok "load 36.5 (float) holds" || fail "load 36.5 did not hold: $(total) $(tr '\n' '|' < "$TMP/log")"
reset; load ""
cards QA 1 2 3; tick_qa; tick_qa; tick_qa
[ "$(total)" = 3 ] && ok "empty load does not hold" || fail "empty load held the lane: $(total)"
reset; load "nope"
cards QA 1; tick_qa
[ "$(total)" = 1 ] && ok "garbage load does not hold" || fail "garbage load held the lane: $(total)"
reset; unset_load
[ -z "$(spawn_load1)" ] && ok "lib mode without LOAD: load1 stays empty" || fail "lib mode read a load: $(spawn_load1)"
cards QA 1; tick_qa
[ "$(total)" = 1 ] && ok "lib mode without LOAD does not hold" || fail "lib mode without LOAD held the lane: $(total)"
# config spawn_load_max khi không có DEVKIT_SPAWN_LOAD
reset; unset DEVKIT_SPAWN_LOAD; echo '{"spawn_load_max":36}' > "$CONFIG_PATH"; load 40
cards QA 1; tick_qa
[ "$(total)" = 0 ] && grep -q "holding spawn load1=40 > 36" "$TMP/log" && ok "config spawn_load_max=36 holds load 40" || fail "config threshold did not hold: $(total)"
export DEVKIT_SPAWN_LOAD=36; echo '{}' > "$CONFIG_PATH"; TICK_SEQ=$(( ${TICK_SEQ:-0} + 1 ))
# tick rẻ vì tải chỉ sau lần đọc board, và không nuốt merge_queue_due
reset; load 40; BOARD_SYNCED=1; REAPED_THIS_TICK=0; ACTIVE_WORKERS=0
tick_is_cheap && ok "load 40 after a board sync: tick_is_cheap" || fail "load 40 was not cheap"
BOARD_SYNCED=0
tick_is_cheap && fail "cheap before the first board sync" || ok "load 40 before a board sync is not cheap"
BOARD_SYNCED=1; REAPED_THIS_TICK=1
tick_is_cheap && fail "cheap while a worker was just reaped" || ok "a just-reaped worker is not a cheap tick"
reset; load 40
merge_queue_due; rc=$?
[ "$rc" -eq 0 ] && ok "load 40: merge_queue_due still runs" || fail "merge_queue_due failed under load (rc=$rc)"
# tải cao + 0 worker không tính no-progress
reset; load 40; cards QA 1; tick_qa
[ "$(total)" = 0 ] && [ "${LOAD_HELD_TICK:-0}" = 1 ] || fail "runaway setup did not hold (total=$(total) held=${LOAD_HELD_TICK:-})"
NO_PROGRESS_CYCLES=2; PREV_DONE_SIG="9"; NO_PROGRESS_CYCLE_COUNT=0; LANDED_COUNT=0; MQ_WAITING=0; REVIEW=0; RUNAWAY_PAUSE_UNTIL=0
rc=0; record_cycle_progress "9" || rc=$?
[ "$rc" -eq 0 ] && [ "${NO_PROGRESS_CYCLE_COUNT:-0}" = 0 ] && ok "high load + 0 workers is not no-progress" || fail "no-progress counted under load (rc=$rc count=${NO_PROGRESS_CYCLE_COUNT:-} held=${LOAD_HELD_TICK:-})"

# ── 5. cả máy: repo khác đang chạy 4 worker thì repo này chỉ còn 1 slot; tự ghi slot khi giao
reset; load 0; foreign_workers 4
cards QA 1 2 3; tick_qa; tick_qa; tick_qa
[ "$(total)" = 1 ] && ok "4 workers in other repos: this repo gets only 1 (machine cap 5)" || fail "machine cap ignored: this repo has $(total)"
n=$(ls "$SB_GLOBAL_SLOT_DIR" | wc -l | tr -d ' ')
[ "$n" = 5 ] && ok "  … the dispatched worker registered itself in the shared slot dir (5 live slots)" || fail "slot dir holds $n files (want 5)"
reset; load 0; foreign_workers 5; READY=2; build_slot_free; rc=$?
[ "$rc" -ne 0 ] && [ "${BUILD_FREE:-0}" = 0 ] && ok "5 workers elsewhere: the build lane holds too" || fail "build started although the machine is full (rc=$rc)"
grep -q "machine" "$TMP/log" && ok "  … and the log names the machine cap" || fail "no machine-cap reason; log: $(tr '\n' '|' < "$TMP/log")"
# worker chết thì slot tự trả lại
reset; load 0; foreign_workers 5; first=${FOREIGN# }; first=${first%% *}; kill "$first" 2>/dev/null; wait "$first" 2>/dev/null; sleep 0.2
cards QA 1 2; tick_qa
[ "$(total)" = 1 ] && ok "a dead worker elsewhere frees its slot (stale file is pruned)" || fail "dead slot not freed: $(total)"

# ── 5b. lib mode được chốt lúc source: `SB_LIB_ONLY=1 . runner` rồi gọi hàm sau đó (SB_LIB_ONLY đã mất) vẫn KHÔNG đếm slot
#      của HOME thật (23/10: test merge train bị giữ "3/3 running on the machine" vì đếm slot sống của test khác)
FH="$TMP/fakehome"; mkdir -p "$FH/.claude/super-board-slots"; LEAK=""
for i in 1 2 3; do sleep 300 >/dev/null 2>&1 & p=$!; LEAK="$LEAK $p"; echo "other:$i" > "$FH/.claude/super-board-slots/$p"; done
n=$(env -u SB_GLOBAL_SLOT_DIR HOME="$FH" bash -c 'SB_LIB_ONLY=1 . "$1" >/dev/null 2>&1; global_slots_used' _ "$RUNNER" 2>/dev/null)
[ "$n" = 0 ] && ok "lib mode without SB_GLOBAL_SLOT_DIR: 3 live slots in HOME are not counted (lib mode pinned at source time)" || fail "test sourcing counted HOME slots: '$n' (want 0)"
for p in $LEAK; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done

# ── 6. thứ tự ưu tiên giữ nguyên: Review → QA đi trước Build trong vòng chính
l1=$(grep -n 'lane_dispatch_tick review Review' "$RUNNER" | head -1 | cut -d: -f1)
l2=$(grep -n 'build_slot_free || true' "$RUNNER" | head -1 | cut -d: -f1)
[ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" -lt "$l2" ] && ok "Review/QA are dispatched before Build in the main loop" || fail "dispatch order changed ($l1 / $l2)"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
