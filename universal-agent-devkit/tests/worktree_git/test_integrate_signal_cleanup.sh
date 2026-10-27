#!/usr/bin/env bash
# agent-workbench #475: `agent-kit integrate` (scripts/git/integrate.py) chép file bị ignore (dotenv, keystore, google-services.json…)
# vào scratch .claude/worktrees/.integrate-scratch-*. Scratch chỉ được gỡ trong `finally`; bị SIGTERM/SIGINT/SIGKILL thì scratch (kèm
# bản chép secret) và gate con không được dọn.
#  S1 SIGTERM giữa lúc gate treo → exit ≠ 0, scratch + .env đã gỡ, không còn trong `git worktree list`, gate + cháu đã dừng, không push
#  S2 SIGINT, S2b SIGHUP (gate ở phiên riêng không còn nhận HUP của terminal), cùng các khẳng định đó
#  S3 SIGKILL (không handler nào chạy được) → lượt integrate kế tiếp dọn scratch mồ côi
# Mọi chờ đợi đều có hạn; dọn dẹp chỉ kill theo PID test tự ghi lại, không bao giờ theo tên.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; TMP="$(cd -P "$TMP" && pwd -P)"
PIDS=""
cleanup() {
  for p in $PIDS $(cat "$TMP/gate.pid" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export DEVKIT_GATE_SLOTS=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
export INTEGRATE_GATE_LOG="$TMP/gate.log"

# Kit giả như test_agent_kit_integrate.sh; post-fix-gate.py giả: FAKE_GATE_HANG=<dir> → ghi "<pid gate> <pid cháu sleep>" vào
# <dir>/gate.pid rồi treo (gate đang chạy suite); FAKE_GATE_EXIT=<n> → thoát ngay với mã n.
FK="$TMP/kit"; mkdir -p "$FK/bin"
for f in "$DEVKIT_DIR"/bin/*; do [ "$(basename "$f")" = post-fix-gate.py ] || ln -s "$f" "$FK/bin/$(basename "$f")"; done
ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"; ln -s "$DEVKIT_DIR/profiles" "$FK/profiles"; ln -s "$DEVKIT_DIR/hooks" "$FK/hooks"
cat > "$FK/bin/post-fix-gate.py" <<'PY'
import os, subprocess, sys, time
with open(os.environ["INTEGRATE_GATE_LOG"], "a") as f:
    f.write(os.getcwd() + " " + " ".join(sys.argv[1:]) + "\n")
if os.environ.get("FAKE_GATE_EXIT"):
    sys.exit(int(os.environ["FAKE_GATE_EXIT"]))
d = os.environ["FAKE_GATE_HANG"]
kid = subprocess.Popen(["sleep", "120"])   # cháu cùng nhóm tiến trình: một suite đang chạy
with open(os.path.join(d, "gate.pid.tmp"), "w") as f:
    f.write(f"{os.getpid()} {kid.pid}\n")
os.replace(os.path.join(d, "gate.pid.tmp"), os.path.join(d, "gate.pid"))
time.sleep(120)
PY
# Bash không tương tác chạy job nền với SIGINT = SIG_IGN; shim trả SIGINT về mặc định rồi exec, để python nhận SIGINT như ở terminal.
SHIM="$TMP/shim.py"
printf 'import os, signal, sys\nsignal.signal(signal.SIGINT, signal.SIG_DFL)\nos.execvp(sys.argv[1], sys.argv[1:])\n' > "$SHIM"
INTEGRATE_PY="$FK/scripts/git/integrate.py"   # abspath giữ DEVKIT = kit giả → gate giả

M="$TMP/main"; O="$TMP/origin.git"
newrepo() {
  rm -rf "$M" "$O"; : > "$INTEGRATE_GATE_LOG"; rm -f "$TMP/gate.pid"
  mkdir -p "$M/.agents" && G "$M" init -q -b main . && G "$M" config user.email t@t && G "$M" config user.name t
  printf 'exit 0\n' > "$M/check.sh"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.claude/\n.env\n' > "$M/.gitignore"
  G "$M" add -A && G "$M" commit -qm base
  git init -q --bare "$O" && G "$M" remote add origin "$O" && G "$M" push -q -u origin main 2>/dev/null
  printf 'PLACEHOLDER=1\n' > "$M/.env"   # file bị ignore mà copy_local_config chép vào scratch (không phải secret thật)
  echo a >> "$M/work.txt" && G "$M" add work.txt && G "$M" commit -qm a
}
origin_head() { git --git-dir="$O" rev-parse main; }
alive() { kill -0 "$1" 2>/dev/null; }
wait_until() {   # wait_until <giây> <lệnh…>: 0 khi lệnh đúng trước hạn
  local end=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -lt "$end" ]; do "$@" && return 0; sleep 0.2; done
  "$@"
}
dead() { ! alive "$1"; }
start_hanging() {   # integrate nền, chờ gate giả treo; đặt IPID, GPID, KPID, SCRATCH
  (cd "$M" && FAKE_GATE_HANG="$TMP" exec python3 "$SHIM" python3 "$INTEGRATE_PY" > "$TMP/out" 2>&1) & IPID=$!
  PIDS="$PIDS $IPID"
  wait_until 90 test -s "$TMP/gate.pid" || { fail "gate giả không khởi động: $(tail -5 "$TMP/out")"; return 1; }
  read -r GPID KPID < "$TMP/gate.pid"
  SCRATCH="$(head -1 "$INTEGRATE_GATE_LOG" | cut -d' ' -f1)"
  [ -f "$SCRATCH/.env" ] || { fail "tiền đề: scratch $SCRATCH không có .env chép từ main"; return 1; }
}

sigcase() {   # sigcase <TERM|INT|HUP> <tên ca>
  newrepo; o0="$(origin_head)"
  start_hanging || return
  kill -"$1" "$IPID"
  wait_until 30 dead "$IPID"; alive "$IPID" && kill -9 "$IPID"
  wait "$IPID"; rc=$?
  wait_until 15 dead "$GPID"; wait_until 5 dead "$KPID"
  local why=""
  [ "$rc" != 0 ] || why="$why rc=0;"
  [ ! -e "$SCRATCH/.env" ] || why="$why .env còn;"
  [ ! -d "$SCRATCH" ] || why="$why scratch còn;"
  ! G "$M" worktree list | grep -q "integrate-scratch" || why="$why còn trong worktree list;"
  [ "$(origin_head)" = "$o0" ] || why="$why đã push;"
  dead "$GPID" || why="$why gate $GPID còn chạy;"
  dead "$KPID" || why="$why cháu $KPID còn chạy;"
  [ -z "$why" ] && ok "$2: exit $rc, scratch + .env đã gỡ, gate và cháu đã dừng, không push" \
    || fail "$2:$why out: $(tail -3 "$TMP/out")"
  kill -9 "$GPID" "$KPID" 2>/dev/null; rm -f "$TMP/gate.pid"
}

sigcase TERM "S1 SIGTERM"
sigcase INT "S2 SIGINT"
sigcase HUP "S2b SIGHUP (terminal đóng)"

# S3 SIGKILL: không handler nào chạy; lượt sau (gate đỏ giả, không push) phải dọn scratch mồ côi của lượt bị giết
newrepo; o0="$(origin_head)"
if start_hanging; then
  kill -9 "$IPID"; wait "$IPID" 2>/dev/null
  kill -9 "$GPID" "$KPID" 2>/dev/null; wait_until 10 dead "$GPID"
  if [ -f "$SCRATCH/.env" ]; then
    : > "$INTEGRATE_GATE_LOG"
    (cd "$M" && FAKE_GATE_EXIT=1 python3 "$INTEGRATE_PY" > "$TMP/out2" 2>&1); rc=$?
    left="$(ls -A "$M/.claude/worktrees" 2>/dev/null | grep -c '^\.integrate-scratch-')"
    [ "$rc" = 1 ] && [ ! -d "$SCRATCH" ] && [ "$left" = 0 ] && [ "$(origin_head)" = "$o0" ] \
      && ! G "$M" worktree list | grep -q "integrate-scratch" \
      && ok "S3 SIGKILL: lượt integrate sau dọn scratch mồ côi (kèm .env), không push" \
      || fail "S3: rc $rc, scratch cũ còn: $([ -d "$SCRATCH" ] && echo có || echo không), scratch còn lại $left, out: $(tail -3 "$TMP/out2")"
  else
    fail "S3 tiền đề: sau SIGKILL scratch $SCRATCH phải còn .env"
  fi
fi

[ "$FAILS" = 0 ] && echo "ALL OK" && exit 0
echo "$FAILS FAILED"; exit 1
