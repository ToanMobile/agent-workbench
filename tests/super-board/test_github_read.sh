#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-github-read.py với `gh` giả (offline).
# 2026-10-16: lệnh đọc gõ sai của một worker (sai số đối số, `--comments` đi cùng `--json`) bị thử lại 3 lần rồi
# ghi file halt (exit 79): cả board dừng vì lỗi của một lệnh. Lỗi cú pháp của người gọi phải trả exit 64 kèm
# dạng lệnh đúng, không halt, và không được âm thầm sửa lệnh (bỏ `--comments` làm agent tưởng "không có comment").
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghread-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: thông báo lỗi đúng như gh 2.100.0 in ra (đo 2026-10-16).
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" --comments "*" --json "*|*" --json "*" --comments "*) echo 'specify only one of `--comments` or `--json`' >&2; exit 1 ;;
  *" pr view 1 2 "*) echo 'accepts at most 1 arg(s), received 2' >&2; exit 1 ;;
  *" issue view "*) echo '{"number":5,"title":"t","body":"b"}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
unset SB_GITHUB_READ_STRICT

run() { python3 "$READ" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }

rc=$(run --kind head -- pr view 1 2)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "wrong arg count ('accepts at most 1 arg'): exit 64, board not halted" \
  || fail "wrong arg count: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

rc=$(run --kind issue -- issue view 5 --json number,title,body --comments)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "--comments with --json: reported (exit 64), not silently dropped, not halted" \
  || fail "--comments with --json: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) out=$(head -c 80 "$TMP/out")"
rm -f "$TMP/halt.json"

rc=$(run --kind issue -- issue view 5 --json number,title,body)
[ "$rc" = 0 ] && grep -q '"number"' "$TMP/out" && ok "valid read still works" || fail "valid read: rc=$rc"

[ "$FAILS" -eq 0 ] && echo "✅ test_github_read: all passed" || { echo "❌ test_github_read: $FAILS failed"; exit 1; }
