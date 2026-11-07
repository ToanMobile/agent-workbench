#!/usr/bin/env bash
# v26 audit PR #1046: sb_verify_single_pfg_cmd (.claude/bin/super-board-verify-flags.sh) chỉ nhận ĐÚNG MỘT lệnh post-fix-gate.py.
# Từ chối thay thế lệnh (`$(` hay backtick: lệnh lồng chạy trước red_only_on_base / chạy lại guard), và token phải là post-fix-gate.py
# trần hoặc đường dẫn kết thúc bằng /post-fix-gate.py (không nhận xpost-fix-gate.py). Gọi thẳng hàm. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/.claude/bin/super-board-verify-flags.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
yes_() { if sb_verify_single_pfg_cmd "$1"; then ok "nhận: $1"; else fail "phải nhận: $1"; fi; }
no_()  { if sb_verify_single_pfg_cmd "$1"; then fail "phải từ chối: $1"; else ok "từ chối: $1"; fi; }

# Nhận: token trần, đường dẫn /post-fix-gate.py, VAR= và cờ python đứng trước
yes_ "post-fix-gate.py --run-tests"
yes_ "python3 post-fix-gate.py"
yes_ "python3 .agents/devkit/bin/post-fix-gate.py --diff origin/main --scoped"
yes_ "VAR=1 python3 -I a/post-fix-gate.py --run-tests"
yes_ "./post-fix-gate.py"

# Từ chối: thay thế lệnh ở đối số hay ở đường dẫn
no_ 'python3 post-fix-gate.py --diff $(git rev-parse HEAD)'
no_ 'python3 $(pwd)/post-fix-gate.py'
no_ 'python3 `pwd`/post-fix-gate.py'
no_ 'python3 post-fix-gate.py --diff `git rev-parse HEAD`'
no_ 'X=$(id) python3 post-fix-gate.py'
# Từ chối: token không phải post-fix-gate.py (tên dài hơn)
no_ "python3 xpost-fix-gate.py"
no_ "python3 bin/my-post-fix-gate.py --run-tests"
# Giữ luật cũ: ghép lệnh, rỗng
no_ "python3 post-fix-gate.py && npm test"
no_ ""

[ "$FAILS" -eq 0 ] && { echo "PASS test_verify_single_pfg_cmd"; exit 0; }
echo "FAIL test_verify_single_pfg_cmd ($FAILS)"; exit 1
