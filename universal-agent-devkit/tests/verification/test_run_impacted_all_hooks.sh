#!/usr/bin/env bash
# tests/run_impacted.sh --all (what `agent-kit test` runs) also runs hooks/tests/test_*.sh (issues-bugs.md A.4, 13/10: 5 of the 9
# files there - test_git_guard_bypass, test_git_guard_nested, test_proof_gate_turn, test_reply_status, test_stop_repeat - ran in no
# suite, command or test: only a change that named them picked them). The three *_test.sh contract files stay out: `agent-kit test`
# runs them itself before the pool, so --all would run them twice.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

K="$TMP/kit"; mkdir -p "$K/tests/verification" "$K/hooks/tests"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/"
: > "$K/tests/impact_map.txt"
echo 'echo ok' > "$K/tests/verification/test_repo_consistency.sh"
echo 'exit 0' > "$K/hooks/tests/test_hook_case.sh"
echo 'echo ran > "$(dirname "$0")/../../contract.ran"' > "$K/hooks/tests/hook_contract_test.sh"
( cd "$K" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
out="$(cd "$K" && DEVKIT_TEST_JOBS=2 bash tests/run_impacted.sh --all 2>&1)"; rc=$?

printf '%s\n' "$out" | grep -qx "✔ hooks/tests/test_hook_case.sh" && ok "--all runs hooks/tests/test_*.sh" || fail "--all skipped hooks/tests/test_hook_case.sh: $out"
[ ! -e "$K/contract.ran" ] && ok "--all leaves the *_test.sh contract files to agent-kit test (no second run)" || fail "--all ran hook_contract_test.sh"
[ "$rc" = 0 ] && ok "--all rc 0" || fail "--all rc=$rc: $out"

echo 'exit 1' > "$K/hooks/tests/test_hook_case.sh"
out="$(cd "$K" && DEVKIT_TEST_JOBS=2 bash tests/run_impacted.sh --all 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "✖ hooks/tests/test_hook_case.sh" && ok "--all: a failing hooks test fails the run, named" || fail "failing hooks test: rc=$rc $out"

rm "$K/tests/verification/test_repo_consistency.sh"
out="$(cd "$K" && DEVKIT_TEST_JOBS=2 bash tests/run_impacted.sh --all 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q "no tests found under tests/\*/test_\*.sh" \
  && ok "--all with only hooks tests left: still the 'no tests found' error (OpenCodeReview 14/10)" || fail "suite gone, hooks left: rc=$rc $out"

[ "$FAILS" -eq 0 ] && echo "✅ test_run_impacted_all_hooks: all passed" || { echo "❌ test_run_impacted_all_hooks: $FAILS failed"; exit 1; }
