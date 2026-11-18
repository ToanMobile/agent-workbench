#!/usr/bin/env bash
# Regression test: with DEVKIT_SKIP_CPU_BUDGET_TESTS=1 (the CI job) tests/run_impacted.sh does NOT run the CPU-budget tests (they measure the
# owner's local hardware and go red on a slow runner); without the variable they run and fail as before; a failing NON-budget test stays red.
# Every check runs a COPY of run_impacted.sh in a fixture kit of fake tests (never the real suite). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_SKIP_CPU_BUDGET_TESTS
export DEVKIT_CAPACITY_LOAD=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk_kit() { # <dir>
  mkdir -p "$1/tests/lib" "$1/tests/verification" "$1/tests/context_memory" "$1/bin"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/"; : > "$1/tests/impact_map.txt"
  cp "$DEVKIT_DIR/bin/capacity.py" "$1/bin/"
  ( cd "$1" && git init -q . )
}
mk_fail() { # <kit> <relative path> <marker>: a fake test that records its run in <marker> and always fails
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "echo run >> '$3'; exit 1" > "$1/$2"
}
run_kit() { # <kit> [VAR=value ...]
  local k="$1"; shift
  OUT="$(cd "$k" && env "$@" bash tests/run_impacted.sh 2>&1)"; RC=$?
}

# A: variable set, a budget test that always fails => exit 0, skip line, never ran
K="$TMP/a"; mk_kit "$K"; M="$TMP/a.mark"
mk_fail "$K" tests/context_memory/test_budgets.sh "$M"
run_kit "$K" DEVKIT_SKIP_CPU_BUDGET_TESTS=1
[ "$RC" -eq 0 ] && ok "A: skipped budget test does not fail the run (rc=0)" || { fail "A: rc=$RC, want 0"; echo "$OUT" | tail -n 15; }
printf '%s\n' "$OUT" | grep -q '· skip CPU-budget test tests/context_memory/test_budgets.sh (DEVKIT_SKIP_CPU_BUDGET_TESTS=1)' && ok "A: skip line printed" || fail "A: no skip line"
[ ! -e "$M" ] && ok "A: the budget test never ran" || fail "A: the budget test ran"

# B: variable unset => the same test runs and the run is red
K="$TMP/b"; mk_kit "$K"; M="$TMP/b.mark"
mk_fail "$K" tests/context_memory/test_budgets.sh "$M"
run_kit "$K" X=1
[ "$RC" -ne 0 ] && ok "B: without the variable a failing budget test is red (rc=$RC)" || fail "B: rc=0, want non-zero"
[ -e "$M" ] && ok "B: the budget test ran" || fail "B: the budget test did not run"

# C: variable set, a failing NON-budget test stays red
K="$TMP/c"; mk_kit "$K"; M="$TMP/c.mark"
mk_fail "$K" tests/verification/test_plain_thing.sh "$M"
run_kit "$K" DEVKIT_SKIP_CPU_BUDGET_TESTS=1
[ "$RC" -ne 0 ] && ok "C: a failing non-budget test stays red with the variable set (rc=$RC)" || fail "C: rc=0, want non-zero"
[ -e "$M" ] && ok "C: the non-budget test ran" || fail "C: the non-budget test did not run"

# D: the variable is for THIS runner only: a test it runs must not inherit it (a test of run_impacted.sh itself, or any nested runner, would
#    skip its own fixtures; PR #1219 broke 6 such tests on CI before this was unset)
K="$TMP/d"; mk_kit "$K"; M="$TMP/d.mark"
printf '%s\n' "printf '%s' \"\${DEVKIT_SKIP_CPU_BUDGET_TESTS-unset}\" > '$M'; exit 0" > "$K/tests/verification/test_env_probe.sh"
run_kit "$K" DEVKIT_SKIP_CPU_BUDGET_TESTS=1
[ "$RC" -eq 0 ] && ok "D: probe test ran (rc=0)" || { fail "D: rc=$RC"; echo "$OUT" | tail -n 10; }
[ "$(cat "$M" 2>/dev/null)" = "unset" ] && ok "D: the child test sees the variable unset" || fail "D: the child saw '$(cat "$M" 2>/dev/null)'"

[ "$FAILS" -eq 0 ] && { echo "all checks passed"; exit 0; } || { echo "$FAILS check(s) failed"; exit 1; }
