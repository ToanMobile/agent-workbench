#!/usr/bin/env bash
# Test hồi quy #1322 (19/11): board của 5 repo app đứng 8–12 ngày vì runner thoát (rc 79) sau một halt đọc GitHub tạm thời
# (504 / timeout ×3) và không ai bật lại. Luật: halt 79 do một lần ĐỌC (còn lệnh đọc để phát lại) thì runner tự lùi lại, thử
# `github-read --resume` (chỉ đọc) tối đa SB_HALT_RECOVER_MAX lần rồi chạy tiếp, không thoát. Halt do lần GHI chưa rõ kết quả
# (--resume từ chối) hoặc hết số lần thử vẫn thoát 79 như cũ (watchdog lo). Các halt khác (9/10/73…) không bị đụng.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-read-halt-1322.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_READ_SKIP_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
tick_sleep() { echo "sleep $1" >> "$TMP/sleeps"; }
export SB_HALT_RECOVER_DELAY=1 SB_HALT_RECOVER_MAX=3

# github-read giả: --resume thất bại FAILS_LEFT lần (504) rồi thành công; MODE=write thì từ chối như halt ghi chưa rõ kết quả.
GH="$TMP/ghread"
cat > "$GH" <<'PY'
#!/usr/bin/env python3
import os, sys
st = os.environ['STATE_FILE']
n = int(open(st).read() or 0) if os.path.exists(st) else 0
open(st, 'w').write(str(n + 1))
halted = os.environ['STATE_FILE'] + '.halted'
if '--check' in sys.argv:
    if os.path.exists(halted):
        sys.stderr.write('[github-read] HALTED\n'); sys.exit(79)
    sys.exit(0)
if '--resume' in sys.argv:
    if os.environ.get('MODE') == 'write':
        sys.stderr.write('[github-read] HALT: saved failure needs manual outcome reconciliation before restart\n'); sys.exit(79)
    if n < int(os.environ.get('FAILS_LEFT', '0')):
        sys.stderr.write('[github-read] HALT: gh: HTTP 504\n'); sys.exit(79)
    if os.path.exists(halted): os.remove(halted)
    sys.exit(0)
if os.path.exists(halted):
    sys.stderr.write('[github-read] HALTED\n'); sys.exit(79)
sys.exit(0)
PY
chmod +x "$GH"
export SB_GITHUB_READ="$GH" STATE_FILE="$TMP/calls"
reset() { : > "$TMP/log"; : > "$TMP/sleeps"; rm -f "$TMP/calls" "$TMP/calls.halted"; READ_SKIPS=0; HALT_RECOVERS=0; }
halt() { : > "$TMP/calls.halted"; }
run_failed() { ( tick_read_failed "$1" nosleep ) >/dev/null 2>&1; echo $?; }

# A: 504 hai lần rồi đọc được -> runner không thoát (tick_read_failed trả 1 = bỏ tick), có lùi lại giữa các lần thử.
reset; export MODE=read FAILS_LEFT=2
rc=$(run_failed 79)
if [ "$rc" = 1 ] && [ "$(wc -l < "$TMP/sleeps" | tr -d ' ')" -ge 2 ]; then
  ok "A: read halt (504 x2) recovered by --resume: runner keeps going after backoff"
else
  fail "A: runner exited rc=$rc instead of recovering (sleeps: $(tr '\n' ';' < "$TMP/sleeps"))"
fi

# B: 504 ba lần liên tiếp (AC): lần thử thứ ba vẫn đọc được thì chạy tiếp.
reset; export MODE=read FAILS_LEFT=3
rc=$( ( SB_HALT_RECOVER_MAX=4; tick_read_failed 79 nosleep ) >/dev/null 2>&1; echo $? )
[ "$rc" = 1 ] && ok "B: three 504s in a row then success: runner backs off and goes on (no exit)" || fail "B: rc=$rc"

# C: hết số lần thử mà vẫn 504 -> thoát 79 như cũ (watchdog bật lại).
reset; export MODE=read FAILS_LEFT=99
rc=$(run_failed 79)
[ "$rc" = 79 ] && ok "C: still failing after SB_HALT_RECOVER_MAX tries: exits 79 as before" || fail "C: rc=$rc"

# D: halt do lần ghi chưa rõ kết quả (--resume từ chối) -> thoát 79 ngay, không lặp thử.
reset; export MODE=write FAILS_LEFT=0
rc=$(run_failed 79)
tries=$(cat "$TMP/calls" 2>/dev/null)
[ "$rc" = 79 ] && [ "${tries:-0}" = 1 ] && ok "D: uncertain-write halt: exits 79 after one refused --resume" || fail "D: rc=$rc resume calls=${tries:-0}"

# E: halt khác (10 = skills chưa sẵn sàng) -> thoát ngay, không gọi --resume.
reset; export MODE=read FAILS_LEFT=0
rc=$(run_failed 10)
[ "$rc" = 10 ] && [ ! -e "$TMP/calls" ] && ok "E: other halt codes still exit untouched" || fail "E: rc=$rc"

# F (R3): gh_checkpoint chạm halt đọc tạm thời -> lùi lại, nhả bằng --resume, không thoát runner.
reset; export MODE=read FAILS_LEFT=1; halt
rc=$( ( gh_checkpoint ) >/dev/null 2>&1; echo $? )
[ "$rc" = 0 ] && ok "F: gh_checkpoint on a transient read halt recovers (no runner exit)" || fail "F: gh_checkpoint exited rc=$rc"

# G (R3): gh_checkpoint chạm halt do GHI chưa rõ kết quả -> vẫn thoát 79.
reset; export MODE=write FAILS_LEFT=0; halt
rc=$( ( gh_checkpoint ) >/dev/null 2>&1; echo $? )
[ "$rc" = 79 ] && ok "G: gh_checkpoint on an uncertain-write halt still exits 79" || fail "G: rc=$rc"

# H (R3): ready_card_held gặp 79 đọc tạm thời -> giữ thẻ tick này (return 0), không thoát.
reset; export MODE=read FAILS_LEFT=0; halt
rc=$( ( ready_card_held 5 PVTI_5; echo "held=$?" ) 2>/dev/null | tail -1 )
[ "$rc" = "held=0" ] && ok "H: ready_card_held on a transient read halt holds the card and keeps the runner" || fail "H: got '$rc' (runner exited or card dispatched)"

[ "$FAILS" -eq 0 ] && { echo "PASS test_runner_read_halt_recover_1322"; exit 0; }
echo "FAIL test_runner_read_halt_recover_1322 ($FAILS)"; exit 1
