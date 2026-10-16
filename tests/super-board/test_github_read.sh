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
  *" pr view 1 2 3 "*) echo 'accepts between 1 and 2 arg(s), received 3' >&2; exit 1 ;;
  *" pr view 1 2 "*) echo 'accepts at most 1 arg(s), received 2' >&2; exit 1 ;;
  *" --bogus "*) echo 'unknown flag: --bogus' >&2; exit 1 ;;
  *" issue view "*) echo '{"number":5,"title":"t","body":"b"}' ;;
  *" api rate_limit --jq "*) echo 'graphql=4979/5000 rest=4999/5000' ;;
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

# Lệnh có khoảng số đối số (cobra RangeArgs) báo "accepts between N and M arg(s)": cũng là lỗi của người gọi.
rc=$(run --kind head -- pr view 1 2 3)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "wrong arg count ('accepts between 1 and 2 arg(s)'): exit 64, board not halted" \
  || fail "'accepts between 1 and 2 arg(s)': rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# Kind không có dạng mẫu trong FORMS (vd scalar): lỗi cú pháp vẫn là của người gọi, exit 64 không halt,
# không traceback, và không bịa gợi ý "Valid form" cho kind không có mẫu.
rc=$(run --kind scalar -- pr view 9 --bogus)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ! grep -q Traceback "$TMP/err" && ! grep -q 'Valid form' "$TMP/err" \
  && ok "caller flag error on a kind outside FORMS: exit 64, not halted, no traceback, no invented form" \
  || fail "flag error on kind scalar: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# Script có lệnh cố định (merge gate) đặt SB_GITHUB_READ_STRICT=1: lỗi cú pháp ở đó là lỗi của script, vẫn halt.
rc=$(SB_GITHUB_READ_STRICT=1 run --kind scalar -- pr view 9 --bogus)
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "SB_GITHUB_READ_STRICT=1: a flag error still halts (fixed commands)" \
  || fail "SB_GITHUB_READ_STRICT=1 flag error: rc=$rc (want 79 + halt file)"
rm -f "$TMP/halt.json"

# Script do chính board chạy với lệnh cố định (super-board-deps.sh trong chuỗi sweep Blocked của runner): gh đổi flag
# (vd máy có gh chưa có --slurp) vẫn halt board kèm lý do, không thành exit 64 "lỗi của người gọi" lặp mỗi 300 s.
mkdir -p "$TMP/oldgh"
printf '#!/usr/bin/env bash\necho "unknown flag: --slurp" >&2\nexit 1\n' > "$TMP/oldgh/gh"; chmod +x "$TMP/oldgh/gh"
PATH="$TMP/oldgh:$PATH" bash "$ROOT/.claude/bin/super-board-deps.sh" --repo o/r >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "fixed-command board script (deps.sh) with a broken gh flag: board halted (79 + reason)" \
  || fail "deps.sh with a broken gh flag: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# 2026-10-16 20:45 OfficeReader: một worker đọc quota bằng `--kind quota -- api rate_limit --jq "graphql=…"` (in chuỗi, không
# phải JSON). Payload sai dạng ở cả 3 lần thử là lỗi đọc của người gọi với MỌI kind, không chỉ kind trong FORMS: exit 64,
# không halt cả board, không bịa gợi ý "Valid form" cho kind không có mẫu.
rc=$(run --kind quota -- api rate_limit --jq '"graphql=\(.resources.graphql.remaining)"')
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ! grep -q 'Valid form' "$TMP/err" \
  && ok "malformed read on a kind outside FORMS (quota + --jq string): exit 64, board not halted" \
  || fail "quota read with --jq string: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"
# Lệnh cố định của runner (STRICT) mà nhận payload sai dạng thì vẫn halt: có thể là GitHub trả thiếu dữ liệu thật.
rc=$(SB_GITHUB_READ_STRICT=1 run --kind quota -- api rate_limit --jq '"graphql=\(.resources.graphql.remaining)"')
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "SB_GITHUB_READ_STRICT=1: a malformed payload still halts (fixed commands)" \
  || fail "SB_GITHUB_READ_STRICT=1 malformed payload: rc=$rc (want 79 + halt file)"
rm -f "$TMP/halt.json"

# deps.sh chuyển graph sang super-board-approval.py, script này đọc GitHub qua module github-read (kind comments/approval/
# permission) cũng bằng lệnh cố định: STRICT phải tới được nó, nếu không sự cố GitHub thật bị nuốt thành "approval evidence
# could not be verified" (audit T0041). Bản sao deps.sh với github-read/approval giả ghi lại STRICT mà approval nhận.
mkdir -p "$TMP/sbbin"
cp "$ROOT/.claude/bin/super-board-deps.sh" "$TMP/sbbin/"
cat > "$TMP/sbbin/super-board-github-read.py" <<'PYF'
import json
print(json.dumps([{"data": {"repository": {"issues": {"nodes": [
    {"number": 1, "title": "t", "body": "", "state": "OPEN", "labels": {"nodes": []}, "comments": {"nodes": []}}]}}}}]))
PYF
cat > "$TMP/sbbin/super-board-approval.py" <<'PYF'
import os, sys
open(os.environ["SB_TEST_STRICT_OUT"], "w").write(os.environ.get("SB_GITHUB_READ_STRICT", "unset"))
sys.stdout.write(sys.stdin.read())
PYF
SB_TEST_STRICT_OUT="$TMP/strict.out" bash "$TMP/sbbin/super-board-deps.sh" --repo o/r >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$TMP/strict.out" 2>/dev/null)" = 1 ] \
  && ok "deps.sh: approval reads (fixed commands) run with SB_GITHUB_READ_STRICT=1" \
  || fail "deps.sh: approval.py got SB_GITHUB_READ_STRICT=$(cat "$TMP/strict.out" 2>/dev/null) rc=$rc ($(tail -1 "$TMP/err"))"

rc=$(run --kind issue -- issue view 5 --json number,title,body --comments)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "--comments with --json: reported (exit 64), not silently dropped, not halted" \
  || fail "--comments with --json: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) out=$(head -c 80 "$TMP/out")"
rm -f "$TMP/halt.json"

rc=$(run --kind issue -- issue view 5 --json number,title,body)
[ "$rc" = 0 ] && grep -q '"number"' "$TMP/out" && ok "valid read still works" || fail "valid read: rc=$rc"

[ "$FAILS" -eq 0 ] && echo "✅ test_github_read: all passed" || { echo "❌ test_github_read: $FAILS failed"; exit 1; }
