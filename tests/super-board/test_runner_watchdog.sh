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
  # Mọi runner watchdog đã spawn (dòng "new pid N" trong log), kể cả khi assert fail giữa chừng: chỉ PID còn là runner
  # của repo giả này.
  for p in $(sed -n 's/.*new pid \([0-9][0-9]*\).*/\1/p' "${WLOG:-/nonexistent}" 2>/dev/null); do
    case "$(ps -ww -o command= -p "$p" 2>/dev/null)" in *"$TMP/"*super-board-run.sh*) PIDS="$PIDS $p" ;; esac
  done
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
# --resume: nội dung file halt giả = loại halt. read = lần đọc đã lưu phát lại được (halt được lưu trữ, exit 0);
# read-fail = phát lại vẫn lỗi; write (hay khác) = ghi chưa rõ kết quả, cần người đối chiếu. Hai loại sau: exit 79.
if '--resume' in args:
    h = os.environ['STUB_HALT']
    if not os.path.exists(h):
        sys.exit(0)
    kind = open(h).read().strip()
    if kind == 'read':
        os.remove(h)
        sys.exit(0)
    if kind == 'write':   # câu của super-board-github-read.py thật cho halt không có lần đọc đã lưu
        print('[github-read] HALT: saved failure needs manual outcome reconciliation before restart', file=sys.stderr)
    sys.exit(79)
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
# Board rỗng; STUB_CARD_FAIL=1: lần đọc board hỏng (runner crash lúc khởi động, trước tick đầu).
cat > "$BIN/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
[ -z "${STUB_CARD_FAIL:-}" ] || exit 1
if [ -n "${STUB_CARD_HALT:-}" ]; then echo halted > "${SB_GITHUB_HALT_FILE:-$STUB_HALT}"; exit 79; fi
[ -z "${SB_GITHUB_HALT_FILE:-}" ] || [ ! -e "$SB_GITHUB_HALT_FILE" ] || exit 79
case "$*" in *"item-id "*) [ -z "${STUB_ITEMID_FAIL:-}" ] || exit 1 ;; esac
case "$*" in
  *" ids"|ids) echo '{"projectId":"P1","fieldId":"F_STATUS","options":{}}' ;;
  *"item-id "*) echo "I_${@: -1}" ;;
  *) echo '{"items":[]}' ;;
esac
SH
printf '#!/usr/bin/env bash\necho %s\n' "'{}'" > "$BIN/super-board-wave-plan.sh"
for c in gh claude; do printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_CALLS"; exit 1\n' "$c" > "$TMP/stub/$c"; done
# `gh project edit` (watchdog ghi trạng thái board lên mô tả Project) thành công, trừ khi STUB_EDIT_FAIL=1.
cat > "$TMP/stub/gh" <<'SH'
#!/usr/bin/env bash
# gh project edit / item-edit thành công (trừ STUB_EDIT_FAIL=1); field-list trả field "Đang chạy"; mọi lệnh khác lỗi.
echo "gh $*" >> "$STUB_CALLS"
case "$1 $2" in
  "project edit") if [ -n "${STUB_GH_HANG:-}" ]; then trap '' ALRM; echo $$ > "$STUB_CALLS.hang"; sleep 25; fi; [ -z "${STUB_EDIT_FAIL:-}" ] && exit 0 ;;
  "project item-edit") [ -z "${STUB_EDIT_FAIL:-}${STUB_ITEM_EDIT_FAIL:-}" ] && exit 0 ;;
  "project field-list") echo '{"fields":[{"id":"F_STATUS","name":"Status"},{"id":"F_RUN","name":"Đang chạy"}]}'; exit 0 ;;
