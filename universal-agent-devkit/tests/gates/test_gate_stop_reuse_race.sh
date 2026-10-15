#!/usr/bin/env bash
# Regression test (review of the A15 lane, 2026-10-15): invariant F1 = "a FAIL is never turned back into a PASS by a stale writer".
# bin/post-fix-gate.py re-uses the PASS of a suite from the file that holds it (the full-pass receipt, or the Stop record budget_pass.json): the read
# happens BEFORE the run waits for test_run.lock. A forced run B that holds the lock meanwhile and FAILS the suite deletes that file. Run A then got the
# lock, never looked at the file again (it re-read it only when it had re-used NOTHING), ran the suites it had left, and ended exit 0 with
# "REG-1 PASS (reused)", wrote REG-1=PASS into the checklist and, as a --full run, wrote full_pass.json exit 0. hooks/regression_gate.sh stores pass_fp on
# exit 0 and skips the gate at every later Stop on that content, so a false PASS stuck. tests/gates/test_gate_stop_record_race.sh did not see it: it adds a
# changed file no rule watches, which makes every verdict exit 2 whatever the suites say.
# Here NO such file exists: A must not end exit 0 on a PASS it only read. A run that finds the stamp of the file it read MOVED looks at what is on disk
# NOW (cached_full_pass, the same keys): a suite that file still says PASS for keeps its PASS (another run PASSED and wrote the same bytes again: another
# inode and ctime, nothing failed: a false STALE made the lane's own parallel --full gate flake), a suite it does not vouch for (gone, UNTESTED, listed in
# `untested`, another full_command) is UNTESTED, never PASS (the same fail-closed answer the Stop record already gave on write): exit 4, not recorded PASS
# anywhere, no receipt exit 0, and the Stop hook is told "busy" (4 + busy: it says so and caches nothing, so the next Stop runs it for real). A does not
# run the suite itself (tests/gates/test_gate_stop_record_race.sh pins that C is the one to run it); FAIL1=1 only makes a design that would re-run it
# show up as exit 1.
#   K1  the file changes while A waits for the lock (a stub holds it, as the forced run B): record (exit-4 Stop seed), budget (a budget-cut Stop seed),
#       receipt (--full seed) read by --full and by a Stop-style run. remove / unvouch / idonly / cmd: A ends exit 4, REG-1 is not run and not recorded PASS,
#       REG-2 runs. rewrite and none (controls): A re-used REG-1 (0 runs), exit 0, the receipt is written as before.
#   K2  EVERY suite is re-used, so A has nothing to run: the file vanishes while A reads it. A ends exit 4 and NEITHER re-used suite is PASS in the receipt
#       or the checklist (a run that downgraded only the first wrote REG-2=PASS back); rewrite and none: exit 0.
#   K3  the file changes AFTER the first check (under the lock, once the suites ran), before the verdict (a writer that took no lock, a person's
#       rm): the second check turns the re-used PASS UNTESTED just the same, exit 4.
#   K6  every suite is re-used and another run holds the lock past the SHORT wait (DEVKIT_REUSE_LOCK_WAIT_S, default 3 s, not the long 45 s): A judges
#       from a stamp check and WRITES NOTHING (receipt "time" unchanged, no checklist PASS): stands / rewritten -> exit 0, removed / unvouched -> exit 4.
#   K7  the same for a Stop-style run that ends exit 2: the partial writer still turns the exit-0 receipt to exit 2 (it only turns a PASS down).
#   S   a record or receipt over 1 MiB is no record (json.load of a 6 MB integer took 126 s on Python 3.9): not re-used, and the partial writer drops it.
#   T   write_full_pass_receipt serialises BEFORE it makes the temp file: `json.dump(kept, f)` (the old writer, a pure-Python generator under the recursion
#       limit) raised on a field nested too deep AFTER mkstemp and left .tmp_full_pass.* behind. The row looks for depths that json.load reads and that old
#       writer refuses; the new writer (json.dumps, the C encoder) may well write them back on 3.14, so what is pinned is: no temp file, no exception.
# The seeds run with --no-checklist, so a REG-1 row in .agents/regression_status.json can only come from run A.
# bash 3.2 and Python 3.9 compatible; every gate run is under a hard timeout (tlimit.py kills the whole group); REUSERACE_KIT=<kit dir> tests another
# copy of the kit (a mutant must go red); PYGATE=/usr/bin/python3 runs the gate under another Python.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_UNITY_REUSE_MAX_S GATE_TOTAL_BUDGET_S TEST_RUN_LOCK_WAIT_S DEVKIT_IMPACTED_SINCE
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${REUSERACE_KIT:-$DEVKIT_DIR}"
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
        time.sleep(1)
    p.wait()
    rc = 124
