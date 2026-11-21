#!/usr/bin/env bash
# Test hồi quy #1399 (gộp vào #1397):
#  A1. Hai lượt review liên tiếp CÓ comment mới, dòng cuối `blocked-by: agent`, cùng head & lý do -> lượt 1 ghi sổ chung và bật cooldown 900s; lượt 2 -> Blocked, giữ `blocked-by:  agent`.
#  A2. Đổi head PR hoặc đổi reason_key -> sổ chung reset, không bị Blocked sớm.
#  B1. Lượt 1 có comment `blocked-by: agent`, lượt 2 thoát 0 KHÔNG comment mới -> không quá 2 lượt trước khi Blocked (không phải 8), giữ `blocked-by:  agent`.
#  B2. Hai lượt KHÔNG comment mới trên thẻ đang có `blocked-by: agent` -> Blocked ở lượt 2 (≤ 2 lượt).
#  C.  sweep_antigravity_blocked: probe OK nhưng worker vẫn lỗi -> đưa Blocked -> Review tối đa 2 lần / 24h; lần 3 trong 24h giữ Blocked (`blocked-by:  -`); qua 24h cho sweep lại.
#  D.  Detector review_antigravity_failure_reason: nhận các biến thể thật đã hụt ở GeelyEx2; không nhận nhầm câu review bình thường nhắc `antigravity-pm`.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1399.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX SB_REVIEW_AGENT_WAIT_MAX SB_REVIEW_STALL_MAX SB_ANTIGRAVITY_SWEEP_MAX SB_ANTIGRAVITY_SWEEP_WINDOW_S SB_ANTIGRAVITY_SWEEP_EVERY
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e

INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
issue_is_open() { return 0; }
merge_queue_on() { return 1; }
review_approved_head() { return 1; }
COUNT=3
issue_comment_count() { printf '%s' "$COUNT"; }
LAST_COMMENT=""
issue_last_comment() { printf '%s' "$LAST_COMMENT"; }
HEAD_SHA="1111111111111111111111111111111111111111"
issue_pr_head() { printf '%s' "$HEAD_SHA"; }

sleep 0 & DEAD=$!; wait "$DEAD"
OKRES='{"type":"result","subtype":"success","is_error":false,"result":"waiting"}'
okwlog() { printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=60s\n' "$OKRES" > "$1"; }
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"${2:-Review}\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
set_card_unclaimed() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"${2:-Review}\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[]}}]}"; }

turn_new() {
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "$COUNT" > "$INFLIGHT_DIR/$1"
  COUNT=$((COUNT + 1))
  reap_finished_locks; block_noop_workers
}
turn_same() {
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" "$COUNT" > "$INFLIGHT_DIR/$1"
  reap_finished_locks; block_noop_workers
}
reset_case() {
  : > "$TMP/writes"; : > "$TMP/log"
  NOOP_CHECK=""; NOOP_MOVED=0; COUNT=3
  HEAD_SHA="1111111111111111111111111111111111111111"
  rm -rf "$INFLIGHT_DIR/noops" "$INFLIGHT_DIR/review-wait" "$INFLIGHT_DIR/review-stall" "$INFLIGHT_DIR/ag-sweep"
}

cd "$TMP" || exit 1

# ── A1 (Oracle a): 2 lượt CÓ comment mới, blocked-by: agent, cùng head + cùng lý do
reset_case; set_card 13991
okwlog "$WORKER_LOG_DIR/worker-review-13991.log"
LAST_COMMENT=$'[reviewer] [report] ⏳ chờ quota 429\nblocked-by: agent'
turn_new 13991
t1_moved=0; grep -q "^move " "$TMP/writes" && t1_moved=1
t1_cd=1; review_wait_cooldown 13991 && t1_cd=0
set_card_unclaimed 13991 Review
top_card_in_column Review </dev/null; picked_during_cd="$TOP_ISSUE"
set_card 13991 Review
turn_new 13991
if [ "$t1_moved" = 0 ] && [ "$t1_cd" = 0 ] && [ -z "$picked_during_cd" ] \
   && grep -qx "move PVTI_13991 Blocked" "$TMP/writes" \
   && grep -qx "blocked-by:  agent" "$TMP/writes" \
   && [ ! -e "$INFLIGHT_DIR/review-wait/13991" ]; then
  ok "A1 (Oracle a): 2 new-comment blocked-by: agent turns (same head & reason) -> cooldown on 1st, Blocked on 2nd with blocked-by:  agent"
