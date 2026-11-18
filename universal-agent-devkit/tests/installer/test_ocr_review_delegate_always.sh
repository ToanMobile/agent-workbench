#!/usr/bin/env bash
# #1332: LLM của OCR bị gỡ hẳn — bin/ocr-review luôn chạy delegation (`ocr delegate preview` + `ocr delegate rule`), không bao giờ
# gọi `ocr review`, kể cả khi `ocr review` giả có endpoint chạy được. Output: `mode: delegate` + `spec: <file>`.
# `--delegate-only` vẫn nhận (no-op) cho người gọi cũ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DEVKIT_DIR/bin/ocr-review"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def f(x):\n    return x\n' > a.py && git add -A && git commit -qm init
printf 'def f(x):\n    return 1 / x\n' > a.py

# ocr giả: ghi mọi lệnh vào log; `ocr review` "có endpoint" và viết report (luật cũ sẽ chọn đường này)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
echo "$*" >> "$OCR_ARGS_LOG"
case "$1 $2" in
  "review "*)
    out=""; prev=""
    for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
    [ -n "$out" ] && printf '{"comments":[]}\n' > "$out"; exit 0 ;;
  "delegate preview")
    printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"a.py","status":"modified","insertions":1,"deletions":1}],"excluded_files":[]}\n'; exit 0 ;;
  "delegate rule")
    printf '{"schema_version":"1","groups":[{"group_id":1,"files":["a.py"],"rule":"ZeroDivisionError"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"

for args in "" "--from HEAD" "--delegate-only"; do
  : > "$TMP/log"
  # shellcheck disable=SC2086
  PATH="$TMP/bin:$PATH" OCR_ARGS_LOG="$TMP/log" python3 "$HELPER" $args --out "$TMP/o" > "$TMP/out" 2> "$TMP/err"; rc=$?
  spec="$(sed -n 's/^spec: //p' "$TMP/out")"
  if grep -q '^review' "$TMP/log"; then
    fail "[$args] ocr-review gọi \`ocr review\` (LLM): $(tr '\n' ';' < "$TMP/log")"
  else
    ok "[$args] không gọi \`ocr review\`"
  fi
  [ "$rc" = 0 ] && grep -q '^mode: delegate' "$TMP/out" && [ -f "$spec" ] && grep -q 'a.py' "$spec" \
    && ok "[$args] mode: delegate + spec có file (rc 0)" || fail "[$args] rc=$rc out=$(tr '\n' ' ' < "$TMP/out") err=$(head -2 "$TMP/err")"
  ! grep -q 'LLM' "$TMP/out" && ok "[$args] output không nhắc LLM endpoint" || fail "[$args] output còn nhắc LLM: $(cat "$TMP/out")"
done

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
