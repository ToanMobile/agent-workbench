#!/usr/bin/env bash
# #369: lane Review không bị bỏ đói slot. Dưới trần max_workers=5 dùng chung, QA/Build kín 5 slot thì Review phải chờ (một trần chung),
# nhưng slot đầu tiên được trả lại phải về tay Review, không về QA/Build: vòng chính giao Review TRƯỚC QA TRƯỚC Build mỗi tick.
# Test mô phỏng đúng thứ tự đó trên hàm thật (lane_dispatch_tick) và có đối chứng: đảo thứ tự (QA trước) thì Review đói.
# Offline: runner source ở lib mode, gh/claude là stub, thư mục slot riêng. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_TEST_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-review-slot.XXXXXX")"
# chỉ kill PID do test này khởi (worker của lane + worker giả của repo khác), không quét theo tên tiến trình
cleanup() { for p in ${BUILD_PID:-} ${QA_PID:-} ${REVIEW_PID:-} ${BUILD_EXTRA:-} ${QA_EXTRA:-} ${REVIEW_EXTRA:-} ${FOREIGN:-}; do kill "${p%%:*}" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/slots"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nexec sleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX
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
load() { printf '%s\n' "$1" > "$TMP/load"; export SB_BUILD_LOAD_FILE="$TMP/load"; }
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
}
total() { build_workers_count; lane_workers_count qa; lane_workers_count review; echo $((BUILD_COUNT + QA_COUNT + REVIEW_COUNT)); }
tick_qa() { reap_finished_locks; lane_dispatch_tick qa QA; }
tick_review() { reap_finished_locks; lane_dispatch_tick review Review; }
foreign_workers() {   # n worker của repo KHÁC: chỉ có file slot trong thư mục chung
  local i pid
  for i in $(seq 1 "$1"); do sleep 300 >/dev/null 2>&1 & pid=$!; FOREIGN="$FOREIGN $pid"; printf 'other-repo:%s\n' "$i" > "$SB_GLOBAL_SLOT_DIR/$pid"; done
}

# board có cả thẻ QA lẫn Review (cards ghi đè cả danh sách): cards2 <qa-issue> <review-issue>
cards2() {
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"QA\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"assignees\":[]}},{\"id\":\"PVTI_$2\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$2,\"assignees\":[]}}]}"
}

# QA kín 5 slot, Review có thẻ chờ, QA còn thẻ chờ
reset; load 0
cards QA 1 2 3 4 5 6; for i in 1 2 3 4 5 6; do tick_qa; done
cards Review 7; REVIEW=1; QA=1
[ "$(total)" = 5 ] && ok "setup: QA holds all 5 slots" || fail "setup gave $(total)"
tick_review
[ "$REVIEW_COUNT" = 0 ] && ok "slots full: Review waits (shared cap)" || fail "Review started over the cap"
# một tester xong → slot trống; vòng chính chạy Review rồi QA như thứ tự trong runner
dead=${QA_PID%%:*}; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null; QA_PID=""; QA_ISSUE=""
cards2 8 7; reap_finished_locks
tick_review
lane_dispatch_tick qa QA
lane_workers_count review
[ "$REVIEW_COUNT" = 1 ] && ok "first freed slot goes to Review" || fail "Review got no slot (count=$REVIEW_COUNT)"
lane_workers_count qa
[ "$(total)" = 5 ] && [ "$QA_COUNT" = 4 ] && ok "QA did not take it (QA 4 + Review 1 = 5)" || fail "total=$(total) qa=$QA_COUNT"

# đối chứng: nếu QA đi trước thì Review đói — chứng minh test phân biệt được thứ tự
reset; load 0
cards QA 1 2 3 4 5 6; for i in 1 2 3 4 5 6; do tick_qa; done
dead=${QA_PID%%:*}; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null; QA_PID=""; QA_ISSUE=""
cards2 8 7; REVIEW=1; QA=1; reap_finished_locks
lane_dispatch_tick qa QA
tick_review
lane_workers_count review
[ "$REVIEW_COUNT" = 0 ] && ok "control: QA-first order starves Review (the oracle can fail)" || fail "control did not starve Review"

# thứ tự trong vòng chính của runner: Review trước QA trước Build
l1=$(grep -n 'lane_dispatch_tick review Review' "$RUNNER" | head -1 | cut -d: -f1)
l2=$(grep -n 'lane_dispatch_tick qa QA' "$RUNNER" | head -1 | cut -d: -f1)
l3=$(grep -n 'build_slot_free || true' "$RUNNER" | head -1 | cut -d: -f1)
[ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ] && [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l3" ] && ok "main loop order: Review < QA < Build ($l1 < $l2 < $l3)" || fail "dispatch order changed ($l1 / $l2 / $l3)"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
