#!/usr/bin/env bash
# T0054 (24/10): `super-board-card.sh move N Done` từ chối (exit 5) khi issue còn nhãn ac-open — thẻ đã merge mà AC chưa chứng
# minh không được vào Done (reviewer từng đóng #315 khi AC cache chưa ai làm). Không nhãn: move đi tiếp như cũ; sang cột khác
# không đọc nhãn. `gh` giả ghi lại từng lệnh. SB_CARD=<file> chạy với bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CARD="${SB_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-card-acopen.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"

# Cache có sẵn ids + item id: move chỉ còn 1 mutation; gh giả trả nhãn theo LABELS, ghi mọi lệnh vào calls.
printf '{"projectId":"P","fieldId":"F","options":{"Done":"o-done","Ready":"o-ready"},"items":{"7":"I7"}}' > "$TMP/cache/board-o-1.json"
cat > "$TMP/bin/gh" <<SH
#!/bin/sh
echo "\$*" >> "$TMP/calls"
case "\$*" in
  *"issue view"*) printf '{"labels":[%s]}' "\$LABELS" ;;
  *mutation*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I7"}}}}' ;;
  *) echo '{"data":{}}' ;;
esac
SH
chmod +x "$TMP/bin/gh"
run() { rm -f "$TMP/calls"; LABELS="$1" PATH="$TMP/bin:$PATH" SB_CARD_CACHE_DIR="$TMP/cache" SB_GITHUB_RETRY_DELAY=0 \
  SB_GITHUB_HALT_FILE="$TMP/github-halt.json" bash "$CARD" --owner o --number 1 --repo o/r move 7 "$2" >"$TMP/out" 2>"$TMP/err"; }

run '{"name":"bug"},{"name":"ac-open"}' Done; rc=$?
[ "$rc" -eq 5 ] && ! grep -q mutation "$TMP/calls" && grep -q 'ac-open' "$TMP/err" \
  && ok "nhãn ac-open: move Done exit 5, không mutation" || fail "ac-open: exit $rc; calls: $(tr '\n' '|' < "$TMP/calls" 2>/dev/null)"

run '{"name":"bug"}' Done; rc=$?
[ "$rc" -eq 0 ] && grep -q mutation "$TMP/calls" && ok "không nhãn ac-open: move Done như cũ" || fail "no label: exit $rc $(cat "$TMP/err")"

run '{"name":"ac-open"}' Ready; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'issue view' "$TMP/calls" && ok "move sang Ready không đọc nhãn, không bị chặn" || fail "Ready: exit $rc"

[ "$FAILS" -eq 0 ] && { echo "card done ac-open: all checks passed"; exit 0; }
echo "card done ac-open: $FAILS FAILED"; exit 1
