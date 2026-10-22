#!/usr/bin/env bash
# Test hồi quy #188 (22/10): thẻ Blocked vì "merge gate đỏ, không phải diff của PR" (#147/PR #160, #78/PR #170) không có
# issue blocker nên sweep_blocked_cards không bao giờ thả; lỗi kit đã sửa trên main mà thẻ vẫn kẹt chờ người kéo tay.
# Luật (requeue_gate_red_blocked):
#  - Thẻ Blocked không needs-you/human-gated, comment [reviewer] [blocker] mới nhất có dòng đầu "merge gate đỏ", dòng
#    `PR: #N`, dòng cuối `blocked-by: -`, PR còn OPEN, và main có commit MỚI HƠN comment → về Review (reviewer chạy lại gate
#    với luật merge thường), kèm comment ghi SHA main đã thử.
#  - Mỗi (thẻ, SHA main) một lần (sổ inflight/gate-retry/<N>), và không quá một lần mỗi SB_GATE_RETRY_COOLDOWN_S.
#  - Thẻ needs-you, blocker khác lý do gate, blocked-by là issue, PR đã đóng, main chưa tiến: không động tới.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-gate-red.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT SB_GATE_RETRY_COOLDOWN_S
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }

MAIN_SHA="aaaa111"; MAIN_DATE="2026-10-22T01:19:00Z"; PR_STATE=OPEN; COMMENT_BODY=""; COMMENT_AT="2026-10-21T23:31:00Z"; LATER_BODY=""
base_head_info() { echo "$MAIN_SHA $MAIN_DATE"; }
pr_open() { [ "$PR_STATE" = OPEN ]; }
gate_red_comments() {   # trang slurp: một comment người + một blocker (+ một blocker muộn hơn của vai khác nếu LATER_BODY)
  echo "$1" >> "$TMP/comment_reads"
  jq -n --arg b "$COMMENT_BODY" --arg at "$COMMENT_AT" --arg lb "$LATER_BODY" \
    '[[{id:1,body:"hello",user:{login:"x"},created_at:"2026-10-20T00:00:00Z",updated_at:"2026-10-20T00:00:00Z"},
       {id:2,body:$b,user:{login:"bot"},created_at:$at,updated_at:$at}]
      + (if $lb == "" then [] else [{id:3,body:$lb,user:{login:"bot"},created_at:"2026-10-22T00:30:00Z",updated_at:"2026-10-22T00:30:00Z"}] end)]'
}

