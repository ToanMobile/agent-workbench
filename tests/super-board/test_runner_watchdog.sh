#!/usr/bin/env bash
# Test hồi quy cho runner claude-p (.claude/bin/super-board-run.sh), stop marker (super-board-stop.sh) và watchdog
# launchd (super-board-watchdog.sh).
#
# 17/10 12:17: runner.log của OfficeReader và NFH kết thúc bằng `Terminated: 15 sleep "$TICK_SECONDS"`. Vòng lặp chạy
# dưới `set -euo pipefail` nên một `sleep` bị kill (rc 143) kết thúc runner; không gì phát hiện hay khởi động lại suốt
# 2 ngày, thẻ Ready nằm im. 19/10 người dùng dừng cả 6 board bằng super-board-stop.sh và sẽ tự khởi động lại: watchdog
# không bao giờ được khởi động board người dùng đã dừng.
#
# Runner thật chạy hộp đen trong một repo giả: các script anh em đọc GitHub (github-read, card, wave-plan) là stub,
# gh/claude/launchctl là stub trên PATH, HOME và thư mục LaunchAgents là thư mục tạm. Test chỉ kill PID nó đã ghi lại
# (runner trong repo giả và con trực tiếp của nó). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Watchdog là launchd (macOS); runner và test dùng ps/lsof/pgrep/plutil của macOS.
[ "$(uname -s)" = Darwin ] || { echo "• skip test_runner_watchdog: macOS only (launchd)"; exit 0; }
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sb-watchdog-test.XXXXXX")" && pwd)"   # pwd: TMPDIR có / cuối sinh ra `//`
PIDS=""
kill_tree() {   # kill_tree <pid>: PID đã ghi lại và các con trực tiếp của nó (sleep của tick)
  local kids
  kids=$(pgrep -P "$1" 2>/dev/null | tr '\n' ' ')
  kill "$1" $kids 2>/dev/null || true
}
cleanup() {
  for p in $PIDS; do kill_tree "$p"; done
  [ -n "${KEEP:-}" ] && echo "kept $TMP" || rm -rf "$TMP"
}
trap cleanup EXIT

wait_for() {   # wait_for <giây> <điều kiện shell>: 0 khi điều kiện đúng trước hạn
  local i=0
  while [ "$i" -lt $(( $1 * 10 )) ]; do
    eval "$2" && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
alive() { kill -0 "$1" 2>/dev/null; }
# Đặt D = PID vừa chết. Tiến trình tự thoát, KHÔNG kill: kill một job nền vừa fork, trước khi nó kịp exec, làm bản sao
# bash con chạy trap EXIT của test này (rm -rf "$TMP") — bash 3.2 chạy trap EXIT khi chết vì SIGTERM.
dead_pid() { sleep 0 & D=$!; wait "$D" 2>/dev/null; }

# ── Repo giả ────────────────────────────────────────────────────────────────────────────────────────────────────────
R="$TMP/repo"
BIN="$R/.claude/bin"
mkdir -p "$BIN" "$R/.claude/super-board/configs" "$TMP/home" "$TMP/stub"
for f in super-board-run.sh super-board-stop.sh super-board-watchdog.sh super-board-verification-ready.py super-board-gh-guard.sh; do
  cp "$ROOT/.claude/bin/$f" "$BIN/" 2>/dev/null || echo "  (missing .claude/bin/$f)"
done
cat > "$R/.claude/super-board/configs/t.json" <<'JSON'
{"worker_backend": "claude-p", "project": {"owner": "o", "number": 1}, "base_branch": "main",
 "human_approves_merge": true, "verify_commands": ["true"], "tick_seconds": 30, "max_workers": 3}
JSON
cat > "$BIN/super-board-github-read.py" <<'PY'
#!/usr/bin/env python3
# Stub: --check = có file halt giả hay không; quota = còn nhiều; mọi lệnh đọc khác = {}.
import os, sys
args = sys.argv[1:]
if '--check' in args:
    sys.exit(79 if os.path.exists(os.environ['STUB_HALT']) else 0)
if 'quota' in args:
    print('{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000}}}')
    sys.exit(0)
print('{}')
PY
cat > "$BIN/super-board-verification-ready.py" <<'PY'
#!/usr/bin/env python3
# Stub: config luôn sẵn sàng. STUB_WRITE_MARK=<path>: ghi stop marker MỘT lần, đúng lúc runner đọc config — mô phỏng
# super-board-stop.sh chạy trùng lúc một lần khởi động tường minh.
import os, sys
m = os.environ.get('STUB_WRITE_MARK')
if m and not os.path.exists(m + '.written'):
    os.makedirs(os.path.dirname(m), exist_ok=True)
    # PID của một "stop.sh" còn sống (shell test): stop đang chạy, như stop.sh thật ghi marker rồi đi dừng worker.
    open(m, 'w').write('STOPPED_AT=race\nPID=%s\n' % os.environ.get('STUB_MARK_PID', ''))
    open(m + '.written', 'w').close()
sys.exit(0)
PY
printf '#!/usr/bin/env bash\necho %s\n' "'{\"items\":[]}'" > "$BIN/super-board-card.sh"   # board rỗng
printf '#!/usr/bin/env bash\necho %s\n' "'{}'" > "$BIN/super-board-wave-plan.sh"
for c in gh claude; do printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_CALLS"; exit 1\n' "$c" > "$TMP/stub/$c"; done
cat > "$TMP/stub/launchctl" <<'SH'
#!/usr/bin/env bash
# Có trạng thái như launchd: bootstrap nạp nhãn, bootout gỡ, print thoát 113 khi nhãn chưa được nạp.
echo "launchctl $*" >> "$STUB_CALLS"
case "$1" in
  print) [ -e "$STUB_CALLS.loaded" ] || exit 113; echo "state = not running" ;;
  bootstrap) touch "$STUB_CALLS.loaded" ;;
  bootout) rm -f "$STUB_CALLS.loaded" ;;
