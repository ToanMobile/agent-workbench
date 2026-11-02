#!/usr/bin/env bash
# Test hồi quy (#696): cây gate-full chạy chậm 4,9–7,3× so với lượt full thường. Code cũ đặt mức nice hai chỗ và thêm giới hạn launchd:
# plist có `/usr/bin/nice -n 10` kèm `ProcessType=Background`, còn gate_full.py tự `os.nice` lên 10 khi đang dưới 10.
# Nay mức nice chỉ đặt MỘT chỗ, ở plist (`/usr/bin/nice -n 10`); plist không có ProcessType; gate_full.py không gọi os.nice.
#   a. plist do `gate-full-schedule.sh install` ghi ra: không có khoá ProcessType (vắng hẳn), vẫn bắt đầu bằng /usr/bin/nice -n 10;
#   b. bin/gate_full.py không có lời gọi os.nice (kiểm trên AST: comment, docstring không tính);
#   c. install không ghi gì vào thư mục log thật: HOME giả trống, log về DEVKIT_GATE_FULL_LOG_DIR trong thư mục tạm.
# launchctl giả và thư mục LaunchAgents tạm: không chạm launchd hay ~/Library. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
SCHED="$DEVKIT_DIR/bin/gate-full-schedule.sh"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-nice-once.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
for f in "$GF" "$SCHED"; do [ -f "$f" ] || { echo "✖ thiếu ${f#$DEVKIT_DIR/}"; exit 1; }; done

# a. plist — bản sao kit ngoài git (kit nằm trong linked worktree thì install lấy gate_full.py của main checkout)
mkdir -p "$T/kit/bin" "$T/la" "$T/repo" "$T/home" && cp "$SCHED" "$GF" "$T/kit/bin/"
git init -q "$T/repo"
printf '#!/bin/sh\nexit 0\n' >"$T/fakelaunchctl"; chmod +x "$T/fakelaunchctl"
export DEVKIT_LAUNCH_AGENTS_DIR="$T/la" DEVKIT_LAUNCHCTL="$T/fakelaunchctl" DEVKIT_GATE_FULL_LOG_DIR="$T/logs"
HOME="$T/home" bash "$T/kit/bin/gate-full-schedule.sh" install --repo "$T/repo" >"$T/sched.out" 2>&1; rc=$?
PL="$(ls "$T/la"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null | head -1)"; PL="${PL:-$T/la/none.plist}"
px() { plutil -extract "$1" raw -o - "$PL" 2>/dev/null; }
chk "a0. install exit 0 và có đúng một plist" '[ "$rc" = 0 ] && [ -f "$PL" ]' "rc=$rc $(tail -3 "$T/sched.out")"
chk "a1. plist không có khoá ProcessType" '[ -f "$PL" ] && ! plutil -extract ProcessType raw -o - "$PL" >/dev/null 2>&1' "ProcessType=$(px ProcessType)"
chk "a2. plist vẫn bắt đầu bằng /usr/bin/nice -n 10" \
  '[ "$(px ProgramArguments.0)" = /usr/bin/nice ] && [ "$(px ProgramArguments.1)" = -n ] && [ "$(px ProgramArguments.2)" = 10 ]'

# b. gate_full.py không gọi os.nice (AST nên comment và docstring không khớp)
python3 -I - "$GF" <<'PY' >"$T/nice.out" 2>&1; brc=$?
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
hits = [n.lineno for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Attribute) and n.func.attr == "nice") or (isinstance(n.func, ast.Name) and n.func.id == "nice"))]
print("lời gọi os.nice ở dòng: %s" % hits)
sys.exit(1 if hits else 0)
PY
chk "b1. bin/gate_full.py không có lời gọi os.nice" '[ "$brc" = 0 ]' "$(cat "$T/nice.out")"

# c. install không rò log ra thư mục thật: HOME giả vẫn trống, log nằm trong $T/logs
chk "c1. install không tạo gì dưới HOME giả (không có ~/Library/Logs)" '[ -z "$(ls -A "$T/home")" ]' "$(ls -A "$T/home")"
chk "c2. thư mục log của repo nằm trong DEVKIT_GATE_FULL_LOG_DIR" '[ "$(ls "$T/logs" 2>/dev/null | wc -l | tr -d " ")" = 1 ]' "$(ls "$T/logs" 2>&1)"

[ "$fails" = 0 ] && { echo "OK"; exit 0; }
echo "FAIL: $fails"
exit 1
