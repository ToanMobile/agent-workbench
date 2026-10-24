#!/usr/bin/env bash
# T0054 (24/10): issue ĐÃ ĐÓNG mà còn nhãn ac-open (merge gate gắn khi PR đã merge nhưng còn AC chưa chứng minh) không được
# runner reconcile sang Done — mọi đường CLOSED → Done (top_card_in_column, reclaim Building, kéo Backlog) đi qua
# issue_is_open, nên nó mở lại issue và trả OPEN. Không nhãn: CLOSED như cũ. Đọc nhãn hỏng: CLOSED như cũ, có log.
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
case "\$*" in *"--json labels"*) [ "\$LABELS" = FAIL ] && exit 1; echo "\$LABELS" ;; esac
SH
chmod +x "$T/bin/gh"

run() {  # $1 = nhãn (chuỗi phẩy) hoặc FAIL; in "rc=<n>"
  rm -f "$T/calls"
  LABELS="$1" PATH="$T/bin:$PATH" SB_LIB_ONLY=1 bash -c '
    R="$1" READ="$2" D="$3"; set --
    . "$R" >/dev/null 2>&1
    SB_GITHUB_READ="$READ"; python3() { sh "$@"; }
    log() { echo "log: $*" >> "$D/calls"; }
    gh_write_once() { echo "write: $*" >> "$D/calls"; }
    if issue_is_open 7; then echo "rc=0"; else echo "rc=$?"; fi' _ "$RUNNER" "$T/read.py" "$T"
}

out=$(run "bug,AC-Open")
[ "$out" = "rc=0" ] && grep -q 'write: issue reopen 7' "$T/calls" \
  && ok "CLOSED + nhãn ac-open (không phân biệt hoa thường): mở lại issue, trả OPEN" || fail "ac-open: $out; $(tr '\n' '|' < "$T/calls")"
out=$(run "bug")
[ "$out" = "rc=1" ] && ! grep -q reopen "$T/calls" && ok "CLOSED không nhãn ac-open: vẫn CLOSED (reconcile Done như cũ)" || fail "plain closed: $out"
out=$(run FAIL)
[ "$out" = "rc=1" ] && grep -q 'could not read labels' "$T/calls" && ok "đọc nhãn hỏng: CLOSED như cũ, có log" || fail "label read fail: $out"

[ "$FAILS" -eq 0 ] && { echo "reconcile ac-open: all checks passed"; exit 0; }
echo "reconcile ac-open: $FAILS FAILED"; exit 1
