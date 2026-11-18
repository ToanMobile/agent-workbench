#!/usr/bin/env bash
# Test hồi quy #1316: review worker kết thúc sạch (exit 0, end_turn) với kết luận "không duyệt" mà không đổi cột, không comment
# thì orchestrator đưa thẻ về Ready (builder nhận), không Blocked ❓. Thoát không kết luận thì vẫn Blocked. Prompt review ghim dòng `move … Ready`.
#  A: kết luận không duyệt -> move Ready, không Blocked, không comment blocker.
#  B: thoát sạch không kết luận -> vẫn Blocked ❓ sau SB_NOOP_MAX lượt (không nới).
#  C: kết luận "merge-ready" (duyệt) mà thẻ vẫn ở Review -> không đưa về Ready.
#  D: SKILL.md super-review có dòng bắt buộc `move <N> Ready` ở nhánh bounce kể cả khi head chưa đổi.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1316.XXXXXX")"
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
issue_last_comment() { printf '%s' ""; }
merge_queue_on() { return 1; }
review_approved_head() { return 1; }
sleep 0 & DEAD=$!; wait "$DEAD"
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
turn() {
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-19T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "$COUNT" > "$INFLIGHT_DIR/$1"
  reap_finished_locks; block_noop_workers
}
wlog() { # <issue> <result text>
  printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":false,"result":"%s"}\nworker_exit: exit=0 signal=- elapsed=300s\n' "$2" > "$WORKER_LOG_DIR/worker-review-$1.log"
}
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; rm -f "$INFLIGHT_DIR"/noops/*; }
cd "$TMP" || exit 1

reset_case; set_card 1401; wlog 1401 "Not approved. The card stays in Review. Next step is the builder."
turn 1401
if grep -qx "move PVTI_1401 Ready" "$TMP/writes" && ! grep -q "Blocked\|\[blocker\]" "$TMP/writes"; then ok "A: clean exit with a not-approved conclusion -> Ready, not Blocked"
else fail "A: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1402; wlog 1402 "I looked around and finished."
turn 1402; turn 1402
if grep -qx "move PVTI_1402 Blocked" "$TMP/writes" && ! grep -q " Ready" "$TMP/writes"; then ok "B: clean exit without a conclusion still Blocked"
else fail "B: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

reset_case; set_card 1403; wlog 1403 "Merge-ready. Approved and queued."
turn 1403
if ! grep -q " Ready" "$TMP/writes"; then ok "C: an approving conclusion is not bounced to Ready"
else fail "C: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

if grep -q 'ends every bounce' "$ROOT/.claude/skills/super-review/SKILL.md" \
   && grep -q 'super-board-card.sh --config <cfg> move <N> Ready' "$ROOT/.claude/skills/super-review/SKILL.md"; then ok "D: review prompt pins the mandatory move … Ready line on bounce"
else fail "D: super-review SKILL.md lacks the mandatory move <N> Ready line"; fi

[ "$FAILS" = 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
