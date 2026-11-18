#!/usr/bin/env bash
# Test hồi quy #1221 AC3: lane Review gọi lại cùng một thẻ mà worker thoát 0 (có comment) không đổi lane thì thẻ sang Blocked
# kèm lý do sau SB_REVIEW_STALL_MAX (3) lượt, không dispatch tiếp tới RUNAWAY. Fixture offline (hàm runner được source, gh là stub).
#  A: 2 lượt -> chưa Blocked; lượt 3 -> Blocked + comment nêu điều kiện chưa đạt, sổ review-stall xoá.
#  B: thẻ đã vào merge queue (approved-head + nhãn) -> miễn.   C: thẻ đổi cột -> sổ bắt đầu lại.
#  D: lượt chờ điều kiện đặt tên (blocked-by: X) -> không tính (đã có trần SB_REVIEW_WAIT_MAX).   E: worker bị kill -> không tính.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1221s.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX SB_REVIEW_STALL_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
unset SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX SB_REVIEW_STALL_MAX
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
COUNT=3
issue_comment_count() { printf '%s' "$COUNT"; }
LAST_COMMENT=""
issue_last_comment() { printf '%s' "$LAST_COMMENT"; }
QUEUED=0
merge_queue_on() { [ "$QUEUED" = 1 ]; }
review_approved_head() { [ "$QUEUED" = 1 ]; }
sleep 0 & DEAD=$!; wait "$DEAD"
OKRES='{"type":"result","subtype":"success","is_error":false,"result":"done"}'
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"${2:-Review}\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
# turn <issue>: một lượt review kết thúc có comment mới (COMMENTS0 = COUNT hiện tại, rồi comment tăng 1)
turn() {
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-17T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=%s\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "${2:-Review}" "$COUNT" > "$INFLIGHT_DIR/$1"
  COUNT=$((COUNT + 1))
  reap_finished_locks; block_noop_workers
}
okwlog() { printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=1200s\n' "$OKRES" > "$1"; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; COUNT=3; QUEUED=0; LAST_COMMENT=$'[reviewer] [report] cần duyệt chéo test\nblocked-by: -'; }
cd "$TMP" || exit 1

reset_case; set_card 1301; okwlog "$WORKER_LOG_DIR/worker-review-1301.log"
turn 1301; turn 1301
mid=0; grep -q "^move " "$TMP/writes" && mid=1
turn 1301
if [ "$mid" = 0 ] && grep -qx "move PVTI_1301 Blocked" "$TMP/writes" && grep -q "review turns in a row" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/review-stall/1301" ]; then ok "A: 3rd clean review turn with the card still in Review -> Blocked with a reason, 2 turns -> not"
else fail "A: mid=$mid writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1302; okwlog "$WORKER_LOG_DIR/worker-review-1302.log"; QUEUED=1
turn 1302; turn 1302; turn 1302; turn 1302
if ! grep -q "^move " "$TMP/writes"; then ok "B: a PR queued for merge is exempt"; else fail "B: queued card blocked"; fi

reset_case; set_card 1303; okwlog "$WORKER_LOG_DIR/worker-review-1303.log"
turn 1303; turn 1303
set_card 1303 Building; turn 1303 Review   # lượt bắt đầu ở Review nhưng thẻ đã sang Building: tiến triển, sổ xoá
set_card 1303 Review; turn 1303; turn 1303
if ! grep -q "^move " "$TMP/writes"; then ok "C: a column change restarts the stall ledger"; else fail "C: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1304; okwlog "$WORKER_LOG_DIR/worker-review-1304.log"
LAST_COMMENT=$'[reviewer] [report] chờ CI\nblocked-by: ci_green'
turn 1304; turn 1304; turn 1304; turn 1304
if ! grep -q "^move " "$TMP/writes"; then ok "D: turns waiting on a named condition are not counted here"; else fail "D: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1305
printf '=== dispatch x\nworker_exit: exit=143 signal=TERM elapsed=99s\n' > "$WORKER_LOG_DIR/worker-review-1305.log"
turn 1305; turn 1305; turn 1305
if ! grep -q "^move " "$TMP/writes"; then ok "E: killed workers (not exit 0) are not counted"; else fail "E: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

[ "$FAILS" = 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
