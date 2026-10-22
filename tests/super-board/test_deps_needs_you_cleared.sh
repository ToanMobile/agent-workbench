#!/usr/bin/env bash
# Test hồi quy #112: thẻ Block `blocked-by: -` rồi người xong việc (super-board-needs-you.py unmark ghi ✅) và kéo về Ready
# thì super-board-deps.sh vẫn đọc dòng `blocked-by: -` cũ → humanGated=true, runnable=false, wave-plan bỏ qua thẻ mãi.
# Sửa: comment ✅ (DONE_MARKER) MỚI hơn comment Block và không còn nhãn needs-you thì dòng `-` cũ không còn khoá thẻ.
# Còn nhãn needs-you, hoặc ✅ cũ hơn Block mới thì vẫn humanGated. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPS="$ROOT/.claude/bin/super-board-deps.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

BLOCK='🙋 Reason tag: needs you\nblocked-by: -'
DONE='<!-- super-board:needs-you:done -->\n✅ Đã xong phần cần người: chạy playtest'
BODY='## Blocked by\n- None.\n'

# $1 labels json array, $2 comment bodies (json array of strings); in ra "<humanGated>|<runnable>"
run() {
  printf '[{"number":9,"title":"t","state":"OPEN","body":"%s","labels":{"nodes":%s},"comments":{"nodes":%s}}]' \
    "$BODY" "$1" "$2" > "$TMP/p.json"
  "$DEPS" --repo o/r --from "$TMP/p.json" 2>&1 | jq -r '.["9"] | "\(.humanGated)|\(.runnable)"' 2>&1 | tail -1
}
C() { printf '[%s]' "$1"; }

R="$(run '[]' "$(C "{\"body\":\"$BLOCK\"},{\"body\":\"$DONE\"}")")"
[ "$R" = "false|true" ] && ok "Block rồi ✅ unmark mới hơn, không nhãn: runnable" || fail "thẻ người đã xong vẫn bị khoá: $R"

R="$(run '[{"name":"needs-you"}]' "$(C "{\"body\":\"$BLOCK\"},{\"body\":\"$DONE\"}")")"
[ "$R" = "true|false" ] && ok "còn nhãn needs-you: vẫn humanGated" || fail "nhãn needs-you còn mà thẻ được thả: $R"

R="$(run '[]' "$(C "{\"body\":\"$DONE\"},{\"body\":\"$BLOCK\"}")")"
[ "$R" = "true|false" ] && ok "✅ cũ hơn Block mới: vẫn humanGated" || fail "Block mới bị ✅ cũ bỏ qua: $R"

R="$(run '[]' "$(C "{\"body\":\"$BLOCK\"}")")"
[ "$R" = "true|false" ] && ok "Block không có ✅: vẫn humanGated" || fail "Block thường bị thả: $R"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
