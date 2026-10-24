#!/usr/bin/env bash
# T0054 (24/10): issue ĐÃ ĐÓNG mà thẻ còn nhãn ac-open (merge gate gắn khi PR đã merge nhưng còn AC chưa chứng minh) không được
# runner reconcile sang Done — mọi đường CLOSED → Done (top_card_in_column, reclaim Building, kéo Backlog) đi qua
# issue_is_open, nên nó mở lại issue và trả OPEN. Nhãn đọc từ snapshot board (PROJECT_ITEMS_JSON): issue đóng không nhãn không
# tốn lần đọc nào. Đóng NOT_PLANNED (người bỏ có chủ đích): để yên. Mở lại thất bại: vẫn OPEN (ngoài Done), có log.
# Chạy issue_is_open THẬT (SB_LIB_ONLY=1), gh và github-read giả. SB_RUNNER=<file> chạy bản cũ để thấy ĐỎ. Offline.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/sb-reconcile-acopen.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
printf '#!/bin/sh\necho CLOSED\n' > "$T/read.py"   # github-read giả: issue luôn CLOSED
cat > "$T/bin/gh" <<SH
#!/bin/sh
echo "gh \$*" >> "$T/calls"
case "\$*" in *stateReason*) echo "\$REASON" ;; esac
SH
chmod +x "$T/bin/gh"

run() {  # $1 = nhãn của thẻ 7 trên snapshot (JSON list), $2 = stateReason, $3 = 1 → reopen thất bại; in "rc=<n>"
  rm -f "$T/calls"
  REASON="$2" REOPEN_FAIL="${3:-0}" PATH="$T/bin:$PATH" SB_LIB_ONLY=1 bash -c '
    R="$1" READ="$2" D="$3" L="$4"; set --
    . "$R" >/dev/null 2>&1
    SB_GITHUB_READ="$READ"; python3() { sh "$@"; }
    PROJECT_ITEMS_JSON="{\"items\":[{\"content\":{\"number\":7},\"labels\":$L},{\"content\":{\"number\":8},\"labels\":[\"ac-open\"]}]}"
    log() { echo "log: $*" >> "$D/calls"; }
    gh_write_once() { echo "write: $*" >> "$D/calls"; [ "$REOPEN_FAIL" = 1 ] && return 1; return 0; }
    if issue_is_open 7; then echo "rc=0"; else echo "rc=$?"; fi' _ "$RUNNER" "$T/read.py" "$T" "$1"
}

out=$(run '["bug","AC-Open"]' COMPLETED)
[ "$out" = "rc=0" ] && grep -q 'write: issue reopen 7' "$T/calls" \
  && ok "CLOSED + nhãn ac-open (không phân biệt hoa thường): mở lại issue, trả OPEN" || fail "ac-open: $out; $(tr '\n' '|' < "$T/calls" 2>/dev/null)"
out=$(run '["bug"]' COMPLETED)
[ "$out" = "rc=1" ] && ! grep -q 'gh ' "$T/calls" 2>/dev/null && ! grep -q reopen "$T/calls" 2>/dev/null \
  && ok "CLOSED không nhãn: CLOSED như cũ, không thêm lần gọi gh nào" || fail "plain closed: $out; $(tr '\n' '|' < "$T/calls" 2>/dev/null)"
out=$(run '["ac-open"]' NOT_PLANNED)
[ "$out" = "rc=1" ] && ! grep -q reopen "$T/calls" && ok "ac-open nhưng đóng NOT_PLANNED (người bỏ): để yên, CLOSED" || fail "not planned: $out"
out=$(run '[{"name":"ac-open"}]' COMPLETED 1)
[ "$out" = "rc=0" ] && grep -q 'could not be reopened' "$T/calls" \
  && ok "mở lại thất bại: vẫn OPEN (không vào Done), có log; nhãn dạng {name}" || fail "reopen fail: $out; $(tr '\n' '|' < "$T/calls")"

[ "$FAILS" -eq 0 ] && { echo "reconcile ac-open: all checks passed"; exit 0; }
echo "reconcile ac-open: $FAILS FAILED"; exit 1
