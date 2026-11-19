#!/usr/bin/env bash
# #1350 (19/11): a reviewer that ends its report with `blocked-by: -` ("hand to a person") for a CONCRETE code finding the builder can fix (#1350: audit major at
# super-board-run.sh:459, the scope already answered by AC1) left the card in Review, then the orchestrator Blocked it ❓. `review_dash_is_bounceable` turns that
# into a bounce to the builder. A `blocked-by: -` stays a person-wait when:
#   - there is no ❌ finding with a file:line, or the comment is not the newest [reviewer] one ending in `blocked-by: -`;
#   - the comment names a closed-list reason (💳 🔐 🧑 🙋, payment, secret, migration, device, ...) or the card is needs-you / human-gated;
#   - the PR is queued for the merge queue, or the worker did not end clean;
#   - the same comment already bounced once, or the card already bounced SB_REVIEW_BOUNCE_MAX (3) times.
# Offline frame of test_review_bounce_ready_1316.sh. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1350.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX SB_REVIEW_STALL_MAX SB_REVIEW_BOUNCE_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
unset SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX SB_REVIEW_STALL_MAX SB_REVIEW_BOUNCE_MAX
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
LAST=""
issue_last_comment() { printf '%s\n' "$LAST"; }
merge_queue_on() { return 1; }
review_approved_head() { return 1; }
sleep 0 & DEAD=$!; wait "$DEAD"

