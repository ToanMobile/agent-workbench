#!/usr/bin/env bash
# Regression test (second review of the A15 lane, 2026-10-15): the run that holds NO test_run.lock.
# bin/post-fix-gate.py re-uses suites from the full-pass receipt; a run that re-used EVERY suite and did not get the lock within the short wait
# (DEVKIT_REUSE_LOCK_WAIT_S, default 3 s) is READ-ONLY: it judges by a stamp check and writes nothing. Invariant F1 = a FAIL that a forced run
# persisted is never turned back into a PASS by a stale reader or writer.
#   P2  a Stop-style run that holds no lock and ends exit 2 (an unwatched file) still went through the PARTIAL receipt writer: it LOADED full_pass.json
#       and os.replace()d it as exit 2 with the suites' PASS rows. A forced run B that holds the lock, FAILS REG-1 and deletes the receipt exactly
#       between that load and that replace got the receipt back as "exit=2 REG-1=PASS": cached_full_pass accepts exit 2, so the next --full re-used the
#       failing REG-1 and wrote an exit-0 receipt (B is applied by a launcher around the gate's own main(), the way a real B would land: no sleep race).
#       The rule: a run without the lock never replaces the receipt; where the writer would have turned it from exit 0 to exit 2 it DROPS it (fail
#       closed: XONG and push are refused either way, only the suites' reuse is lost). A run that took no lock because it had nothing to re-use or to
#       run holds no handle either (a second matrix that matches nothing): the same rule, keyed on the handle, not on "the wait ran out".
#         inside  B's FAIL lands between A's load and A's write       (the interleaving under test)
#         before  B persisted its FAIL a moment earlier               (control: safe before and after)
#       Each row checks the receipt after A (none), that A made no os.replace onto it, and what the next --full does (REG-1 runs and FAILS, exit 1).
#   W   a run that still has a suite to RUN waits TEST_RUN_LOCK_WAIT_S for the lock, not DEVKIT_REUSE_LOCK_WAIT_S (that short wait is for a run with
#       nothing left to run): the lock is held ~4 s, REG-1 is re-used, REG-2 must run: exit 0 with REG-2 run once; a run that gave up after the
#       short wait ended exit 4 BUSY and ran nothing.
#   V   a read-only run that exits 0 wrote no receipt, so it is not an acceptance: --json says "accepted": false and the verdict says so; the control
#       (the lock is free) is accepted. The run log (runs.jsonl) says busy=false for it (it is no lock wait), busy=true for a run that ended BUSY and for
#       a run whose re-used PASS went STALE: the same formula as the --json summary.
#   F   a FORCED read-only run that ends exit != 0 (--full, an unwatched file: exit 2) must not leave the exit-0 receipt of the same content standing
#       either: it writes nothing new and only drops it; the control (exit 0) leaves the receipt it re-used untouched.
#   N   DEVKIT_REUSE_LOCK_WAIT_S and TEST_RUN_LOCK_WAIT_S that are not finite numbers (nan, inf) fall back to their defaults, as an unparsable value
#       does: min(45, nan) is 45 (the long wait for a run that has nothing to run) and a nan deadline never expires (the run waits for ever).
#         row 1  every suite re-used, the lock held, TEST_RUN_LOCK_WAIT_S=nan: the run goes read-only after the short wait (it hung until killed)
#         row 2  the lock released after 5 s, DEVKIT_REUSE_LOCK_WAIT_S=nan | inf, TEST_RUN_LOCK_WAIT_S=10: the run gives up after the default 3 s and
#                is read-only (it waited 10 s, got the lock at 5 s and was not read-only)
#         row 3  acquire_test_run_lock itself, on a clock that jumps: nan / inf / abc / "" wait the default 900 s, -1 / 0 try once
# The seeds run with --no-checklist. bash 3.2 and Python 3.9 compatible; every gate run is under a hard timeout (tlimit.py kills the whole group);
# ROREC_KIT=<kit dir> tests another copy of the kit (a mutant must go red); PYGATE=/usr/bin/python3 runs the gate under another Python.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_UNITY_REUSE_MAX_S GATE_TOTAL_BUDGET_S TEST_RUN_LOCK_WAIT_S DEVKIT_IMPACTED_SINCE DEVKIT_REUSE_LOCK_WAIT_S
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${ROREC_KIT:-$DEVKIT_DIR}"
GATE="$KIT/bin/post-fix-gate.py"
PY="${PYGATE:-python3}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
HOLDER=""
trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
RC=0

