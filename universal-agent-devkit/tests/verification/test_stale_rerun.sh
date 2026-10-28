#!/usr/bin/env bash
# Regression test: scripts/stale_rerun.py — SessionStart re-runs STALE suites in the background.
#  - only light suites (no Gradle / Unity / xcodebuild), only from a matrix the gate trusts,
#    within a time budget; each run is real: result + evidence log, like the gate
#  - a watched file that changes while the suite runs → the result is thrown away (it
#    tested neither the old nor the new code) and the row stays STALE
#  - heavy suites stay STALE for the nightly job; STALE_RERUN=0 turns it off
#  - SessionStart says what it started
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="${SR_KIT:-$(cd "$(dirname "$0")/../.." && pwd)}"   # SR_KIT: chạy cùng bộ ca trên một bản kit khác (RED trên bản gốc)
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; RERUN="$DEVKIT_DIR/scripts/testing/stale_rerun.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src/a" "$P/src/b" "$P/src/c" "$P/.agents"
# main checkout kiểu cũ: ở trunk mode (mặc định) người ghi tự động không ghi file track của main, dòng chờ vào sổ ngoài git
# (tests/worktree_git/test_trunk_main_pending_writers.sh kiểm đường đó)
cd "$P" && git init -q . && git config user.email t@t && git config user.name t && git config devkit.trunkMode false
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
sys.path.insert(0, kit + "/scripts/testing")
sys.path.insert(0, kit + "/scripts"); import stale_rerun
stale_rerun.run_one(Path(p), "REG-A", "python3 -c 'import time; print(time.time())' > %s/ran_at" % tmp, [], 30)
PY
wait $holder
python3 -c "import sys; sys.exit(0 if float(open('$TMP/ran_at').read()) >= float(open('$TMP/released_at').read()) else 1)" 2>/dev/null \
  && ok "run_one waits for the project's test-run lock" || fail "run_one ran while another run held the lock"

# The wait is bounded by the run's own timeout (it waited forever, with a timeout computed
# before the wait): a lock held past it → BUSY, nothing run, nothing recorded; a lock
# released in time → the suite then gets its whole timeout.
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
sys.path.insert(0, kit + "/scripts/testing")
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
# Once the lock is held the suite gets its whole timeout: the wait never turns a green suite
# into a TIMEOUT (review 2026-09-25: nightly reported such a suite as turned red; second review:
# any threshold on the wait still left a band of false TIMEOUTs, and a band of hidden hangs).
last_status() { status_of | python3 -c "import ast,sys; print(ast.literal_eval(sys.stdin.read())['last']['status'])"; }
hold_lock 2
res="$(python3 - "$P" "$TMP" "$DEVKIT_DIR" <<'PY'
import sys; from pathlib import Path
p, tmp, kit = sys.argv[1:]
sys.path.insert(0, kit + "/scripts/testing")
sys.path.insert(0, kit + "/scripts"); import stale_rerun
print(stale_rerun.run_one(Path(p), "REG-A", "sleep 3", [], 4))
PY
)"
wait "$holder" 2>/dev/null
printf '%s' "$res" | grep -q "^REG-A: PASS" && [ "$(last_status)" = "PASS" ] \
  && ok "run_one: a 3 s suite after a 2 s lock wait on a 4 s timeout → PASS recorded" \
  || fail "lock wait cut the suite's own timeout: '$res' (status $(last_status))"
# A short wait does not excuse a real hang: waiting 1.5 s of an 8 s budget, a suite that hangs
# is still recorded as TIMEOUT (review 2026-09-25: any wait over 1 s discarded every TIMEOUT).
hold_lock 1.5
res="$(python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys; from pathlib import Path
p, kit = sys.argv[1:]
sys.path.insert(0, kit + "/scripts/testing")
sys.path.insert(0, kit + "/scripts"); import stale_rerun
print(stale_rerun.run_one(Path(p), "REG-A", "sleep 30", [], 8))
PY
)"
wait "$holder" 2>/dev/null
[ "$(last_status)" = "TIMEOUT" ] \
  && ok "run_one: a hang after a short lock wait is still recorded as TIMEOUT" \
  || fail "short lock wait hid a real hang: '$res' (status $(status_of))"

