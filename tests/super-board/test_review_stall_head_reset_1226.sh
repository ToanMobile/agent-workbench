#!/usr/bin/env bash
# Regression #1226: the Review-stall ledger restarts when the PR head changes (progress). Offline fixture, harness from test_review_stall_blocked_1221.sh.
#  A: 2 no-op turns at head A, then head B: 3rd turn does NOT block.   B: 3 turns at the same head still block.
#  C: head read fails: no reset (3 turns still block), nothing new blocks.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1226s.XXXXXX")"
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
merge_queue_on() { return 1; }
review_approved_head() { return 1; }
HEAD_SHA=""
issue_pr_head() { printf '%s' "$HEAD_SHA"; }
sleep 0 & DEAD=$!; wait "$DEAD"
OKRES='{"type":"result","subtype":"success","is_error":false,"result":"done"}'
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
turn() {
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-17T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "$COUNT" > "$INFLIGHT_DIR/$1"
  COUNT=$((COUNT + 1))
  reap_finished_locks; block_noop_workers
}
okwlog() { printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=1200s\n' "$OKRES" > "$1"; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; COUNT=3; HEAD_SHA=""; LAST_COMMENT=$'[reviewer] [report] cần duyệt chéo test\nblocked-by: -'; }
cd "$TMP" || exit 1

reset_case; set_card 1401; okwlog "$WORKER_LOG_DIR/worker-review-1401.log"
HEAD_SHA=aaaa; turn 1401; turn 1401; HEAD_SHA=bbbb; turn 1401
if ! grep -q "^move " "$TMP/writes"; then ok "A: head changed after 2 turns -> 3rd turn not blocked"; else fail "A: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1402; okwlog "$WORKER_LOG_DIR/worker-review-1402.log"
HEAD_SHA=aaaa; turn 1402; turn 1402; turn 1402
if grep -qx "move PVTI_1402 Blocked" "$TMP/writes"; then ok "B: 3 turns at the same head still block"; else fail "B: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1403; okwlog "$WORKER_LOG_DIR/worker-review-1403.log"
HEAD_SHA=aaaa; turn 1403; turn 1403; HEAD_SHA=""; turn 1403
if grep -qx "move PVTI_1403 Blocked" "$TMP/writes"; then ok "C1: head read fails -> no reset, still blocks"; else fail "C1: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi
reset_case; set_card 1404; okwlog "$WORKER_LOG_DIR/worker-review-1404.log"
HEAD_SHA=""; turn 1404; turn 1404
if ! grep -q "^move " "$TMP/writes"; then ok "C2: head unreadable, 2 turns -> not blocked"; else fail "C2: blocked early"; fi

[ "$FAILS" = 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
