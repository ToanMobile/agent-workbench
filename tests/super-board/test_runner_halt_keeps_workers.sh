#!/usr/bin/env bash
# Test hồi quy #306: runner thoát vì GitHub halt (rc 79) không được giết worker đang chạy giữa lượt.
# Worker có lớp đọc GitHub chung và tự dừng ở check_halt; runner kế tiếp adopt lại như sau crash (rc 69).
# Chỉ lỗi readiness (rc 9/10) mới dừng worker do chính lần chạy này khởi tạo. halt_cleanup nằm sau nhánh SB_LIB_ONLY
# nên được cắt từ script rồi eval, với own_lane_pids / runner_state_exit / SB_GITHUB_READ là stub.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

GH_READ="$(mktemp "${TMPDIR:-/tmp}/sb-halt-ghread.XXXXXX")"
cleanup() {
  # PID các sleep do test này tạo (sim chạy trong $(...) nên ghi ra file, không qua biến)
  for p in $(cat "$GH_READ.pids" 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  rm -f "$GH_READ" "$GH_READ.pids"
}
trap cleanup EXIT

# github-read giả: --check thất bại (đúng tình huống halt vì GitHub)
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$GH_READ"
export SB_GITHUB_READ="$GH_READ"

fn="$(awk '/^halt_cleanup\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$RUNNER")"
[ -n "$fn" ] || { fail "halt_cleanup not found in runner"; exit 1; }
runner_state_exit() { :; }
own_lane_pids() { echo "$WORKER_PID"; }
eval "$fn"

# $1 = rc mà runner thoát; in "alive" hoặc "dead" cho worker (sleep) của lần chạy này.
# halt_cleanup đọc rc từ $? khi trap chạy: `( exit rc )` đặt $? ngay trước khi gọi hàm.
sim() {
  sleep 300 & WORKER_PID=$!; echo "$WORKER_PID" >> "$GH_READ.pids"
  ( exit "$1" ); halt_cleanup
  sleep 0.3
  if kill -0 "$WORKER_PID" 2>/dev/null; then echo alive; else echo dead; fi
}

[ "$(sim 79)" = alive ] && ok "rc 79 (GitHub halt): worker stays alive for adoption" || fail "rc 79 killed the worker (#306)"
[ "$(sim 69)" = alive ] && ok "rc 69 (crash): worker stays alive" || fail "rc 69 killed the worker"
[ "$(sim 10)" = dead ] && ok "rc 10 (skills not ready): worker stopped" || fail "rc 10 did not stop the worker"
[ "$(sim 9)" = dead ] && ok "rc 9 (verification not ready): worker stopped" || fail "rc 9 did not stop the worker"

[ "$FAILS" -eq 0 ] || { echo "$FAILS failure(s)"; exit 1; }
echo "all passed"
