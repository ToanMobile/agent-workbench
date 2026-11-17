#!/usr/bin/env bash
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
    if kind.startswith('write'):   # câu của super-board-github-read.py thật cho halt không có lần đọc đã lưu
        print('[github-read] HALT: saved failure needs manual outcome reconciliation before restart', file=sys.stderr)
    sys.exit(79)
# --reconcile (#190): đối chiếu halt do một lần GHI chưa rõ kết quả bằng cách ĐỌC lại GitHub. Loại halt = nội dung file halt giả:
# write-applied = ghi đã xảy ra (lưu trữ halt, exit 0); write-pending = đọc xác minh ghi CHƯA xảy ra (exit 10); write khác =
# không kiểm chứng được (exit 11). Hai loại sau không đụng file halt.
if '--reconcile' in args:
    h = os.environ['STUB_HALT']
    kind = open(h).read().strip() if os.path.exists(h) else ''
    if kind == 'write-applied':
        os.remove(h)
        print('[github-read] reconciled: PR #7 is MERGED', file=sys.stderr)
        sys.exit(0)
    sys.exit(10 if kind == 'write-pending' else 11)
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
  *" items"|items) [ -z "${STUB_ITEMS_FAIL:-}" ] || exit 69; if [ -n "${STUB_ITEMS:-}" ]; then printf '%s\n' "$STUB_ITEMS"; else echo '{"items":[]}'; fi ;;
  *"item-id "*) echo "I_${@: -1}" ;;
  *) echo '{"items":[]}' ;;
esac
SH
printf '#!/usr/bin/env bash\necho %s\n' "'{}'" > "$BIN/super-board-wave-plan.sh"
# Stub thông báo Telegram: ghi lại mỗi lần gửi (watchdog phải báo khi giữ halt vì không kiểm chứng được).
cat > "$BIN/super-board-notify.py" <<'PY'
#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_CALLS"], "a").write("notify " + " ".join(sys.argv[1:]) + "\n")
PY
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

# Múi giờ của board trong test (#150): ca board đang chạy đặt runner bắt đầu 2 giờ trước và mong "HH:MM" (cùng ngày); watchdog in
# "dd/MM HH:MM" cho mốc hôm qua nên từ 00:00 tới 02:00 +07 (và lúc test chạy qua nửa đêm) ca đó đỏ. Giờ +07 từ 03:00 tới 22:59 thì
# dùng +07 như thật, ngoài khung đó dùng UTC (lúc ấy là 16:00–19:59, mốc 2 giờ trước vẫn cùng ngày).
BTZ=Asia/Ho_Chi_Minh
BH=$(TZ="$BTZ" date +%H); [ $((10#$BH)) -ge 3 ] && [ $((10#$BH)) -le 22 ] || BTZ=UTC
ENVV=(-u SB_GITHUB_READ_STRICT -u POSTFIX_GATE_FORCE_FULL -u SB_DAEMON -u SB_WATCHDOG_START -u SB_WATCHDOG_AUTOINSTALL
  -u JAVA_HOME -u ANDROID_HOME -u ANDROID_SDK_ROOT -u STUB_WRITE_MARK -u STUB_CARD_FAIL -u CLAUDE_CONFIG_DIR -u DEVKIT_LANG
  HOME="$TMP/home" PATH="$TMP/stub:$PATH" SB_ACCOUNT_POOL="$TMP/no-pool" SB_STATE_DIR="$TMP/home/sb"
  SB_LAUNCH_AGENTS_DIR="$TMP/LaunchAgents" STUB_HALT="$TMP/halt" STUB_CALLS="$TMP/calls" SB_BOARD_TZ="$BTZ"
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


# ── #1221: watchdog dựng lại runner halt RUNAWAY (chế độ daemon, một lần mỗi giờ), tôn trọng stop marker, giữ nguyên halt khác ──
# Runner giả: ghi SB_DAEMON nó nhận được rồi ngủ, để thấy lần khởi động lại có daemon hay không.
cat > "$BIN/super-board-run.sh" <<'SH'
#!/usr/bin/env bash
echo "daemon=${SB_DAEMON:-unset} wd=${SB_WATCHDOG_START:-unset}" >> "$STUB_CALLS.runner"
sleep 20
SH
chmod +x "$BIN/super-board-run.sh"
wd() { ( cd "$R" && run_env bash "$BIN/super-board-watchdog.sh" check t ) >> "$TMP/wd.out" 2>&1; }
RESTART_FILE="$RUNDIR/t.runaway-restart"
set_state() {   # set_state <pid> <STATE> <RC> [CAUSE]
  mkdir -p "$RUNDIR"
  printf 'PID=%s\nSLUG=t\nSTARTED=1\nDAEMON=0\nLOG=\nSTATE=%s\nRC=%s\nWARN=non-daemon\n' "$1" "$2" "$3" > "$STATE"
  [ -z "${4:-}" ] || printf 'CAUSE=%s\n' "$4" >> "$STATE"
  printf 'ENV_PATH=%s\n' "$TMP/stub:$PATH" >> "$STATE"
  : > "$STUB_CALLS.runner"
  rm -f "$WD" "$WLOG" "$RESTART_FILE" "$MARK"
}
no_runner() { sleep 1; [ ! -s "$STUB_CALLS.runner" ]; }
STUB_CALLS="$TMP/calls"; export STUB_CALLS
dead_pid

# A: halted + CAUSE=runaway, no marker → restarted with SB_DAEMON=1
set_state "$D" halted 0 runaway; wd
if wait_for 8 'grep -q "daemon=1 wd=1" "$STUB_CALLS.runner" 2>/dev/null'; then ok "A: RUNAWAY halt restarted by the watchdog with SB_DAEMON=1"
else fail "A: RUNAWAY halt not restarted in daemon mode ($(cat "$STUB_CALLS.runner" 2>/dev/null) / $(tail -1 "$WLOG" 2>/dev/null))"; fi
# once per hour: a RUNAWAY halt again within the hour is not restarted a second time
set_state "$D" halted 0 runaway; date +%s > "$RESTART_FILE"; wd
no_runner && ok "A2: a second RUNAWAY halt within the hour is not restarted" || fail "A2: restarted twice within the hour"

# B: same as A with the stop marker → never restarted
set_state "$D" halted 0 runaway; printf 'STOPPED_AT=test\n' > "$MARK"; wd
no_runner && ok "B: stop marker present → RUNAWAY halt not restarted" || fail "B: restarted despite the stop marker"

# C: halted for another cause → unchanged, not restarted
set_state "$D" halted 9; wd
no_runner && ok "C: halted rc=9 → not restarted" || fail "C: rc=9 halt restarted"
set_state "$D" halted 0; wd
no_runner && ok "C2: halted without CAUSE=runaway → not restarted" || fail "C2: halt without CAUSE restarted"

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAILED: $FAILS"; exit 1; }