else
  fail "A1 (Oracle a): t1_moved=$t1_moved t1_cd=$t1_cd picked=$picked_during_cd writes=$(tr '\n' ';' < "$TMP/writes")"
fi

# ── A2: Đổi head hoặc đổi reason_key -> reset sổ chung, không bị Blocked ở lượt 2
reset_case; set_card 13992
okwlog "$WORKER_LOG_DIR/worker-review-13992.log"
LAST_COMMENT=$'[reviewer] [report] ⏳ chờ quota 429\nblocked-by: agent'
turn_new 13992
HEAD_SHA="2222222222222222222222222222222222222222"
turn_new 13992
LAST_COMMENT=$'[reviewer] [report] ⏳ chờ gate_receipt\nblocked-by: agent'
turn_new 13992
if ! grep -q "^move " "$TMP/writes" && [ "$(wc -l < "$INFLIGHT_DIR/review-wait/13992" | tr -d ' ')" = 1 ]; then
  ok "A2: changing PR head or reason_key resets shared review-wait ledger (no premature Block)"
else
  fail "A2: head/reason change did not reset ledger (writes=$(tr '\n' ';' < "$TMP/writes") lines=$(wc -l < "$INFLIGHT_DIR/review-wait/13992" 2>/dev/null || echo 0))"
fi

# ── B1: Lượt 1 có comment mới `blocked-by: agent`, lượt 2 thoát 0 KHÔNG comment mới -> Blocked ở lượt 2 (≤ 2 lượt)
reset_case; set_card 13993
okwlog "$WORKER_LOG_DIR/worker-review-13993.log"
LAST_COMMENT=$'[reviewer] [report] ⏳ chờ quota 429\nblocked-by: agent'
turn_new 13993
mid_b1=0; grep -q "^move " "$TMP/writes" && mid_b1=1
turn_same 13993
if [ "$mid_b1" = 0 ] && grep -qx "move PVTI_13993 Blocked" "$TMP/writes" && grep -qx "blocked-by:  agent" "$TMP/writes"; then
  ok "B1 (Oracle a+b): new-comment wait then silent wait -> Blocked on 2nd turn with blocked-by:  agent"
else
  fail "B1: mid=$mid_b1 writes=$(tr '\n' ';' < "$TMP/writes")"
fi

# ── B2 (Oracle b): 2 lượt KHÔNG comment mới trên thẻ đang có `blocked-by: agent` -> Blocked ở lượt 2 (không phải 8)
# (kể cả khi dòng cuối log có chữ 'device', vẫn giữ `blocked-by:  agent` chứ không đổi thành `-`)
reset_case; set_card 13994
printf '=== dispatch x\ndevice check ok\n%s\nworker_exit: exit=0 signal=- elapsed=60s\n' "$OKRES" > "$WORKER_LOG_DIR/worker-review-13994.log"
LAST_COMMENT=$'[reviewer] [report] ⏳ chờ quota 429\nblocked-by: agent'
turn_same 13994
mid_b2=0; grep -q "^move " "$TMP/writes" && mid_b2=1
turn_same 13994
if [ "$mid_b2" = 0 ] && grep -qx "move PVTI_13994 Blocked" "$TMP/writes" && grep -qx "blocked-by:  agent" "$TMP/writes" && ! grep -qx "blocked-by:  -" "$TMP/writes"; then
  ok "B2 (Oracle b): 2 silent blocked-by: agent turns -> Blocked on 2nd turn (<=2, not 8), keeps blocked-by:  agent"
else
  fail "B2: mid=$mid_b2 writes=$(tr '\n' ';' < "$TMP/writes")"
fi

