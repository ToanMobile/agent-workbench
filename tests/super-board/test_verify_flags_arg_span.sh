#!/usr/bin/env bash
# #802: sb_verify_inject_flags (.claude/bin/super-board-verify-flags.sh) so token --full/--force-full/--scoped (và --diff, --json) với CẢ
# chuỗi lệnh verify. Lệnh ghép `post-fix-gate.py --run-tests && npm run e2e -- --full` có --full của lệnh KHÁC, nên --scoped không được
# chèn: post-fix-gate chạy chế độ impacted, không ghi scoped_pass.json, merge gate và QA chọn tập suite khác nhau cho cùng cây (#251).
# Luật: chỉ xét token trong phần đối số của post-fix-gate.py, từ sau token tới dấu hết lệnh (; & | ) } backtick, xuống dòng); chuyển
# hướng (< > >& <& &> >|) không kết thúc lệnh.
# Gọi thẳng hàm (gate, QA và train cùng gọi nó). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/.claude/bin/super-board-verify-flags.sh"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/sb-vf-span.XXXXXX")"; TMPE="$TMPD/err"
trap 'rm -rf "$TMPD"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

G=".agents/devkit/bin/post-fix-gate.py"
FL="--diff origin/main --scoped"
want() {  # want <lệnh> <lệnh mong đợi> [json]
  local got
  got=$(sb_verify_inject_flags "$1" main ${3:-} 2>/dev/null)
  if [ "$got" = "$2" ]; then ok "$1"; else fail "for: $1 want [$2] got [$got]"; fi
}

# Token của lệnh KHÁC không chặn cờ của post-fix-gate (AC 1 của #802)
want "python3 $G --run-tests && npm run e2e -- --full" "python3 $G $FL --run-tests && npm run e2e -- --full"
want "python3 $G --run-tests; other --force-full" "python3 $G $FL --run-tests; other --force-full"
want "python3 $G --run-tests | tee log --scoped" "python3 $G $FL --run-tests | tee log --scoped"
want "bash -c 'python3 $G --run-tests' && other --full" "bash -c 'python3 $G $FL --run-tests' && other --full"
# Cùng lớp lỗi với --diff / --json: `--diff-filter` hay `--json` của lệnh khác không chặn cờ của gate
want "python3 $G --run-tests && git diff --diff-filter=M" "python3 $G $FL --run-tests && git diff --diff-filter=M"
want "python3 $G --run-tests && gh pr view --json x" "python3 $G $FL --json --run-tests && gh pr view --json x" json

# Lệnh có --full / --force-full / --scoped của CHÍNH post-fix-gate: giữ ý đó, không chèn --scoped (AC 2 của #802)
want "python3 $G --run-tests --full" "python3 $G --run-tests --full --diff origin/main"
want "python3 $G --run-tests --force-full" "python3 $G --run-tests --force-full --diff origin/main"
want "python3 $G --run-tests --full && npm test" "python3 $G --diff origin/main --run-tests --full && npm test"
want "bash -c 'python3 $G --run-tests --full'" "bash -c 'python3 $G --diff origin/main --run-tests --full'"
want "python3 $G --diff origin/x --scoped --run-tests && other --full" "python3 $G --diff origin/x --scoped --run-tests && other --full"
# Chuyển hướng (`2>/dev/null`, `2>&1`) không kết thúc lệnh: cờ của gate đứng sau nó vẫn là của gate (OCR)
want "python3 $G 2>/dev/null --full" "python3 $G --diff origin/main 2>/dev/null --full"
want "python3 $G --run-tests 2>&1 --full | tee log" "python3 $G --diff origin/main --run-tests 2>&1 --full | tee log"
want "python3 $G --run-tests &>log --full" "python3 $G --diff origin/main --run-tests &>log --full"
want "python3 $G --run-tests >|log --full" "python3 $G --diff origin/main --run-tests >|log --full"
want "python3 $G --run-tests --full>log" "python3 $G --diff origin/main --run-tests --full>log"
# Xuống dòng / backtick kết thúc lệnh của gate: cờ chèn ngay sau token, không nối vào lệnh sau (OCR, cùng luật #102)
NL='
'
want "python3 $G --run-tests${NL}npm test" "python3 $G $FL --run-tests${NL}npm test"
want "echo \`python3 $G --run-tests\` done" "echo \`python3 $G $FL --run-tests\` done"
# Lệnh một lệnh như cũ: cờ ở cuối; --json chỉ khi được hỏi
want "python3 $G --run-tests" "python3 $G --run-tests $FL"
want "python3 $G --run-tests" "python3 $G --run-tests $FL --json" json
want "python3 $G --run-tests --json" "python3 $G --run-tests --json $FL" json
# --full-name không phải token --full (giữ luật so token nguyên)
want "python3 $G --run-tests --full-name x" "python3 $G --run-tests --full-name x $FL"
# Không có post-fix-gate.py: in nguyên
want "npm test -- --full" "npm test -- --full"

# Không tách được token mà lệnh đã đủ cờ: không cảnh báo (như trước #802); thiếu cờ thì cảnh báo.
sb_verify_inject_flags "echo post-fix-gate.pyx --diff x --full" main >/dev/null 2>"$TMPE"; [ -s "$TMPE" ] && fail "warning printed for a command with nothing to add: $(cat "$TMPE")" || ok "no warning when nothing would be added"
sb_verify_inject_flags "echo post-fix-gate.pyx && true" main >/dev/null 2>"$TMPE"; grep -q "cannot locate" "$TMPE" && ok "warning kept when flags would be needed" || fail "warning lost"

# sb_redact_text (dùng chung gate/train): token bị che; không nạp được bộ che ⇒ exit khác 0 và KHÔNG in gì (đóng an toàn).
TOK="gh""p_$(printf 'Z%.0s' $(seq 1 30))"
out=$(printf 'auth %s\n' "$TOK" | sb_redact_text); rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] && ! printf '%s' "$out" | grep -q "$TOK" && ok "sb_redact_text redacts a token" || fail "sb_redact_text: rc=$rc out=[$out]"
# Byte không phải UTF-8 (log nhị phân, mã màu hỏng): vẫn che và in được, không rơi vào đường giấu cả đoạn (audit Antigravity).
out=$(printf 'bin \377\376 auth %s\n' "$TOK" | sb_redact_text); rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] && ! printf '%s' "$out" | grep -q "$TOK" && ok "sb_redact_text handles non-UTF-8 bytes" || fail "sb_redact_text non-UTF-8: rc=$rc out=[$out]"
mkdir -p "$TMPD/bin"; cp "$ROOT/.claude/bin/super-board-verify-flags.sh" "$TMPD/bin/"
out=$(printf 'auth %s\n' "$TOK" | HERE=/nonexistent DEVKIT_ROOT=/nonexistent bash -c '. "$1"; sb_redact_text' _ "$TMPD/bin/super-board-verify-flags.sh"); rc=$?
[ "$rc" -ne 0 ] && [ -z "$out" ] && ok "sb_redact_text without a kit: non-zero, prints nothing (fail closed)" || fail "sb_redact_text fail-closed: rc=$rc out=[$out]"

echo
[ "$FAILS" -eq 0 ] && { echo "test_verify_flags_arg_span: PASS"; exit 0; } || { echo "test_verify_flags_arg_span: FAIL ($FAILS)"; exit 1; }
