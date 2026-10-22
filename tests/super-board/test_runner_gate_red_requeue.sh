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

MAIN_SHA="aaaa111"; MAIN_DATE="2026-10-22T01:19:00Z"; PR_STATE=OPEN; COMMENT_BODY=""; COMMENT_AT="2026-10-21T23:31:00Z"
base_head_info() { echo "$MAIN_SHA $MAIN_DATE"; }
pr_open() { [ "$PR_STATE" = OPEN ]; }
gate_red_comments() {   # trang slurp: một comment người + một blocker
  echo "$1" >> "$TMP/comment_reads"
  jq -n --arg b "$COMMENT_BODY" --arg at "$COMMENT_AT" \
    '[[{id:1,body:"hello",user:{login:"x"},created_at:"2026-10-20T00:00:00Z",updated_at:"2026-10-20T00:00:00Z"},
       {id:2,body:$b,user:{login:"bot"},created_at:$at,updated_at:$at}]]'
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
  COMMENT_BODY="$GATE_RED"; unset SB_GATE_RETRY_COOLDOWN_S
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

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; }
echo "$FAILS failed"; exit 1
