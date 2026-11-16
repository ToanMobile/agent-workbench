#!/usr/bin/env bash
# Regression test (#1216): tests/run_impacted.sh retries a failed TIMING test exactly once (CPU-budget tests go red on a slow CI
# runner under load, not on a defect); the 2nd run's exit code is final; a non-timing test is never retried.
# Every check runs a COPY of run_impacted.sh in a fixture kit of fake tests (never the real suite). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES
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
# a fake test that appends one line to <marker> per run and exits 1 on its first <fails> runs, 0 afterwards
mk_test() { # <kit> <relative path> <marker> <fails>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "echo run >> '$3'; [ \"\$(wc -l < '$3' | tr -d ' ')\" -le $4 ] && exit 1; exit 0" > "$1/$2"
}
runs() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
run_kit() { OUT="$(cd "$1" && bash tests/run_impacted.sh 2>&1)"; RC=$?; }

# A: timing test fails once, passes on the 2nd run => exit 0 and the retry line
K="$TMP/a"; mk_kit "$K"; M="$TMP/a.mark"
mk_test "$K" tests/context_memory/test_budgets.sh "$M" 1
run_kit "$K"
[ "$RC" -eq 0 ] && ok "A: flaky timing test passes on the retry (rc=0)" || { fail "A: rc=$RC, want 0"; echo "$OUT" | tail -n 15; }
printf '%s\n' "$OUT" | grep -q '· retry timing test tests/context_memory/test_budgets.sh (first rc=1)' && ok "A: retry line printed" || fail "A: no retry line"
[ "$(runs "$M")" = 2 ] && ok "A: ran exactly twice" || fail "A: ran $(runs "$M") times"

# B: always fails => still red after exactly one retry
K="$TMP/b"; mk_kit "$K"; M="$TMP/b.mark"
mk_test "$K" tests/context_memory/test_budgets.sh "$M" 99
run_kit "$K"
[ "$RC" -ne 0 ] && ok "B: a timing test failing twice stays red (rc=$RC)" || fail "B: rc=0, want non-zero"
[ "$(runs "$M")" = 2 ] && ok "B: ran exactly twice" || fail "B: ran $(runs "$M") times"

# C: non-timing test failing once is not retried
K="$TMP/c"; mk_kit "$K"; M="$TMP/c.mark"
mk_test "$K" tests/verification/test_plain_thing.sh "$M" 1
run_kit "$K"
[ "$RC" -ne 0 ] && ok "C: non-timing test not retried (rc=$RC)" || fail "C: rc=0, want non-zero"
[ "$(runs "$M")" = 1 ] && ok "C: ran once" || fail "C: ran $(runs "$M") times"
printf '%s\n' "$OUT" | grep -q 'retry timing test' && fail "C: retry line printed" || ok "C: no retry line"

[ "$FAILS" -eq 0 ] && { echo "all checks passed"; exit 0; } || { echo "$FAILS check(s) failed"; exit 1; }
