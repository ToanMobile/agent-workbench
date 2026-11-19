#!/usr/bin/env bash
# Test hồi quy #1350 (tách từ #1318/#1322): các chỗ ĐỌC GitHub bắt buộc còn lại của runner (issue_is_open qua rate_limit_skip,
# mq_collect_rc, ...) từng `exit 79` thẳng, nên một lần đọc hỏng tạm thời vẫn dừng cả board. Luật: đi qua recover_read_halt
# (một helper dùng chung); lỗi đọc kéo dài hoặc halt do GHI chưa rõ kết quả vẫn thoát 79 (hợp đồng github-halt.json giữ nguyên).
# Watchdog: runner chết quá trần khởi động lại thì phải báo người (notify), không chỉ ghi log. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-read-sites-1350.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_READ_SKIP_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
tick_sleep() { echo "sleep $1" >> "$TMP/sleeps"; }
export SB_HALT_RECOVER_DELAY=1 SB_HALT_RECOVER_MAX=3

# github-read giả: mỗi lệnh đọc (--kind …) chạm halt (79) khi có file .halted; --resume hỏng FAILS_LEFT lần rồi nhả;
# MODE=write: --resume từ chối như halt ghi chưa rõ kết quả.
GH="$TMP/ghread"
cat > "$GH" <<'PY'
#!/usr/bin/env python3
import os, sys
st = os.environ['STATE_FILE']
halted = st + '.halted'
n = int(open(st).read() or 0) if os.path.exists(st) else 0
if '--resume' in sys.argv:
    open(st, 'w').write(str(n + 1))
    if os.environ.get('MODE') == 'write':
        sys.stderr.write('[github-read] HALT: saved failure needs manual outcome reconciliation before restart\n'); sys.exit(79)
    if n < int(os.environ.get('FAILS_LEFT', '0')):
        sys.stderr.write('[github-read] HALT: gh: HTTP 504\n'); sys.exit(79)
    if os.path.exists(halted): os.remove(halted)
    sys.exit(0)
if os.path.exists(halted):
    sys.stderr.write('[github-read] HALTED\n'); sys.exit(79)
if '--check' in sys.argv: sys.exit(0)
print('OPEN'); sys.exit(0)
PY
chmod +x "$GH"
export SB_GITHUB_READ="$GH" STATE_FILE="$TMP/calls"
reset() { : > "$TMP/log"; : > "$TMP/sleeps"; rm -f "$TMP/calls" "$TMP/calls.halted"; READ_SKIPS=0; HALT_RECOVERS=0; RL_SKIP_UNTIL=0; }
halt() { : > "$TMP/calls.halted"; }

