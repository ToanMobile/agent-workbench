#!/usr/bin/env bash
# Regression test (review of the A15 lane, 2026-10-15): invariant F1 = "a FAIL is never turned back into a PASS by a stale writer".
# bin/post-fix-gate.py re-uses the PASS of a suite from the file that holds it (the full-pass receipt, or the Stop record budget_pass.json): the read
# happens BEFORE the run waits for test_run.lock. A forced run B that holds the lock meanwhile and FAILS the suite deletes that file. Run A then got the
# lock, never looked at the file again (it re-read it only when it had re-used NOTHING), ran the suites it had left, and ended exit 0 with
# "REG-1 PASS (reused)", wrote REG-1=PASS into the checklist and, as a --full run, wrote full_pass.json exit 0. hooks/regression_gate.sh stores pass_fp on
# exit 0 and skips the gate at every later Stop on that content, so a false PASS stuck. tests/gates/test_gate_stop_record_race.sh did not see it: it adds a
# changed file no rule watches, which makes every verdict exit 2 whatever the suites say.
# Here NO such file exists: A must not end exit 0 on a PASS it only read. What it re-used is UNTESTED once the file that vouched for it moved (the
# same fail-closed answer the Stop record already gave on write): exit 4, REG-1 is not recorded PASS anywhere, no receipt exit 0, and the Stop hook is
# told "busy" (4 + busy: it says so and caches nothing, so the next Stop runs REG-1 for real). A does not run REG-1 itself (tests/gates/
# test_gate_stop_record_race.sh pins that C is the one to run it); FAIL1=1 only makes a design that would re-run it show up as exit 1.
#   K1  the file changes while A waits for the lock (a stub holds it, as the forced run B): record (exit-4 Stop seed), budget (a budget-cut Stop seed),
#       receipt (--full seed) read by --full and by a Stop-style run: A ends exit 4, REG-1 is not run and not recorded PASS, REG-2 runs.
#       Control of each: B does not touch the file: A re-uses REG-1 (0 runs), exit 0, the receipt is written as before.
#   K2  EVERY suite is re-used, so A has nothing to run and took NO lock: the file vanishes while A reads it. A takes the lock for the check-and-write
#       pair now, finds the stamp moved and ends exit 4. Control: untouched, A re-uses both (0 runs), exit 0, receipt written.
#   K3  the file changes AFTER the first check (under the lock, once the suites ran), before the verdict (a writer that took no lock, a person's
#       rm): the second check turns the re-used PASS UNTESTED just the same, exit 4.
#   K5  every suite is re-used and another run holds the lock past TEST_RUN_LOCK_WAIT_S: the re-used PASS cannot be checked, so exit 4 (BUSY) and the
#       receipt is not rewritten (before: exit 0 and a rewrite with no lock).
#   S   a record or receipt over 1 MiB is no record (json.load of a 6 MB integer took 126 s on Python 3.9): not re-used, and the partial writer drops it.
#   T   write_full_pass_receipt serialises BEFORE it makes the temp file: a field json cannot dump (nested too deep) left .tmp_full_pass.* behind.
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
status1() { python3 -I -c 'import json,sys
try:
    print(((json.load(open(sys.argv[1]))["items"].get("REG-1") or {}).get("last") or {}).get("status") or "none")
except (OSError, ValueError, KeyError): print("none")' "$R/.agents/regression_status.json"; }
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
# A launcher around the gate's own main(): the first call of one function of the gate removes the files that hold the re-used results (what a forced
# run's FAIL does: write_full_pass_receipt exit 1 and drop_budget_record), or does nothing (RACE_HOW=none: the control, the same code path).
#   read      local_state_sha: cached_full_pass calls it AFTER it loaded the file, before it returns: the change is inside A's own read
#   verdict   run_performance_audit: after the suites, before the verdict (static layers): a writer that holds no lock
cat > "$TMP/launcher.py" <<'PY'
import importlib.util, os, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_race", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_race"] = m
spec.loader.exec_module(m)
name = {"read": "local_state_sha", "verdict": "run_performance_audit"}[os.environ["RACE_AT"]]
real, fired = getattr(m, name), []
def hooked(*a, **k):
    if not fired:
        fired.append(1)
        if os.environ["RACE_HOW"] == "remove":
            for f in os.environ["RACE_FILES"].split(":"):
                try:
                    os.remove(f)
                except FileNotFoundError:
                    pass
    return real(*a, **k)