esac
exit 1
SH
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
# gh "độc" trong worktree của một worker: chỉ chạy được nếu watchdog đưa thư mục này vào PATH của runner.
mkdir -p "$R/.claude/worktrees/evil"
printf '#!/usr/bin/env bash\n: > "%s"\nexit 1\n' "$TMP/pathinjected" > "$R/.claude/worktrees/evil/gh"
chmod +x "$BIN"/* "$TMP/stub"/* "$R/.claude/worktrees/evil/gh"

# Runner và watchdog cần jq, git, python3 thật (gh/claude/launchctl là stub).
for c in jq git python3; do command -v "$c" >/dev/null 2>&1 || { echo "• skip test_runner_watchdog: $c not installed"; exit 0; }; done
# An toàn trước tiên: stub nào không che được lệnh thật thì dừng, không chạy runner.
for c in gh claude launchctl; do
  got=$(env PATH="$TMP/stub:$PATH" bash -c "type -P $c")
  [ "$got" = "$TMP/stub/$c" ] || { echo "✖ stub $c not first on PATH (got '$got'): refusing to run"; exit 1; }
done

ENVV=(-u SB_GITHUB_READ_STRICT -u POSTFIX_GATE_FORCE_FULL -u SB_DAEMON -u SB_WATCHDOG_START -u SB_WATCHDOG_AUTOINSTALL
  -u JAVA_HOME -u ANDROID_HOME -u ANDROID_SDK_ROOT -u STUB_WRITE_MARK -u STUB_CARD_FAIL -u CLAUDE_CONFIG_DIR -u DEVKIT_LANG
  HOME="$TMP/home" PATH="$TMP/stub:$PATH" SB_ACCOUNT_POOL="$TMP/no-pool" SB_STATE_DIR="$TMP/home/sb"
  SB_LAUNCH_AGENTS_DIR="$TMP/LaunchAgents" STUB_HALT="$TMP/halt" STUB_CALLS="$TMP/calls" SB_BOARD_TZ=Asia/Ho_Chi_Minh
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

# ── 6g. tick_seconds không hợp lệ: sleep tự lỗi (không phải bị kill) thì không được quay vòng đọc GitHub liên tục ────
R3="$TMP/repo3"; mkdir -p "$R3/.claude/bin" "$R3/.claude/super-board/configs"
cp "$BIN"/super-board-* "$R3/.claude/bin/"
sed 's/"tick_seconds": 30/"tick_seconds": "abc"/' "$R/.claude/super-board/configs/t.json" > "$R3/.claude/super-board/configs/t.json"
( ( cd "$R3" && exec env "${ENVV[@]}" SB_DAEMON=1 bash "$R3/.claude/bin/super-board-run.sh" t ) > "$TMP/run12.out" 2>&1 & echo $! > "$TMP/rp" )
RP=$(cat "$TMP/rp"); PIDS="$PIDS $RP"
wait_for 20 '[ "$(ticks "$TMP/run12.out")" -ge 1 ]'
sleep 4
n=$(ticks "$TMP/run12.out")
kill_tree "$RP"; wait_for 10 '! alive "$RP"'
[ "$n" -le 2 ] && ok "an invalid tick_seconds does not spin the loop ($n ticks in ~4 s)" \
  || fail "invalid tick_seconds: $n ticks in ~4 s (busy loop reading GitHub)"

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
  # Đầu ENV_PATH là một thư mục trong worktree của worker (có gh giả): watchdog phải bỏ nó. LOG ngoài thư mục log của
  # board: watchdog phải ghi vào log mặc định.
  printf 'DISPATCHES=7\nNO_PROGRESS=4\nENV_PATH=%s\nENV_JAVA_HOME=/opt/test-jdk\n' "$R/.claude/worktrees/evil:$TMP/stub:$PATH" >> "$STATE"
  printf 'ENV_CLAUDE_CONFIG_DIR=%s\n' "$R/.claude/worktrees/evil/cfg" >> "$STATE"   # thư mục cấu hình (hooks) của worker
  sed -i '' "s#^LOG=\$#LOG=$TMP/outside.log#" "$STATE"
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
[ ! -e "$TMP/pathinjected" ] && ok "a PATH entry inside the repo (a worker's worktree) is dropped from the restarted runner's PATH" \
  || fail "restarted runner ran a gh planted in the repo's worktrees through the recorded PATH"
[ ! -e "$TMP/outside.log" ] && ok "a LOG outside the board's log folders is ignored (default runner.log used)" \
  || fail "restarted runner wrote to the LOG path planted in the record"
[ -z "$(field ENV_CLAUDE_CONFIG_DIR "$STATE")" ] && ok "a CLAUDE_CONFIG_DIR inside the repo is not passed to the restarted runner" \
  || fail "restarted runner got CLAUDE_CONFIG_DIR=$(field ENV_CLAUDE_CONFIG_DIR "$STATE") from the record"
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

# Runner watchdog vừa spawn còn sống nhưng chưa ghi bản ghi (đang khởi động): không spawn runner thứ hai.
mkdir -p "$TMP/fake2"; printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/fake2/super-board-run.sh"
FR=$( (bash "$TMP/fake2/super-board-run.sh" >/dev/null 2>&1 & echo $!) ); PIDS="$PIDS $FR"
dead_pid; set_state "$D" crashed 143
printf 'RESTARTS=1\nLAST_RESTART=1\nVERDICT=\nSPAWNED=%s\n' "$FR" > "$WD"
expect_no_restart "the runner it spawned is alive but has not recorded itself yet"
kill_tree "$FR"

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

# Halt vì một lần ĐỌC GitHub lỗi tạm (20/10 09:00: máy gập nắp ngủ, 09:07 thức dậy khi mạng chưa lên, `gh api
# rate_limit` hỏng 3 lần → 5 board halt rc=79, nằm im 3,5 giờ tới khi có người khởi động tay). Lần đọc đã lưu phát lại
# được an toàn (--resume chỉ đọc): watchdog tự resume rồi khởi động lại. Ghi chưa rõ kết quả hoặc phát lại vẫn lỗi:
# giữ halt, không khởi động lại.
rm -f "$WD"; dead_pid; set_state "$D" halted 79
printf 'write\n' > "$TMP/halt"; expect_no_restart "halt with an uncertain write (a person reconciles it)"
[ "$(field VERDICT "$WD")" = github-halt ] && ok "uncertain-write halt → verdict github-halt (🔴 needs a person), not halt-wait" \
  || fail "uncertain-write halt verdict: $(field VERDICT "$WD")"
printf 'read-fail\n' > "$TMP/halt"; expect_no_restart "halt whose saved read still fails (GitHub/network still down)"
[ "$(field VERDICT "$WD")" = halt-wait ] && ok "read halt that still fails → verdict halt-wait (🟠 retrying)" \
  || fail "read-fail halt verdict: $(field VERDICT "$WD")"
[ -e "$TMP/halt" ] && ok "a halt whose replay failed is kept" || fail "halt file removed although its replay failed"
# Halt khi watchdog đang backoff (runner vừa được khởi động lại rồi halt ngay): không được tiêu file halt rồi dừng ở
# backoff — lượt sau sẽ thấy halted mà hết halt và bỏ board mãi.
printf 'RESTARTS=1\nLAST_RESTART=%s\nVERDICT=\n' "$(date +%s)" > "$WD"; printf 'read\n' > "$TMP/halt"
expect_no_restart "read halt inside the backoff window"
[ -e "$TMP/halt" ] && ok "halt kept while in backoff (resumed only when a restart follows)" || fail "halt consumed during backoff"
printf 'RESTARTS=1\nLAST_RESTART=1\nVERDICT=\n' > "$WD"
expect_restart "read halt once the backoff elapsed"
kill_tree "$RP"; wait_for 10 '! alive "$RP"'
dead_pid; set_state "$D" halted 79; rm -f "$WD"
printf 'read\n' > "$TMP/halt"; expect_restart "halt whose saved read now replays OK (transient read failure)"
[ ! -e "$TMP/halt" ] && grep -q 'auto-resumed' "$WLOG" 2>/dev/null && ok "auto-resume of a transient read halt is logged" \
  || fail "auto-resume not logged or halt kept: $(tail -2 "$WLOG" 2>/dev/null | tr '\n' ' ')"
L=$(grep '^gh project edit 1 --owner o --description' "$TMP/calls" | tail -1)
case "$L" in *"🟢 đang chạy từ"*) fail "restarted board shows the dead runner's start time: $L" ;;
  *"🟢 đang chạy"*) ok "restarted board does not show the dead runner's start time" ;; *) fail "restart status: '$L'" ;; esac
kill_tree "$RP"; wait_for 10 '! alive "$RP"'
rm -f "$WD" "$TMP/halt"

# Trạng thái board hiện trên GitHub (người dùng 20/10: "thể hiện lên board 1 icon … chứ để mấy giờ sau mới phát hiện được"
# và "thêm thời gian để biết task chạy được bao lâu, bắt đầu từ khi nào"): mỗi check ghi icon, worker đang chạy kèm giờ
# bắt đầu + thời lượng, và giờ cập nhật vào mô tả ngắn của Project khi trạng thái đổi, nhịp 5 phút khi không đổi (giờ cập
# nhật cũ = máy ngủ / watchdog chết). Lỗi gh không làm check hỏng.
BST="$RUNDIR/t.board-status"
edits() { local n; n=$(grep -c '^gh project edit 1 --owner o --description' "$TMP/calls" 2>/dev/null); echo "${n:-0}"; }
last_edit() { grep '^gh project edit 1 --owner o --description' "$TMP/calls" 2>/dev/null | tail -1; }
rm -f "$WD" "$BST"; : > "$TMP/calls"
printf 'STOPPED_AT=test\n' > "$MARK"; wd
# "cập nhật HH:MM dd/MM" là hợp đồng với .github/scripts/board_heartbeat.py (cron đánh ⚫ khi giờ này cũ).
case "$(last_edit)" in *"⏸️"*"cập nhật "[0-2][0-9]:[0-5][0-9]" "[0-3][0-9]/[01][0-9]) ok "stopped board → ⏸️ with 'cập nhật HH:MM dd/MM' on the Project description" ;; *) fail "stopped board status: '$(last_edit)'" ;; esac
e0=$(edits); wd
[ "$(edits)" = "$e0" ] && ok "same status inside 5 min → no second GitHub write" || fail "status rewritten every check ($(edits) writes)"
rm -f "$MARK"; dead_pid; set_state "$D" halted 79; printf 'read-fail\n' > "$TMP/halt"; wd
case "$(last_edit)" in *"🟠"*) ok "halted board waiting on GitHub → 🟠" ;; *) fail "halt-wait status: '$(last_edit)'" ;; esac
sed -i '' 's/^AT=.*/AT=1/' "$BST"
e0=$(edits); wd
[ "$(edits)" -gt "$e0" ] && ok "same status after 5 min → heartbeat rewrite (fresh time)" || fail "no heartbeat after 5 min"
rm -f "$TMP/halt"; set_state "$D" finished 0; e0=$(edits); STUB_EDIT_FAIL=1 wd; rc=$?
[ "$rc" -eq 0 ] && [ "$(edits)" -gt "$e0" ] && ok "a failing gh project edit does not fail the check" || fail "check rc=$rc with failing gh"
e0=$(edits); wd
[ "$(edits)" -gt "$e0" ] && ok "a failed write is retried on the next check" || fail "failed write not retried"
# Board đang chạy: runner sống (tiến trình tên super-board-run.sh), một worker build #15 sống bắt đầu 75 phút trước, một
# lock của worker đã chết (#16) không được liệt kê.
mkdir -p "$TMP/fake3" "$R/.claude/super-board/inflight"; printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/fake3/super-board-run.sh"
FR3=$( (bash "$TMP/fake3/super-board-run.sh" >/dev/null 2>&1 & echo $!) ); PIDS="$PIDS $FR3"
RS=$(( $(date +%s) - 7200 )); WS=$(( $(date +%s) - 4500 ))   # mốc cố định: test chậm qua phút mới không đổi kỳ vọng
set_state "$FR3" running; sed -i '' "s/^STARTED=.*/STARTED=$RS/" "$STATE"
W15=$(date -u -r "$WS" '+%Y-%m-%dT%H:%M:%SZ')
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$FR3" "$W15" > "$R/.claude/super-board/inflight/15"
dead_pid; printf 'PID=%s\nLANE=qa\nSTARTED=%s\n' "$D" "$W15" > "$R/.claude/super-board/inflight/16"
wd; L=$(last_edit)
case "$L" in *"🟢"*"🔨#15"*"từ $(TZ=Asia/Ho_Chi_Minh date -r "$WS" '+%H:%M')"*"1g15p"*) ok "running board → 🟢, live worker #15 with its start time and 1g15p elapsed" ;;
  *) fail "running status lacks worker start/elapsed: '$L'" ;; esac
