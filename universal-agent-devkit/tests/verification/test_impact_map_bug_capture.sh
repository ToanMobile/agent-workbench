#!/usr/bin/env bash
# tests/impact_map.txt, scripts/context/enrich_context.py -> tests/verification/test_bug_capture.sh (2026-10-09 follow-up, found by a
# RED-proof): the bug-capture test reaches enrich_context.py through hooks/prompt_context.sh and names neither, so a change to
# enrich_context.py (the ROLE_OPENING filter that drops real reports) never selected it: the gate did not run the one test that guards
# that filter, and a RED-proof that put the filter's bug back called the test VACUOUS because it never ran in the sandbox.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
sel() { (cd "$DEVKIT_DIR" && env -u DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED="$1" bash tests/run_impacted.sh --list 2>/dev/null); }
sel scripts/context/enrich_context.py | grep -qx "tests/verification/test_bug_capture.sh" \
  && ok "a change to enrich_context.py selects test_bug_capture.sh" || fail "enrich_context.py does not select test_bug_capture.sh: $(sel scripts/context/enrich_context.py | tr '\n' ' ')"
[ "$FAILS" -eq 0 ] && echo "✅ test_impact_map_bug_capture: all passed" || { echo "❌ test_impact_map_bug_capture: $FAILS failed"; exit 1; }