esac
# RunAtLoad chạy `check` ngay lúc bootstrap: ghi lại bản ghi runner đang có tại thời điểm đó.
[ "$1" = bootstrap ] && echo "state-at-bootstrap $(sed -n 's/^PID=//p' "$STUB_STATE" 2>/dev/null) $(sed -n 's/^STATE=//p' "$STUB_STATE" 2>/dev/null)" >> "$STUB_CALLS"
exit 0
SH
chmod +x "$BIN"/* "$TMP/stub"/*

# An toàn trước tiên: stub nào không che được lệnh thật thì dừng, không chạy runner.
for c in gh claude launchctl; do
  got=$(env PATH="$TMP/stub:$PATH" bash -c "type -P $c")
  [ "$got" = "$TMP/stub/$c" ] || { echo "✖ stub $c not first on PATH (got '$got'): refusing to run"; exit 1; }
done

ENVV=(-u SB_GITHUB_READ_STRICT -u POSTFIX_GATE_FORCE_FULL -u SB_DAEMON -u SB_WATCHDOG_START -u SB_WATCHDOG_AUTOINSTALL
  -u JAVA_HOME -u ANDROID_HOME -u ANDROID_SDK_ROOT -u STUB_WRITE_MARK
  HOME="$TMP/home" PATH="$TMP/stub:$PATH" SB_ACCOUNT_POOL="$TMP/no-pool" SB_STATE_DIR="$TMP/home/sb"
  SB_LAUNCH_AGENTS_DIR="$TMP/LaunchAgents" STUB_HALT="$TMP/halt" STUB_CALLS="$TMP/calls"
  STUB_STATE="$TMP/repo/.claude/super-board/runner/t.state")
run_env() { env "${ENVV[@]}" "$@"; }
start_runner() {   # start_runner <out> [VAR=val…]: runner nền trong repo giả, đặt RP = PID của chính bash runner
  local out="$1"; shift
  # exec hai lần (subshell → env → bash): $! là PID runner, sleep của tick là con trực tiếp của nó; subshell ngoài
  # tách runner khỏi shell test (cha là launchd) nên runner chết là được dọn ngay, không thành zombie.
  ( ( cd "$R" && exec env "${ENVV[@]}" "$@" bash "$BIN/super-board-run.sh" t ) > "$out" 2>&1 & echo $! > "$TMP/rp" )
  RP=$(cat "$TMP/rp"); PIDS="$PIDS $RP"
}
ticks() { local n; n=$(grep -c 'tick — Ready=' "$1" 2>/dev/null); echo "${n:-0}"; }
tick_sleep_pid() { pgrep -P "$RP" sleep 2>/dev/null | head -1; }

RUNDIR="$R/.claude/super-board/runner"
WLABEL="com.superboard.watchdog.t.$(printf '%s' "$R" | shasum | cut -c1-8)"   # nhãn theo slug + sha1 đường dẫn repo
STATE="$RUNDIR/t.state"; MARK="$RUNDIR/t.stopped"; WD="$RUNDIR/t.watchdog"; WLOG="$RUNDIR/t.watchdog.log"
field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }

# ── 1. Một `sleep` bị kill không kết thúc vòng lặp (17/10) ──────────────────────────────────────────────────────────
OUT1="$TMP/run1.out"
start_runner "$OUT1" SB_DAEMON=1
if wait_for 30 '[ "$(ticks "$OUT1")" -ge 1 ] && [ -n "$(tick_sleep_pid)" ]'; then
  kill -TERM "$(tick_sleep_pid)"
  if wait_for 10 '[ "$(ticks "$OUT1")" -ge 2 ]' && alive "$RP"; then
    ok "runner keeps ticking after its tick sleep is killed"
  else
    fail "runner did not survive a killed sleep (alive=$(alive "$RP" && echo yes || echo no))"; tail -5 "$OUT1" | sed 's/^/    /'
  fi
else
  fail "runner never reached its first tick sleep"; tail -15 "$OUT1" | sed 's/^/    /'
fi

# ── 2. Runner ghi bản ghi trạng thái cho watchdog ───────────────────────────────────────────────────────────────────
[ "$(field STATE "$STATE")" = running ] && [ "$(field PID "$STATE")" = "$RP" ] && [ "$(field DAEMON "$STATE")" = 1 ] \
  && ok "runner records STATE=running, its pid and SB_DAEMON" \
  || fail "runner state record missing or wrong: $(tr '\n' ' ' < "$STATE" 2>/dev/null)"
# Lần khởi động tường minh đầu tiên nạp watchdog (RunAtLoad chạy `check` ngay): bản ghi của runner mới phải có trước đó,
# nếu không `check` đọc bản ghi cũ (PID chết) và khởi động runner thứ hai.
grep -q "^state-at-bootstrap $RP running$" "$TMP/calls" 2>/dev/null \
  && ok "the new runner's record is written before the watchdog loads" \
  || fail "watchdog loaded before the runner recorded itself: $(grep state-at-bootstrap "$TMP/calls" 2>/dev/null)"

# ── 3. Stop marker xuất hiện khi runner đang chạy: runner tự thoát ở tick kế tiếp ───────────────────────────────────
if alive "$RP"; then
  mkdir -p "$RUNDIR"; printf 'STOPPED_AT=test\n' > "$MARK"
  wait_for 10 '[ -n "$(tick_sleep_pid)" ]' && kill -TERM "$(tick_sleep_pid)"   # không chờ hết 30 s
  if wait_for 10 '! alive "$RP"'; then
    ok "runner exits by itself once the stop marker exists"
  else
    fail "runner kept running with a stop marker present"; kill_tree "$RP"
  fi
  [ "$(field STATE "$STATE")" = stopped ] && ok "state says STATE=stopped" || fail "state after marker exit: $(tr '\n' ' ' < "$STATE" 2>/dev/null)"
else
  fail "runner already dead before the stop-marker case"
fi

# ── 4. super-board-stop.sh ghi marker bền, kể cả khi không còn gì để dừng ───────────────────────────────────────────
rm -f "$MARK"
( cd "$R" && run_env bash "$BIN/super-board-stop.sh" t ) > "$TMP/stop.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$MARK" ] && grep -q '^STOPPED_AT=' "$MARK" \
  && ok "stop.sh writes the durable stop marker even with nothing to stop" \
  || { fail "stop.sh rc=$rc, marker $( [ -f "$MARK" ] && echo present || echo missing)"; tail -5 "$TMP/stop.out" | sed 's/^/    /'; }

# ── 5. Runner do watchdog khởi động từ chối chạy khi có marker, không đụng state ────────────────────────────────────
cp "$STATE" "$TMP/state.before" 2>/dev/null || : > "$TMP/state.before"
start_runner "$TMP/run2.out" SB_DAEMON=1 SB_WATCHDOG_START=1
if wait_for 15 '! alive "$RP"'; then
  [ -f "$MARK" ] && cmp -s "$STATE" "$TMP/state.before" \
    && ok "watchdog start refused while stopped: marker kept, state untouched" \
    || fail "watchdog start touched the marker or the state"
else
  fail "watchdog-started runner ran despite the stop marker"; kill_tree "$RP"
fi

# ── 6. Khởi động tường minh xoá marker; board rỗng không daemon thoát sạch: STATE=finished ──────────────────────────
# PATH khác lần khởi động ở mục 1: plist phải giống hệt, watchdog không bị gỡ rồi nạp lại.
start_runner "$TMP/run3.out" PATH="$TMP/stub:/usr/local/sbin:$PATH"
if wait_for 30 '! alive "$RP"'; then
  [ "$(grep -c '^launchctl bootstrap' "$TMP/calls" 2>/dev/null)" = 1 ] \
    && ok "a second explicit start from another PATH keeps the loaded watchdog (no re-bootstrap)" \
    || fail "watchdog re-bootstrapped on a second start: $(grep -c '^launchctl bootstrap' "$TMP/calls") bootstraps"
  [ ! -e "$MARK" ] && ok "explicit start clears the stop marker" || fail "explicit start left the stop marker"
  [ "$(field STATE "$STATE")" = finished ] && [ "$(field RC "$STATE")" = 0 ] \
    && ok "clean finish recorded as STATE=finished rc=0" || fail "state after clean finish: $(tr '\n' ' ' < "$STATE" 2>/dev/null)"
  [ -f "$TMP/LaunchAgents/$WLABEL.plist" ] && grep -q "bootstrap gui/$(id -u)" "$TMP/calls" 2>/dev/null \
    && ok "explicit start installs the repo's launchd watchdog" || fail "explicit start did not install the watchdog"
else
  fail "explicit non-daemon start on an empty board did not exit"; kill_tree "$RP"
fi

# ── 6b. Runner dừng có chủ đích vì GitHub bị halt (exit 79): STATE=halted, watchdog sẽ không khởi động lại ─────────
: > "$TMP/halt"
start_runner "$TMP/run5.out"
if wait_for 20 '! alive "$RP"'; then
  [ "$(field STATE "$STATE")" = halted ] && [ "$(field RC "$STATE")" = 79 ] \
    && ok "GitHub halt exit recorded as STATE=halted rc=79" || fail "state after halt exit: $(tr '\n' ' ' < "$STATE" 2>/dev/null)"
else
  fail "runner kept running with GitHub reads halted"; kill_tree "$RP"
fi
rm -f "$TMP/halt"

# ── 6c. stop chạy trùng lúc một lần khởi động tường minh (marker ghi khi runner đang đọc config): stop thắng ────────
# FS = một "super-board-stop.sh" giả còn đang chạy (stop.sh thật ghi marker rồi còn đi comment, dừng worker).
mkdir -p "$TMP/fake"; printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/fake/super-board-stop.sh"
FS=$( (bash "$TMP/fake/super-board-stop.sh" >/dev/null 2>&1 & echo $!) ); PIDS="$PIDS $FS"
rm -f "$MARK" "$MARK.written"; cp "$STATE" "$TMP/state.before6c"
start_runner "$TMP/run7.out" STUB_WRITE_MARK="$MARK" STUB_MARK_PID="$FS"
if wait_for 20 '! alive "$RP"'; then
  [ -e "$MARK" ] && cmp -s "$STATE" "$TMP/state.before6c" \
    && ok "a stop landing while an explicit start boots wins: marker kept, runner never ran" \
    || fail "explicit start cleared a marker written during its own startup (marker $( [ -e "$MARK" ] && echo kept || echo GONE), state: $(field STATE "$STATE"))"
else
  fail "explicit start kept running after a stop landed during its startup"; kill_tree "$RP"
fi
rm -f "$MARK" "$MARK.written"

# Marker cũ hơn lúc runner ra đời nhưng stop.sh ghi nó vẫn đang chạy: stop vẫn thắng.
printf 'STOPPED_AT=old\nPID=%s\n' "$FS" > "$MARK"
touch -t "$(date -r "$(( $(date +%s) - 10 ))" +%Y%m%d%H%M.%S)" "$MARK"
cp "$STATE" "$TMP/state.before6c2"
start_runner "$TMP/run7b.out"
if wait_for 20 '! alive "$RP"'; then
  [ -e "$MARK" ] && grep -q 'start overruled' "$TMP/run7b.out" \
    && ok "an older marker whose stop.sh is still running also wins over an explicit start" \
    || fail "explicit start cleared the marker of a stop.sh still running"
else
  fail "explicit start ran while stop.sh was still stopping"; kill_tree "$RP"
fi
kill_tree "$FS"; rm -f "$MARK"

# ── 6d. Không ghi được marker (đĩa đầy, thư mục hỏng): stop.sh vẫn dừng board và báo rõ ─────────────────────────────
R2="$TMP/repo2"; mkdir -p "$R2/.claude/bin" "$R2/.claude/super-board/configs"
cp "$BIN/super-board-stop.sh" "$BIN/super-board-run.sh" "$R2/.claude/bin/"
cp "$R/.claude/super-board/configs/t.json" "$R2/.claude/super-board/configs/"
: > "$R2/.claude/super-board/runner"   # một FILE ở chỗ thư mục marker
( cd "$R2" && run_env bash "$R2/.claude/bin/super-board-stop.sh" t ) > "$TMP/stop2.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'could not write the stop marker' "$TMP/stop2.out" \
  && ok "stop.sh keeps stopping (rc 0) and warns when the marker cannot be written" \
  || { fail "stop.sh with an unwritable marker: rc=$rc"; tail -3 "$TMP/stop2.out" | sed 's/^/    /'; }
# Cùng repo hỏng đó: runner không ghi được bản ghi vẫn chạy hết (board rỗng, không daemon), không chết dưới set -e.
cp "$BIN"/super-board-* "$R2/.claude/bin/"
( ( cd "$R2" && exec env "${ENVV[@]}" bash "$R2/.claude/bin/super-board-run.sh" t ) > "$TMP/run8.out" 2>&1 & echo $! > "$TMP/rp" )
RP=$(cat "$TMP/rp"); PIDS="$PIDS $RP"
if wait_for 30 '! alive "$RP"'; then
  grep -q 'exiting cleanly' "$TMP/run8.out" && grep -q 'could not write' "$TMP/run8.out" \
    && ok "a runner that cannot write its record warns and keeps running" \
    || { fail "runner died when its record could not be written"; tail -3 "$TMP/run8.out" | sed 's/^/    /'; }
else
  fail "runner without a writable record did not finish"; kill_tree "$RP"
fi

# ── 6e. `stop && run` tuần tự trong cùng một giây: lần khởi động sau mới hơn, phải chạy (stop.sh đã xong) ───────────
dead_pid
T=$(( $(date +%s) + 2 ))
printf 'STOPPED_AT=seq\nPID=%s\n' "$D" > "$MARK"
touch -t "$(date -r "$T" +%Y%m%d%H%M.%S)" "$MARK"   # mtime = giây T; runner ra đời ngay đầu giây T
wait_for 5 '[ "$(date +%s)" -ge '"$T"' ]'
start_runner "$TMP/run9.out"
if wait_for 30 '! alive "$RP"'; then
  [ ! -e "$MARK" ] && [ "$(field STATE "$STATE")" = finished ] \
    && ok "stop then run in the same second: the later start runs (stop.sh already exited)" \
    || fail "same-second stop && run left the board stopped (marker $( [ -e "$MARK" ] && echo kept || echo gone), STATE=$(field STATE "$STATE"))"
else
  fail "same-second start did not finish"; kill_tree "$RP"
fi

# ── 6f. Ctrl-C trên một lần chạy foreground là người dùng dừng: STATE=stopped, watchdog không khởi động lại ─────────
# Runner chạy trong process group riêng với SIGINT mặc định (như foreground ở terminal); SIGINT gửi cho cả group.
OUT6F="$TMP/run10.out"
rc6f=$( (cd "$R" && run_env SB_DAEMON=1 python3 - "$BIN/super-board-run.sh" "$OUT6F" <<'PY'
import os, signal, subprocess, sys, time
script, out = sys.argv[1], sys.argv[2]
with open(out, 'w') as f:
    p = subprocess.Popen(['bash', script, 't'], stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                         start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
deadline = time.time() + 30
while time.time() < deadline and 'tick — Ready=' not in open(out, errors='replace').read():
    time.sleep(0.2)
time.sleep(1)
os.killpg(p.pid, signal.SIGINT)
try:
    print(p.wait(timeout=15))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL); print('timeout')
PY
) 2>&1 )
[ "$(field STATE "$STATE")" = stopped ] && [ ! -e "$MARK" ] \
  && ok "Ctrl-C on a foreground run is recorded as STATE=stopped (rc $rc6f)" \
  || fail "Ctrl-C recorded as STATE=$(field STATE "$STATE") rc=$(field RC "$STATE") ($rc6f)"

# ── 7. Watchdog: chỉ khởi động lại runner chết khi board đang chạy và không có marker ───────────────────────────────
wd() { ( cd "$R" && run_env bash "$BIN/super-board-watchdog.sh" check t ) >> "$TMP/wd.out" 2>&1; }
set_state() {   # set_state <pid> <STATE> [RC] [DAEMON]
  # ENV_PATH giữ stub ở đầu: runner do watchdog khởi động lại cũng không chạm gh/claude thật.
  mkdir -p "$RUNDIR"
  printf 'PID=%s\nSLUG=t\nSTARTED=1\nDAEMON=%s\nLOG=\nSTATE=%s\nRC=%s\n' "$1" "${4:-1}" "$2" "${3:-}" > "$STATE"
  printf 'DISPATCHES=7\nENV_PATH=%s\nENV_JAVA_HOME=/opt/test-jdk\n' "$TMP/stub:$PATH" >> "$STATE"
  # Dòng do worker cài vào: watchdog không được đưa BASH_ENV vào runner (bash chạy file đó lúc khởi động).
  printf 'ENV_BASH_ENV=%s\n' "$TMP/inject.sh" >> "$STATE"
}
printf '#!/usr/bin/env bash\n: > "%s"\n' "$TMP/injected" > "$TMP/inject.sh"
restarts_logged() { local n; n=$(grep -c 'restarted the runner' "$WLOG" 2>/dev/null); echo "${n:-0}"; }
expect_no_restart() {   # $1 = mô tả; watchdog không ghi lần khởi động lại nào và state PID vẫn là $D
  local before; before=$(restarts_logged)
  wd
  if [ "$(restarts_logged)" = "$before" ] && [ "$(field PID "$STATE")" = "$D" ]; then ok "watchdog: $1 → not restarted"; else
    fail "watchdog restarted: $1"; wait_for 5 '[ "$(field PID "$STATE")" != "$D" ]'; P=$(field PID "$STATE"); [ -n "$P" ] && kill_tree "$P"; fi
}
expect_restart() {   # $1 = mô tả; đặt RP = runner mới
  wd
  if wait_for 15 '[ "$(field PID "$STATE")" != "$D" ] && alive "$(field PID "$STATE")"'; then
    RP=$(field PID "$STATE")
    case "$(ps -ww -o command= -p "$RP" 2>/dev/null)" in
      *"$BIN/super-board-run.sh t"*) PIDS="$PIDS $RP"; ok "watchdog: $1 → restarted (pid $RP)" ;;
      *) fail "watchdog: state pid $RP is not this repo's runner" ;;
    esac
  else
    fail "watchdog: $1 → no restart"; tail -3 "$WLOG" 2>/dev/null | sed 's/^/    /'
  fi
}
rm -f "$MARK" "$WD" "$STATE"
dead_pid
wd; [ ! -e "$STATE" ] && ok "watchdog: no runner record → nothing started (boards stopped before this change)" || fail "watchdog created a runner from nothing"
set_state "$D" running; printf 'STOPPED_AT=test\n' > "$MARK"
expect_no_restart "dead runner, stop marker set"
rm -f "$MARK"
set_state "$D" finished 0;  expect_no_restart "clean finish (STATE=finished)"
set_state "$D" halted 79;   expect_no_restart "deliberate halt (STATE=halted rc=79)"
set_state "$D" crashed 143; : > "$TMP/halt"
expect_no_restart "GitHub reads halted (github-halt.json)"
rm -f "$TMP/halt"
expect_restart "crashed runner (rc 143), no marker"
[ "$(field PID "$STATE")" != "$D" ] && [ "$(field DAEMON "$STATE")" = 1 ] && sleep 2 && alive "$RP" \
  && ok "restart keeps SB_DAEMON=1 from the record (daemon runner stays up)" || fail "restart lost SB_DAEMON or did not happen"
grep -q 'watchdog restart' "$R/docs/super-board/runner.log" 2>/dev/null && ok "restarted runner logs that the watchdog started it" \
  || fail "restarted runner log does not say it was a watchdog restart"
grep -q 'restarted' "$WLOG" 2>/dev/null && ok "restart logged to $(basename "$WLOG")" || fail "restart not logged"
[ "$(field ENV_JAVA_HOME "$STATE")" = /opt/test-jdk ] && [ "$(field DISPATCHES "$STATE")" = 7 ] \
  && ok "restarted runner gets the recorded JAVA_HOME back and keeps counting dispatches (7)" \
  || fail "restarted runner: ENV_JAVA_HOME='$(field ENV_JAVA_HOME "$STATE")' DISPATCHES='$(field DISPATCHES "$STATE")'"
[ ! -e "$TMP/injected" ] && ok "an ENV_BASH_ENV line planted in the record is not passed to the restarted runner" \
  || fail "watchdog passed ENV_BASH_ENV from the record: injected code ran in the restarted runner"

# Runner còn sống: không khởi động thêm runner thứ hai — cả từ watchdog lẫn từ một lần khởi động tường minh.
D="$RP"; expect_no_restart "runner alive"
[ -z "$(field SPAWNED "$WD")" ] && ok "a recorded live runner clears SPAWNED (no false spawn-died later)" \
  || fail "SPAWNED=$(field SPAWNED "$WD") kept while the recorded runner is alive"
LIVE="$RP"; cp "$STATE" "$TMP/state.live"
start_runner "$TMP/run6.out"
if wait_for 15 '! alive "$RP"'; then
  cmp -s "$STATE" "$TMP/state.live" && alive "$LIVE" && grep -q "pid ${LIVE} of board t is still running" "$TMP/run6.out" \
    && ok "a second runner refuses to start while the recorded runner is alive (state untouched)" \
    || fail "second runner: state changed or live runner gone"
else
  fail "a second runner started next to the live one"; kill_tree "$RP"
fi
RP="$LIVE"

# Backoff: runner vừa được khởi động lại chết ngay → chờ; hết hạn chờ → khởi động lại lần 2.
kill -TERM "$RP"; wait_for 10 '! alive "$RP"'
[ "$(field PID "$STATE")" = "$RP" ] && [ "$(field STATE "$STATE")" = crashed ] \
  && ok "a runner killed without the marker is recorded as crashed" \
  || fail "killed runner $RP recorded as: $(tr '\n' ' ' < "$STATE" 2>/dev/null)"
D="$RP"; expect_no_restart "second death inside the backoff window"
printf 'RESTARTS=%s\nLAST_RESTART=1\nVERDICT=\n' "$(field RESTARTS "$WD")" > "$WD"
expect_restart "backoff elapsed"
[ "$(field RESTARTS "$WD")" = 2 ] && ok "consecutive restarts counted (2)" || fail "RESTARTS=$(field RESTARTS "$WD")"
kill_tree "$RP"; wait_for 10 '! alive "$RP"'

# Trần: quá số lần khởi động lại liên tiếp thì bỏ cuộc, chỉ ghi log một lần.
D="$RP"; printf 'RESTARTS=5\nLAST_RESTART=1\nVERDICT=\n' > "$WD"
expect_no_restart "5 consecutive restarts already (crash loop)"
wd
[ "$(grep -c 'gave up' "$WLOG" 2>/dev/null)" = 1 ] && ok "give-up logged exactly once" || fail "give-up lines: $(grep -c 'gave up' "$WLOG" 2>/dev/null)"

# Runner watchdog vừa khởi động chết trước khi ghi bản ghi (lỗi config, trước trap): không khởi động lại lặp lại.
dead_pid; E="$D"; dead_pid; set_state "$D" crashed 143
printf 'RESTARTS=1\nLAST_RESTART=1\nVERDICT=\nSPAWNED=%s\n' "$E" > "$WD"
expect_no_restart "the runner it started died before recording itself"
grep -q 'exited before recording itself' "$WLOG" 2>/dev/null && ok "spawn-died logged" || fail "spawn-died not logged"

# Hai `check` cùng lúc (launchd + chạy tay): đúng một lần khởi động lại.
rm -f "$WD"; dead_pid; set_state "$D" crashed 143
n0=$(restarts_logged); wd & wd & wait
n1=$(restarts_logged)
wait_for 15 '[ "$(field PID "$STATE")" != "$D" ]'
P=$(field PID "$STATE"); [ "$P" = "$D" ] || { PIDS="$PIDS $P"; kill_tree "$P"; wait_for 10 '! alive "$P"'; }
[ $((n1 - n0)) -eq 1 ] && ok "two concurrent checks restart the runner once" || fail "two concurrent checks restarted $((n1 - n0)) times"

# PID tái dùng: PID trong record còn sống nhưng không phải runner → coi như runner đã chết.
rm -f "$WD"; S=$( (sleep 300 >/dev/null 2>&1 & echo $!) ); PIDS="$PIDS $S"; D="$S"; set_state "$S" running
expect_restart "record pid reused by another process"
kill_tree "$RP"; wait_for 10 '! alive "$RP"'

# Khởi động tường minh đặt lại backoff (RESTARTS) của watchdog.
printf 'RESTARTS=3\nLAST_RESTART=1\nVERDICT=\n' > "$WD"
start_runner "$TMP/run4.out"
wait_for 30 '! alive "$RP"' || kill_tree "$RP"
[ ! -e "$WD" ] && ok "explicit start resets the watchdog backoff" || fail "explicit start kept RESTARTS=$(field RESTARTS "$WD")"

[ -f "$BIN/super-board-watchdog.sh" ] && ! sed 's/#.*//' "$BIN/super-board-watchdog.sh" | grep -qE '(^|[^a-z])(pkill|killall)([^a-z]|$)' \
  && ok "watchdog never kills by name" || fail "watchdog missing or uses pkill/killall"

