#!/usr/bin/env bash
# Regression (DevKit speed, plan item 1c): the suites of one gate run ran one after another, so a matrix of five
# independent DevKit suites cost the SUM of their times (~370 s at the workbench). A suite the base-ref matrix marks
# "parallel_safe": true now runs side by side with the flagged suites next to it; same commands, same verdicts.
#   1. two flagged suites that each wait for the other to START both pass (only possible when they overlap; the
#      sequential gate fails the first one after its 5 s wait: RED)
#   2. no flag = unchanged order: a suite that needs its predecessor's finished side effect still passes
#   3. a suite that is not flagged is a barrier: the flagged ones before it have finished, the ones after start later
#   4. two flagged suites with one command run it once, both report the result (O2 dedupe survives the group)
#   5. a failing flagged suite fails the gate and does not hide its sibling's PASS
#   6. the flag is read from the base-ref matrix only: a working-copy edit that adds it changes nothing
#   7. DEVKIT_GATE_PARALLEL=0 turns it off (the kill switch)
#   8. a flagged suite is told (DEVKIT_GATE_DONE) which test scripts the flagged suites before it run, per job, so
#      run_impacted.sh still skips them
#   9. GATE_TOTAL_BUDGET_S still counts the time of the group before a suite that cannot join it
#  10. a Gradle/Unity/device command is never grouped, whatever the flag says
#  11. a suite that waited for a group slot past the budget is not started
#  12. Ctrl-C ends the gate at once while a group runs (daemon threads), as it did with the sequential loop
#  13. the functions a worker thread calls put bin/ on sys.path once, not on every call
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0

# make_repo '<json list of suites>' ; scripts live under tests/ (the gate only tracks scripts named like tests/x.sh)
make_repo() {
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  # rendezvous: touch my marker, wait up to 10 s for the other's marker, pass only when it appeared
  for me in a b; do
    other=a; [ "$me" = a ] && other=b
    printf 'touch "$MARK/%s.started"\ni=0\nwhile [ ! -f "$MARK/%s.started" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done\n[ -f "$MARK/%s.started" ]\n' "$me" "$other" "$other" > "tests/rv_$me.sh"
  done
  printf 'sleep 1\ntouch "$MARK/a.done"\n' > tests/slow_a.sh                                  # finishes after 1 s
  printf '[ -f "$MARK/a.done" ]\n' > tests/need_a.sh                                         # needs slow_a's side effect
  printf '[ -f "$MARK/a.done" ] || exit 1\nsleep 1\ntouch "$MARK/b.done"\n' > tests/need_a_slow_b.sh
  printf '[ -f "$MARK/b.done" ]\n' > tests/need_b.sh
  printf 'echo x >> "$MARK/count"\nsleep 1\n' > tests/count.sh
  printf 'exit 1\n' > tests/boom.sh
  printf 'exit 0\n' > tests/fine.sh
  printf 'printf "%%s" "$DEVKIT_GATE_DONE" > "$MARK/done_seen"\n' > tests/see_done.sh
  printf 'sleep 1\n' > tests/first.sh
  for n in slow2 slow2b slow2c; do printf 'sleep 2\n' > "tests/$n.sh"; done
  for n in a b; do printf 'touch "$MARK/long_%s.started"\nsleep 25\n' "$n" > "tests/long_$n.sh"; done   # outlive the Ctrl-C of case 12
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
}
suite() { # id command [flag]
  local flag=""; [ "${3:-}" = p ] && flag=',"parallel_safe":true'
  printf '{"id":"%s","name":"%s","command":"%s"%s}' "$1" "$1" "$2" "$flag"
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?; }
passed()  { printf '%s\n' "$OUT" | grep -qE "\[x\].*$1"; }
failed()  { printf '%s\n' "$OUT" | grep -qE "\[ \] (FAIL|TIMEOUT).*$1"; }

# 1. overlap: only a gate that runs the two flagged suites at the same time can pass them
make_repo "$(suite REG-A 'sh tests/rv_a.sh' p),$(suite REG-B 'sh tests/rv_b.sh' p)"
run_gate
if [ "$RC" = 0 ] && passed REG-A && passed REG-B; then ok "1: two flagged suites that wait for each other run side by side (exit 0)"
else bad "1: flagged suites did not overlap (exit $RC) — the gate ran them one after another"; printf '%s\n' "$OUT" | tail -15; fi

