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

[ "$FAILS" -eq 0 ] && echo "✅ test_flaky: all passed" || { echo "❌ test_flaky: $FAILS failed"; exit 1; }
