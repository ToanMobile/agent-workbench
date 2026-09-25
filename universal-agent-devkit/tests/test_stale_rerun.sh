#!/usr/bin/env bash
# Regression test: scripts/stale_rerun.py — SessionStart re-runs STALE suites in the background.
#  - only light suites (no Gradle / Unity / xcodebuild), only from a matrix the gate trusts,
#    within a time budget; each run is real: result + evidence log, like the gate
#  - a watched file that changes while the suite runs → the result is thrown away (it
#    tested neither the old nor the new code) and the row stays STALE
#  - heavy suites stay STALE for the nightly job; STALE_RERUN=0 turns it off
#  - SessionStart says what it started
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; RERUN="$DEVKIT_DIR/scripts/stale_rerun.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src/a" "$P/src/b" "$P/src/c" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo 1 > src/a/x.py; echo 1 > src/b/y.py; echo 1 > src/c/z.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[
 {"component":"A","watch_files":["src/a/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"echo light-a"}]},
 {"component":"B","watch_files":["src/b/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b","command":"true || ./gradlew test"}]},
 {"component":"C","watch_files":["src/c/*"],"mandatory_regression_tests":[{"id":"REG-C","name":"c","command":"echo 2 >> src/c/z.py"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
for f in src/a/x.py src/b/y.py src/c/z.py; do echo 2 >> "$f"; done
python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
git add -A && git commit -qm ran && sleep 1.1
for f in src/a/x.py src/b/y.py src/c/z.py; do echo 3 >> "$f"; done
python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null
# REG-C's own command edits its watched file: after the gate run it is stale too.
[ "$(st REG-A)" = STALE ] && [ "$(st REG-B)" = STALE ] && [ "$(st REG-C)" = STALE ] && ok "setup: three STALE suites" \
  || fail "setup: A=$(st REG-A) B=$(st REG-B) C=$(st REG-C)"

STALE_RERUN=0 python3 "$RERUN" "$P" --wait >/dev/null 2>&1
[ "$(st REG-A)" = STALE ] && ok "STALE_RERUN=0 runs nothing" || fail "ran with STALE_RERUN=0"

python3 "$RERUN" "$P" --wait > "$TMP/out" 2>&1
[ "$(st REG-A)" = PASS ] && ok "light stale suite re-run for real → PASS" || fail "A: $(st REG-A) $(cat "$TMP/out")"
log="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['REG-A']['last'].get('log') or '')")"
[ -n "$log" ] && grep -q "light-a" "$P/$log" && ok "the re-run keeps its evidence log" || fail "no log: $log"
[ "$(st REG-B)" = STALE ] && ok "heavy suite (gradle) left STALE for the nightly job" || fail "B: $(st REG-B)"
[ "$(st REG-C)" = STALE ] && ok "watched file changed during the run → result discarded, still STALE" || fail "C: $(st REG-C)"

python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p)); d["adopted"] = False
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "echo changed"; json.dump(d, open(p, "w"))
PY
echo 4 >> src/a/x.py; python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null
python3 "$RERUN" "$P" --wait >/dev/null 2>&1
[ "$(st REG-A)" = STALE ] && ok "matrix the gate does not trust (uncommitted change) → nothing runs" || fail "untrusted ran: $(st REG-A)"
git checkout -q .agents/regression_matrix.active.json

out="$(echo '{}' | bash "$DEVKIT_DIR/hooks/session_context.sh" 2>&1)"
printf '%s' "$out" | grep -q "chạy lại nền" && ok "SessionStart starts the background re-run and says so" || fail "session: $out"
for _ in $(seq 1 30); do [ "$(st REG-A)" = PASS ] && break; sleep 0.3; done
[ "$(st REG-A)" = PASS ] && ok "background re-run finished → PASS" || fail "background: $(st REG-A)"

# A suite run in the project tree waits for the per-project test-run lock that the gate holds
# (.claude/audit-gate/test_run.lock): stale re-run and nightly go through run_one.
python3 - "$P" "$TMP" <<'PY' &
import fcntl, os, sys, time
p, tmp = sys.argv[1], sys.argv[2]
os.makedirs(p + "/.claude/audit-gate", exist_ok=True)
with open(p + "/.claude/audit-gate/test_run.lock", "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(tmp + "/held", "w").close()
    time.sleep(2)
    open(tmp + "/released_at", "w").write(repr(time.time()))
PY
holder=$!
for _ in $(seq 1 50); do [ -f "$TMP/held" ] && break; sleep 0.1; done
python3 - "$P" "$TMP" "$DEVKIT_DIR" <<'PY'
import sys; from pathlib import Path
p, tmp, kit = sys.argv[1:]
sys.path.insert(0, kit + "/scripts"); import stale_rerun
stale_rerun.run_one(Path(p), "REG-A", "python3 -c 'import time; print(time.time())' > %s/ran_at" % tmp, [], 30)
PY
wait $holder
python3 -c "import sys; sys.exit(0 if float(open('$TMP/ran_at').read()) >= float(open('$TMP/released_at').read()) else 1)" 2>/dev/null \
  && ok "run_one waits for the project's test-run lock" || fail "run_one ran while another run held the lock"

# The wait is bounded by the run's own timeout (it waited forever, with a timeout computed
# before the wait): a lock held past it → BUSY, nothing run, nothing recorded; a lock
# released in time → the suite gets only what is left of the budget.
hold_lock() { # <seconds> — hold the project's test-run lock in the background
  rm -f "$TMP/held"
  python3 - "$P" "$TMP" "$1" <<'PY' &
import fcntl, os, sys, time
p, tmp, secs = sys.argv[1], sys.argv[2], float(sys.argv[3])
os.makedirs(p + "/.claude/audit-gate", exist_ok=True)
with open(p + "/.claude/audit-gate/test_run.lock", "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(tmp + "/held", "w").close()
    time.sleep(secs)
PY
  holder=$!
  for _ in $(seq 1 50); do [ -f "$TMP/held" ] && break; sleep 0.1; done
}
status_of() { python3 -c "import json,sys; print(json.load(open(sys.argv[1] + '/.agents/regression_status.json'))['items']['REG-A'])" "$P"; }
before_busy="$(status_of)"
rm -f "$TMP/busy_ran"; hold_lock 6
res="$(python3 - "$P" "$TMP" "$DEVKIT_DIR" <<'PY'
import sys, time; from pathlib import Path
p, tmp, kit = sys.argv[1:]
sys.path.insert(0, kit + "/scripts"); import stale_rerun
t0 = time.monotonic()
line = stale_rerun.run_one(Path(p), "REG-A", "touch %s/busy_ran" % tmp, [], 2)
print("%.1f|%s" % (time.monotonic() - t0, line))
PY
)"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
after_busy="$(status_of)"
python3 -c "import sys; e, line = sys.argv[1].split('|', 1); sys.exit(0 if float(e) < 4 and 'BUSY' in line else 1)" "$res" \
  && [ ! -f "$TMP/busy_ran" ] && [ "$before_busy" = "$after_busy" ] \
  && ok "run_one: lock held past its timeout → BUSY within the budget, nothing run or recorded" \
  || fail "run_one lock wait unbounded (res='$res' ran=$([ -f "$TMP/busy_ran" ] && echo y || echo n) recorded=$([ "$before_busy" = "$after_busy" ] && echo n || echo y))"
hold_lock 2
res="$(python3 - "$P" "$TMP" "$DEVKIT_DIR" <<'PY'
import sys; from pathlib import Path
p, tmp, kit = sys.argv[1:]
sys.path.insert(0, kit + "/scripts"); import stale_rerun
print(stale_rerun.run_one(Path(p), "REG-A", "sleep 3", [], 4))
PY
)"
wait "$holder" 2>/dev/null
printf '%s' "$res" | grep -q TIMEOUT && ok "run_one: time spent waiting for the lock comes off the suite's timeout" \
  || fail "suite got the full timeout after waiting for the lock: '$res'"

[ "$FAILS" -eq 0 ] && echo "✅ test_stale_rerun: all passed" || { echo "❌ test_stale_rerun: $FAILS failed"; exit 1; }