# 2. default order untouched without the flag
make_repo "$(suite REG-A 'sh tests/slow_a.sh'),$(suite REG-B 'sh tests/need_a.sh')"
run_gate
if [ "$RC" = 0 ] && passed REG-A && passed REG-B; then ok "2: no flag = the old sequential order (the second suite sees the first one's result)"
else bad "2: unflagged suites no longer run in order (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 3. a suite without the flag is a barrier
make_repo "$(suite REG-A 'sh tests/slow_a.sh' p),$(suite REG-B 'sh tests/need_a_slow_b.sh'),$(suite REG-C 'sh tests/need_b.sh' p)"
run_gate
if [ "$RC" = 0 ] && passed REG-A && passed REG-B && passed REG-C; then ok "3: an unflagged suite waits for the flagged group before it, and starts the group after it later"
else bad "3: the barrier did not hold (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 4. one command named by two flagged suites runs once
make_repo "$(suite REG-A 'sh tests/count.sh' p),$(suite REG-B 'sh tests/count.sh' p)"
run_gate
n="$(wc -l < "$MARK/count" 2>/dev/null | tr -d ' ')"
if [ "$RC" = 0 ] && [ "${n:-0}" = 1 ] && passed REG-A && passed REG-B; then ok "4: the same command in two flagged suites runs once and both report it"
else bad "4: dedupe broke (exit $RC, command ran ${n:-0} times)"; printf '%s\n' "$OUT" | tail -15; fi

# 5. a failing flagged suite fails the gate and leaves its sibling's PASS
make_repo "$(suite REG-A 'sh tests/fine.sh' p),$(suite REG-B 'sh tests/boom.sh' p)"
run_gate
if [ "$RC" != 0 ] && passed REG-A && failed REG-B; then ok "5: a failing flagged suite fails the gate, its sibling still reports PASS"
else bad "5: failure not reported per suite (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 6. the flag counts only from the base-ref matrix
make_repo "$(suite REG-A 'sh tests/slow_a.sh'),$(suite REG-B 'sh tests/need_a.sh')"
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s,%s]}]}\n' \
  "$(suite REG-A 'sh tests/slow_a.sh' p)" "$(suite REG-B 'sh tests/need_a.sh' p)" > matrix.json   # uncommitted: the change under audit adds the flag
run_gate   # a matrix edited since HEAD is UNVERIFIED (exit 2) but the gate still runs HEAD's commands: both suites must pass in order
if [ "$RC" = 2 ] && passed REG-A && passed REG-B && ! failed REG-B; then ok "6: a flag added only in the working copy is ignored (the base-ref matrix decides)"
else bad "6: a working-copy edit switched the gate to parallel (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 7. kill switch (0) and a cap of 1: both give the sequential order
for cap in 0 1; do
  make_repo "$(suite REG-A 'sh tests/slow_a.sh' p),$(suite REG-B 'sh tests/need_a.sh' p)"
  OUT="$(DEVKIT_GATE_PARALLEL=$cap CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
  if [ "$RC" = 0 ] && passed REG-A && passed REG-B; then ok "7: DEVKIT_GATE_PARALLEL=$cap runs flagged suites one after another"
  else bad "7: DEVKIT_GATE_PARALLEL=$cap did not restore the sequential order (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi
done

# 8. each job gets the scripts of the flagged suites before it in DEVKIT_GATE_DONE
make_repo "$(suite REG-A 'sh tests/first.sh' p),$(suite REG-B 'sh tests/see_done.sh' p)"
run_gate
seen="$(cat "$MARK/done_seen" 2>/dev/null)"
case "$seen" in
  *"/tests/first.sh"*) [ "$RC" = 0 ] && ok "8: a flagged suite is told which test scripts the flagged suites before it run" \
                        || bad "8: gate exit $RC" ;;
  *) bad "8: DEVKIT_GATE_DONE of the second flagged suite lacks tests/first.sh (saw: '$seen')" ;;
esac

