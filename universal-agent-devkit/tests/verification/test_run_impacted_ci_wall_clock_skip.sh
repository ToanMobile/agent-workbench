#!/usr/bin/env bash
# Regression test (#1318): tests/gates/test_hook_big_command_fast_path.sh kills each hook at a 3 s wall-clock bound; on a slow GitHub runner a
# 50 KB case lands at 3.01 s and the CI job `devkit-tests` goes red on load, not on a defect (runs 44434672814, 44429843025), so the merge
# queue sees CI red and a card hits rebuild_cap and waits for a human. With DEVKIT_SKIP_CPU_BUDGET_TESTS=1 (the CI job) run_impacted.sh must
# skip it like the CPU-budget tests; without the variable (local gate, gate-full) it still runs and a failure stays red.
# Every check runs a COPY of run_impacted.sh in a fixture kit with a fake test of that name (never the real suite). bash 3.2 compatible.
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
T=tests/gates/test_hook_big_command_fast_path.sh

mk_kit() { # <dir> <marker>: a fixture kit whose only test is a fake $T that records its run in <marker> and always fails
  mkdir -p "$1/tests/lib" "$1/tests/gates" "$1/bin"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/"; : > "$1/tests/impact_map.txt"
  cp "$DEVKIT_DIR/bin/capacity.py" "$1/bin/"
  printf '%s\n' "echo run >> '$2'; exit 1" > "$1/$T"
  ( cd "$1" && git init -q . )
}
run_kit() { # <kit> [VAR=value ...]
  local k="$1"; shift
  OUT="$(cd "$k" && env "$@" bash tests/run_impacted.sh 2>&1)"; RC=$?
}

# A: CI (variable set) => the wall-clock test is skipped, the run is green, the skip is said
K="$TMP/a"; M="$TMP/a.mark"; mk_kit "$K" "$M"
run_kit "$K" DEVKIT_SKIP_CPU_BUDGET_TESTS=1
[ "$RC" -eq 0 ] && ok "A: CI run skips the wall-clock test (rc=0)" || { fail "A: rc=$RC, want 0"; echo "$OUT" | tail -n 15; }
printf '%s\n' "$OUT" | grep -qF "· skip CPU-budget test $T (DEVKIT_SKIP_CPU_BUDGET_TESTS=1)" && ok "A: skip line printed" || fail "A: no skip line"
[ ! -e "$M" ] && ok "A: the wall-clock test never ran" || fail "A: the wall-clock test ran"

# B: local gate / gate-full (variable unset) => it runs and a failure is red
K="$TMP/b"; M="$TMP/b.mark"; mk_kit "$K" "$M"
run_kit "$K" X=1
[ "$RC" -ne 0 ] && ok "B: without the variable a failing wall-clock test is red (rc=$RC)" || fail "B: rc=0, want non-zero"
[ -e "$M" ] && ok "B: the wall-clock test ran" || fail "B: the wall-clock test did not run"

[ "$FAILS" -eq 0 ] && { echo "all checks passed"; exit 0; } || { echo "$FAILS check(s) failed"; exit 1; }
