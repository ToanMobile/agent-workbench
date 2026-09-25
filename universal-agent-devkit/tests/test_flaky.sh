#!/usr/bin/env bash
# Regression test: a test that fails, then passes on the same code, is FLAKY — never a PASS.
#  - post-fix-gate --run-tests re-runs a failing suite once (only a suite that ran under
#    FLAKY_RETRY_MAX_S, default 120 s); red then green → the run stays FAIL (the gate still
#    rejects) and is flagged flaky; the checklist shows 🔁 FLAKY and opens a bug for it.
#  - a suite that fails twice is FAIL, not flaky; FLAKY_RETRY=0 turns the re-run off.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_project() {  # new_project <command>
  P="$TMP/p$RANDOM"; mkdir -p "$P/src" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/core.py
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [{"component": "Core", "watch_files": ["src/*.py"],
      "mandatory_regression_tests": [{"id": "REG-CORE", "name": "core", "command": sys.argv[1]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$1"
    git add -A && git commit -qm init && echo "x = 2" > src/core.py )
}
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['REG-CORE']))"; }
gate() { ( cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1 ); }

# red on the first call, green on the second
new_project 'if [ -f .ran ]; then echo green; else touch .ran; echo "1 failed"; exit 1; fi'
gate; rc=$?
[ "$rc" != 0 ] && ok "red then green: the gate still rejects (exit $rc)" || fail "flaky run passed the gate"
[ "$(st)" = FLAKY ] && ok "red then green on the same code → FLAKY, not PASS" || fail "status: $(st)"
grep -q "FLAKY" "$P/.agents/regression_checklist.md" && ok "view shows the flaky test" || fail "view"
python3 -c "import json;d=json.load(open('$P/.agents/regression_status.json'))['items'];assert any(i.get('kind')=='bug' and 'REG-CORE' in i.get('tests',[]) and i.get('fixed') is False for i in d.values())" 2>/dev/null \
  && ok "a flaky test opens a bug linked to it" || fail "no flaky bug"
log="$(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['REG-CORE']['last'].get('log') or '')")"
[ -n "$log" ] && grep -qx "1 failed" "$P/$log" && grep -qx "green" "$P/$log" && grep -q "FLAKY_RETRY" "$P/$log" \
  && ok "evidence keeps both runs" || fail "evidence: $log"

new_project 'echo "1 failed"; exit 1'
gate
[ "$(st)" = FAIL ] && ok "red twice → FAIL, not flaky" || fail "twice: $(st)"

new_project 'if [ -f .ran ]; then echo green; else touch .ran; echo "1 failed"; exit 1; fi'
( cd "$P" && FLAKY_RETRY=0 CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1 )
[ "$(st)" = FAIL ] && [ -f "$P/.ran" ] && ok "FLAKY_RETRY=0: no re-run, plain FAIL" || fail "retry off: $(st)"

# A BUILD / infra failure (no test failed: Gradle lost its own output file) then green on the re-run is
# not a flaky test: the green run is a real PASS of the same code, flagged infra_retry, and no bug opens.
new_project 'if [ -f .ran ]; then echo "BUILD SUCCESSFUL"; else touch .ran; printf "> Task :app:testReleaseUnitTest FAILED\n* What went wrong:\nExecution failed for task :app:testReleaseUnitTest.\n> Failed to create MD5 hash for file results-generic.bin (No such file or directory)\nBUILD FAILED\n"; exit 1; fi'
gate; rc=$?
[ "$rc" = 0 ] && [ "$(st)" = PASS ] && ok "infra failure then green → PASS (the re-run really ran green), not FLAKY" || fail "infra: rc=$rc st=$(st)"
python3 -c "import json;d=json.load(open('$P/.agents/regression_status.json'))['items'];assert d['REG-CORE']['last'].get('infra_retry') is True;assert not any(i.get('kind')=='bug' for i in d.values())" 2>/dev/null \
  && ok "infra re-run is flagged infra_retry and opens no flaky bug" || fail "infra flag/bug: $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['REG-CORE']['last'])")"
# …but a real test failure that passes on the re-run stays FLAKY, even with Gradle's task-failure noise around it
new_project 'if [ -f .ran ]; then echo "BUILD SUCCESSFUL"; else touch .ran; printf "com.x.CartTest > total FAILED\n    java.lang.AssertionError at CartTest.kt:12\n> Task :app:testReleaseUnitTest FAILED\nExecution failed for task :app:testReleaseUnitTest.\n> There were failing tests.\n"; exit 1; fi'
gate
[ "$(st)" = FLAKY ] && ok "a test that failed (Gradle test line) then passed → still FLAKY" || fail "gradle flaky: $(st)"