case "$L" in *"#16"*) fail "a dead worker's lock (#16) is listed as running" ;; *) ok "a dead worker's lock is not listed" ;; esac
# Từng card: field chữ "Đang chạy" của Project ghi lane + giờ bắt đầu + thời lượng khi worker sống, xoá khi worker dừng.
grep -q "^gh project item-edit --id I_15 --project-id P1 --field-id F_RUN --text 🔨 build · từ $(TZ=Asia/Ho_Chi_Minh date -r "$WS" '+%H:%M') · 1g15p" "$TMP/calls" \
  && ok "card #15 gets its 'Đang chạy' field: lane, start time, elapsed" || fail "card field not written: $(grep 'item-edit' "$TMP/calls" | tail -2 | tr '\n' ' ')"
grep -q -- '--id I_16 .*--text' "$TMP/calls" && fail "card of a dead worker (#16) got a running field" || ok "card of a dead worker gets no running field"
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$D" "$W15" > "$R/.claude/super-board/inflight/15"; wd
grep -q '^gh project item-edit --id I_15 --project-id P1 --field-id F_RUN --clear' "$TMP/calls" \
  && ok "worker of #15 gone → its card field is cleared" || fail "card field not cleared: $(grep 'item-edit' "$TMP/calls" | tail -2 | tr '\n' ' ')"