# hard timeout: the command runs in its own process group, which is killed (TERM, then KILL) past the limit; exit 124 then
cat > "$TMP/tlimit.py" <<'PY'
import os, signal, subprocess, sys, time
limit = float(sys.argv[1])
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    rc = p.wait(timeout=limit)
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:   # macOS refuses a signal to a group that holds a zombie: signal the child itself
            try:
                p.send_signal(sig)
            except OSError:
                pass
        time.sleep(1)
    p.wait()
    rc = 124
sys.exit(rc)
PY
tl() { python3 -I "$TMP/tlimit.py" "$@"; }
tl 60 true >/dev/null 2>&1   # warm the interpreter and the wrapper once

make_repo() { # the same tree for every row: REG-1 / REG-2 watch app/*, lib/Other.kt is no rule's file (every Stop-style verdict is exit 2)
  rm -rf "$R" "$MARK" && mkdir -p "$R/app/src/main/kotlin/pkg" "$R/tests" "$MARK" "$R/lib" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'echo x >> "$MARK/s1"\nexit "${FAIL1:-0}"\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\nexit "${EXIT2:-0}"\n' > tests/s2.sh
  printf '{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"REG-1","command":"sh tests/s1.sh"},{"id":"REG-2","name":"REG-2","command":"sh tests/s2.sh","untested_exit":2}]}]}\n' > matrix.json
  # a second matrix that matches nothing in this change: a run under it has nothing to re-use and nothing to run, so it takes no lock at all
  printf '{"project":"t","rules":[{"component":"Nothing","watch_files":["nothing/*"],"mandatory_regression_tests":[{"id":"REG-X","name":"REG-X","command":"sh tests/s1.sh"}]}]}\n' > matrix2.json
  git add -A && git commit -qm init
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  [ "${1:-}" = unwatched ] && echo "class Other" > lib/Other.kt
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
run_gate() { # NAME=value words, then "--" and the flags; output in $TMP/out.txt, exit in RC
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  tl 240 env CLAUDE_PROJECT_DIR="$R" ${envs[@]+"${envs[@]}"} "$PY" "$GATE" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} > "$TMP/out.txt" 2>&1; RC=$?
}
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
state() { python3 -I -c 'import json,sys
try:
    d = json.load(open(sys.argv[1])); print("exit=%s" % d.get("exit"), ",".join("%s=%s" % (t["id"], t["status"]) for t in d["tests"]), "untested=" + ",".join(d.get("untested") or []))
except (OSError, ValueError): print("none")' "$1"; }
rtime() { python3 -I -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("time"))
except (OSError, ValueError): print("none")' "$GD/full_pass.json"; }
# the last line of the run log (<git dir>/postfix-gate/runs.jsonl): "busy verdict"
lastlog() { python3 -I -c 'import json,sys
try:
    r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]; print(str(r.get("busy")).lower(), r.get("verdict"))
except (OSError, ValueError, IndexError): print("none none")' "$GD/runs.jsonl"; }

# a stub that holds test_run.lock until told to let go (or for ever): the forced run B that is still running
hold_lock() { # $1 = release file
  rm -f "$TMP/lock.held" "$1"
  python3 -I - "$R" "$TMP/lock.held" "$1" <<'PY' &
import fcntl, os, sys, time
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    for _ in range(1200):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
  HOLDER=$!
  local i=0; while [ ! -f "$TMP/lock.held" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}
release_lock() { touch "$TMP/lock.release"; [ -z "$HOLDER" ] || { wait "$HOLDER" 2>/dev/null; HOLDER=""; }; }

# A launcher around the gate's own main(), driven by the environment:
#   RACE_RELEASE_AFTER=N  a timer lets the lock stub go N s after the run's FIRST ask for the lock (a clock that runs from A's own request holds up
#                         under load better than a sleep counted from the start)
#   PW_WHEN=inside|before the forced run B FAILS REG-1 and deletes full_pass.json (+ budget_pass.json), what write_full_pass_receipt(exit 1) and
#                         drop_budget_record do: right AFTER the receipt writer loaded the file (inside: between its load and its write), or right BEFORE
#                         it did (before); a writer that never loads it gets B's FAIL right after it returned (inside) so a design that reads nothing
#                         is not a false red
#   PW_REPLACES=<file>    every os.replace onto full_pass.json appends a line (what was written without the lock)
#   RACE_STALE=1          the files go at the first run_performance_audit call (after the suites, before the verdict): the re-used PASS turns STALE
cat > "$TMP/launcher.py" <<'PY'
import importlib.util, os, sys, threading
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_ro", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_ro"] = m
spec.loader.exec_module(m)
env = os.environ

def b_fails():
    for f in ("full_pass.json", "budget_pass.json"):
        try:
            os.remove(os.path.join(env["PW_GD"], f))
        except FileNotFoundError:
            pass
    open(env["PW_FIRED"], "a").write("removed\n")

if env.get("RACE_RELEASE_AFTER"):
    real_acq, asked = m.acquire_test_run_lock, []
    def acq(*a, **k):
        if not asked:
            asked.append(1)
            threading.Timer(float(env["RACE_RELEASE_AFTER"]), lambda: open(env["RACE_RELEASE"], "w").close()).start()
        return real_acq(*a, **k)
    m.acquire_test_run_lock = acq

when = env.get("PW_WHEN")
if when:
    real_load, real_write, fired = m._load_state_json, m.write_full_pass_receipt, []
    def load(path, *a, **k):
        if not fired and sys._getframe(1).f_code.co_name == "write_full_pass_receipt":
            fired.append(1)
            if when == "before":
                b_fails()
                return real_load(path, *a, **k)
            v = real_load(path, *a, **k)
            b_fails()
            return v
        return real_load(path, *a, **k)
    def write(*a, **k):
        try:
            return real_write(*a, **k)
        finally:
            if not fired:
                fired.append(1)
                b_fails()
    m._load_state_json, m.write_full_pass_receipt = load, write

if env.get("PW_REPLACES"):
    real_replace = os.replace
    def replace(src, dst, *a, **k):
        if os.path.basename(str(dst)) == "full_pass.json":
            open(env["PW_REPLACES"], "a").write("replace\n")
        return real_replace(src, dst, *a, **k)
    os.replace = replace

if env.get("RACE_STALE"):
    real_audit, done = m.run_performance_audit, []
    def audit(*a, **k):
        if not done:
            done.append(1)
            for f in ("full_pass.json", "budget_pass.json"):
                try:
                    os.remove(os.path.join(env["PW_GD"], f))
                except FileNotFoundError:
                    pass
        return real_audit(*a, **k)
    m.run_performance_audit = audit
sys.exit(m.main())
PY
a_run() { # $1 = stop | full, then NAME=value words (this one run's environment; the later word wins); output $TMP/a.out, exit $TMP/a.rc
  local mode="$1"; shift
  local envs=(FAIL1=0 EXIT2=0) flags=(--json)   # --json: its "busy" and "accepted" are what the Stop hook and the callers read
  if [ "$mode" = stop ]; then envs+=(GATE_TOTAL_BUDGET_S=900); else flags+=(--full); fi
  tl "${A_TL:-240}" env CLAUDE_PROJECT_DIR="$R" "${envs[@]}" PW_GD="$GD" PW_FIRED="$TMP/fired" RACE_RELEASE="$TMP/lock.release" "$@" \
     "$PY" "$TMP/launcher.py" "$GATE" --matrix "${A_MATRIX:-$R/matrix.json}" --lang en --run-tests "${flags[@]}" > "$TMP/a.out" 2>&1
  echo $? > "$TMP/a.rc"
}
seed_pass() { run_gate -- --full --no-checklist --allow-no-tests; SEED_RC=$RC; SEED_STATE="$(state "$GD/full_pass.json")"; }
seed_ok() { # $1 label
  if [ "$SEED_RC" = 0 ] && [ "$SEED_STATE" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; then return 0; fi
  bad "$1: setup went wrong: seed rc=$SEED_RC state='$SEED_STATE'"; return 1
}

# P2: B's FAIL lands between A's load of the receipt and A's write. $1 inside | before, $2 readonly (the lock is held, A gives up after 1 s) | nolock
pw() {
  local when="$1" kind="$2" label="P2/$2/$1"
  make_repo unwatched; seed_pass; seed_ok "$label" || return
  local s1_0; s1_0=$(runs s1); rm -f "$TMP/fired" "$TMP/replaces"
  local matrix="$R/matrix.json"; [ "$kind" = nolock ] && matrix="$R/matrix2.json"
  [ "$kind" = readonly ] && hold_lock "$TMP/lock.release"
  A_MATRIX="$matrix" a_run stop FAIL1=1 DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=1 PW_WHEN="$when" PW_REPLACES="$TMP/replaces"
  release_lock
  local a_rc a_runs a_state a_repl a_trace f_rc f_runs f_state f_reused
  a_rc="$(cat "$TMP/a.rc")"; a_runs=$(( $(runs s1) - s1_0 )); a_state="$(state "$GD/full_pass.json")"
  a_repl=$([ -f "$TMP/replaces" ] && wc -l < "$TMP/replaces" | tr -d ' ' || echo 0); a_trace=$(grep -c Traceback "$TMP/a.out")
  local read_only_line; read_only_line=$(grep -c 'wrote nothing' "$TMP/a.out")
  # the next --full, as B found REG-1 failing: does REG-1 run (exit 1) or is the failing suite re-used?
  local s1_1; s1_1=$(runs s1)
  run_gate FAIL1=1 -- --full --no-checklist --allow-no-tests; f_rc=$RC; f_runs=$(( $(runs s1) - s1_1 )); f_state="$(state "$GD/full_pass.json")"
  f_reused=$(grep -c 'reusing the full PASS' "$TMP/out.txt")
  if [ "$kind" = readonly ] && [ "$read_only_line" = 0 ]; then bad "$label: setup went wrong: A was not read-only (no 'wrote nothing' line)"; tail -5 "$TMP/a.out"; return; fi
  if [ "$a_rc" = 2 ] && [ "$a_runs" = 0 ] && [ "$a_state" = none ] && [ "$a_repl" = 0 ] && [ "$a_trace" = 0 ] \
     && [ "$f_rc" = 1 ] && [ "$f_runs" = 1 ] && [ "$f_reused" = 0 ] && [ "$f_state" = none ]; then
    ok "$label: a run without the lock ended exit 2 and left NO receipt (no os.replace onto it); the next --full ran REG-1 and failed (exit 1), it did not re-use the PASS B had removed"
  else
    bad "$label: A exit $a_rc (want 2), REG-1 ran $a_runs (want 0), receipt after A '$a_state' (want none), os.replace onto it $a_repl (want 0), tracebacks $a_trace; next --full exit $f_rc (want 1), REG-1 ran $f_runs (want 1), re-used $f_reused (want 0), receipt after it '$f_state' (want none: a FAIL)"
  fi
}
pw inside readonly; pw before readonly; pw inside nolock; pw before nolock

# W: a run that still has a suite to RUN waits TEST_RUN_LOCK_WAIT_S for the lock, not the short wait
w() { # $1 label, $2 the lock is released this many seconds after A's first ask
  make_repo; run_gate GATE_TOTAL_BUDGET_S=900 EXIT2=2 -- --no-checklist; local seed_rc=$RC
  local s1_0 s2_0; s1_0=$(runs s1); s2_0=$(runs s2)
  hold_lock "$TMP/lock.release"
  a_run stop EXIT2=0 DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=20 RACE_RELEASE_AFTER="$2"
  release_lock
  local a_rc a_s1 a_s2
  a_rc="$(cat "$TMP/a.rc")"; a_s1=$(( $(runs s1) - s1_0 )); a_s2=$(( $(runs s2) - s2_0 ))
  if [ "$seed_rc" != 4 ] || ! grep -q "reusing the suites that passed" "$TMP/a.out"; then bad "$1: setup went wrong: seed rc=$seed_rc (want 4), A re-used nothing"; tail -5 "$TMP/a.out"; return; fi
  if [ "$a_rc" = 0 ] && [ "$a_s1" = 0 ] && [ "$a_s2" = 1 ] && grep -q '"busy": false' "$TMP/a.out"; then
    ok "$1: REG-1 re-used, REG-2 still to run: A waited the long wait ($2 s of 20), got the lock, ran REG-2, exit 0"
  else
    bad "$1: A exit $a_rc (want 0), REG-1/REG-2 ran $a_s1/$a_s2 (want 0/1), busy true lines: $(grep -c '"busy": true' "$TMP/a.out") (a run that gave up after DEVKIT_REUSE_LOCK_WAIT_S ends exit 4 BUSY)"
  fi
}
w "W/suite-left-to-run" 4

# V: a read-only run that exits 0 wrote no receipt: not an acceptance, not a lock wait in the run log
v_readonly() { # $1 label, $2 A (full | stop)
  make_repo; run_gate -- --full --no-checklist; local seed_rc=$RC; local t0; t0="$(rtime)"
  hold_lock "$TMP/lock.release"
  a_run "$2" DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=10
  release_lock
  local a_rc t1 log text_ok=yes; a_rc="$(cat "$TMP/a.rc")"; t1="$(rtime)"; log="$(lastlog)"
  if [ "$seed_rc" != 0 ] || ! grep -q 'wrote nothing' "$TMP/a.out"; then bad "$1: setup went wrong: seed rc=$seed_rc, A read-only lines: $(grep -c 'wrote nothing' "$TMP/a.out")"; tail -5 "$TMP/a.out"; return; fi
  # the verdict of a forced run is worded for what it is; a Stop-style run's PASS line is the one every Stop-style run prints
  if [ "$2" = full ]; then grep -q 'NOT READY FOR ACCEPTANCE' "$TMP/a.out" && ! grep -q 'PASS — READY FOR ACCEPTANCE' "$TMP/a.out" || text_ok=no; fi
  if [ "$a_rc" = 0 ] && [ "$t1" = "$t0" ] && grep -q '"accepted": false' "$TMP/a.out" && [ "$text_ok" = yes ] && [ "$log" = "false REUSED" ]; then
    ok "$1: the read-only run ends exit 0 but is NOT accepted: \"accepted\": false$([ "$2" = full ] && echo ', the verdict says NOT READY FOR ACCEPTANCE'), no receipt written, run log busy/verdict '$log'"
  else
    bad "$1: A exit $a_rc (want 0), receipt time $t0 -> $t1 (want unchanged), accepted:false lines $(grep -c '"accepted": false' "$TMP/a.out") (want 1), verdict worded as not accepted: $text_ok (a forced run: 'NOT READY FOR ACCEPTANCE', no 'PASS — READY'), run log '$log' (want 'false REUSED')"
  fi
}
v_readonly "V/full/read-only" full
v_readonly "V/stop/read-only" stop
# control: the lock is free, a forced run that re-used everything is accepted and says so
make_repo; run_gate -- --full --no-checklist; v_seed=$RC
a_run full DEVKIT_REUSE_LOCK_WAIT_S=1
v_rc="$(cat "$TMP/a.rc")"; v_log="$(lastlog)"
if [ "$v_seed" = 0 ] && [ "$v_rc" = 0 ] && grep -q '"accepted": true' "$TMP/a.out" && grep -q 'PASS — READY FOR ACCEPTANCE & HANDOVER' "$TMP/a.out" && [ "$v_log" = "false REUSED" ]; then
  ok "V/full/free control: the lock is free: accepted: true, 'PASS — READY FOR ACCEPTANCE & HANDOVER', run log '$v_log'"
else
  bad "V/full/free control: exit $v_rc (want 0), accepted:true lines $(grep -c '"accepted": true' "$TMP/a.out"), READY lines $(grep -c 'PASS — READY FOR ACCEPTANCE & HANDOVER' "$TMP/a.out"), run log '$v_log' (want 'false REUSED')"
fi
# the run log's busy is true for a run that ended BUSY (a suite left to run, the lock held) ...
make_repo; run_gate GATE_TOTAL_BUDGET_S=900 EXIT2=2 -- --no-checklist; b_seed=$RC
hold_lock "$TMP/lock.release"
a_run stop EXIT2=0 TEST_RUN_LOCK_WAIT_S=1
release_lock
b_rc="$(cat "$TMP/a.rc")"; b_log="$(lastlog)"
if [ "$b_seed" = 4 ] && [ "$b_rc" = 4 ] && [ "$b_log" = "true BUSY" ]; then
  ok "V/log/busy control: a run with a suite left to run that met the held lock ended BUSY (exit 4): run log '$b_log'"
else
  bad "V/log/busy control: seed rc=$b_seed (want 4), A exit $b_rc (want 4), run log '$b_log' (want 'true BUSY')"
fi
# ... and for a run whose re-used PASS went STALE (the file that vouched for it was deleted after the suites): another run interfered
make_repo; run_gate -- --full --no-checklist; s_seed=$RC
a_run stop RACE_STALE=1
s_rc="$(cat "$TMP/a.rc")"; s_log="$(lastlog)"
if [ "$s_seed" = 0 ] && [ "$s_rc" = 4 ] && grep -q '"busy": true' "$TMP/a.out" && [ "$s_log" = "true UNTESTED" ]; then
  ok "V/log/stale: a run whose re-used PASS went STALE ended exit 4, --json busy true, run log '$s_log' (the same formula)"
else
  bad "V/log/stale: seed rc=$s_seed (want 0), A exit $s_rc (want 4), json busy true lines $(grep -c '"busy": true' "$TMP/a.out"), run log '$s_log' (want 'true UNTESTED')"
fi

# F: a FORCED read-only run (--full, every suite re-used, the lock held past the short wait) that ends exit != 0 must not leave the exit-0 receipt of the
# same content standing either (a guard that let only Stop-style runs through left it exit 0, so XONG and push stood on a receipt the run contradicts).
# It writes nothing new (no os.replace onto the receipt: a lock-less replace that carries a re-used PASS could put a PASS back) and only DROPS it.
f_forced() { # $1 label, $2 exit2 (an unwatched file: the verdict is exit 2) | exit0 (control: the verdict is exit 0, the receipt is the PASS it re-used)
  if [ "$2" = exit2 ]; then make_repo unwatched; else make_repo; fi
  seed_pass; seed_ok "$1" || return
  local t0 t1 a_rc a_state a_repl; t0="$(rtime)"; rm -f "$TMP/replaces"
  hold_lock "$TMP/lock.release"
  a_run full DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=10 PW_REPLACES="$TMP/replaces"
  release_lock
  a_rc="$(cat "$TMP/a.rc")"; a_state="$(state "$GD/full_pass.json")"; t1="$(rtime)"
  a_repl=$([ -f "$TMP/replaces" ] && wc -l < "$TMP/replaces" | tr -d ' ' || echo 0)
  if ! grep -q 'wrote nothing' "$TMP/a.out"; then bad "$1: setup went wrong: A was not read-only (no 'wrote nothing' line)"; tail -5 "$TMP/a.out"; return; fi
  if [ "$2" = exit2 ]; then
    if [ "$a_rc" = 2 ] && [ "$a_state" = none ] && [ "$a_repl" = 0 ] && grep -q '"accepted": false' "$TMP/a.out" && ! grep -q Traceback "$TMP/a.out"; then
      ok "$1: a forced read-only run ended exit 2: the exit-0 receipt is dropped (not left standing, nothing written), accepted: false"
    else
      bad "$1: A exit $a_rc (want 2), receipt after A '$a_state' (want none), os.replace onto it $a_repl (want 0), accepted:false lines $(grep -c '"accepted": false' "$TMP/a.out") (want 1)"
    fi
  else
    if [ "$a_rc" = 0 ] && [ "$a_state" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ] && [ "$t1" = "$t0" ] && [ "$a_repl" = 0 ]; then
      ok "$1 control: a forced read-only run that ended exit 0 left the receipt it re-used byte for byte (time unchanged, nothing written)"
    else
      bad "$1 control: A exit $a_rc (want 0), receipt after A '$a_state', time $t0 -> $t1 (want unchanged), os.replace onto it $a_repl (want 0)"
    fi
  fi
}
f_forced "F/forced/read-only/exit2" exit2
f_forced "F/forced/read-only/exit0" exit0

# N: values that are not finite numbers
# row 1: every suite re-used, the lock held for ever (until the test lets go), TEST_RUN_LOCK_WAIT_S=nan: read-only after the short wait
for bad_val in nan; do
  make_repo; seed_pass; seed_ok "N/long=$bad_val" || continue
  hold_lock "$TMP/lock.release"
  A_TL=60 a_run stop DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S="$bad_val"
  release_lock
  n_rc="$(cat "$TMP/a.rc")"
  if [ "$n_rc" = 0 ] && grep -q 'wrote nothing' "$TMP/a.out"; then
    ok "N/long=$bad_val: TEST_RUN_LOCK_WAIT_S=$bad_val is the default, not a deadline that never expires: the run went read-only after the short wait (exit 0)"
  else
    bad "N/long=$bad_val: A exit $n_rc (want 0; 124 = it waited for the lock until it was killed), read-only lines $(grep -c 'wrote nothing' "$TMP/a.out") (want 1)"
  fi
done
# row 2: the lock is released 5 s after A asks; DEVKIT_REUSE_LOCK_WAIT_S that is no finite number is the default 3 s: A gives up first, writes nothing
for bad_val in nan inf; do
  make_repo; run_gate -- --full --no-checklist; n_seed=$RC; t0="$(rtime)"
  hold_lock "$TMP/lock.release"
  a_run stop DEVKIT_REUSE_LOCK_WAIT_S="$bad_val" TEST_RUN_LOCK_WAIT_S=10 RACE_RELEASE_AFTER=5
  release_lock
  n_rc="$(cat "$TMP/a.rc")"; t1="$(rtime)"
  if [ "$n_seed" = 0 ] && [ "$n_rc" = 0 ] && [ "$t1" = "$t0" ] && grep -q 'wrote nothing' "$TMP/a.out"; then
    ok "N/short=$bad_val: DEVKIT_REUSE_LOCK_WAIT_S=$bad_val is the default 3 s: the run gave up before the lock went free (5 s), read-only, receipt untouched"
  else
    bad "N/short=$bad_val: seed rc=$n_seed, A exit $n_rc (want 0), receipt time $t0 -> $t1 (want unchanged), read-only lines $(grep -c 'wrote nothing' "$TMP/a.out") (want 1: a run that waited past the default 3 s got the lock and was not read-only)"
  fi
done
# row 3: acquire_test_run_lock itself, on a clock that jumps (no wall-clock wait): how long does it wait for a lock that is never released?
N3_OUT="$("$PY" -I - "$GATE" "$R" <<'PY' 2>&1
import fcntl, importlib.util, os, sys, time
gate, root = sys.argv[1:3]
os.environ["CLAUDE_PROJECT_DIR"] = root
spec = importlib.util.spec_from_file_location("pfg_n3", gate)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
state = os.path.join(root, ".claude", "audit-gate")
os.makedirs(state, exist_ok=True)
holder = open(os.path.join(state, "test_run.lock"), "a")
fcntl.flock(holder, fcntl.LOCK_EX)           # another open file description: this process cannot take it
now, sleeps = [1000.0], [0]
class Stop(Exception):
    pass
def mono():
    return now[0]
def sleep(s):
    sleeps[0] += 1
    now[0] += s                              # the clock moves by what was slept
    if sleeps[0] > 20000:
        raise Stop()
m.time.monotonic, m.time.sleep = mono, sleep   # m.time is the time module itself
for val in ("nan", "inf", "-inf", "abc", "", "-1", "0", "30", "1e999"):
    os.environ["TEST_RUN_LOCK_WAIT_S"] = val
    now[0], sleeps[0] = 1000.0, 0
    try:
        fh, held = m.acquire_test_run_lock(root)
        res = "gave_up_after_%ds" % round(now[0] - 1000.0) if not held else "GOT_THE_LOCK"
    except Stop:
        res = "NEVER_GAVE_UP"
    print("val=%r %s" % (val, res))
PY
)"
n3() { # $1 the value, $2 what it must give
  local got; got="$(printf '%s\n' "$N3_OUT" | sed -n "s/^val='$1' //p")"
  if [ "$got" = "$2" ]; then ok "N/acquire TEST_RUN_LOCK_WAIT_S='$1': $2"; else bad "N/acquire TEST_RUN_LOCK_WAIT_S='$1': got '$got', want '$2'"; fi
}
n3 nan gave_up_after_900s; n3 inf gave_up_after_900s; n3 -inf gave_up_after_900s; n3 abc gave_up_after_900s; n3 "" gave_up_after_900s
n3 1e999 gave_up_after_900s; n3 -1 gave_up_after_0s; n3 0 gave_up_after_0s; n3 30 gave_up_after_30s
printf '%s\n' "$N3_OUT" | grep -q Traceback && bad "N/acquire: the probe crashed: $(printf '%s\n' "$N3_OUT" | tail -3)"

echo
[ "$FAILS" -eq 0 ] && echo "gate readonly receipt race: all checks passed" || { echo "gate readonly receipt race: $FAILS FAILED"; exit 1; }