sys.exit(rc)
PY
tl() { python3 -I "$TMP/tlimit.py" "$@"; }
# warm the interpreter and the wrapper once (the first exec of a fresh file can be slow)
tl 60 true >/dev/null 2>&1

make_repo() { # $1 = unwatched: also a changed source file no rule watches (the verdict is exit 2 whatever the suites say)
  rm -rf "$R" "$MARK" && mkdir -p "$R/app/src/main/kotlin/pkg" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'echo x >> "$MARK/s1"\n[ -n "${SLEEP1:-}" ] && sleep "$SLEEP1"\nexit "${FAIL1:-0}"\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\nexit "${EXIT2:-0}"\n' > tests/s2.sh
  printf '{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"REG-1","command":"sh tests/s1.sh"},{"id":"REG-2","name":"REG-2","command":"sh tests/s2.sh","untested_exit":2}]}]}\n' > matrix.json
  git add -A && git commit -qm init
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  [ "${1:-}" = unwatched ] && { mkdir -p lib && echo "class Other" > lib/Other.kt; }
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
stamp() { python3 -I -c 'import os,sys
try:
    st = os.stat(sys.argv[1]); print(st.st_ino, st.st_mtime_ns, st.st_size)
except OSError: print("none")' "$1"; }
status_of() { python3 -I -c 'import json,sys
try:
    print(((json.load(open(sys.argv[1]))["items"].get(sys.argv[2]) or {}).get("last") or {}).get("status") or "none")
except (OSError, ValueError, KeyError): print("none")' "$R/.agents/regression_status.json" "$1"; }
status1() { status_of REG-1; }
seed() { # $1 = record (Stop, REG-2 exits its untested_exit: exit 4) | budget (Stop cut by the time budget) | receipt (--full, exit 4) | pass (--full, exit 0)
  case "$1" in
    record)  run_gate GATE_TOTAL_BUDGET_S=900 EXIT2=2 -- --no-checklist ;;
    budget)  run_gate GATE_TOTAL_BUDGET_S=1 SLEEP1=2 -- --no-checklist ;;
    receipt) run_gate EXIT2=2 -- --full --no-checklist ;;
    pass)    run_gate -- --full --no-checklist ;;
  esac
  SEED_RC=$RC
  if [ "$1" = receipt ] || [ "$1" = pass ]; then SEED_STATE="$(state "$GD/full_pass.json")"; else SEED_STATE="$(state "$GD/budget_pass.json")"; fi
}