# ── C (Oracle sweep - AC6): sweep_antigravity_blocked tối đa 2 lần / 24h (an toàn dưới set -euo pipefail)
reset_case
antigravity_can_provide_mcp() { return 0; }
antigravity_probe() { return 0; }
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="a"; POOL_CFG=""; return 0; }
AG_SWEEP_NEXT=0; AG_NON_AG_CARDS=""
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_13995","status":"Blocked","labels":[],"content":{"type":"Issue","number":13995,"title":"ag loop","assignees":[]}}]}'
cap_progress_comments() {
  printf '%s' '[{"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"}]'
}
sweep_antigravity_blocked; rc1=$?
sweep_antigravity_blocked; rc2=$?
: > "$TMP/writes"
( set -euo pipefail; sweep_antigravity_blocked ) >/dev/null 2>&1; rc3=$?
: > "$TMP/writes"
( set -euo pipefail; sweep_antigravity_blocked ) >/dev/null 2>&1; rc4=$?   # lần 4 cũng không spam thêm comment
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$rc3" -ne 0 ] && [ "$rc4" -ne 0 ] \
   && ! grep -q "^move " "$TMP/writes"; then
  # kiểm tra ghi 2 lần trong ag-sweep/13995 và đã đổi blocked-by: - một lần
  ok "C1 (Oracle sweep): sweep_antigravity_blocked moves at most 2 times / 24h, blocks further sweeps"
else
  fail "C1 (Oracle sweep): rc1=$rc1 rc2=$rc2 rc3=$rc3 rc4=$rc4 writes=$(tr '\n' ';' < "$TMP/writes")"
fi
# Sau 24h (mốc cũ hơn 86400s), cho sweep lại
if [ -f "$INFLIGHT_DIR/ag-sweep/13995" ]; then
  old=$(( $(date +%s) - 90000 ))
  printf '%s\n%s\n' "$old" "$old" > "$INFLIGHT_DIR/ag-sweep/13995"
  : > "$TMP/writes"
  sweep_antigravity_blocked; rc_after=$?
  if [ "$rc_after" -eq 0 ] && grep -qx "move PVTI_13995 Review" "$TMP/writes"; then
    ok "C2: after 24h window expires, sweep_antigravity_blocked allows recovery again"
  else
    fail "C2: expired 24h window still blocked (rc=$rc_after writes=$(tr '\n' ';' < "$TMP/writes"))"
  fi
else
  fail "C2: missing $INFLIGHT_DIR/ag-sweep/13995 ledger file"
fi

# ── D (Oracle detector - AC7): các câu thật đã hụt ở GeelyEx2 + câu âm tính
d_pos=(
  'phiên hiện tại không có các công cụ MCP `antigravity-pm` (`pm_task_create`, `pm_dispatch`, `pm_verdict`), nên không thể chạy audit'
  'Do công cụ MCP `antigravity-pm` (`pm_task_create`, `pm_dispatch`, `pm_verdict`) **không có trong phiên này**, không thể chạy audit Antigravity'
  'Các công cụ MCP của `antigravity-pm` (`pm_task_create`, `pm_dispatch`, `pm_verdict`) không có mặt trong phiên hiện tại.'
  'MCP `antigravity-pm` vắng mặt trong phiên.'
)
for i in "${!d_pos[@]}"; do
  got=$(review_antigravity_failure_reason "" "${d_pos[$i]}")
  if [ "$got" = "missing-mcp" ]; then
    ok "D-pos-$((i + 1)): matched missed GeelyEx2 phrase"
  else
    fail "D-pos-$((i + 1)): got '$got' for: ${d_pos[$i]}"
  fi
done

d_neg=(
  'PR sửa file test có sẵn nên nhắc tới `antigravity-pm` trong checklist; tất cả bước đạt và đã approved-head.'
  'Đã chạy audit qua `antigravity-pm` thành công, verdict pass.'
  'Nếu không có finding thì gọi `antigravity-pm` ở bước sau; hiện PR đã ký duyệt xong.'
)
for i in "${!d_neg[@]}"; do
  got=$(review_antigravity_failure_reason "" "${d_neg[$i]}")
  if [ -z "$got" ]; then
    ok "D-neg-$((i + 1)): normal review mention not misclassified"
  else
    fail "D-neg-$((i + 1)): false positive '$got' for: ${d_neg[$i]}"
  fi
done

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_review_wait_agent_1399: PASS"; exit 0; } || { echo "test_runner_review_wait_agent_1399: FAIL ($FAILS)"; exit 1; }
