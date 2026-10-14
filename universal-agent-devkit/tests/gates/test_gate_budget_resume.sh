#!/usr/bin/env bash
# Regression (DevKit, Goods 2026-10-14): a Stop run that spent GATE_TOTAL_BUDGET_S ended UNTESTED (exit 4) and kept NOTHING: the
# suites that had PASSED inside it (REG-GAME-02 + REG-GAME-03, 901-967 s together, over the 900 s budget) were run again from the
# start by the next Stop on the same content, and REG-GAME-04 never got its turn: 63 min in 72 h, one session hit the same
# fingerprint 4 times. The mechanism: the Stop hook has no --full, so its run is "partial", and a partial run never records its own
# suite results (the receipt is written only by a full run; the budget branch skipped even that, on purpose, to leave a valid
# receipt alone). A budget-cut run now leaves a record of its own (.git/postfix-gate/budget_pass.json, never full_pass.json),
# read only by a non-forced (Stop-style) run, under the SAME re-use rules as a receipt (fingerprint taken BEFORE the suites, matrix,
# local state, format, age, Unity age, no device suite) and listing every suite that did not PASS on its full command as "untested".
# Suites: REG-1 instant, REG-2 sleeps 4.5 s (starts at once, inside the 3 s budget), REG-3 instant (starts after the budget: BUDGET).
#   1. same content twice: run 1 = exit 4 (REG-1+REG-2 PASS, REG-3 BUDGET), run 2 = only REG-3 runs, exit 0 (RED on the old gate:
#      run 2 ran REG-1 and REG-2 again and was cut again); no full-pass receipt is ever written by either (still not a PASS)
#   2. the content changes between the runs: every suite runs again       3. --no-cache: every suite runs again
#   4. a suite that FAILED on the same content leaves nothing to re-use (the record is deleted)
#   5. a device suite (adb) is never re-used, the plain one is           6. a Unity test suite is re-used, DEVKIT_UNITY_REUSE_MAX_S=0 stops it
#   7. a --full run does not read the record (acceptance never rests on a Stop run)
#   8. a PASS that did not run the suite's full command (impacted, package, module, resource, BUDGET, UNTESTED) is never recorded as PASS
#  8b. code edited WHILE run 1 ran is not the code tested: no record, run 2 runs everything
#   9. a FIFO planted at the record path never hangs the gate
#  10. the Stop hook end to end: run 1 cut and said so, run 2 on the same tree runs only REG-3 and lets the Stop through
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_UNITY_REUSE_MAX_S DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S GATE_TOTAL_BUDGET_S REGRESSION_GATE_BUDGET_S
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0
BUDGET=3   # only the START side is load-sensitive: the suites before the cut must start within BUDGET s of the loop (they are instant)