setattr(m, name, hooked)
sys.exit(m.main())
PY
a_run() { # $1 = stop | full, $2 = hook (none | read | verdict), $3 = remove | none (the launcher), then NAME=value words; output $TMP/a.out, exit $TMP/a.rc
  local mode="$1" hook="$2" how="$3"; shift 3
  local envs=(FAIL1=1 EXIT2=0) flags=(--json) runner=("$GATE")   # --json: its "busy" is what the Stop hook reads (4 + busy = say it, cache nothing)
  if [ "$mode" = stop ]; then envs+=(GATE_TOTAL_BUDGET_S=900); else flags+=(--full); fi
  if [ "$hook" != none ]; then
    envs+=(RACE_AT="$hook" RACE_HOW="$how" "RACE_FILES=$GD/full_pass.json:$GD/budget_pass.json"); runner=("$TMP/launcher.py" "$GATE")
  fi
  tl 240 env CLAUDE_PROJECT_DIR="$R" "${envs[@]}" "$@" "$PY" "${runner[@]}" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} > "$TMP/a.out" 2>&1
  echo $? > "$TMP/a.rc"
}
snapshot() { # what A left behind, in the variables the checks read
  A_RC="$(cat "$TMP/a.rc" 2>/dev/null)"; A_S1=$(( $(runs s1) - B1 )); A_S2=$(( $(runs s2) - B2 ))
  A_REUSED=no; grep -q "reusing the" "$TMP/a.out" 2>/dev/null && A_REUSED=yes
  A_TRACE=$(grep -c Traceback "$TMP/a.out" 2>/dev/null); A_STATUS1="$(status1)"
  A_RECEIPT="$(state "$GD/full_pass.json")"; A_RECORD="$(state "$GD/budget_pass.json")"
}
mark_runs() { B1=$(runs s1); B2=$(runs s2); }
not_exit0() { case "$1" in exit=0*) return 1 ;; *) return 0 ;; esac; }
reg1_ticked() { grep REG-1 "$TMP/a.out" | grep -q '\[x\]'; }   # the suite table shows REG-1 as a PASS ([x])