case "$(last_edit)" in *"không có worker"*) ok "board without live workers says so" ;; *) fail "board text: '$(last_edit)'" ;; esac
# gh (Go) bỏ qua SIGALRM: `perl alarm; exec gh` không cắt được một gh treo (mạng nửa vời sau khi máy thức) và lượt check
# của launchd không bao giờ thoát. Mỗi lệnh gh phải bị giết khi hết giờ.
printf 'KEY=x\nAT=1\n' > "$BST"; t0=$(date +%s)
STUB_GH_HANG=1 SB_BOARD_GH_TIMEOUT=2 wd
[ $(( $(date +%s) - t0 )) -lt 15 ] && ok "a hung gh (ignores SIGALRM) is killed at its timeout" \
  || fail "check waited $(( $(date +%s) - t0 ))s for a hung gh"
# Publish chỉ để hiển thị: đọc card lỗi không được ghi file halt dùng chung (sẽ làm runner và mọi worker dừng).
rm -f "$TMP/halt"; printf 'KEY=x\nAT=1\nFIELD=F_RUN\nCARDS=15\n' > "$BST"
STUB_CARD_HALT=1 wd
[ ! -e "$TMP/halt" ] && ok "a failed card read during publish does not halt the board" || fail "publish wrote the board's GitHub halt file"
rm -f "$TMP/halt"
# CARDS lấy từ file worker ghi được: chỉ nhận số.
printf 'KEY=x\nAT=1\nFIELD=F_RUN\nCARDS=15 * ../x\n' > "$BST"; wd
grep -qE -- '--id I_[^0-9]' "$TMP/calls" && fail "non-numeric CARDS entry used as an issue" || ok "non-numeric CARDS entries ignored"
# Xoá field hỏng (field bị xoá trên GitHub): lượt sau đọc lại id field thay vì thử mãi id cũ.
printf 'KEY=x\nAT=1\nFIELD=F_GONE\nCARDS=15\n' > "$BST"; STUB_ITEM_EDIT_FAIL=1 wd
[ -z "$(field FIELD "$BST")" ] && [ "$(field CARDS "$BST")" = 15 ] && ok "failed clear → field id re-read next time, card kept" \
  || fail "after a failed clear: FIELD='$(field FIELD "$BST")' CARDS='$(field CARDS "$BST")'"