# ── 8. install / status / uninstall (LaunchAgents và launchctl là stub) ────────────────────────────────────────────
# Repo trong thư mục tạm, không có SB_LAUNCH_AGENTS_DIR: install từ chối, không ghi plist vào ~/Library/LaunchAgents.
out=$( (cd "$R" && run_env SB_LAUNCH_AGENTS_DIR= bash "$BIN/super-board-watchdog.sh" install t) 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$TMP/home/Library/LaunchAgents/$WLABEL.plist" ] && printf '%s' "$out" | grep -q 'refusing to install' \
  && ok "install refuses a temporary checkout (no real LaunchAgent pointing at it)" || fail "install from a temp dir: rc=$rc out=$out"

PL="$TMP/LaunchAgents/$WLABEL.plist"
rm -f "$PL"; : > "$TMP/calls"
( cd "$R" && run_env bash "$BIN/super-board-watchdog.sh" install t ) > "$TMP/install.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && plutil -lint "$PL" >/dev/null 2>&1; then
  ok "install writes a valid plist"
  pa=$(plutil -extract ProgramArguments json -o - "$PL" 2>/dev/null)
  [ "$pa" = "[\"\\/bin\\/bash\",\"$(printf '%s' "$BIN" | sed 's#/#\\/#g')\\/super-board-watchdog.sh\",\"check\",\"t\"]" ] \
    && ok "plist runs: /bin/bash <repo>/.claude/bin/super-board-watchdog.sh check t" || fail "ProgramArguments: $pa"
  [ "$(plutil -extract StartInterval raw -o - "$PL" 2>/dev/null)" = 60 ] && ok "StartInterval 60 s" || fail "StartInterval wrong"
  [ "$(plutil -extract AbandonProcessGroup raw -o - "$PL" 2>/dev/null)" = true ] \
    && ok "AbandonProcessGroup: a restarted runner outlives the check" || fail "AbandonProcessGroup not true"
  case ":$(plutil -extract EnvironmentVariables.PATH raw -o - "$PL" 2>/dev/null):" in
    *:/usr/bin:*) ok "plist sets PATH (launchd default lacks gh/jq/claude)" ;; *) fail "plist PATH missing" ;; esac
  grep -q "bootstrap gui/$(id -u) $PL" "$TMP/calls" && ok "install loads it with launchctl bootstrap" || fail "launchctl calls: $(tr '\n' ';' < "$TMP/calls")"
  # Đã nạp sẵn (mục 1): gỡ, chờ launchd gỡ xong (print thất bại), rồi mới bootstrap.
  [ "$(grep -E '^launchctl (bootout|print|bootstrap)' "$TMP/calls" | tail -3 | cut -d' ' -f2 | tr '\n' ' ')" = "bootout print bootstrap " ] \
    && ok "reinstall: bootout, wait until unloaded, then bootstrap" || fail "reinstall order: $(tr '\n' ';' < "$TMP/calls")"