# K1: the file changes while A waits for the lock. $1 label, $2 seed, $3 A (stop|full), $4 remove|none
k1() {
  make_repo; seed "$2"; mark_runs
  if [ "$SEED_RC" = 4 ] && [ "$SEED_STATE" = "exit=4 REG-1=PASS,REG-2=UNTESTED untested=REG-2" ]; then :
  else bad "$1: setup went wrong: seed ($2) rc=$SEED_RC state='$SEED_STATE'"; fi
  hold_lock "$TMP/lock.release"
  ( a_run "$3" none none ) &
  local apid=$! i=0
  while ! grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  A_WAIT=no; grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && A_WAIT=yes
  [ "$4" = remove ] && rm -f "$GD/full_pass.json" "$GD/budget_pass.json"
  touch "$TMP/lock.release"; wait "$HOLDER" 2>/dev/null; HOLDER=""; wait "$apid" 2>/dev/null
  snapshot
  if [ "$A_WAIT" != yes ] || [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A waited=$A_WAIT re-used=$A_REUSED"; printf '%s\n' "$(tail -5 "$TMP/a.out")"; return; fi
  if [ "$4" = remove ]; then
    if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 1 ] && [ "$A_STATUS1" != PASS ] && not_exit0 "$A_RECEIPT" && not_exit0 "$A_RECORD" \
       && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && ! reg1_ticked && [ "$A_TRACE" = 0 ]; then
      ok "$1: the $2 was removed while A waited: the re-used REG-1 is UNTESTED, exit 4 (not 0), checklist REG-1 '$A_STATUS1' (not PASS), no receipt or record exit 0"
    else
      bad "$1: A exit $A_RC (want 4), REG-1/REG-2 ran $A_S1/$A_S2 (want 0/1), checklist REG-1 '$A_STATUS1' (not PASS), receipt '$A_RECEIPT' record '$A_RECORD' (none with exit=0), tracebacks $A_TRACE"
    fi
  else
    local want_receipt=yes; [ "$3" = full ] || want_receipt=no
    if [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 1 ] && [ "$A_STATUS1" = PASS ] \
       && grep -q '"busy": false' "$TMP/a.out" && { [ "$want_receipt" = no ] || [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; }; then
      ok "$1 control: nothing touched the $2: A re-used REG-1 (0 runs), ran REG-2, exit 0, checklist REG-1 PASS$([ "$want_receipt" = yes ] && echo ', receipt exit 0 written')"
    else
      bad "$1 control: A exit $A_RC (want 0), REG-1/REG-2 ran $A_S1/$A_S2 (want 0/1), checklist '$A_STATUS1' (want PASS), receipt '$A_RECEIPT'"
    fi
  fi
}
k1 "K1/record/stop"   record  stop remove;  k1 "K1/record/stop"   record  stop none
k1 "K1/budget/stop"   budget  stop remove;  k1 "K1/budget/stop"   budget  stop none
k1 "K1/receipt/full"  receipt full remove;  k1 "K1/receipt/full"  receipt full none
k1 "K1/receipt/stop"  receipt stop remove;  k1 "K1/receipt/stop"  receipt stop none

# K2: every suite is re-used, A runs nothing and (before) took no lock. The file vanishes inside A's read of it.
k2() { # $1 label, $2 A (stop|full), $3 remove|none
  make_repo; seed pass; mark_runs
  if [ "$SEED_RC" = 0 ] && [ "$SEED_STATE" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; then :
  else bad "$1: setup went wrong: seed rc=$SEED_RC state='$SEED_STATE'"; fi
  a_run "$2" read "$3"; snapshot
  if [ "$A_REUSED" != yes ]; then bad "$1: setup went wrong: A re-used nothing"; printf '%s\n' "$(tail -5 "$TMP/a.out")"; return; fi
  if [ "$3" = remove ]; then
    if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_STATUS1" != PASS ] && not_exit0 "$A_RECEIPT" && grep -q "no longer stands" "$TMP/a.out" && grep -q '"busy": true' "$TMP/a.out" && ! reg1_ticked && [ "$A_TRACE" = 0 ]; then
      ok "$1: the receipt vanished while A (every suite re-used) read it: nothing re-used stands, exit 4 (not 0), checklist REG-1 '$A_STATUS1' (not PASS), no receipt exit 0"
    else
      bad "$1: A exit $A_RC (want 4), runs $A_S1/$A_S2 (want 0/0), checklist '$A_STATUS1' (not PASS), receipt '$A_RECEIPT' (not exit 0), tracebacks $A_TRACE"
    fi
  else
    local want_receipt=yes; [ "$2" = full ] || want_receipt=no
    if [ "$A_RC" = 0 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$A_STATUS1" = PASS ] \
       && { [ "$want_receipt" = no ] || [ "$A_RECEIPT" = "exit=0 REG-1=PASS,REG-2=PASS untested=" ]; }; then
      ok "$1 control: untouched: A re-used both suites (0 runs), exit 0, checklist REG-1 PASS$([ "$want_receipt" = yes ] && echo ', receipt exit 0 written')"
    else
      bad "$1 control: A exit $A_RC (want 0), runs $A_S1/$A_S2 (want 0/0), checklist '$A_STATUS1' (want PASS), receipt '$A_RECEIPT'"
    fi
  fi
}
k2 "K2/all-reused/full" full remove; k2 "K2/all-reused/full" full none
k2 "K2/all-reused/stop" stop remove; k2 "K2/all-reused/stop" stop none

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

# K5: every suite re-used, another run holds the lock past the wait: nothing can be checked, nothing is written, not a PASS
make_repo; seed pass; mark_runs
before="$(stamp "$GD/full_pass.json")"
hold_lock "$TMP/lock.release"
a_run full none none TEST_RUN_LOCK_WAIT_S=2; snapshot
touch "$TMP/lock.release"; wait "$HOLDER" 2>/dev/null; HOLDER=""
after="$(stamp "$GD/full_pass.json")"
if [ "$A_RC" = 4 ] && [ "$A_S1" = 0 ] && [ "$A_S2" = 0 ] && [ "$before" = "$after" ] && [ "$A_TRACE" = 0 ]; then
  ok "K5/busy: every suite re-used, the lock held past the wait: exit 4 (BUSY, not PASS), no suite run, the receipt file untouched"
else
  bad "K5/busy: A exit $A_RC (want 4), runs $A_S1/$A_S2 (want 0/0), receipt stamp '$before' -> '$after' (want unchanged), tracebacks $A_TRACE"
fi

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

# T: write_full_pass_receipt serialises before it makes the temp file. The receipt of the same content carries a field json.load reads and the
# serialiser of the day cannot write back (nested deep: the depth where that happens depends on the Python, so it is looked for)
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
        continue            # this depth is read and written back by the serialiser of the day: not the case looked for
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
  ok "T/receipt: $T_FOUND receipt(s) the reader loads and the serialiser cannot write back: no .tmp_full_pass.* left, no exception"
elif [ "$seed_rc" = 2 ] && [ "${T_FOUND:-0}" = 0 ] && [ -n "$T_PYV" ] && [ "$T_LEFT" = 0 ] && [ "$T_EXC" = 0 ] && ! printf '%s' "$T_OUT" | grep -q Traceback; then
  # Python 3.9 (measured): json.load and json.dump hit the recursion limit at the SAME depth (995 of 1000 here), so no receipt exists that is read and
  # not written back: nothing to leak. The row has its teeth on a Python whose C json decoder does not count Python frames (3.14).
  ok "T/receipt: n/a on Python $T_PYV: json.load and json.dump refuse the same depths, no receipt is read and not written back"
else
  bad "T/receipt: seed rc=$seed_rc, depths found ${T_FOUND:-0} (want >= 1), with a leftover temp file: $T_LEFT, exceptions: $T_EXC"; printf '%s\n' "$T_OUT" | tail -12
fi

echo
[ "$FAILS" -eq 0 ] && echo "gate stop reuse race: all checks passed" || { echo "gate stop reuse race: $FAILS FAILED"; exit 1; }