# #427 vòng 2: nightly (scripts/governance/nightly.py → run_one record_per_test) chạy run_impacted.sh chuẩn với DEVKIT_PER_TEST_CACHE=record:
# MỌI test chạy thật (per_test_cache.py plan chỉ gọi hit() ở chế độ "1"; ca dưới đặt sẵn "1" cho nightly), PASS từng test được ghi để một lượt sau trên ĐÚNG
# cây đó (gate buổi sáng: DEVKIT_PER_TEST_CACHE=1) dùng lại. Suite khác không thấy biến; "0" của người dùng: tắt. Kit giả: run_impacted.sh +
# per_test_cache.py + run_bounded.py THẬT của kit đang test, một test đếm số lần chạy (như tests/gates/test_gate_per_test_cache.sh).
R2="$TMP/pt"; KIT="$R2/universal-agent-devkit"; mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$R2/.agents"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/"; : > "$KIT/tests/impact_map.txt"; : > "$KIT/tests/lib/test_durations.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
printf 'echo 1 >> %s/count.t1\n' "$TMP" > "$KIT/tests/v/test_t1.sh"
printf 'echo "${DEVKIT_PER_TEST_CACHE-unset}" >> %s/env.txt\n' "$TMP" > "$R2/probe.sh"
echo 0 > "$R2/notes.txt"
cat > "$R2/.agents/regression_matrix.active.json" <<'JSON'
{"adopted": true, "rules":[
 {"component":"ALL","watch_files":["universal-agent-devkit/tests/*"],"mandatory_regression_tests":[{"id":"REG-ALL","name":"all","command":"bash universal-agent-devkit/tests/run_impacted.sh --all"}]},
 {"component":"ENV","watch_files":["probe.sh"],"mandatory_regression_tests":[{"id":"REG-ENV","name":"env","command":"bash probe.sh"}]}]}
JSON
( cd "$R2" && git init -q . && git config user.email t@t && git config user.name t && git config devkit.trunkMode false && git add -A && git commit -qm init )
t1() { [ -f "$TMP/count.t1" ] && wc -l < "$TMP/count.t1" | tr -d ' ' || echo 0; }
night() { # night [VAR=value ...] — nightly run of R2 by name (test_nightly.sh covers the LaunchAgent run)
  env "$@" HOME="$TMP/home" NIGHTLY_NOTIFY=0 CLAUDE_PROJECT_DIR="$R2" SB_HEAVY_SLOT_DIR="$TMP/slots" DEVKIT_SLOT_LOAD_WAIT_S=0 \
    python3 "$DEVKIT_DIR/scripts/governance/nightly.py" run "$R2" > "$TMP/night.out" 2>&1; }
morning() { ( cd "$KIT" && DEVKIT_PER_TEST_CACHE=1 SB_HEAVY_SLOT_DIR="$TMP/slots" bash tests/run_impacted.sh --all ) > "$TMP/morning.out" 2>&1; }
mkdir -p "$TMP/home" "$TMP/slots"; unset DEVKIT_PER_TEST_CACHE
b=$(t1); night; n1=$(( $(t1) - b )); b=$(t1); morning; m1=$(( $(t1) - b ))
[ "$n1" = 1 ] && [ "$m1" = 0 ] && grep -q '↺ tests/v/test_t1.sh' "$TMP/morning.out" \
  && ok "nightly records each test's PASS: a DEVKIT_PER_TEST_CACHE=1 run on the same tree reuses it" \
  || fail "nightly record → morning reuse: nightly ran t1 $n1× (want 1), morning ran it $m1× (want 0): $(tail -3 "$TMP/morning.out") | $(tail -2 "$TMP/night.out")"