# a stub that holds test_run.lock until told to let go: the forced run B that is still running
hold_lock() { # $1 = release file
  rm -f "$TMP/lock.held" "$1"
  python3 -I - "$R" "$TMP/lock.held" "$1" <<'PY' &
import fcntl, os, sys, time
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    for _ in range(600):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
  HOLDER=$!
  local i=0; while [ ! -f "$TMP/lock.held" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}
# What another run can do to the file that vouched for the re-used suites (python, shared by this script and the launcher below):
#   remove   a forced run FAILED the suite: write_full_pass_receipt exit 1 / drop_budget_record delete the file
#   rewrite  a forced run PASSED and wrote the same bytes again (tmp + os.replace, as the gate's own writers do): another inode and ctime, nothing failed
#   unvouch  another run replaced the file by one that does NOT vouch for REG-1 (REG-1 UNTESTED): valid, same keys, no PASS for it
#   idonly   ... one that still has REG-1 PASS but lists it in `untested` (so a reader runs it again)
#   cmd      ... a Stop record whose REG-1 passed another command (full_command): the PASS is not for the command this run would have started
cat > "$TMP/change.py" <<'PY'
import json, os, sys

def apply(how, files):
    for p in files:
        if how == "none" or not os.path.exists(p):
            continue
        if how == "remove":
            os.remove(p)
        elif how == "rewrite":
            with open(p + ".tmp", "wb") as f:
                f.write(open(p, "rb").read())
            os.replace(p + ".tmp", p)
        elif how in ("unvouch", "idonly", "cmd"):
            d = json.load(open(p))
            for t in d["tests"]:
                if t["id"] == "REG-1" and how == "unvouch":
                    t["status"] = "UNTESTED"
                if t["id"] == "REG-1" and how == "cmd":
                    t["full_command"] = "sh tests/other.sh"
            if how != "cmd":
                d["untested"] = sorted(set(d.get("untested") or []) | {"REG-1"})
                d["exit"] = 4
            with open(p + ".tmp", "w") as f:
                f.write(json.dumps(d))
            os.replace(p + ".tmp", p)

if __name__ == "__main__":
    apply(sys.argv[1], sys.argv[2:])
PY
change_state() { python3 -I "$TMP/change.py" "$1" "$GD/full_pass.json" "$GD/budget_pass.json"; }   # $1 = remove | rewrite | unvouch
# A launcher around the gate's own main(): the first call of one function of the gate removes the files that hold the re-used results (what a forced
# run's FAIL does: write_full_pass_receipt exit 1 and drop_budget_record), or does nothing (RACE_HOW=none: the control, the same code path).
#   read      local_state_sha: cached_full_pass calls it AFTER it loaded the file, before it returns: the change is inside A's own read
#   verdict   run_performance_audit: after the suites, before the verdict (static layers): a writer that holds no lock
#   acquire   acquire_test_run_lock: before A asks for the lock (A read the file BEFORE, so the change is while it waits); with RACE_RELEASE_AFTER=N a timer
#             lets the lock stub go N s after that call, so a run that waits LONGER than its short wait gets the lock and a run that gives up does not
cat > "$TMP/launcher.py" <<'PY'
import importlib.util, os, sys, threading
sys.path.insert(0, os.environ["RACE_DIR"])
import change
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_race", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_race"] = m
spec.loader.exec_module(m)
name = {"read": "local_state_sha", "verdict": "run_performance_audit", "acquire": "acquire_test_run_lock"}[os.environ["RACE_AT"]]
real, fired = getattr(m, name), []
def hooked(*a, **k):
    if not fired:
        fired.append(1)
        change.apply(os.environ["RACE_HOW"], os.environ["RACE_FILES"].split(":"))
        if os.environ.get("RACE_RELEASE_AFTER"):
            threading.Timer(float(os.environ["RACE_RELEASE_AFTER"]), lambda: open(os.environ["RACE_RELEASE"], "w").close()).start()
    return real(*a, **k)
setattr(m, name, hooked)
sys.exit(m.main())
PY
a_run() { # $1 = stop | full, $2 = hook (none | read | verdict | acquire), $3 = remove | rewrite | unvouch | none (the launcher), then NAME=value words; output $TMP/a.out, exit $TMP/a.rc
  local mode="$1" hook="$2" how="$3"; shift 3
  local envs=(FAIL1=1 EXIT2=0) flags=(--json) runner=("$GATE")   # --json: its "busy" is what the Stop hook reads (4 + busy = say it, cache nothing)
  if [ "$mode" = stop ]; then envs+=(GATE_TOTAL_BUDGET_S=900); else flags+=(--full); fi
  if [ "$hook" != none ]; then
    envs+=(RACE_AT="$hook" RACE_HOW="$how" RACE_DIR="$TMP" "RACE_FILES=$GD/full_pass.json:$GD/budget_pass.json"); runner=("$TMP/launcher.py" "$GATE")
  fi
  tl 240 env CLAUDE_PROJECT_DIR="$R" "${envs[@]}" "$@" "$PY" "${runner[@]}" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} > "$TMP/a.out" 2>&1
  echo $? > "$TMP/a.rc"
}
snapshot() { # what A left behind, in the variables the checks read
  A_RC="$(cat "$TMP/a.rc" 2>/dev/null)"; A_S1=$(( $(runs s1) - B1 )); A_S2=$(( $(runs s2) - B2 ))
  A_REUSED=no; grep -q "reusing the" "$TMP/a.out" 2>/dev/null && A_REUSED=yes
  A_TRACE=$(grep -c Traceback "$TMP/a.out" 2>/dev/null); A_STATUS1="$(status1)"; A_STATUS2="$(status_of REG-2)"
  A_RECEIPT="$(state "$GD/full_pass.json")"; A_RECORD="$(state "$GD/budget_pass.json")"
}
mark_runs() { B1=$(runs s1); B2=$(runs s2); }
not_exit0() { case "$1" in exit=0*) return 1 ;; *) return 0 ;; esac; }
reg1_ticked() { grep REG-1 "$TMP/a.out" | grep -q '\[x\]'; }   # the suite table shows REG-1 as a PASS ([x])
reg_ticked() { grep -E 'REG-[12]' "$TMP/a.out" | grep -q '\[x\]'; }   # ... or either suite (K2 re-used both: the table must tick neither)