suite() { printf '{"id":"%s","name":"%s","command":"%s"}' "$1" "$1" "$2"; }
S1='sh tests/s1.sh'; S2='sh tests/s2.sh'; S3='sh tests/s3.sh'
make_repo() { # $1 = suites (json list body), run in "$R"
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'echo x >> "$MARK/s1"\nexit "${FAIL1:-0}"\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\nsleep 4.5\n[ -n "${EDIT2:-}" ] && echo "// edited by a suite" >> src/Core.kt\nexit 0\n' > tests/s2.sh
  printf 'echo x >> "$MARK/s3"\nexit 0\n' > tests/s3.sh
  printf 'echo x >> "$MARK/s5"\nsleep 4.5\nexit 0\n' > tests/s5.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
# one gate run the way the Stop hook calls it (no --full) unless flags say otherwise; env words first, flags after "--"
run_gate() {
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  OUT="$(CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=$BUDGET ${envs[@]+"${envs[@]}"} python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} 2>&1)"; RC=$?
}
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
counts() { echo "$(runs s1):$(runs s2):$(runs s3)"; }
# the run counts of ONE gate run, in $D: "s1:s2:s3" increments since the last call (no subshell: LAST must persist)
LAST="0:0:0"; D=""
delta() {
  local now; now="$(counts)"
  D="$(python3 -I -c 'import sys; a=[int(x) for x in sys.argv[1].split(":")]; b=[int(x) for x in sys.argv[2].split(":")]; print(":".join(str(x-y) for x,y in zip(a,b)))' "$now" "$LAST")"
  LAST="$now"
}

# 1. same content twice
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate; delta; d1="$D"; rc1=$RC
printf '%s' "$OUT" | grep -qE "\[ \] UNTESTED.*REG-3" && c1=yes || c1=no
run_gate; delta; d2="$D"; rc2=$RC
if [ "$rc1" = 4 ] && [ "$d1" = "1:1:0" ] && [ "$c1" = yes ]; then ok "1a: run 1 spent the budget: exit 4, REG-1 + REG-2 ran, REG-3 is UNTESTED (BUDGET), not a PASS"
else bad "1a: run 1 exit $rc1, runs $d1, REG-3 untested=$c1 (want exit 4, 1:1:0, yes)"; printf '%s\n' "$OUT" | tail -12; fi
if [ "$rc2" = 0 ] && [ "$d2" = "0:0:1" ]; then ok "1b: run 2 on the same content re-used REG-1 + REG-2 and ran only REG-3: exit 0 (runs $d2)"
else bad "1b: run 2 exit $rc2, runs $d2 (want exit 0 and 0:0:1: the suites that passed in run 1 are not run again)"; printf '%s\n' "$OUT" | tail -12; fi
printf '%s' "$OUT" | grep -q "reused from" && ok "1c: run 2 says which suites it re-used" || bad "1c: run 2 does not say it re-used anything"
[ ! -e "$GD/full_pass.json" ] && ok "1d: neither run wrote a full-pass receipt (the budget record is never a handover PASS)" || bad "1d: a full-pass receipt exists"

# 2. content changed between the runs
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate; delta
echo "fun ok() = 3" > "$R/src/Core.kt"
run_gate; delta; d="$D"
if [ "$d" = "1:1:0" ]; then ok "2: edited content runs every suite again (run 2 ran REG-1 + REG-2, cut at REG-3 again)"
else bad "2: runs after the edit $d (want 1:1:0)"; printf '%s\n' "$OUT" | tail -12; fi

# 3. --no-cache (same repo: run 2 above left a record for the edited content, so it is there to be ignored)
run_gate -- --no-cache; delta; d="$D"
if [ "$d" = "1:1:0" ]; then ok "3: --no-cache runs every suite again"
else bad "3: --no-cache runs $d (want 1:1:0)"; fi

# 4. a suite that FAILED on the same content: nothing of the earlier record survives (same repo, the record is still there)
run_gate FAIL1=1 -- --no-cache; delta; d="$D"; rc=$RC
[ "$rc" = 1 ] && ok "4a: the --no-cache run with a failing REG-1 is exit 1 (runs $d)" || bad "4a: exit $rc (want 1)"
run_gate; delta; d="$D"
if [ "$d" = "1:1:0" ]; then ok "4b: after a FAIL on this content the next run re-uses nothing (REG-1 + REG-2 ran again)"
else bad "4b: runs $d (want 1:1:0: the record must be gone after a FAIL)"; fi

# 5. a device suite is never re-used
make_repo "$(suite REG-1 "$S1 adb"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate; delta
run_gate; delta; d="$D"
if [ "$d" = "1:0:1" ]; then ok "5: the adb suite ran again, the plain one was re-used (runs $d)"
else bad "5: runs $d (want 1:0:1)"; printf '%s\n' "$OUT" | tail -12; fi

# 6. a Unity test suite: re-used inside DEVKIT_UNITY_REUSE_MAX_S, never with 0
make_repo "$(suite REG-1 "$S1 unity-batch editmode"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate; delta
run_gate; delta; d="$D"
if [ "$d" = "0:0:1" ]; then ok "6a: the Unity suite and the plain one were re-used (runs $d)"
else bad "6a: runs $d (want 0:0:1)"; printf '%s\n' "$OUT" | tail -12; fi
run_gate DEVKIT_UNITY_REUSE_MAX_S=0; delta; d="$D"
if [ "$d" = "1:0:1" ]; then ok "6b: DEVKIT_UNITY_REUSE_MAX_S=0 runs the Unity suite again (runs $d)"
else bad "6b: runs $d (want 1:0:1)"; fi

# 7. a --full run does not read the record
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate; delta
run_gate GATE_TOTAL_BUDGET_S=0 -- --full; delta; d="$D"
if [ "$d" = "1:1:1" ]; then ok "7: --full ran every suite (it does not take results from a Stop run)"
else bad "7: --full runs $d (want 1:1:1)"; fi

# 8. only a suite that ran its FULL command is recorded as PASS (the unit under the writer)
python3 -I - "$GATE" <<'PY' && ok "8: a budget record lists as untested everything that is not a clean full-command PASS" || bad "8: budget_untested_ids"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
mk = lambda i, st, mode, cmd="sh x": {"id": i, "status": st, "mode": mode, "command": cmd}
tests = [mk("FULL", "PASS", "full"), mk("CACHED", "PASS", "cached"), mk("COVERED", "PASS", "covered"),
         mk("SKIP", "PASS", "skip-compile"), mk("IMP", "PASS", "impacted"), mk("PKG", "PASS", "package"),
         mk("MOD", "PASS", "module"), mk("RES", "PASS", "resource"), mk("BUDGET", "UNTESTED", "full"),
         mk("UNT", "UNTESTED", "full"), mk("FAIL", "FAIL", "full"), mk("TMO", "TIMEOUT", "full"),
         mk("NOMODE", "PASS", None), mk("NOCMD", "PASS", "full", cmd="")]
got = m.budget_untested_ids(tests)
want = ["BUDGET", "FAIL", "IMP", "MOD", "NOMODE", "PKG", "RES", "TMO", "UNT"]
assert got == want, (got, want)
PY

# 8b. code that changes WHILE the suites run was not the code tested: nothing is recorded (the fingerprint is taken before the
#     suites, a Stop run takes none otherwise; taken after, the record would label the edited code as tested)
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate EDIT2=1; delta
[ ! -e "$GD/budget_pass.json" ] && ok "8b: no record after a run whose tree changed while its suites ran" \
  || bad "8b: a budget record was written although the tree changed during the run"
run_gate; delta; d="$D"
if [ "$d" = "1:1:0" ]; then ok "8b: run 2 on the edited tree ran every suite again (runs $d)"
else bad "8b: runs $d (want 1:1:0: the record must not name the content the suites did not run on)"; fi

# 8c. the tree changes while run 2 WAITS for the test-run lock: the suites it already re-used (marked before the wait) belong to the
#     old content, so the record it writes when it is cut again must not name the new one. REG-5 is a second slow suite.
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-5 'sh tests/s5.sh'),$(suite REG-3 "$S3")"; LAST="0:0:0"
run_gate                                   # REG-1 + REG-2 run, REG-5 and REG-3 are cut: the record names the tree as it is now
rm -f "$TMP/held" "$TMP/release" "$TMP/run2.out"
python3 -I - "$R" "$TMP/held" "$TMP/release" <<'PY' &
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
holder=$!
i=0; while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
CLAUDE_PROJECT_DIR="$R" GATE_TOTAL_BUDGET_S=$BUDGET python3 -u "$GATE" --matrix "$R/matrix.json" --lang en --run-tests > "$TMP/run2.out" 2>&1 &
g2=$!
i=0; while ! grep -q "reusing the suites that passed" "$TMP/run2.out" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
echo "fun ok() = 9" > "$R/src/Core.kt"   # edited while run 2 waits for the lock
touch "$TMP/release"; wait "$holder" 2>/dev/null; wait "$g2" 2>/dev/null
run_gate; delta; d="$D"
if [ "$(runs s1):$(runs s2)" = "2:2" ]; then ok "8c: a tree edited while run 2 waited for the lock got no record: run 3 ran REG-1 + REG-2 again"
else bad "8c: REG-1 ran $(runs s1)x, REG-2 $(runs s2)x after run 3 (want 2 and 2: the record must not name content its re-used suites never ran on)"; fi