# A: rate_limit_skip(79) với lỗi đọc tạm thời (3 lần --resume hỏng rồi thành công) -> 0 = bỏ thẻ này, runner đi tiếp.
reset; export MODE=read FAILS_LEFT=2; halt
( rate_limit_skip 79 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "A: rate_limit_skip 79 on a transient read halt releases it (card skipped, runner keeps going)" || fail "A: rc=$rc"

# B: lỗi đọc kéo dài -> trả 1: caller exit 79 như cũ (halt thật vẫn dừng).
reset; export MODE=read FAILS_LEFT=99; halt
( rate_limit_skip 79 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "B: persistent read failure still returns 1 (caller exits 79)" || fail "B: rc=$rc"

# C: halt do lần GHI chưa rõ kết quả -> trả 1.
reset; export MODE=write FAILS_LEFT=0; halt
( rate_limit_skip 79 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "C: uncertain-write halt is not released (returns 1)" || fail "C: rc=$rc"

# D: mã khác (10, 64) vẫn không bị nuốt.
reset; export MODE=read FAILS_LEFT=0
( rate_limit_skip 10 ) >/dev/null 2>&1; r10=$?
( rate_limit_skip 64 ) >/dev/null 2>&1; r64=$?
[ "$r10" = 1 ] && [ "$r64" = 1 ] && [ ! -e "$TMP/calls" ] && ok "D: other codes untouched, no --resume call" || fail "D: rc10=$r10 rc64=$r64"

# E: issue_is_open gặp 79 tạm thời qua đường thật (stub github-read) -> caller mẫu giữ nguyên mẫu `|| { rate_limit_skip … && continue; exit }`.
reset; export MODE=read FAILS_LEFT=2; halt
out=$( ( for i in 1; do
  issue_rc=0; issue_is_open 7 || issue_rc=$?
  [ "$issue_rc" -le 1 ] || { rate_limit_skip "$issue_rc" && continue; exit "$issue_rc"; }
done; echo survived ) 2>/dev/null | tail -1 )
[ "$out" = survived ] && ok "E: issue_is_open read failure at a call site: runner survives after --resume" || fail "E: got '$out' (runner exited)"

# F: mq_collect_rc: 79 tạm thời -> không exit; 79 kéo dài -> exit 79; 9 vẫn exit 9.
mq() { printf '%s' "$1" > "$TMP/mq.rc"; : > "$TMP/mq.pid"; ( mq_collect_rc "$TMP/mq.rc" "$TMP/mq.pid"; echo survived ) 2>/dev/null | tail -1; }
reset; export MODE=read FAILS_LEFT=2; halt
r=$(mq 79); [ "$r" = survived ] && ok "F1: mq_collect_rc 79 on a transient read halt: runner keeps going" || fail "F1: got '$r'"
reset; export MODE=read FAILS_LEFT=99; halt
( printf 79 > "$TMP/mq.rc"; mq_collect_rc "$TMP/mq.rc" "$TMP/mq.pid" ) >/dev/null 2>&1; rc=$?
[ "$rc" = 79 ] && ok "F2: mq_collect_rc 79 with a persistent failure exits 79" || fail "F2: rc=$rc"
reset; export MODE=read FAILS_LEFT=0
( printf 9 > "$TMP/mq.rc"; mq_collect_rc "$TMP/mq.rc" "$TMP/mq.pid" ) >/dev/null 2>&1; rc=$?
[ "$rc" = 9 ] && ok "F3: mq_collect_rc 9 still halts" || fail "F3: rc=$rc"

# H: suite_fuse_tick (đọc thẻ Blocked) gặp 79 tạm thời -> không exit; kéo dài -> exit 79.
INFLIGHT_DIR="$TMP/inflight"; SB_FUSE_WINDOW_H=1; RUN_MANIFEST=/dev/null
PROJECT_ITEMS_JSON='{"items":[{"status":"Blocked","content":{"number":5}}]}'
fuse_card_info() { return 79; }
reset; export MODE=read FAILS_LEFT=2; halt
r=$( ( suite_fuse_tick; echo survived ) 2>/dev/null | tail -1 )
[ "$r" = survived ] && ok "H1: suite_fuse_tick 79 on a transient read halt: runner keeps going" || fail "H1: got '$r'"
reset; export MODE=read FAILS_LEFT=99; halt
( suite_fuse_tick ) >/dev/null 2>&1; rc=$?
[ "$rc" = 79 ] && ok "H2: suite_fuse_tick 79 with a persistent failure exits 79" || fail "H2: rc=$rc"

# I: startup_reconcile: gh_rate_guard / fetch_project_items gặp 79 tạm thời -> không exit; kéo dài -> exit 79.
reap_finished_locks() { :; }; adopt_live_locks() { :; }; reclaim_stranded_building() { :; }; sweep_merged_lanes() { :; }
gh_rate_guard() { return 0; }; fetch_project_items() { return 79; }
reset; export MODE=read FAILS_LEFT=2; halt
r=$( ( startup_reconcile; echo survived ) 2>/dev/null | tail -1 )
[ "$r" = survived ] && ok "I1: startup_reconcile fetch 79 on a transient read halt: runner keeps going" || fail "I1: got '$r'"
gh_rate_guard() { return 79; }; fetch_project_items() { return 0; }
reset; export MODE=read FAILS_LEFT=2; halt
r=$( ( startup_reconcile; echo survived ) 2>/dev/null | tail -1 )
[ "$r" = survived ] && ok "I2: startup_reconcile quota 79 on a transient read halt: runner keeps going" || fail "I2: got '$r'"
reset; export MODE=read FAILS_LEFT=99; halt
( startup_reconcile ) >/dev/null 2>&1; rc=$?
[ "$rc" = 79 ] && ok "I3: startup_reconcile 79 with a persistent failure exits 79" || fail "I3: rc=$rc"

# J: 79 mà không có file halt (issue_is_open ép lỗi lạ thành 79) -> không nhả, không --resume: caller thoát như cũ.
reset; export MODE=read FAILS_LEFT=0
( rate_limit_skip 79 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -e "$TMP/calls" ] && ok "J: 79 with no halt record is not swallowed (returns 1, no --resume)" || fail "J: rc=$rc"

# G: watchdog — quá trần khởi động lại: giữ nguyên không khởi động, và gửi notify đúng một lần.
if [ "$(uname -s)" = Darwin ]; then
  R="$TMP/repo"; BIN="$R/.claude/bin"; STUB="$TMP/stub"; mkdir -p "$BIN" "$R/.claude/super-board/runner" "$STUB" "$TMP/home"
  cp "$ROOT/.claude/bin/super-board-watchdog.sh" "$BIN/"
  cat > "$BIN/super-board-notify.py" <<'PY'
#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_CALLS"], "a").write("notify " + " ".join(sys.argv[1:]) + "\n")
PY
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n' > "$BIN/super-board-github-read.py"
  for c in gh claude; do printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/$c"; chmod +x "$STUB/$c"; done
  sleep 0 & D=$!; wait "$D" 2>/dev/null
  printf 'PID=%s\nSLUG=t\nSTARTED=1\nDAEMON=1\nLOG=\nSTATE=crashed\nRC=143\nENV_PATH=%s\n' "$D" "$STUB:$PATH" > "$R/.claude/super-board/runner/t.state"
  printf 'RESTARTS=5\nLAST_RESTART=1\nVERDICT=\n' > "$R/.claude/super-board/runner/t.watchdog"
  wd() { ( cd "$R" && HOME="$TMP/home" STUB_CALLS="$TMP/wcalls" SB_LAUNCH_AGENTS_DIR="$TMP/la" PATH="$STUB:$PATH" bash "$BIN/super-board-watchdog.sh" check t ) >> "$TMP/wd.out" 2>&1; }
  wd; wd
  n=$(grep -c '^notify ' "$TMP/wcalls" 2>/dev/null); n=${n:-0}
  [ "$n" = 1 ] && grep -q 'gave up\|crash loop' "$TMP/wcalls" && ok "G: restart ceiling reached → watchdog stops trying and notifies once" || fail "G: notifies=$n ($(cat "$TMP/wcalls" 2>/dev/null | head -2))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS test_runner_read_recover_sites_1350"; exit 0; }
echo "FAIL test_runner_read_recover_sites_1350 ($FAILS)"; exit 1
