#!/usr/bin/env bash
# #807: `ocr-review --help` chạy một OCR review thật (gửi diff chưa commit tới LLM) thay vì in hướng dẫn; cờ lạ bị bỏ qua im lặng.
# `ocr` giả trên PATH ghi marker mỗi lần được gọi. Đòi: --help / -h in hướng dẫn, thoát 0, không gọi `ocr`; --bogus và đối số vị
# trí lạ thoát 64, không gọi `ocr`; lệnh kiểu caller thật (review_gate: --delegate-only --out DIR, lane: -b TEXT --from REF) vẫn tới
# `ocr`. Trên code chưa sửa: --help gọi `ocr` (marker có) ⇒ ĐỎ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DEVKIT_DIR/bin/ocr-review"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'x = 1\n' > a.py && git add -A && git commit -qm init
printf 'x = 2\n' > a.py

mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
echo "$*" >> "$OCR_MARKER"
echo '{"reviewable_files": [], "excluded_files": [], "groups": []}'
SH
chmod +x "$TMP/bin/ocr"

run() {   # run <args…>: rc in $rc, marker reset before
  rm -f "$TMP/marker"
  PATH="$TMP/bin:$PATH" OCR_MARKER="$TMP/marker" python3 "$HELPER" "$@" > "$TMP/out" 2> "$TMP/err"; rc=$?
}

for h in --help -h; do
  run "$h"
  [ "$rc" = 0 ] && ok "$h exits 0" || fail "$h exit $rc (want 0)"
  grep -q -- '--delegate-only' "$TMP/out" && ok "$h prints the usage" || fail "$h printed no usage: $(head -c 200 "$TMP/out")"
  [ ! -e "$TMP/marker" ] && ok "$h never calls ocr" || fail "$h called ocr: $(cat "$TMP/marker")"
done

run --out "$TMP/o0" --help
[ "$rc" = 0 ] && [ ! -e "$TMP/marker" ] && ok "--help after other flags: usage, no ocr" || fail "--out X --help: rc $rc marker $(cat "$TMP/marker" 2>/dev/null)"

for bad in --bogus stray; do
  run "$bad"
  [ "$rc" = 64 ] && ok "$bad exits 64" || fail "$bad exit $rc (want 64)"
  grep -q -- "$bad" "$TMP/err" && ok "$bad named on stderr" || fail "$bad not named: $(head -c 200 "$TMP/err")"
  [ ! -e "$TMP/marker" ] && ok "$bad never calls ocr" || fail "$bad called ocr: $(cat "$TMP/marker")"
done

# callers' flags still accepted and still reach ocr
run --delegate-only --out "$TMP/o1"
[ "$rc" = 0 ] && grep -q 'delegate preview' "$TMP/marker" 2>/dev/null && ok "review_gate style (--delegate-only --out) reaches ocr" \
  || fail "--delegate-only --out: rc $rc marker $(cat "$TMP/marker" 2>/dev/null) err $(head -c 200 "$TMP/err")"
run -b "focus" --from HEAD --to HEAD --delegate-only --out "$TMP/o2"
[ "$rc" = 0 ] && grep -q 'delegate preview' "$TMP/marker" 2>/dev/null && ok "lane style (-b --from --to) reaches ocr" \
  || fail "-b --from --to: rc $rc marker $(cat "$TMP/marker" 2>/dev/null) err $(head -c 200 "$TMP/err")"
run -b "--help" --background x -c HEAD --commit HEAD --delegate-only --out "$TMP/o3"
[ "$rc" = 0 ] && grep -q 'delegate preview' "$TMP/marker" 2>/dev/null && ok "an option VALUE that looks like --help is a value, not a flag" \
  || fail "-b --help: rc $rc marker $(cat "$TMP/marker" 2>/dev/null)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
