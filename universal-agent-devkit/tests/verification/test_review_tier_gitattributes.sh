#!/usr/bin/env bash
# #892 (tồn dư của #858): PR thêm `.gitattributes` với `-diff` làm numstat ra `-` (0 dòng) cho file bị che, nên PR 600 dòng tụt
# xuống bậc S. `git diff --text` không ghi đè thuộc tính trong cây PR (đã đo), nên .gitattributes là đường dẫn ép bậc L.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIER="$DEVKIT_DIR/bin/review_tier.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export GIT_CONFIG_GLOBAL=/dev/null
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/repo"; mkdir -p "$R/src"
G "$R" init -q -b main . || fail "setup: git init"
printf 'a\nb\n' > "$R/src/a.py"
G "$R" add -A && G "$R" commit -qm base || fail "setup: commit base"
G "$R" checkout -q -b pr || fail "setup: nhánh pr"
seq 1 600 | sed 's/^/n/' > "$R/src/big.py"; printf 'src/** -diff\n' > "$R/.gitattributes"
G "$R" add -A && G "$R" commit -qm "600 dòng + -diff" || fail "setup: commit pr"
got="$(cd "$R" && python3 "$TIER" --base main 2>"$TMP/err")"
case "$got" in "L product_lines=1 "*gitattributes*) ok "git: 600 dòng + .gitattributes -diff → L ($got)" ;;
  *) fail "git: 600 dòng + .gitattributes -diff: '$got' ($(head -c 300 "$TMP/err"))" ;; esac

# Mỗi cách viết đường dẫn (hoa/thường, thư mục con) đều ép L.
for p in .gitattributes sub/.GitAttributes; do
  printf '1\t0\t%s\n' "$p" > "$TMP/in.numstat"
  got="$(python3 "$TIER" --numstat "$TMP/in.numstat" 2>/dev/null | awk '{print $1}')"
  [ "$got" = L ] && ok "numstat $p → L" || fail "numstat $p: '$got'"
done

[ "$FAILS" = 0 ] && echo "✅ test_review_tier_gitattributes: PASS" || { echo "❌ test_review_tier_gitattributes: $FAILS failed"; exit 1; }
