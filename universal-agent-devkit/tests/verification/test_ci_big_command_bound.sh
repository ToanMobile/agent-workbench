#!/usr/bin/env bash
# Regression test (#1318): tests/gates/test_hook_big_command_fast_path.sh kills each hook at BIG_COMMAND_BOUND_S (default 3 s) of wall
# clock; on the slow GitHub runner a 50 KB case lands at 3.01 s and the CI job `devkit-tests` goes red on load, not on a defect (runs
# 44434672814, 44429843025), so the merge queue sees CI red and a card hits rebuild_cap and waits for a human. The CI job must widen the
# bound (above 3 s, under the hooks' 7 s watchdog) and still RUN the test: its verdict checks (a danger hidden after 20-300 KB is refused)
# are the only CI cover of the big-command path on macOS /bin/bash 3.2, so it must not join the CPU-budget skip list.
# A: the workflow step that runs run_impacted.sh sets the bound. B: the test reads that variable. C: a COPY of run_impacted.sh in a fixture
# kit, with the CI variables set, runs a fake test of that name and passes the bound through (never the real suite). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WF="$DEVKIT_DIR/../.github/workflows/pr-review.yml"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_SKIP_CPU_BUDGET_TESTS BIG_COMMAND_BOUND_S
export DEVKIT_CAPACITY_LOAD=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
T=tests/gates/test_hook_big_command_fast_path.sh

# A: in pr-review.yml, the step whose run line calls run_impacted.sh sets BIG_COMMAND_BOUND_S to a number in (3, 7)
if [ ! -f "$WF" ]; then
  echo "skip A: no $WF (kit installed outside agent-workbench)"
else
  B="$(awk '/- name:/{env=""} /BIG_COMMAND_BOUND_S:/{v=$2; gsub(/"/, "", v); env=v} /run: bash universal-agent-devkit\/tests\/run_impacted\.sh/{print env; exit}' "$WF")"
  if printf '%s' "$B" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && awk -v b="$B" 'BEGIN{exit !(b > 3 && b < 7)}'; then
    ok "A: the CI step sets BIG_COMMAND_BOUND_S=$B (above 3, under the 7 s watchdog)"
  else
    fail "A: the CI step running run_impacted.sh sets BIG_COMMAND_BOUND_S='$B', want a number in (3, 7)"
  fi
fi

# B: the real test takes its bound from that variable (default 3)
grep -qF 'BOUND="${BIG_COMMAND_BOUND_S:-3}"' "$DEVKIT_DIR/$T" && ok "B: $T reads BIG_COMMAND_BOUND_S" || fail "B: $T no longer reads BIG_COMMAND_BOUND_S"

# C: with the CI variables, run_impacted.sh runs the test (no CPU-budget skip) and the child sees the bound
K="$TMP/kit"; M="$TMP/c.mark"
mkdir -p "$K/tests/lib" "$K/tests/gates" "$K/bin"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/"; : > "$K/tests/impact_map.txt"
cp "$DEVKIT_DIR/bin/capacity.py" "$K/bin/"
printf '%s\n' "printf '%s' \"\${BIG_COMMAND_BOUND_S-unset}\" > '$M'; exit 0" > "$K/$T"
( cd "$K" && git init -q . )
OUT="$(cd "$K" && env DEVKIT_SKIP_CPU_BUDGET_TESTS=1 BIG_COMMAND_BOUND_S=6 bash tests/run_impacted.sh 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "C: run rc=0" || { fail "C: rc=$RC, want 0"; echo "$OUT" | tail -n 10; }
printf '%s\n' "$OUT" | grep -qF "· skip CPU-budget test $T" && fail "C: CI skips $T (its verdict checks would be lost)" || ok "C: CI does not skip $T"
[ "$(cat "$M" 2>/dev/null)" = "6" ] && ok "C: the test ran and saw BIG_COMMAND_BOUND_S=6" || fail "C: the test saw '$(cat "$M" 2>/dev/null || echo 'not run')'"

[ "$FAILS" -eq 0 ] && { echo "all checks passed"; exit 0; } || { echo "$FAILS check(s) failed"; exit 1; }
