#!/usr/bin/env bash
# #1000 mục 6: sb_verify_runs_gate chỉ nhận lệnh CHẠY post-fix-gate.py. Trình thông dịch phải đứng đầu một đoạn lệnh (không phải đối số
# của echo/printf), và token phải là đúng tên post-fix-gate.py (đường dẫn trước nó rỗng hoặc kết thúc bằng /), không phải not-post-fix-gate.py.
# Nhận nhầm = duyệt test sửa tra từ biên bản PM bỏ exit 2 "stale" mà không ai kiểm lại (fail-open). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/.claude/bin/super-board-verify-flags.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

no() { if sb_verify_runs_gate "$1"; then fail "nhận nhầm: $1"; else ok "không nhận: $1"; fi; }
yes() { if sb_verify_runs_gate "$1"; then ok "nhận: $1"; else fail "bỏ sót: $1"; fi; }

no "echo python3 post-fix-gate.py"
no "echo python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests"
no "printf %s bash kit/bin/post-fix-gate.py"
no "not-post-fix-gate.py --run-tests"
no "python3 not-post-fix-gate.py"
no "python3 x/not-post-fix-gate.py --run-tests"
no "npm test && echo sh post-fix-gate.py"

yes "python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --brief"
yes "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped"
yes "npm test; python3 bin/post-fix-gate.py"
yes "cd x && python3 bin/post-fix-gate.py"
yes "universal-agent-devkit/bin/post-fix-gate.py --run-tests"
yes "./post-fix-gate.py"
yes "post-fix-gate.py --run-tests"
yes "sh tests/x.sh && bash kit/bin/post-fix-gate.py"
yes "python3 -u universal-agent-devkit/bin/post-fix-gate.py --run-tests"
yes "/usr/bin/python3 universal-agent-devkit/bin/post-fix-gate.py"
yes "python3.12 universal-agent-devkit/bin/post-fix-gate.py"
yes "(python3 kit/bin/post-fix-gate.py)"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