# K1: the file changes while A waits for the lock. $1 label, $2 seed, $3 A (stop|full), $4 remove | unvouch (A must not stand on it) | rewrite | none (it stands)
k1() {
  make_repo; seed "$2"; mark_runs
  if [ "$SEED_RC" = 4 ] && [ "$SEED_STATE" = "exit=4 REG-1=PASS,REG-2=UNTESTED untested=REG-2" ]; then :
  else bad "$1: setup went wrong: seed ($2) rc=$SEED_RC state='$SEED_STATE'"; fi
  hold_lock "$TMP/lock.release"
  ( a_run "$3" none none ) &
  local apid=$! i=0
  while ! grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  A_WAIT=no; grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && A_WAIT=yes
  [ "$4" = none ] || change_state "$4"
  touch "$TMP/lock.release"; wait "$HOLDER" 2>/dev/null; HOLDER=""; wait "$apid" 2>/dev/null
  snapshot
  if [ "$A_WAIT" != yes ] || [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A waited=$A_WAIT re-used=$A_REUSED"; printf '%s\n' "$(tail -5 "$TMP/a.out")"; return; fi
  if [ "$4" != rewrite ] && [ "$4" != none ]; then
    if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 1 ] && [ "$A_STATUS1" != PASS ] && not_exit0 "$A_RECEIPT" && not_exit0 "$A_RECORD" \
       && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && ! reg1_ticked && [ "$A_TRACE" = 0 ]; then
      ok "$1: the $2 was changed ($4) while A waited: the re-used REG-1 is UNTESTED, exit 4 (not 0), checklist REG-1 '$A_STATUS1' (not PASS), no receipt or record exit 0"
    else
      bad "$1: A exit $A_RC (want 4), REG-1/REG-2 ran $A_S1/$A_S2 (want 0/1), checklist REG-1 '$A_STATUS1' (not PASS), receipt '$A_RECEIPT' record '$A_RECORD' (none with exit=0), tracebacks $A_TRACE"
    fi
  else
    local want_receipt=yes; [ "$3" = full ] || want_receipt=no
    if [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 1 ] && [ "$A_STATUS1" = PASS ] \
       && grep -q '"busy": false' "$TMP/a.out" && { [ "$want_receipt" = no ] || [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; }; then
      ok "$1 control ($4): the $2 still stands: A re-used REG-1 (0 runs), ran REG-2, exit 0, checklist REG-1 PASS$([ "$want_receipt" = yes ] && echo ', receipt exit 0 written')"
    else
      bad "$1 control ($4): A exit $A_RC (want 0), REG-1/REG-2 ran $A_S1/$A_S2 (want 0/1), checklist '$A_STATUS1' (want PASS), receipt '$A_RECEIPT', busy/stale text in the output: $(grep -c 'no longer stands' "$TMP/a.out")"
    fi
  fi
}
# rewrite = the file replaced by another run that PASSED and wrote the same bytes (another inode and ctime): nothing failed, A must keep its PASS
# unvouch / idonly / cmd = replaced by a valid file that does not vouch for REG-1: A must not (the re-check is "does the CURRENT file still say PASS for this", not "is there a file")
for row in "record stop" "budget stop" "receipt full" "receipt stop"; do
  set -- $row
  for how in remove unvouch rewrite none; do k1 "K1/$1/$2" "$1" "$2" "$how"; done
done
# a record that still says PASS but names REG-1 in `untested`, and one whose REG-1 passed another command: not what this run re-used
k1 "K1/record/stop" record stop idonly; k1 "K1/receipt/full" receipt full idonly; k1 "K1/record/stop" record stop cmd; k1 "K1/budget/stop" budget stop cmd

# K2: every suite is re-used, A runs nothing and (before) took no lock. The file vanishes inside A's read of it.
k2() { # $1 label, $2 A (stop|full), $3 remove | rewrite | none
  make_repo; seed pass; mark_runs
  if [ "$SEED_RC" = 0 ] && [ "$SEED_STATE" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; then :
  else bad "$1: setup went wrong: seed rc=$SEED_RC state='$SEED_STATE'"; fi
  a_run "$2" read "$3"; snapshot
  if [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A re-used nothing"; printf '%s\n' "$(tail -5 "$TMP/a.out")"; return; fi
  if [ "$3" = remove ]; then
    # EVERY re-used suite goes: neither the receipt nor the checklist may hold a PASS for REG-1 OR REG-2 (a run that downgrades only the first re-used
    # suite wrote exit=4 REG-1=UNTESTED,REG-2=PASS back: the F1 hole for the second suite)
    if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_STATUS1" != PASS ] && [ "$A_STATUS2" != PASS ] && not_exit0 "$A_RECEIPT" \
       && ! printf '%s' "$A_RECEIPT$A_RECORD" | grep -q '=PASS' && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && ! reg_ticked && [ "$A_TRACE" = 0 ]; then
      ok "$1: the receipt vanished while A (every suite re-used) read it: nothing re-used stands, exit 4 (not 0), checklist REG-1 '$A_STATUS1' REG-2 '$A_STATUS2' (not PASS), no PASS in the receipt '$A_RECEIPT'"
    else
      bad "$1: A exit $A_RC (want 4), runs $A_S1/$A_S2 (want 0/0), checklist '$A_STATUS1'/'$A_STATUS2' (not PASS), receipt '$A_RECEIPT' record '$A_RECORD' (no =PASS, not exit 0), tracebacks $A_TRACE"
    fi
  else
    local want_receipt=yes; [ "$2" = full ] || want_receipt=no
    if [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_STATUS1" = PASS ] \
       && { [ "$want_receipt" = no ] || [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; }; then
      ok "$1 control ($3): the receipt stands: A re-used both suites (0 runs), exit 0, checklist REG-1 PASS$([ "$want_receipt" = yes ] && echo ', receipt exit 0 written')"
    else
      bad "$1 control ($3): A exit $A_RC (want 0), runs $A_S1/$A_S2 (want 0/0), checklist '$A_STATUS1' (want PASS), receipt '$A_RECEIPT'"
    fi
  fi
}
for how in remove rewrite none; do k2 "K2/all-reused/full" full "$how"; k2 "K2/all-reused/stop" stop "$how"; done

# K3: the file changes after the check under the lock and before the verdict (a writer that holds no lock)
k3() { # $1 label, $2 remove|none
  make_repo; seed record; mark_runs
  a_run stop verdict "$2"; snapshot
  if [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A re-used nothing"; return; fi
  if [ "$2" = remove ]; then
    if [ "$A_RC" = 4 ] && [ "$A_S2" = 1 ] && [ "$A_STATUS1" != PASS ] && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && [ "$A_TRACE" = 0 ]; then
      ok "$1: the record vanished after the lock check: the re-used REG-1 turned UNTESTED, exit 4 (not 0), checklist REG-1 '$A_STATUS1'"
    else
      bad "$1: A exit $A_RC (want 4), REG-2 ran $A_S2 (want 1), checklist REG-1 '$A_STATUS1' (not PASS), tracebacks $A_TRACE"
    fi
  else
    [ "$A_RC" = 0 ] && [ "$A_STATUS1" = PASS ] && ok "$1 control: untouched: exit 0, checklist REG-1 PASS" || bad "$1 control: exit $A_RC (want 0), checklist '$A_STATUS1' (want PASS)"
  fi
}
k3 "K3/verdict" remove; k3 "K3/verdict" none

# K6: every suite re-used and another run holds the lock past the SHORT wait (DEVKIT_REUSE_LOCK_WAIT_S, default 3 s): nothing is left to run, so A does
# not wait for the long one (TEST_RUN_LOCK_WAIT_S: 45 s through the Stop hook). It judges from a stamp check and WRITES NOTHING: no receipt rewrite, no
# record, no PASS row in the checklist. Why that cannot be a false PASS: A says PASS only while the file that vouched for the suites still stands (or
# still says PASS after another run rewrote it), the only writers of that file hold the lock, and A writes nothing, so it cannot put a PASS back that a
# FAIL took away; a FAIL that no one has written yet is not known to anyone (the same as A having run just before that run started).
# The stub lets go 4 s after A's first ask for the lock (a timer in the launcher): a run that waited the long 10 s would get the lock then and write
# the receipt ("time" moves), a run that gave up after 1 s does not. $3: none (it stands) | rewrite (another run PASSED, same bytes) | remove | unvouch.
rtime() { python3 -I -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("time"))
except (OSError, ValueError): print("none")' "$GD/full_pass.json"; }
k6() { # $1 label, $2 A (stop | full), $3 none | rewrite | remove | unvouch | free (no stub: the lock is there: A writes as before)
  make_repo; seed pass; mark_runs; local t0; t0="$(rtime)"
  if [ "$SEED_RC" = 0 ] && [ "$SEED_STATE" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; then :
  else bad "$1: setup went wrong: seed rc=$SEED_RC state='$SEED_STATE'"; fi
  local how="$3" envs=(DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=10)
  if [ "$3" = free ]; then how=none; else hold_lock "$TMP/lock.release"; envs+=(RACE_RELEASE="$TMP/lock.release" RACE_RELEASE_AFTER=4); fi
  a_run "$2" acquire "$how" "${envs[@]}"; snapshot
  touch "$TMP/lock.release"; [ -z "$HOLDER" ] || { wait "$HOLDER" 2>/dev/null; HOLDER=""; }
  local t1; t1="$(rtime)"
  if [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A re-used nothing"; printf '%s\n' "$(tail -5 "$TMP/a.out")"; return; fi
  case "$3" in
    none|rewrite)
      if [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$t1" = "$t0" ] && [ "$A_STATUS1" != PASS ] && [ "$A_STATUS2" != PASS ] \
         && [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ] && grep -q "wrote nothing" "$TMP/a.out" && grep -q '"busy": false' "$TMP/a.out" && [ "$A_TRACE" = 0 ]; then
        ok "$1: the lock held past the short wait, the file $([ "$3" = rewrite ] && echo 'rewritten with the same bytes ')stands: exit 0, nothing written (receipt time unchanged, checklist REG-1 '$A_STATUS1' REG-2 '$A_STATUS2')"
      else
        bad "$1: A exit $A_RC (want 0), runs $A_S1/$A_S2 (want 0/0), receipt time $t0 -> $t1 (want unchanged), checklist '$A_STATUS1'/'$A_STATUS2' (not PASS), receipt '$A_RECEIPT', 'wrote nothing' lines: $(grep -c 'wrote nothing' "$TMP/a.out")"
      fi ;;
    remove|unvouch)
      local want_receipt="none"; [ "$3" = unvouch ] && want_receipt="exit=4 REG-1=UNTESTED,REG-2=PASS untested=REG-1"
      if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_RECEIPT" = "$want_receipt" ] && [ "$A_STATUS1" != PASS ] \
         && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && [ "$A_TRACE" = 0 ]; then
        ok "$1: the lock held past the short wait and the file was changed ($3): not exit 0 (4), nothing written, receipt '$A_RECEIPT'"
      else
        bad "$1: A exit $A_RC (want 4), runs $A_S1/$A_S2 (want 0/0), receipt '$A_RECEIPT' (want '$want_receipt'), checklist '$A_STATUS1' (not PASS), tracebacks $A_TRACE"
      fi ;;
    free)
      if [ "$A_RC" = 0 ] && [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ] && { [ "$2" = stop ] || [ "$t1" != "$t0" ]; }; then
        ok "$1 control: the lock is free: A takes it, re-uses both suites and $([ "$2" = full ] && echo 'writes the receipt again (time moved)' || echo 'ends exit 0')"
      else
        bad "$1 control: A exit $A_RC (want 0), receipt time $t0 -> $t1 (want it moved for --full), receipt '$A_RECEIPT'"
      fi ;;
  esac
}
for how in none rewrite remove unvouch; do k6 "K6/all-reused/full/$how" full "$how"; done
k6 "K6/all-reused/stop/none" stop none; k6 "K6/all-reused/full/free" full free

# K7: the same, but A (a Stop-style run) ends exit 2: the receipt of this content is exit 0 (a --full run with --allow-no-tests). Writing NOTHING must not
# keep it exit 0: the partial writer only ever turns it to exit 2 (XONG and push are refused as before), it never writes a PASS, so it still runs.
k7() { # $1 label, $2 held (the lock is held past the short wait) | free
  make_repo unwatched; run_gate -- --full --no-checklist --allow-no-tests; SEED_RC=$RC; SEED_STATE="$(state "$GD/full_pass.json")"; mark_runs
  if [ "$SEED_RC" = 0 ] && [ "$SEED_STATE" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; then :
  else bad "$1: setup went wrong: seed rc=$SEED_RC state='$SEED_STATE'"; fi
  local envs=(DEVKIT_REUSE_LOCK_WAIT_S=1 TEST_RUN_LOCK_WAIT_S=10)
  if [ "$2" = held ]; then hold_lock "$TMP/lock.release"; envs+=(RACE_RELEASE="$TMP/lock.release" RACE_RELEASE_AFTER=4); fi
  a_run stop acquire none "${envs[@]}"; snapshot
  touch "$TMP/lock.release"; [ -z "$HOLDER" ] || { wait "$HOLDER" 2>/dev/null; HOLDER=""; }
  if [ "$A_RC" = 2 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_RECEIPT" = "exit=2 REG-1=PASS,REG-2=PASS untested=" ] && [ "$A_TRACE" = 0 ]; then
    ok "$1 ($2): a Stop-style run that re-used everything and ended exit 2 turned the exit-0 receipt to exit 2 (suites kept), not left it exit 0"
  else
    bad "$1 ($2): A exit $A_RC (want 2), runs $A_S1/$A_S2 (want 0/0), receipt '$A_RECEIPT' (want 'exit=2 REG-1=PASS,REG-2=PASS untested=')"
  fi
}
k7 "K7/partial-downgrade" held; k7 "K7/partial-downgrade" free

# S: a record or receipt over 1 MiB is no record
pad() { python3 -I -c 'import json,sys
p, n = sys.argv[1], int(sys.argv[2])
d = json.load(open(p)); d["pad"] = "a" * n
open(p, "w").write(json.dumps(d))' "$1" "$2"; }
for n in 100000 1100000; do
  make_repo; seed record; pad "$GD/budget_pass.json" "$n"; mark_runs
  run_gate GATE_TOTAL_BUDGET_S=900 EXIT2=0 --; A_RC=$RC; A_S1=$(( $(runs s1) - B1 )); A_S2=$(( $(runs s2) - B2 ))
  if [ "$n" = 100000 ]; then
    [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 1 ] && ok "S/record control: a record of $n padded bytes is read (REG-1 re-used: 0 runs, exit 0)" || bad "S/record control: exit $A_RC runs $A_S1/$A_S2 (want 0, 0/1)"
  else
    [ "$A_RC" = 0 ] && [ "$A_S1" = 1 ] && [ "$A_S2" = 1 ] && ! grep -q Traceback "$TMP/out.txt" && ok "S/record: a record of $n padded bytes (over 1 MiB) is no record: both suites run, no crash" || bad "S/record: exit $A_RC runs $A_S1/$A_S2 (want 0, 1/1: an oversized record was read)"
  fi
done
# the partial writer (a Stop-style run that ends exit 2) loads the receipt of the same content too: an oversized one is dropped, never loaded
for n in 100000 1100000; do
  make_repo unwatched; run_gate -- --full --no-checklist; seed_rc=$RC; pad "$GD/full_pass.json" "$n"; mark_runs
  run_gate GATE_TOTAL_BUDGET_S=900 EXIT2=0 --; A_RC=$RC; left="$(state "$GD/full_pass.json" | cut -c1-40)"
  if [ "$seed_rc" != 2 ]; then bad "S/receipt: setup went wrong: seed --full rc=$seed_rc (want 2: an unwatched file)"
  elif [ "$n" = 100000 ]; then
    [ "$A_RC" = 2 ] && [ "$left" != none ] && ok "S/receipt control: a receipt of $n padded bytes is read and kept ('$left')" || bad "S/receipt control: exit $A_RC receipt '$left' (want 2, a receipt)"
  else
    [ "$A_RC" = 2 ] && [ "$left" = none ] && ok "S/receipt: a receipt of $n padded bytes (over 1 MiB) is dropped by the partial writer, never loaded" || bad "S/receipt: exit $A_RC receipt '$left' (want 2, none)"
  fi
done

# T: write_full_pass_receipt serialises before it makes the temp file. The receipt of the same content carries a field nested so deep that json.load
# reads it and `json.dump(kept, f)` (the old writer) refuses it (the depth where that happens depends on the Python, so it is looked for)
make_repo unwatched; run_gate -- --full --no-checklist; seed_rc=$RC
T_OUT="$("$PY" -I - "$GATE" "$R" "$GD" <<'PY' 2>&1
import importlib.util, io, json, os, sys
gate, root, gd = sys.argv[1:4]
os.environ["CLAUDE_PROJECT_DIR"] = root
spec = importlib.util.spec_from_file_location("pfg_t", gate)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
sys.path.insert(0, os.path.dirname(gate))
import tree_fp
rp = tree_fp.receipt_path(root)
orig = json.load(open(rp))
fp = tree_fp.tree_fingerprint(root)
assert orig["fingerprint"] == fp, "setup: the receipt is of this content"
tests = [{"id": "REG-1", "status": "PASS", "command": "sh tests/s1.sh"}, {"id": "REG-2", "status": "PASS", "command": "sh tests/s2.sh"}]
found = 0
for depth in (900, 950, 980, 990, 995, 1000, 1500, 3000, 20000, 100000):
    orig["exit"] = 0
    text = json.dumps(orig)[:-1] + ',"x":' + "[" * depth + "]" * depth + "}"
    try:
        kept = json.loads(text)
        json.dump(kept, io.StringIO())
        continue            # json.dump (the old writer) writes this depth back too: not the case looked for
    except RecursionError:
        pass
    try:
        json.loads(text)
    except RecursionError:
        continue            # not even read: the reader drops it before any temp file
    found += 1
    open(rp, "w").write(text)
    try:
        m.write_full_pass_receipt(root, 2, os.path.join(root, "matrix.json"), tests, tested_fp=fp, partial=True)
        res = "ok"
    except BaseException as e:  # noqa: BLE001
        res = "EXC:" + type(e).__name__
    left = [f for f in os.listdir(gd) if f.startswith(".tmp_")]
    print("depth=%d result=%s leftover=%d" % (depth, res, len(left)))
    for f in left:
        os.remove(os.path.join(gd, f))
print("found=%d" % found)
print("pyver=%d.%d" % sys.version_info[:2])
PY
)"
T_FOUND="$(printf '%s\n' "$T_OUT" | sed -n 's/^found=//p')"
T_LEFT="$(printf '%s\n' "$T_OUT" | grep -c 'leftover=[1-9]')"
T_EXC="$(printf '%s\n' "$T_OUT" | grep -c 'result=EXC')"
T_PYV="$(printf '%s\n' "$T_OUT" | sed -n 's/^pyver=//p')"
if [ "$seed_rc" = 2 ] && [ "${T_FOUND:-0}" -ge 1 ] && [ "$T_LEFT" = 0 ] && [ "$T_EXC" = 0 ]; then
  ok "T/receipt: $T_FOUND receipt(s) json.load reads and the old json.dump writer refuses: write_full_pass_receipt leaves no .tmp_full_pass.* and raises nothing"
elif [ "$seed_rc" = 2 ] && [ "${T_FOUND:-0}" = 0 ] && [ -n "$T_PYV" ] && [ "$T_LEFT" = 0 ] && [ "$T_EXC" = 0 ] && ! printf '%s' "$T_OUT" | grep -q Traceback; then
  # Python 3.9 (measured): json.load and json.dump hit the recursion limit at the SAME depth (995 of 1000 here), so no receipt exists that is read and
  # not written back: nothing to leak. The row has its teeth on a Python whose C json decoder does not count Python frames (3.14).
  ok "T/receipt: n/a on Python $T_PYV: json.load and json.dump refuse the same depths, no receipt is read and not written back"
else
  bad "T/receipt: seed rc=$seed_rc, depths found ${T_FOUND:-0} (want >= 1), with a leftover temp file: $T_LEFT, exceptions: $T_EXC"; printf '%s\n' "$T_OUT" | tail -12
fi

echo
[ "$FAILS" -eq 0 ] && echo "gate stop reuse race: all checks passed" || { echo "gate stop reuse race: $FAILS FAILED"; exit 1; }