# Runner dừng có chủ đích ở foreground (Ctrl-C, STATE=stopped): ⏸️, không phải 🔴.
dead_pid; set_state "$D" stopped 130; wd
case "$(last_edit)" in *"⏸️"*) ok "foreground stop (STATE=stopped) → ⏸️" ;; *) fail "stopped state status: '$(last_edit)'" ;; esac
set_state "$FR3" running; sed -i '' "s/^STARTED=.*/STARTED=$RS/" "$STATE"
# File halt riêng của publish còn sót (lượt trước bị giết): lượt publish mới vẫn chạy được ngay.
printf 'KEY=x\nAT=1\nFIELD=F_RUN\nCARDS=15\n' > "$BST"; printf '{}' > "$RUNDIR/t.publish-halt.json"
c0=$(grep -c -- '--clear' "$TMP/calls"); wd
[ "$(grep -c -- '--clear' "$TMP/calls")" -gt "$c0" ] && ok "a leftover publish-halt file does not block the next publish" \
  || fail "leftover publish-halt blocked the clear"
# Đọc item-id lỗi (mạng) không phải field hỏng: giữ id field.
printf 'KEY=x\nAT=1\nFIELD=F_RUN\nCARDS=15\n' > "$BST"; STUB_ITEMID_FAIL=1 wd
[ "$(field FIELD "$BST")" = F_RUN ] && [ "$(field CARDS "$BST")" = 15 ] && ok "item-id read failure keeps the field id and the card" \
  || fail "item-id failure: FIELD='$(field FIELD "$BST")' CARDS='$(field CARDS "$BST")'"
