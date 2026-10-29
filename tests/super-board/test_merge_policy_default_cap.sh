#!/usr/bin/env bash
# Mặc định auto_max_lines khi key vắng hoặc null là 0: diff 500 dòng không vào category size.
# Số dương vẫn là cổng opt-in. Script chỉ gọi super-board-merge-policy.py trên file JSON cục bộ.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.diff"
cat > "$TMP/big.json" <<'JSON'
{"labels":[],"body":"","files":[{"path":"src/app.ts","additions":500,"deletions":0}]}
JSON

verdict() { # $1 = config json
  python3 "$POLICY" --config "$1" --meta "$TMP/big.json" --diff "$TMP/empty.diff" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("size" if any(h.get("category")=="size" for h in d["human"]) else "ok")'
}

echo '{}' > "$TMP/unset.json"
[ "$(verdict "$TMP/unset.json")" = ok ] \
  && ok "unset auto_max_lines: 500 changed lines stay auto" \
  || fail "unset auto_max_lines still size-gates a 500-line diff"

echo '{"merge_policy":{"auto_max_lines":null}}' > "$TMP/null.json"
[ "$(verdict "$TMP/null.json")" = ok ] \
  && ok "null auto_max_lines: 500 changed lines stay auto" \
  || fail "null auto_max_lines still size-gates a 500-line diff"

echo '{"merge_policy":{"auto_max_lines":0}}' > "$TMP/zero.json"
[ "$(verdict "$TMP/zero.json")" = ok ] \
  && ok "explicit 0: 500 changed lines stay auto" \
  || fail "explicit 0 size-gated a 500-line diff"

echo '{"merge_policy":{"auto_max_lines":100}}' > "$TMP/cap.json"
[ "$(verdict "$TMP/cap.json")" = size ] \
  && ok "positive cap 100: 500 changed lines wait for a human" \
  || fail "positive cap 100 did not size-gate a 500-line diff"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL $FAILS"; exit 1; }
