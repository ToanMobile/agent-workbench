#!/usr/bin/env bash
# #558 (28/10): #535 đóng (COMPLETED) mà thẻ nằm Blocked tới khi kéo tay sang Done — reconcile chỉ nhìn cột đang được dispatch
# (Ready/QA/Review/Building). sweep_closed_cards quét MỌI thẻ ngoài Done mỗi tick: issue CLOSED completed → Done + một comment report;
# NOT_PLANNED giữ nguyên cột (chỉ log); ghi board hỏng → thẻ giữ nguyên, board không dừng, tick sau thử lại.
# Chạy hàm THẬT (SB_LIB_ONLY=1), github-read + gh ghi giả. SB_RUNNER=<file> chạy bản cũ để thấy ĐỎ. Offline.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/sb-sweep-closed.XXXXXX"); trap 'rm -rf "$T"' EXIT
# github-read giả: `issue list --state closed` trả danh sách đóng; đọc state từng thẻ luôn CLOSED
cat > "$T/read.py" <<'SH'
#!/bin/sh
case "$*" in
  *"issue list"*) printf '%s\n' "$CLOSED_JSON" ;;
  *) echo CLOSED ;;
esac
SH

run() {  # $1 = JSON issue đóng, $2 = 1 → ghi board hỏng; in các dòng ghi vào $T/calls
  rm -f "$T/calls"
  CLOSED_JSON="$1" BOARD_FAIL="${2:-0}" SB_LIB_ONLY=1 bash -c '
    R="$1" READ="$2" D="$3"; set --
    . "$R" >/dev/null 2>&1
    SB_GITHUB_READ="$READ"; python3() { sh "$@"; }
    INFLIGHT_DIR="$D/inflight"; mkdir -p "$INFLIGHT_DIR"; BOT_LOGIN=""
    PROJECT_ITEMS_JSON="{\"items\":[
      {\"id\":\"I535\",\"status\":\"Blocked\",\"content\":{\"type\":\"Issue\",\"number\":535}},
      {\"id\":\"I536\",\"status\":\"Review\",\"content\":{\"type\":\"Issue\",\"number\":536}},
      {\"id\":\"I537\",\"status\":\"Done\",\"content\":{\"type\":\"Issue\",\"number\":537}},
      {\"id\":\"I538\",\"status\":\"Blocked\",\"content\":{\"type\":\"Issue\",\"number\":538}}]}"
    log() { echo "log: $*" >> "$D/calls"; }
    gh_checkpoint() { :; }
    set_card_status() { echo "move: $1 -> $2 (blocking=${SB_CARD_BLOCKING:-})" >> "$D/calls"; [ "$BOARD_FAIL" = 1 ] && return 1; return 0; }
    gh_write_once() { echo "write: $*" >> "$D/calls"; return 0; }
    issue_locked() { return 1; }
    if sweep_closed_cards; then echo rc=0; else echo rc=1; fi >> "$D/calls"' _ "$RUNNER" "$T/read.py" "$T" >/dev/null 2>&1
}

run '[{"number":535,"stateReason":"COMPLETED"},{"number":537,"stateReason":"COMPLETED"},{"number":538,"stateReason":"NOT_PLANNED"}]'
grep -q 'move: I535 -> Done' "$T/calls" 2>/dev/null && grep -q 'write: issue comment 535' "$T/calls" \
  && ok "Blocked + CLOSED completed: sang Done kèm comment report; rc=0 (board cần đọc lại)" || fail "completed: $(tr '\n' '|' < "$T/calls" 2>/dev/null)"
grep -q 'rc=0' "$T/calls" || fail "đã chuyển thẻ mà không trả 0"
grep -q 'I537' "$T/calls" && fail "thẻ đã ở Done bị đụng tới" || ok "thẻ đã ở Done: không đụng"
grep -q 'I538' "$T/calls" && fail "NOT_PLANNED bị chuyển cột" || ok "đóng not_planned: giữ cột (không move, không comment)"
grep -q 'log:.*#538.*not planned' "$T/calls" && ok "not_planned có log" || fail "not_planned không có log"

run '[{"number":535,"stateReason":"COMPLETED"}]' 1
grep -q 'blocking=1' "$T/calls" && ! grep -q 'write: issue comment' "$T/calls" && ! grep -q 'rc=0' "$T/calls" \
  && ok "ghi board hỏng: không chặn thẻ/halt (SB_CARD_BLOCKING), không comment, rc≠0 → tick sau thử lại" || fail "write fail: $(tr '\n' '|' < "$T/calls" 2>/dev/null)"

run '[]'
! grep -q 'move:' "$T/calls" && ok "không issue đóng: không ghi gì" || fail "empty: $(tr '\n' '|' < "$T/calls")"

[ "$FAILS" -eq 0 ] && { echo "sweep closed cards: all checks passed"; exit 0; }
echo "sweep closed cards: $FAILS FAILED"; exit 1
