#!/usr/bin/env bash
# Regression test (GeelyEx2 2026-10-11 11:59:25, OfficeReader 09:57:37): a suite KILLED from outside (SIGKILL exit 137 "Killed: 9",
# SIGTERM exit 143) ran no test to a verdict. The Stop hook blocked on it as a failing test ("fix code/test") although no code
# change can answer a kill: Geely 181 s of hook wall (REG-CAR-01) and 1 block, Office 163.7 s (REG-OR-APP) and 18 checklist rows
# left red. The 11:55:52 Geely block next to it stays: REG-GUARD-01 failed for real (case 5 below). Frequency outside those two
# days is unknown (EVIDENCE_KEEP keeps 10 logs per suite).
#   killed, no test failure printed          -> the Stop is allowed with a visible message, the verdict stays FAIL
#   killed after the retry of a lost results store (INFRA_RETRY) -> same
#   a real failing test (printed or exit 1)  -> still blocks;  an interrupt (exit 130) is no kill  -> still blocks
#   killed after a failing test was printed  -> still blocks (a verdict exists)
#   a compile error first, the re-run killed -> still blocks (review of Dot 20, 2026-10-12: the first run was a code problem)
#   the CLI gate never turns a killed suite into a PASS, and writes no full-pass receipt (XONG / push stay refused)
# Switch: REGRESSION_GATE_KILLED_IS_ENV=0 restores the old behaviour (killed = block).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export VACUITY_REVERT=0
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
stop() { printf '{"session_id":"s-%s","hook_event_name":"Stop"}' "$RANDOM" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
make_repo() { # $1 = body of suite.sh
  rm -rf "$REPO" && mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '%s\n' "$1" > suite.sh
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh suite.sh"}]}]}
JSON
  printf 'counter\n' > .gitignore
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
}

# 1. killed from outside, nothing printed about a test -> allowed + visible message
make_repo 'kill -9 $$'
stop; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && ok "killed suite: the Stop is allowed with a visible message" \
  || fail "killed suite blocked or silent (rc=$rc out='$(head -c 300 "$TMP/out")' err='$(head -c 300 "$TMP/err")')"

# 1b. the gate verdict is unchanged: the CLI run is REJECT, no receipt, so XONG / push stay refused
make_repo 'kill -9 $$'
CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --matrix "$REPO/templates/regression_matrix.json" --lang en --run-tests --full >"$TMP/cli" 2>&1; crc=$?
GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"
[ "$crc" = 1 ] && [ ! -e "$GD/postfix-gate/full_pass.json" ] && ok "CLI gate: exit 1, no full-pass receipt (a killed suite is never a PASS)" \
  || fail "CLI gate on a killed suite: exit $crc, receipt $([ -e "$GD/postfix-gate/full_pass.json" ] && echo written || echo none)"

# 1c. SIGTERM (exit -15 direct) and the shell forms of both kills (137, 143)
make_repo 'kill -TERM $$'
stop; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && ok "SIGTERM-killed suite: the Stop is allowed with a visible message" \
  || fail "SIGTERM-killed suite blocked or silent (rc=$rc err='$(head -c 200 "$TMP/err")')"
make_repo 'exit 137'
stop; rc=$?
[ "$rc" = 0 ] && ok "exit 137 (SIGKILL seen through a shell): allowed" || fail "exit 137 blocked (rc=$rc)"
make_repo 'exit 143'
stop; rc=$?
[ "$rc" = 0 ] && ok "exit 143 (SIGTERM seen through a shell): allowed" || fail "exit 143 blocked (rc=$rc)"
# 1d. only a kill is no verdict: Ctrl-C (130) still blocks
make_repo 'exit 130'
stop; rc=$?
[ "$rc" = 2 ] && ok "exit 130 (interrupt): still blocks" || fail "exit 130 allowed (rc=$rc)"

# 2. a real failing test (exit 1, Gradle-style failure line) -> still blocks
make_repo 'echo "FooTest > bar FAILED"; echo "1 test completed, 1 failed"; exit 1'
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-1" "$TMP/err" && ok "real test failure: still blocks" || fail "real test failure not blocked (rc=$rc)"

# 3. killed AFTER a failing test was printed -> a verdict exists, still blocks
make_repo 'echo "FooTest > bar FAILED"; kill -9 $$'
stop; rc=$?
[ "$rc" = 2 ] && ok "killed after a printed test failure: still blocks" || fail "killed-after-failure allowed (rc=$rc)"

# 4. lost results store (INFRA_RETRY), the retry is killed -> allowed
make_repo 'n=$(cat counter 2>/dev/null || echo 0); echo $((n + 1)) > counter
if [ "$n" = 0 ]; then echo "> java.nio.file.NoSuchFileException: build/test-results/t/binary/in-progress-results-generic.bin"; exit 1; fi
kill -9 $$'
stop; rc=$?
[ "$rc" = 0 ] && ok "lost results store, then the retry is killed: allowed" || fail "infra + kill blocked (rc=$rc)"

# 4b. a compile error on the first run, the re-run then killed: the first run was a code problem, the kill does not erase it
#     (review of Dot 20, 2026-10-12: the old rule looked only at the last run); the output names no failing test on purpose
make_repo 'n=$(cat counter 2>/dev/null || echo 0); echo $((n + 1)) > counter
if [ "$n" = 0 ]; then echo "e: Core.kt: Unresolved reference: Foo"; exit 1; fi
kill -9 $$'
stop; rc=$?
[ "$rc" = 2 ] && ok "compile error, then the re-run is killed: still blocks" || fail "compile error + kill allowed (rc=$rc)"

# 4c. killed on the first run and killed again on the re-run -> allowed (both runs reached no verdict)
make_repo 'kill -9 $$'
stop; rc=$?
[ "$rc" = 0 ] && ok "killed twice (run and re-run): allowed" || fail "killed twice blocked (rc=$rc)"

# 4d. NO re-run at all: the real incidents (Geely 181 s, Office 163.7 s) ran longer than FLAKY_RETRY_MAX_S (120 s), so flaky_retry returned
#     None and the kill was judged on the only run there was (round-2 review of Dot 20: every case above re-runs, so a mutant that
#     broke exactly this path survived). FLAKY_RETRY_MAX_S=0 puts every suite past the cap.
make_repo 'kill -9 $$'
FLAKY_RETRY_MAX_S=0 stop; rc=$?
[ "$rc" = 0 ] && ok "no re-run (suite past the cap), killed: allowed" || fail "no-re-run kill blocked (rc=$rc)"
make_repo 'exit 137'
FLAKY_RETRY_MAX_S=0 stop; rc=$?
[ "$rc" = 0 ] && ok "no re-run, exit 137: allowed" || fail "no-re-run exit 137 blocked (rc=$rc)"
make_repo 'echo "e: Core.kt: Unresolved reference: Foo"; exit 1'
FLAKY_RETRY_MAX_S=0 stop; rc=$?
[ "$rc" = 2 ] && ok "no re-run, compile error: still blocks" || fail "no-re-run compile error allowed (rc=$rc)"
make_repo 'echo "FooTest > bar FAILED"; kill -9 $$'
FLAKY_RETRY_MAX_S=0 stop; rc=$?
[ "$rc" = 2 ] && ok "no re-run, killed after a printed test failure: still blocks" || fail "no-re-run kill after a failure allowed (rc=$rc)"

# 5. two suites: a real failure next to a killed one -> blocks (the real failure is not hidden)
#    #647 (fail-fast): the first red suite stops the rest, so the real failure runs FIRST here (REG-F, then REG-K). With REG-K first the kill
#    stops the run before REG-F starts: the Stop is then allowed as an environment kill and REG-F is UNTESTED (known ceiling of fail-fast).
rm -rf "$REPO" && mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt; echo 'kill -9 $$' > k.sh; echo 'echo "FooTest > bar FAILED"; exit 1' > f.sh
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-F","name":"failing","command":"sh f.sh"},{"id":"REG-K","name":"killed","command":"sh k.sh"}]}]}
JSON
git add -A && git commit -qm init; echo "fun ok() = 2" > src/Core.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-F" "$TMP/err" && ok "killed suite next to a real failure: still blocks" || fail "mixed case allowed (rc=$rc)"

# 6. kill switch restores the old behaviour
make_repo 'kill -9 $$'
printf '{"session_id":"s-x","hook_event_name":"Stop"}' | REGRESSION_GATE_KILLED_IS_ENV=0 CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && ok "REGRESSION_GATE_KILLED_IS_ENV=0: a killed suite blocks again" || fail "switch ignored (rc=$rc)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