# Mô tả dài (nhiều worker) dưới locale C của launchd: cắt theo ký tự, không cắt giữa UTF-8, "cập nhật" vẫn ở cuối.
for i in 31 32 33 34 35 36 37 38 39 40 41 42; do printf 'PID=%s\nLANE=review\nSTARTED=%s\n' "$FR3" "$W15" > "$R/.claude/super-board/inflight/$i"; done
printf 'KEY=x\nAT=1\n' > "$BST"; LC_ALL=C LANG=C wd
last_edit | sed 's/^gh project edit 1 --owner o --description //' > "$TMP/long.txt"
python3 -c "import sys; t=open(sys.argv[1],'rb').read().decode('utf-8'); assert 'cập nhật' in t.split('·')[-1], t; assert '…' in t, t; assert len(t.strip()) <= 230, len(t)" "$TMP/long.txt" 2>/dev/null \
  && ok "long status cut on characters under the C locale, stamp kept at the end" || fail "long status broken: $(cat "$TMP/long.txt")"
for i in 31 32 33 34 35 36 37 38 39 40 41 42; do rm -f "$R/.claude/super-board/inflight/$i"; done
# Watchdog bị dừng (launchd stop, Ctrl-C) khi đang chờ một gh treo: gh không được sống tiếp mồ côi.
printf 'KEY=x\nAT=1\n' > "$BST"
( STUB_GH_HANG=1 SB_BOARD_GH_TIMEOUT=60 wd ) & WDP=$!
rm -f "$TMP/calls.hang"; wait_for 10 '[ -s "$TMP/calls.hang" ]' || true
HANG=$(cat "$TMP/calls.hang" 2>/dev/null); PERLP=$(ps -o ppid= -p "${HANG:-0}" 2>/dev/null | tr -d ' ')   # wrapper = cha của gh giả
[ -n "$PERLP" ] && kill -TERM "$PERLP" 2>/dev/null
if [ -n "$HANG" ] && wait_for 5 '! kill -0 "$HANG" 2>/dev/null'; then ok "TERM to the timeout wrapper also stops the hung gh"
else fail "hung gh left running after the wrapper got TERM (hang=$HANG perl=$PERLP)"; [ -n "$HANG" ] && kill "$HANG" 2>/dev/null; fi
wait "$WDP" 2>/dev/null
# Hết ngân sách publish (nhiều card × 20 s): không gọi thêm gh, card chưa xoá giữ trong CARDS cho lượt sau.
printf 'KEY=x\nAT=1\nFIELD=F_RUN\nCARDS=15\n' > "$BST"; c0=$(grep -c -- '--clear' "$TMP/calls")
BOARD_STATUS_BUDGET=0 wd
[ "$(grep -c -- '--clear' "$TMP/calls")" = "$c0" ] && [ "$(field CARDS "$BST")" = 15 ] \
  && ok "publish budget spent → no more gh calls, card #15 kept for the next check" \
  || fail "budget ignored: clears $(grep -c -- '--clear' "$TMP/calls") (was $c0), CARDS='$(field CARDS "$BST")'"