# Two Gradle runs in one project tree corrupt build/test-results/**/binary/results.bin: the task
# dies on java.io.EOFException (or a missing in-progress-results*.bin), sometimes next to test
# failures the corrupted run printed. OfficeReader, 2026-09-25 (.agents/evidence/REG-OR-CORE/
# 20260925-070114.log): "2 failed" + AssertionFailedError + "> java.io.EOFException", green on the
# re-run → a false "Test chập chờn (flaky)" bug row. A run that died on the test-results store is
# infrastructure: re-run it, and never call it FLAKY.
CORE_SHAPE='FileOpenErrorTypeStabilityTest > obfuscated app exception FAILED\n    org.opentest4j.AssertionFailedError at FileOpenErrorTypeStabilityTest.kt:40\n> Task :core:common:testDebugUnitTest FAILED\n71 tests completed, 2 failed\nFAILURE: Build failed with an exception.\n* What went wrong:\nExecution failed for task '"'"':core:common:testDebugUnitTest'"'"'.\n> java.io.EOFException\nBUILD FAILED in 13s\n'
new_project "if [ -f .ran ]; then echo 'BUILD SUCCESSFUL'; else touch .ran; printf '$CORE_SHAPE'; exit 1; fi"
gate; rc=$?
[ "$rc" = 0 ] && [ "$(st)" = PASS ] && ok "EOFException run (with the corrupted run's test failures) then green → PASS, not FLAKY" \
  || fail "EOFException: rc=$rc st=$(st)"
python3 -c "import json;d=json.load(open('$P/.agents/regression_status.json'))['items'];assert d['REG-CORE']['last'].get('infra_retry') is True;assert not any(i.get('kind')=='bug' for i in d.values())" 2>/dev/null \
  && ok "EOFException: flagged infra_retry, no flaky bug row" || fail "EOFException bug row: $(python3 -c "import json;print([i.get('title') for i in json.load(open('$P/.agents/regression_status.json'))['items'].values() if i.get('kind')=='bug'])")"
# The infra re-run is not the flaky re-run: it happens past FLAKY_RETRY_MAX_S (a long Gradle suite).
new_project "if [ -f .ran ]; then echo 'BUILD SUCCESSFUL'; else touch .ran; printf '> Task :app:testDebugUnitTest FAILED\nCould not write XML test results for com.x.T to file /p/app/build/test-results/testDebugUnitTest/TEST-com.x.T.xml\n'; exit 1; fi"
( cd "$P" && FLAKY_RETRY_MAX_S=0 CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1 ); rc=$?
[ "$rc" = 0 ] && [ "$(st)" = PASS ] && ok "\"Could not write … test-results\": re-run even past FLAKY_RETRY_MAX_S → PASS" || fail "infra past cap: rc=$rc st=$(st)"
# Both runs die on the results store (REG-OR-FEATURE/20260925-070153-2.log: EOFException, then
# NoSuchFileException on in-progress-results-generic.bin): FAIL, never FLAKY, no bug row.
new_project "if [ -f .ran ]; then printf '> Task :f:testDebugUnitTest FAILED\n> java.nio.file.NoSuchFileException: /p/f/build/test-results/testDebugUnitTest/binary/in-progress-results-generic.bin\n'; exit 1; else touch .ran; printf '> Task :f:testDebugUnitTest FAILED\n> java.io.EOFException\n'; exit 1; fi"
gate
[ "$(st)" = FAIL ] && python3 -c "import json;d=json.load(open('$P/.agents/regression_status.json'))['items'];assert not any(i.get('kind')=='bug' for i in d.values())" 2>/dev/null \
  && ok "results store broken on both runs → FAIL, no flaky bug" || fail "both infra: $(st)"

# Two gate runs on ONE project tree at once (two sessions' Stop hooks) must not run their suites
# side by side: a per-project test-run lock (.claude/audit-gate/test_run.lock) serialises them.
# The suite marks itself active outside the tree and reports an overlap as a failed test.
MARK="$TMP/active"; mkdir -p "$MARK"; : > "$TMP/overlap.log"
new_project "m=$MARK/\$\$; : > \$m; i=0; while [ \$i -lt 25 ]; do n=\$(ls $MARK | wc -l); [ \$n -gt 1 ] && break; sleep 0.1; i=\$((i+1)); done; rm -f \$m; if [ \$n -gt 1 ]; then echo OVERLAP >> $TMP/overlap.log; echo '1 failed'; exit 1; fi; echo 'BUILD SUCCESSFUL'"
( cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >"$TMP/g1" 2>&1 ) & g1=$!
( cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >"$TMP/g2" 2>&1 ) & g2=$!
wait $g1; r1=$?; wait $g2; r2=$?
[ ! -s "$TMP/overlap.log" ] && ok "two concurrent gate runs: suites serialised (no overlap)" || fail "suites overlapped $(wc -l < "$TMP/overlap.log") time(s)"
[ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$(st)" = PASS ] && ok "two concurrent gate runs: both PASS" || fail "concurrent: r1=$r1 r2=$r2 st=$(st)"
python3 -c "import json;d=json.load(open('$P/.agents/regression_status.json'))['items'];assert not any(i.get('kind')=='bug' for i in d.values())" 2>/dev/null \
  && ok "two concurrent gate runs: no FLAKY bug row" || fail "concurrent runs opened a bug row"

[ "$FAILS" -eq 0 ] && echo "✅ test_flaky: all passed" || { echo "❌ test_flaky: $FAILS failed"; exit 1; }
