#!/usr/bin/env bash
# Test hồi quy #1318: worker build/QA thoát exit 0 (kết thúc sạch) có comment lane mới sau lúc dispatch thì runner đi tiếp, không tính
# "died mid-run" / no-op, không Blocked chờ người. Thoát không comment mới vẫn giữ hành vi cũ.
#  A: build exit 0, thẻ còn Building, comment `[builder] … Next: qa` mới -> move QA, không sổ reclaim, không [blocker] (ĐỎ trên runner cũ).
#  B: QA exit 0, thẻ còn QA, `[qa] [report] ❌` mới -> nhãn loop:rebuild-1 rồi Ready (ĐỎ trên runner cũ).
#  B2: QA exit 0, `[qa] [report] ✅` mới -> Review. B3: thẻ đã loop:rebuild-2 (= rebuild_cap) -> không tự chuyển.
#  C: QA thoát không comment mới -> vẫn Blocked ❓ sau SB_NOOP_MAX lượt (không nới).
#  D: build exit 0 không comment mới -> vẫn trả về Ready + ghi sổ reclaim như cũ.
#  E: build exit 0, comment `[builder]` có trước lúc dispatch -> không tính là bàn giao (sổ reclaim như cũ).
#  F: super-build/SKILL.md ghim dòng push commit local + một lần move trước khi kết thúc lượt.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1318.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_RECLAIM_MAX SB_RECLAIM_WINDOW_S
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"; REBUILD_CAP=2
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
gh() { echo "rawgh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
issue_is_open() { return 0; }
merge_queue_on() { return 1; }
review_approved_head() { return 1; }
COUNT=3
issue_comment_count() { printf '%s' "$COUNT"; }
issue_last_comment() { printf '%s' ""; }
COMMENTS='[]'
issue_comments_since() { printf '%s' "$COMMENTS"; }
sleep 0 & DEAD=$!; wait "$DEAD"
set_card() { # <issue> <status> [labels json]
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":${3:-[]},\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"labels\":${3:-[]},\"assignees\":[\"sb-bot\"]}}]}"
}
wlog() { # <lane> <issue>: a clean end (exit 0 + success result) of a dispatch at 12:00:00Z
  printf '=== dispatch lane=%s issue=#%s at 2026-11-19T12:00:00Z ===\n{"type":"result","subtype":"success","is_error":false,"result":"done"}\nworker_exit: exit=0 signal=- elapsed=205s\n' "$1" "$2" > "$WORKER_LOG_DIR/worker-$1-$2.log"
}
lock() { # <lane> <issue> [FROM_COL COMMENTS0]
  printf 'PID=%s\nLANE=%s\nSTARTED=2026-11-19T12:00:00Z\nWORKER_LOG=%s\n' "$DEAD" "$1" "$WORKER_LOG_DIR/worker-$1-$2.log" > "$INFLIGHT_DIR/$2"
  [ -z "${3:-}" ] || printf 'FROM_COL=%s\nCOMMENTS0=%s\n' "$3" "$4" >> "$INFLIGHT_DIR/$2"
}
build_turn() { lock build "$1"; reap_finished_locks; reclaim_dead_builds; }
qa_turn() { lock qa "$1" QA 3; reap_finished_locks; block_noop_workers; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; RECLAIM_BUILDING=""; rm -rf "$INFLIGHT_DIR"/noops "$INFLIGHT_DIR"/reclaims; COUNT=3; COMMENTS='[]'; }
cmt() { # <created_at> <body> -> one comment JSON object
  jq -nc --arg t "$1" --arg b "$2" '{created_at: $t, body: $b}'
}
w() { tr '\n' ';' < "$TMP/writes" | cut -c1-300; }
cd "$TMP" || exit 1

# A
reset_case; set_card 1501 Building; wlog build 1501; COUNT=4
COMMENTS="[$(cmt 2026-11-19T12:03:00Z $'[builder] [report] ✅ built · PR #9\nDid: x\nNext: qa')]"
build_turn 1501
if grep -qx "move PVTI_1501 QA" "$TMP/writes" && ! grep -q "Ready\|Blocked\|\[blocker\]" "$TMP/writes" && [ ! -s "$INFLIGHT_DIR/reclaims/1501" ]; then
  ok "A: build exit 0 + new [builder] Next: qa -> QA, no reclaim, no blocker"
else fail "A: writes: $(w) reclaims=$(cat "$INFLIGHT_DIR/reclaims/1501" 2>/dev/null)"; fi

# B
reset_case; set_card 1502 QA; wlog qa 1502; COUNT=4
COMMENTS="[$(cmt 2026-11-19T12:04:00Z $'<!-- marker -->\n[qa] [report] ❌ failing · round 1 @ 3f9c2ab\nDid: ran AC1\nNext: builder')]"
qa_turn 1502
if grep -q "gh issue edit 1502 --add-label loop:rebuild-1" "$TMP/writes" && grep -qx "move PVTI_1502 Ready" "$TMP/writes" && ! grep -q "Blocked" "$TMP/writes"; then
  ok "B: QA exit 0 + new [qa] [report] ❌ -> loop:rebuild-1, Ready"
else fail "B: writes: $(w)"; fi

# B2
reset_case; set_card 1503 QA; wlog qa 1503; COUNT=4
COMMENTS="[$(cmt 2026-11-19T12:04:00Z $'[qa] [report] ✅ passing · round 1 @ 3f9c2ab\nNext: reviewer')]"
qa_turn 1503
if grep -qx "move PVTI_1503 Review" "$TMP/writes" && ! grep -q "loop:rebuild" "$TMP/writes"; then ok "B2: QA exit 0 + new [qa] [report] ✅ -> Review"
else fail "B2: writes: $(w)"; fi

# B3
reset_case; set_card 1504 QA '["loop:rebuild-2"]'; wlog qa 1504; COUNT=4
COMMENTS="[$(cmt 2026-11-19T12:04:00Z $'[qa] [report] ❌ failing · round 3 @ 3f9c2ab\nNext: builder')]"
qa_turn 1504
if ! grep -q "move PVTI_1504" "$TMP/writes" && ! grep -q "add-label" "$TMP/writes"; then ok "B3: QA ❌ at rebuild_cap -> runner does not route it"
else fail "B3: writes: $(w)"; fi

# C
reset_case; set_card 1505 QA; wlog qa 1505
qa_turn 1505; qa_turn 1505
if grep -qx "move PVTI_1505 Blocked" "$TMP/writes" && ! grep -q "Review\|Ready" "$TMP/writes"; then ok "C: QA exit 0 without a new comment -> still Blocked after SB_NOOP_MAX"
else fail "C: writes: $(w)"; fi

# D
reset_case; set_card 1506 Building; wlog build 1506
build_turn 1506
if grep -qx "move PVTI_1506 Ready" "$TMP/writes" && ! grep -q " QA" "$TMP/writes" && [ -s "$INFLIGHT_DIR/reclaims/1506" ]; then
  ok "D: build exit 0 without a new comment -> Ready + reclaim ledger as before"
else fail "D: writes: $(w) reclaims=$(cat "$INFLIGHT_DIR/reclaims/1506" 2>/dev/null)"; fi

# E
reset_case; set_card 1507 Building; wlog build 1507; COUNT=4
COMMENTS="[$(cmt 2026-11-19T11:59:00Z $'[builder] [report] ✅ built\nNext: qa')]"
build_turn 1507
if ! grep -q " QA" "$TMP/writes" && [ -s "$INFLIGHT_DIR/reclaims/1507" ]; then ok "E: a [builder] report older than the dispatch is not a handoff"
else fail "E: writes: $(w)"; fi

# F
SK="$ROOT/.claude/skills/super-build/SKILL.md"
if grep -qF 'Before ending any turn, push every local commit' "$SK" && grep -qF 'the last command of the turn is one' "$SK"; then
  ok "F: super-build SKILL.md pins push-before-exit + one move"
else fail "F: super-build SKILL.md lacks the push-before-exit line"; fi

[ "$FAILS" = 0 ] && { echo "PASS test_worker_exit_handoff_1318"; exit 0; }
echo "FAIL test_worker_exit_handoff_1318 ($FAILS)"; exit 1