# 9. a FIFO planted at the record path (the state folder is writable by an agent) never hangs the gate: the record is read
#     through _state_fd, written by replacing it
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")"; LAST="0:0:0"
mkdir -p "$GD" && mkfifo "$GD/budget_pass.json"
( run_gate; echo "$RC" > "$TMP/fifo.rc" ) & fpid=$!
i=0; while kill -0 "$fpid" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.3; i=$((i + 1)); done
if kill -0 "$fpid" 2>/dev/null; then
  # the gate is a grandchild of $fpid: end it by its unique matrix path (this test's own temp folder), never by a broad pattern
  kill "$fpid" 2>/dev/null; pkill -f "$R/matrix.json" 2>/dev/null; bad "9: the gate hung on a FIFO at budget_pass.json"
else
  wait "$fpid" 2>/dev/null; frc="$(cat "$TMP/fifo.rc" 2>/dev/null)"
  if [ "$frc" = 4 ] && [ -f "$GD/budget_pass.json" ]; then ok "9: a FIFO at budget_pass.json did not hang the gate: the usual budget cut (exit 4), the FIFO replaced by a regular record"
  else bad "9: the gate ended with exit '$frc' on a FIFO at budget_pass.json (want 4 and a regular record: $([ -f "$GD/budget_pass.json" ] && echo yes || echo no))"; fi
fi

# 10. the Stop hook end to end
H="$TMP/hookrepo"
rm -rf "$H" "$MARK"; mkdir -p "$H/src" "$H/tests" "$H/.agents" "$MARK" && cd "$H" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cp "$R/tests/s1.sh" "$R/tests/s2.sh" "$R/tests/s3.sh" tests/
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[$(suite REG-1 "$S1"),$(suite REG-2 "$S2"),$(suite REG-3 "$S3")]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
LAST="0:0:0"
bgstop() { printf '{"session_id":"bg-1","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$H" REGRESSION_GATE_BUDGET_S=$BUDGET bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
bgstop; rc1=$?; delta; d1="$D"
grep -q 'ngân sách' "$TMP/out" && grep -q 'REG-3' "$TMP/out" && c1=yes || c1=no
bgstop; rc2=$?; delta; d2="$D"
if [ "$rc1" = 0 ] && [ "$d1" = "1:1:0" ] && [ "$c1" = yes ]; then ok "10a: hook Stop 1: budget spent, the Stop is let through with the UNTESTED message naming REG-3 (runs $d1)"
else bad "10a: hook Stop 1 rc=$rc1 runs=$d1 message=$c1 out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")'"; fi
if [ "$rc2" = 0 ] && [ "$d2" = "0:0:1" ] && ! grep -q 'ngân sách' "$TMP/out"; then ok "10b: hook Stop 2 on the same tree ran only REG-3 and ended the budget cycle (runs $d2)"
else bad "10b: hook Stop 2 rc=$rc2 runs=$d2 out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")'"; fi
cd "$TMP" || exit 1

echo
[ "$FAILS" -eq 0 ] && echo "budget resume: all checks passed" || { echo "budget resume: $FAILS FAILED"; exit 1; }