# 9. GATE_TOTAL_BUDGET_S counts the time the group before a suite took: the suite after a slow group is BUDGET, as it was sequentially
make_repo "$(suite REG-A 'sh tests/slow2.sh' p),$(suite REG-B 'sh tests/fine.sh')"
OUT="$(GATE_TOTAL_BUDGET_S=1 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
if passed REG-A && ! passed REG-B && printf '%s\n' "$OUT" | grep -qE "\[ \] UNTESTED.*REG-B"; then ok "9: the budget is checked after the group before an unflagged suite finished (REG-B is UNTESTED/BUDGET)"
else bad "9: the budget did not see the group's time (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 10. a Gradle/Unity/device command never joins a group, even when the matrix flags it (they share build/test-results)
make_repo "$(suite REG-A 'sh tests/slow_a.sh #gradlew' p),$(suite REG-B 'sh tests/need_a.sh' p)"
run_gate
if [ "$RC" = 0 ] && passed REG-A && passed REG-B; then ok "10: a flagged suite whose command is Gradle runs alone, the flagged suite after it starts when it is done"
else bad "10: a flagged Gradle command ran next to its sibling (exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 11. a suite that waited for a slot past GATE_TOTAL_BUDGET_S is not started (cap 2, three 2 s suites, budget 1 s)
make_repo "$(suite REG-A 'sh tests/slow2.sh' p),$(suite REG-B 'sh tests/slow2b.sh' p),$(suite REG-C 'sh tests/slow2c.sh' p)"
OUT="$(DEVKIT_GATE_PARALLEL=2 GATE_TOTAL_BUDGET_S=1 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
n_pass="$(printf '%s\n' "$OUT" | grep -cE "\[x\].*REG-[ABC] ")"; n_untested="$(printf '%s\n' "$OUT" | grep -cE "\[ \] UNTESTED.*REG-[ABC] ")"
if [ "$n_pass" = 2 ] && [ "$n_untested" = 1 ]; then ok "11: the suite that waited for a slot past the budget is UNTESTED/BUDGET, the two that started in time passed"
else bad "11: budget not re-checked at the slot ($n_pass passed, $n_untested untested, exit $RC)"; printf '%s\n' "$OUT" | tail -15; fi

# 12. Ctrl-C while a group runs: the gate must end at once (a non-daemon worker thread keeps it alive until its suite ends)
make_repo "$(suite REG-A 'sh tests/long_a.sh' p),$(suite REG-B 'sh tests/long_b.sh' p)"
secs="$(python3 -I - "$GATE" "$R" "$MARK" <<'PY'
import os, signal, subprocess, sys, time
gate, repo, mark = sys.argv[1:4]
p = subprocess.Popen([sys.executable, gate, "--matrix", repo + "/matrix.json", "--lang", "en", "--run-tests"],
                     env=dict(os.environ, CLAUDE_PROJECT_DIR=repo), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))   # a background job of bash ignores SIGINT otherwise
end = time.time() + 60
while time.time() < end and not (os.path.exists(mark + "/long_a.started") and os.path.exists(mark + "/long_b.started")):
    time.sleep(0.1)
t0 = time.time()
p.send_signal(signal.SIGINT)
try:
    p.wait(timeout=12)
    print(round(time.time() - t0, 1))
except subprocess.TimeoutExpired:
    p.kill(); p.wait(); print(99)
PY
)"
pkill -f "tests/long_[ab].sh" 2>/dev/null   # the suites' own process groups outlive the gate in both cases
if awk "BEGIN{exit !(${secs:-99} < 8)}"; then ok "12: Ctrl-C ended the gate in ${secs}s while two suites of a group were running"
else bad "12: the gate did not end after Ctrl-C (${secs:-?}s; 99 = still running after 12 s)"; fi

# 13. a worker thread must not re-insert bin/ into sys.path on every call (shared global, grows without bound)
make_repo "$(suite REG-A 'sh tests/fine.sh')"
cnt="$(python3 -I - "$GATE" "$R" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg"] = m; spec.loader.exec_module(m)
b = str(pathlib.Path(sys.argv[1]).resolve().parent)
sys.path[:] = [x for x in sys.path if x != b]
for _ in range(3):
    m.test_failure_reported("x")
    m.keep_evidence(pathlib.Path(sys.argv[2]), {"id": "REG-X"}, "cmd", "out")
print(sys.path.count(b))
PY
)"
if [ "$cnt" = 1 ]; then ok "13: three calls of the worker-thread helpers put bin/ on sys.path once"
else bad "13: bin/ is on sys.path ${cnt:-?} times after 3 calls (it is re-inserted on every call)"; fi

[ "$FAILS" = 0 ] && echo "ALL OK" || { echo "$FAILS FAILED"; exit 1; }