b=$(t1); night DEVKIT_PER_TEST_CACHE=1; n2=$(( $(t1) - b ))
[ "$n2" = 1 ] && ok "nightly with DEVKIT_PER_TEST_CACHE=1 in its environment still runs every test (a PASS on this tree exists)" \
  || fail "nightly reused a PASS (ran t1 $n2×, want 1): it is the night's real full run"
[ "$(sort -u "$TMP/env.txt" 2>/dev/null | tr '\n' ' ')" = "unset " ] \
  && ok "a suite that is not the canonical run_impacted.sh never sees DEVKIT_PER_TEST_CACHE (ambient 1 included)" \
  || fail "REG-ENV saw DEVKIT_PER_TEST_CACHE = '$(sort -u "$TMP/env.txt" 2>/dev/null | tr '\n' ' ')' (want 'unset ')"
echo 1 > "$R2/notes.txt"   # a new tree: no PASS recorded on it yet
b=$(t1); night DEVKIT_PER_TEST_CACHE=0; n4=$(( $(t1) - b )); b=$(t1); morning; m4=$(( $(t1) - b ))
[ "$n4" = 1 ] && [ "$m4" = 1 ] && ok "DEVKIT_PER_TEST_CACHE=0 (user's off switch): nightly runs every test and records nothing" \
  || fail "off switch: nightly ran t1 $n4× (want 1), the next run on that tree ran it $m4× (want 1, nothing to reuse)"

# #532: INT/TERM vào stale_rerun giết cả nhóm tiến trình của suite (Popen start_new_session), không để suite mồ côi; quá giờ vẫn SIGKILL.
orphan() { # orphan <SIGNAL> — cha Python (SIGINT mặc định, không bị `&` của shell tắt) chạy _execute với suite ngủ 300 s; trả về "<exit cha> dead|alive"
  python3 - "$1" "$DEVKIT_DIR/scripts/testing" "$TMP" <<'PY'
import os, signal, subprocess, sys, time
sig, kit, tmp = getattr(signal, "SIG" + sys.argv[1]), sys.argv[2], sys.argv[3]
pidf = tmp + "/orphan.pid"
if os.path.exists(pidf): os.remove(pidf)
code = ("import sys, pathlib; sys.path.insert(0, %r); import stale_rerun as s; "
        "s._execute(pathlib.Path(%r), 'sleep 300 & echo $! > %s; wait', 60)" % (kit, tmp, pidf))
parent = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(80):
    if os.path.exists(pidf) and os.path.getsize(pidf): break
    time.sleep(0.1)
child = int(open(pidf).read())
parent.send_signal(sig)
try: rc = parent.wait(timeout=10)
except subprocess.TimeoutExpired: parent.kill(); rc = "hang"
time.sleep(0.3)
try: os.kill(child, 0); alive = True
except ProcessLookupError: alive = False
if alive: os.kill(child, signal.SIGKILL)
print(rc, "alive" if alive else "dead")
PY
}
for sig in INT TERM; do
  res="$(orphan $sig)"
  case "$res" in *" dead") ok "SIG$sig vào stale_rerun giết suite con (không còn PID sau khi cha thoát)";;
    *) fail "SIG$sig: suite con mồ côi ($res)";; esac
done
python3 -c "
import sys; sys.path.insert(0, '$DEVKIT_DIR/scripts/testing'); import stale_rerun as s, pathlib
st, _, _ = s._execute(pathlib.Path('$TMP'), 'sleep 300', 1); sys.exit(0 if st == 'TIMEOUT' else 1)" \
  && ok "quá giờ vẫn SIGKILL → TIMEOUT" || fail "timeout path changed"

[ "$FAILS" -eq 0 ] && echo "✅ test_stale_rerun: all passed" || { echo "❌ test_stale_rerun: $FAILS failed"; exit 1; }