else
  fail "install rc=$rc or invalid plist"; tail -5 "$TMP/install.out" | sed 's/^/    /'
fi
printf 'STOPPED_AT=test\n' > "$MARK"
st=$( ( cd "$R" && run_env bash "$BIN/super-board-watchdog.sh" status t ) 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$st" | grep -q 'stop marker: set' && ok "status shows the stop marker" || fail "status rc=$rc: $st"
( cd "$R" && run_env bash "$BIN/super-board-watchdog.sh" uninstall t ) > /dev/null 2>&1
[ ! -e "$PL" ] && grep -q "bootout gui/$(id -u)/$WLABEL" "$TMP/calls" \
  && ok "uninstall unloads and removes the plist" || fail "uninstall left $PL or did not bootout"

# ── 9. super_board_all.py stop gọi stop.sh cả khi runner đã chết (để marker luôn được ghi) ──────────────────────────
SBA="$ROOT/universal-agent-devkit/scripts/governance/super_board_all.py"
if [ -f "$SBA" ]; then
  mkdir -p "$TMP/all/.claude/bin"
  printf '#!/usr/bin/env bash\necho "stop $*" >> "%s"\n' "$TMP/all.calls" > "$TMP/all/.claude/bin/super-board-stop.sh"
  python3 - "$SBA" "$TMP/all" > "$TMP/all.out" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sba", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.REPOS = [{"slug": "zz-none", "name": "test", "dir": sys.argv[2], "tuios_window": "x", "url": "x"}]
m.get_running_pids = lambda slug: []
m.stop_all()
PY
  grep -q 'stop zz-none' "$TMP/all.calls" 2>/dev/null && ok "super_board_all.py stop runs stop.sh for a board whose runner is already dead" \
    || fail "super_board_all.py stop skipped stop.sh (no marker would be written)"
  grep -q 'CHƯA có stop marker' "$TMP/all.out" && ok "super_board_all.py stop warns when no marker was written" \
    || fail "super_board_all.py stop claimed success without a marker: $(tr '\n' ' ' < "$TMP/all.out")"
  mkdir -p "$TMP/all/.claude/super-board/runner"
  printf 'RESTARTS=5\nLAST_RESTART=1\nVERDICT=gave-up\n' > "$TMP/all/.claude/super-board/runner/zz-none.watchdog"
  python3 - "$SBA" "$TMP/all" > "$TMP/all.status" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sba", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.REPOS = [{"slug": "zz-none", "name": "test", "dir": sys.argv[2], "tuios_window": "x", "url": "x"}]
m.get_running_pids = lambda slug: []
m.status_all()
PY
  grep -q 'verdict=gave-up' "$TMP/all.status" && ok "super_board_all.py status shows a watchdog that gave up" \
    || fail "status hides the watchdog verdict: $(tr '\n' ' ' < "$TMP/all.status")"
else
  echo "• skip: $SBA exists only in agent-workbench"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_watchdog: all passed" || { echo "❌ test_runner_watchdog: $FAILS failed"; exit 1; }
