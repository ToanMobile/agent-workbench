#!/usr/bin/env bash
# agent-workbench #480: `agent-kit integrate` ran integrate.py as a child of the bash dispatcher (no exec), so a SIGTERM/SIGINT sent
# to the agent-kit pid killed only bash: integrate.py and its gate --full went on and could still push main; the #475 handlers never
# saw the signal. The dispatcher now execs python, so the signal reaches integrate.py itself.
#  E1 SIGTERM to the agent-kit pid while the gate hangs -> exit 143, gate + grandchild stopped, scratch gone, nothing pushed
#  E2 SIGINT, same assertions
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

# Fake kit: real agent-kit copy + real scripts, a fake post-fix-gate.py that records "<gate pid> <grandchild pid>" and hangs.
FK="$TMP/kit"; mkdir -p "$FK/bin"
for f in "$DEVKIT_DIR"/bin/*; do [ "$(basename "$f")" = post-fix-gate.py ] || ln -s "$f" "$FK/bin/$(basename "$f")"; done
rm -f "$FK/bin/agent-kit" && cp "$DEVKIT_DIR/bin/agent-kit" "$FK/bin/agent-kit"
ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"; ln -s "$DEVKIT_DIR/profiles" "$FK/profiles"; ln -s "$DEVKIT_DIR/hooks" "$FK/hooks"
ln -s "$DEVKIT_DIR/completions" "$FK/completions"
cat > "$FK/bin/post-fix-gate.py" <<'PY'
import os, subprocess, sys, time
with open(os.environ["INTEGRATE_GATE_LOG"], "a") as f:
    f.write(os.getcwd() + " " + " ".join(sys.argv[1:]) + "\n")
d = os.environ["FAKE_GATE_HANG"]
kid = subprocess.Popen(["sleep", "120"])
with open(os.path.join(d, "gate.pid.tmp"), "w") as f:
    f.write(f"{os.getpid()} {kid.pid}\n")
os.replace(os.path.join(d, "gate.pid.tmp"), os.path.join(d, "gate.pid"))
time.sleep(120)
PY
# A non-interactive bash runs background jobs with SIGINT ignored; restore the default, then exec, so python sees SIGINT as at a terminal.
SHIM="$TMP/shim.py"
printf 'import os, signal, sys\nsignal.signal(signal.SIGINT, signal.SIG_DFL)\nos.execvp(sys.argv[1], sys.argv[1:])\n' > "$SHIM"
AK="$FK/bin/agent-kit"

M="$TMP/main"; O="$TMP/origin.git"
newrepo() {
  rm -rf "$M" "$O"; : > "$INTEGRATE_GATE_LOG"; rm -f "$TMP/gate.pid"
  mkdir -p "$M/.agents" && G "$M" init -q -b main . && G "$M" config user.email t@t && G "$M" config user.name t
  printf 'exit 0\n' > "$M/check.sh"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.claude/\n.env\n' > "$M/.gitignore"
  G "$M" add -A && G "$M" commit -qm base
  git init -q --bare "$O" && G "$M" remote add origin "$O" && G "$M" push -q -u origin main 2>/dev/null
  printf 'PLACEHOLDER=1\n' > "$M/.env"
  echo a >> "$M/work.txt" && G "$M" add work.txt && G "$M" commit -qm a
}
origin_head() { git --git-dir="$O" rev-parse main; }
alive() { kill -0 "$1" 2>/dev/null; }
dead() { ! alive "$1"; }
wait_until() {
  local end=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -lt "$end" ]; do "$@" && return 0; sleep 0.2; done
  "$@"
}

sigcase() {   # sigcase <TERM|INT> <name>
  newrepo; local o0; o0="$(origin_head)"
  (cd "$M" && FAKE_GATE_HANG="$TMP" exec python3 "$SHIM" bash "$AK" integrate > "$TMP/out" 2>&1) & local apid=$!
  PIDS="$PIDS $apid"
  wait_until 90 test -s "$TMP/gate.pid" || { fail "$2: fake gate did not start: $(tail -5 "$TMP/out")"; return; }
  local gpid kpid scratch
  read -r gpid kpid < "$TMP/gate.pid"
  scratch="$(head -1 "$INTEGRATE_GATE_LOG" | cut -d' ' -f1)"
  kill -"$1" "$apid"
  wait_until 30 dead "$apid"; alive "$apid" && kill -9 "$apid"
  wait "$apid"; local rc=$?
  wait_until 15 dead "$gpid"; wait_until 5 dead "$kpid"
  local why=""
  [ "$rc" = 143 ] || [ "$1" != TERM ] || why="$why rc=$rc (want 143);"
  [ "$rc" != 0 ] || why="$why rc=0;"
  [ ! -d "$scratch" ] || why="$why scratch still there;"
  dead "$gpid" || why="$why gate $gpid still running;"
  dead "$kpid" || why="$why grandchild $kpid still running;"
  [ "$(origin_head)" = "$o0" ] || why="$why pushed;"
  [ -z "$why" ] && ok "$2: exit $rc, gate + grandchild stopped, scratch gone, no push" || fail "$2:$why out: $(tail -3 "$TMP/out")"
  kill -9 "$gpid" "$kpid" 2>/dev/null; rm -f "$TMP/gate.pid"
}

sigcase TERM "E1 SIGTERM to the agent-kit pid"
sigcase INT "E2 SIGINT to the agent-kit pid"

[ "$FAILS" = 0 ] && echo "ALL OK" && exit 0
echo "$FAILS FAILED"; exit 1