case "$L" in *"chạy từ $(TZ=Asia/Ho_Chi_Minh date -r "$RS" '+%H:%M')"*) ok "running board shows since when the runner runs" ;; *) fail "runner start missing: '$L'" ;; esac
e0=$(edits); SB_BOARD_STATUS=0 wd
[ "$(edits)" = "$e0" ] && ok "SB_BOARD_STATUS=0 turns the GitHub status off" || fail "SB_BOARD_STATUS=0 still wrote"
kill_tree "$FR3"; rm -f "$WD" "$BST" "$STATE" "$R/.claude/super-board/inflight/15" "$R/.claude/super-board/inflight/16"

[ -f "$BIN/super-board-watchdog.sh" ] && ! sed 's/#.*//' "$BIN/super-board-watchdog.sh" | grep -qE '(^|[^a-z])(pkill|killall)([^a-z]|$)' \
  && ok "watchdog never kills by name" || fail "watchdog missing or uses pkill/killall"

# Runner do watchdog khởi động crash trước tick đầu (đọc board hỏng): bản ghi vẫn mang bộ đếm RUNAWAY đã chuyển sang.
rm -f "$WD"; dead_pid; set_state "$D" crashed 143
start_runner "$TMP/run11.out" SB_WATCHDOG_START=1 SB_DAEMON=1 STUB_CARD_FAIL=1
wait_for 20 '! alive "$RP"' || kill_tree "$RP"
[ "$(field STATE "$STATE")" = crashed ] && [ "$(field NO_PROGRESS "$STATE")" = 4 ] \
  && ok "a restarted runner crashing before its first tick keeps the carried no-progress count (4)" \
  || fail "carried NO_PROGRESS lost: STATE=$(field STATE "$STATE") NO_PROGRESS=$(field NO_PROGRESS "$STATE")"

# ── 8. install / status / uninstall (LaunchAgents và launchctl là stub) ────────────────────────────────────────────
# Repo trong thư mục tạm, không có SB_LAUNCH_AGENTS_DIR: install từ chối, không ghi plist vào ~/Library/LaunchAgents.
case "$TMP/" in
  /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
    out=$( (cd "$R" && run_env SB_LAUNCH_AGENTS_DIR= bash "$BIN/super-board-watchdog.sh" install t) 2>&1 ); rc=$?
    [ "$rc" -ne 0 ] && [ ! -e "$TMP/home/Library/LaunchAgents/$WLABEL.plist" ] && printf '%s' "$out" | grep -q 'refusing to install' \
      && ok "install refuses a temporary checkout (no real LaunchAgent pointing at it)" || fail "install from a temp dir: rc=$rc out=$out" ;;
  *) echo "• skip install-refusal case: TMPDIR ($TMP) is not a known temporary prefix" ;;
esac

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