set_card() {   # set_card <number> [labels-json]
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Review\",\"labels\":${2:-[]},\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"
}
turn() {   # turn <issue> [comments0]: a review worker lock, reaped, then the no-op sweep
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-19T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "${2:-$COUNT}" > "$INFLIGHT_DIR/$1"
  reap_finished_locks; block_noop_workers
}
wlog_clean() { printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":false,"result":"%s"}\nworker_exit: exit=0 signal=- elapsed=300s\n' "$2" > "$WORKER_LOG_DIR/worker-review-$1.log"; }
wlog_killed() { printf '=== dispatch x\nworker_exit: exit=137 signal=KILL elapsed=300s\n' > "$WORKER_LOG_DIR/worker-review-$1.log"; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; rm -f "$INFLIGHT_DIR"/noops/* "$INFLIGHT_DIR"/review-wait/* "$INFLIGHT_DIR"/review-stall/*; }
fresh_ledger() { SWEPT_CARDS=""; : > "$INFLIGHT_DIR/swept-cards"; }
finding() {   # finding <where> [extra words on the ❌ line] : the newest [reviewer] comment of the #1350 shape
  printf '[reviewer] [report] ⏸ chưa vào queue · PR #1360 @ ce04a734\n❌ Phát hiện của audit (major): `%s` — set_card_status không qua recover_read_halt. %s\nNext: người xem quyết định.\nblocked-by: -' "$1" "${2:-}"
}
FINAL="Tôi chưa review lại và chưa ghi gì lên card."
cd "$TMP" || exit 1

# A: concrete finding + `blocked-by: -`, worker comment count unchanged (#1350) -> Ready, one orchestrator comment, not Blocked
reset_case; fresh_ledger; set_card 1501; wlog_clean 1501 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:459')"
turn 1501
if grep -qx "move PVTI_1501 Ready" "$TMP/writes" && ! grep -q "Blocked" "$TMP/writes" && grep -q "gh issue comment 1501" "$TMP/writes"; then ok "A: finding + blocked-by: - (count == c0) -> Ready + comment, not Blocked"
else fail "A: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# A2: same shape but the worker commented this turn (count > c0) -> Ready
reset_case; fresh_ledger; set_card 1502; wlog_clean 1502 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:460')"
turn 1502 2
if grep -qx "move PVTI_1502 Ready" "$TMP/writes"; then ok "A2: finding + blocked-by: - (count > c0) -> Ready"
else fail "A2: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# B: closed-list reason -> a real person-wait, not bounced
for word in "🙋 cần người quyết" "thanh toán" "payment" "migration"; do
  reset_case; fresh_ledger; set_card 1503; wlog_clean 1503 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:461' "$word")"
  turn 1503
  if ! grep -q "move PVTI_1503 Ready" "$TMP/writes" && grep -q "move PVTI_1503 Blocked" "$TMP/writes"; then ok "B: closed-list reason '$word' -> not bounced, Blocked as before"
  else fail "B($word): writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi
done

# C: needs-you / human-gated card -> never bounced
for lab in needs-you human-gated; do
  reset_case; fresh_ledger; set_card 1504 "[\"$lab\"]"; wlog_clean 1504 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:462')"
  turn 1504
  if ! grep -q "move PVTI_1504 Ready" "$TMP/writes"; then ok "C: label $lab -> never bounced"
  else fail "C($lab): writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi
done

# D: the same comment a second time -> not bounced again
reset_case; fresh_ledger; set_card 1505; wlog_clean 1505 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:463')"
turn 1505
: > "$TMP/writes"; reset_case; set_card 1505; wlog_clean 1505 "$FINAL"
turn 1505
if ! grep -q "move PVTI_1505 Ready" "$TMP/writes"; then ok "D: the same reviewer comment bounces only once"
else fail "D: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# E: ceiling SB_REVIEW_BOUNCE_MAX = 3 bounces per card (different comments each time)
fresh_ledger
for n in 1 2 3; do
  reset_case; set_card 1506; wlog_clean 1506 "$FINAL"; LAST="$(finding ".claude/bin/super-board-run.sh:47$n")"
  turn 1506
  grep -qx "move PVTI_1506 Ready" "$TMP/writes" || fail "E: bounce $n of 3 did not happen: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"
done
reset_case; set_card 1506; wlog_clean 1506 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:479')"
turn 1506
if ! grep -q "move PVTI_1506 Ready" "$TMP/writes"; then ok "E: the 4th bounce of one card is refused (ceiling 3)"
else fail "E: 4th bounce happened: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

# F: no file:line -> a scope question without a concrete finding stays a person-wait
reset_case; fresh_ledger; set_card 1507; wlog_clean 1507 "$FINAL"
LAST=$'[reviewer] [report] ⏸ chờ\n❌ cần xác nhận phạm vi với chủ repo.\nNext: người xem quyết định.\nblocked-by: -'
turn 1507
if ! grep -q "move PVTI_1507 Ready" "$TMP/writes"; then ok "F: no file:line finding -> not bounced"
else fail "F: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# G: PR queued (merge-queue + approved-head) -> never bounced
reset_case; fresh_ledger; set_card 1508; wlog_clean 1508 "$FINAL"; LAST="$(finding '.claude/bin/super-board-run.sh:464')"
merge_queue_on() { return 0; }; review_approved_head() { return 0; }
turn 1508
merge_queue_on() { return 1; }; review_approved_head() { return 1; }
if ! grep -q "move PVTI_1508 Ready" "$TMP/writes"; then ok "G: queued PR is never bounced"
else fail "G: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# H: the worker did not end clean (killed) -> not bounced
reset_case; fresh_ledger; set_card 1509; wlog_killed 1509; LAST="$(finding '.claude/bin/super-board-run.sh:465')"
turn 1509
if ! grep -q "move PVTI_1509 Ready" "$TMP/writes"; then ok "H: a killed worker is not bounced"
else fail "H: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# I: the #1316 path still works (not approved, no blocked-by line)
reset_case; fresh_ledger; set_card 1510; wlog_clean 1510 "Not approved. The card stays in Review. Next step is the builder."; LAST=""
turn 1510
if grep -qx "move PVTI_1510 Ready" "$TMP/writes"; then ok "I: the #1316 not-approved path still routes to Ready"
else fail "I: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-240)"; fi

# J: doc rule in review-flow.md
if grep -q 'blocked-by: -' "$ROOT/.claude/skills/super-review/references/review-flow.md" \
   && grep -qi 'closed list' "$ROOT/.claude/skills/super-review/references/review-flow.md"; then ok "J: review-flow.md states the closed-list rule for blocked-by: -"
else fail "J: review-flow.md lacks the closed-list rule"; fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_review_blocked_by_dash_bounce_1350: PASS"; exit 0; } || { echo "test_review_blocked_by_dash_bounce_1350: FAIL ($FAILS)"; exit 1; }