GATE_RED='[reviewer] [blocker] 🛑 blocked · 🔧 merge gate đỏ vì test sentinel, không phải diff của PR #170
Card:        #78 kit
PR:          #170
Reason tag:  🔧
Owner:       Eric
blocked-by:  -'
set_card() {   # set_card <number> [labels-json]
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Blocked\",\"labels\":${2:-[\"feature\"]},\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\"}}]}"
}
reset_case() {
  : > "$TMP/writes"; : > "$TMP/log"; : > "$TMP/comment_reads"
  rm -rf "$INFLIGHT_DIR"/*
  PR_STATE=OPEN; MAIN_SHA="aaaa111"; MAIN_DATE="2026-10-22T01:19:00Z"; COMMENT_AT="2026-10-21T23:31:00Z"
  COMMENT_BODY="$GATE_RED"; LATER_BODY=""; unset SB_GATE_RETRY_COOLDOWN_S
}
cd "$TMP" || exit 1
no_move() { ! grep -q "^move " "$TMP/writes"; }

reset_case; set_card 78
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 0 ] && grep -qx "move PVTI_78 Review" "$TMP/writes" && grep -q "aaaa111" "$TMP/writes" && grep -q "^gh issue comment 78" "$TMP/writes"; then
  ok "A: gate-red Blocked card + newer main -> Review, comment names main SHA"
else fail "A: not requeued (rc=$rc writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

requeue_gate_red_blocked; rc=$?   # same main SHA
n=$(grep -c "^move " "$TMP/writes")
if [ "$rc" -eq 1 ] && [ "$n" = 1 ]; then ok "B: same main SHA -> not retried"; else fail "B: repeated for same SHA (rc=$rc moves=$n)"; fi

MAIN_SHA="bbbb222"; MAIN_DATE="2026-10-22T02:00:00Z"; SB_GATE_RETRY_COOLDOWN_S=3600
requeue_gate_red_blocked; rc=$?
n=$(grep -c "^move " "$TMP/writes")
if [ "$rc" -eq 1 ] && [ "$n" = 1 ]; then ok "C1: new SHA inside cooldown -> not retried"; else fail "C1: cooldown ignored (rc=$rc moves=$n)"; fi
SB_GATE_RETRY_COOLDOWN_S=0
requeue_gate_red_blocked; rc=$?
n=$(grep -c "^move " "$TMP/writes")
if [ "$rc" -eq 0 ] && [ "$n" = 2 ]; then ok "C2: new SHA after cooldown -> retried once more"; else fail "C2: not retried (rc=$rc moves=$n)"; fi
requeue_gate_red_blocked; rc=$?   # cooldown 0, same SHA as C2: only the per-SHA record can stop it
n=$(grep -c "^move " "$TMP/writes")
if [ "$rc" -eq 1 ] && [ "$n" = 2 ]; then ok "C3: same SHA after cooldown -> not retried"; else fail "C3: SHA dedupe ignored (rc=$rc moves=$n)"; fi

reset_case; set_card 79 '["feature","needs-you"]'
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move && [ ! -s "$TMP/comment_reads" ]; then ok "D: needs-you card untouched, comments not read"; else fail "D: needs-you card touched (rc=$rc)"; fi

reset_case; set_card 80; COMMENT_BODY='[reviewer] [blocker] 🛑 blocked · 🔑 cần token
Reason tag:  🔑
blocked-by:  -'
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "E: other human blocker untouched"; else fail "E: non-gate blocker requeued (rc=$rc)"; fi

reset_case; set_card 81; COMMENT_BODY="$(printf '%s' "$GATE_RED" | sed 's/^blocked-by:.*/blocked-by:  #12/')"
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "F: issue blocker left to sweep_blocked_cards"; else fail "F: issue-blocked card requeued (rc=$rc)"; fi

reset_case; set_card 82; PR_STATE=CLOSED
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "G: closed PR untouched"; else fail "G: closed PR requeued (rc=$rc)"; fi

reset_case; set_card 83; MAIN_DATE="2026-10-21T20:00:00Z"
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "H: main not newer than the block comment -> untouched"; else fail "H: requeued without new main commit (rc=$rc)"; fi

# I (R1): the card was requeued, then blocked again by another role's blocker (worker died): the LAST blocker of any role
# decides, so main moving must not requeue it.
reset_case; set_card 84; LATER_BODY='[orchestrator] [blocker] 🛑 blocked · worker chết
PR:          #170
blocked-by:  -'
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "I: later non-reviewer blocker wins -> untouched"; else fail "I: stale gate-red blocker requeued (rc=$rc)"; fi

# J (R2): empty / corrupt gate-retry record must not stop the runner; a non-numeric epoch counts as 0 (cooldown over).
for junk in "" "zzzz999" "zzzz999 abc"; do
  reset_case; set_card 85; mkdir -p "$INFLIGHT_DIR/gate-retry"; printf '%s' "$junk" > "$INFLIGHT_DIR/gate-retry/85"
  out=$( (requeue_gate_red_blocked; echo "rc=$?") 2>&1 | tail -1 )
  if [ "$out" = "rc=0" ] && grep -qx "move PVTI_85 Review" "$TMP/writes"; then ok "J: corrupt retry record '$junk' -> requeued, runner alive"
  else fail "J: corrupt retry record '$junk' broke the sweep ($out)"; fi
done

# K (R3): needs-you + loop:rebuild-N is work again (FOR_A_PERSON_JQ exemption) -> eligible; plain needs-you stays untouched (D).
reset_case; set_card 86 '["bug","needs-you","loop:rebuild-1"]'
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 0 ] && grep -qx "move PVTI_86 Review" "$TMP/writes"; then ok "K: needs-you + loop:rebuild-1 treated as work (shared for_a_person)"; else fail "K: shared for_a_person not used (rc=$rc)"; fi

# L (R5): `blocked-by: -` must be the LAST line, not just any line.
reset_case; set_card 87; COMMENT_BODY="$GATE_RED
Next: waiting for a person to look"
requeue_gate_red_blocked; rc=$?
if [ "$rc" -eq 1 ] && no_move; then ok "L: blocked-by not last line -> untouched"; else fail "L: mid-body blocked-by matched (rc=$rc)"; fi

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; }
echo "$FAILS failed"; exit 1
