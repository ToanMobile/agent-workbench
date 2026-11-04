#!/usr/bin/env bash
# tests/run_impacted.sh + tests/lib/job_pool.py (04/11): two shards of one gate run side by side and share ONE pool of DEVKIT_TEST_JOBS slots.
#   a. two runners (DEVKIT_IMPACTED_DIRS=gates and =!gates, DEVKIT_TEST_JOBS=3, one DEVKIT_TEST_POOL_DIR): never more than 3 tests at once
#      across both, every test ran, both exit 0. Control: the same two runners without the pool reach more than 3 (the probe can see it).
#   b. a timing test of the alone list (test_budgets.sh) runs with no test of either runner beside it.
#   c. a test never sees DEVKIT_TEST_POOL_DIR / DEVKIT_JOB_POOL / the gate's DEVKIT_TEST_JOBS pin: a runner it starts itself must not wait on
#      the pool its parent holds, nor run the pinned count of tests inside one slot.
#   d. a red test of one runner stays red (rc 1, ✖ line), the other runner is not touched.
#   e. a pool dir that does not exist: the runner runs as before (no wait, every test ran).
#   f. tests/lib/clean_git_env.sh unsets the pool variables (INSTINCT-046).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED DEVKIT_TEST_POOL_DIR DEVKIT_JOB_POOL DEVKIT_SCOPED_TESTS
unset DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_PER_TEST_CACHE
export DEVKIT_CAPACITY_LOAD=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

# every fake test: enter $CONC_DIR, log "<name> <tests running now>", sleep, leave; the env it sees goes to $ENV_LOG
mk_test() { # <kit> <relative path> <sleep seconds> [exit code]
  local f="$1/$2" body
  mkdir -p "$(dirname "$f")"
  body='mkdir "$CONC_DIR/$$"; n=$(ls "$CONC_DIR" | wc -l | tr -d " "); echo "NAME $n" >> "$RUN_LOG"; echo "NAME pool=${DEVKIT_TEST_POOL_DIR:-} jp=${DEVKIT_JOB_POOL:-} jobs=${DEVKIT_TEST_JOBS:-}" >> "$ENV_LOG"; sleep SECS; n=$(ls "$CONC_DIR" | wc -l | tr -d " "); echo "NAME $n" >> "$RUN_LOG"; rmdir "$CONC_DIR/$$"; exit RC'
  body="${body//NAME/$(basename "$2" .sh)}"; body="${body//SECS/$3}"; body="${body//RC/${4:-0}}"
  printf '%s\n' "$body" > "$f"
}
mk_kit() { # <dir>: an empty kit with a copy of the runner, its helpers and bin/capacity.py
  mkdir -p "$1/tests/lib" "$1/bin"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/"; : > "$1/tests/impact_map.txt"
  cp "$DEVKIT_DIR/tests/lib/run_bounded.py" "$1/tests/lib/"
  [ -f "$DEVKIT_DIR/tests/lib/job_pool.py" ] && cp "$DEVKIT_DIR/tests/lib/job_pool.py" "$1/tests/lib/"
  cp "$DEVKIT_DIR/bin/capacity.py" "$1/bin/"
  ( cd "$1" && git init -q . )   # a scratch repo of its own: never the repo this test lives in
}
K="$TMP/kit"; mk_kit "$K"
for i in 1 2 3 4 5; do mk_test "$K" "tests/gates/test_g$i.sh" 2; done   # longer than the other runner: its alone test starts while these run
for i in 1 2 3 4; do mk_test "$K" "tests/verification/test_v$i.sh" 1; done
mk_test "$K" tests/context_memory/test_budgets.sh 1   # in the runner's alone list
peak() { awk '{ if ($2 > m) m = $2 } END { print m + 0 }' "$1"; }

# two_runners <tag> <pool dir or ""> [rc of test_v4]: both shards at once, OUT_G / OUT_R / RC_G / RC_R, logs $TMP/<tag>.*
two_runners() {
  export RUN_LOG="$TMP/$1.run" ENV_LOG="$TMP/$1.env" CONC_DIR="$TMP/$1.conc"; mkdir -p "$CONC_DIR"; : > "$RUN_LOG"; : > "$ENV_LOG"
  ( cd "$K" && env DEVKIT_IMPACTED_DIRS=gates DEVKIT_TEST_JOBS=3 ${2:+DEVKIT_TEST_POOL_DIR="$2"} bash tests/run_impacted.sh --all > "$TMP/$1.g" 2>&1; echo $? > "$TMP/$1.g.rc" ) &
  ( cd "$K" && env DEVKIT_IMPACTED_DIRS='!gates' DEVKIT_TEST_JOBS=3 ${2:+DEVKIT_TEST_POOL_DIR="$2"} bash tests/run_impacted.sh --all > "$TMP/$1.r" 2>&1; echo $? > "$TMP/$1.r.rc" ) &
  wait
  OUT_G="$(cat "$TMP/$1.g")"; OUT_R="$(cat "$TMP/$1.r")"; RC_G="$(cat "$TMP/$1.g.rc")"; RC_R="$(cat "$TMP/$1.r.rc")"
}
ended() { grep -c '^✔' "$TMP/$1.g" "$TMP/$1.r" | awk -F: '{ s += $2 } END { print s + 0 }'; }

# a. control first: without the pool the two runners together run up to 3 + 3 at once
two_runners nopool ""
[ "$(peak "$TMP/nopool.run")" -gt 3 ] && ok "a: control: two runners without a pool ran $(peak "$TMP/nopool.run") tests at once" \
  || fail "a: control: the probe never saw more than 3 at once without a pool ($(peak "$TMP/nopool.run")): it cannot tell"
mkdir -p "$TMP/pool"
two_runners pool "$TMP/pool"
p="$(peak "$TMP/pool.run")"
[ "$p" -le 3 ] && ok "a: one shared pool of 3: at most $p tests at once across both runners" || fail "a: $p tests at once with a pool of 3"
[ "$RC_G" = 0 ] && [ "$RC_R" = 0 ] && [ "$(ended pool)" = 10 ] && ok "a: both runners exit 0, all 10 tests ran" \
  || { fail "a: rc $RC_G / $RC_R, $(ended pool) of 10 tests passed"; printf '%s\n%s\n' "$OUT_G" "$OUT_R" | tail -12; }

# b. the alone test saw nobody else, at its start and at its end
b="$(awk '$1 == "test_budgets" && $2 != 1' "$TMP/pool.run")"
[ -z "$b" ] && grep -q '^test_budgets 1$' "$TMP/pool.run" && ok "b: the alone test ran with no test of either runner beside it" \
  || fail "b: the alone test saw others: $(grep '^test_budgets' "$TMP/pool.run" | tr '\n' ' ')"

# c. the pool variables never reach a test
leak="$(grep -v 'pool= jp= jobs=$' "$TMP/pool.env")"
[ -z "$leak" ] && ok "c: no test sees DEVKIT_TEST_POOL_DIR / DEVKIT_JOB_POOL / DEVKIT_TEST_JOBS" || fail "c: leaked to a test: $(printf '%s' "$leak" | head -2 | tr '\n' ' ')"

# d. a red test in one runner
mk_test "$K" tests/verification/test_v4.sh 1 3
rm -rf "$TMP/pool"; mkdir -p "$TMP/pool"
two_runners red "$TMP/pool"
[ "$RC_R" = 1 ] && printf '%s\n' "$OUT_R" | grep -q '^✖ tests/verification/test_v4.sh' && [ "$RC_G" = 0 ] \
  && ok "d: a red test stays red in its runner (rc 1, ✖ line), the other runner passes" || fail "d: rc $RC_G / $RC_R"
mk_test "$K" tests/verification/test_v4.sh 1

# e. a pool dir that is gone: no wait, as before
export RUN_LOG="$TMP/e.run" ENV_LOG="$TMP/e.env" CONC_DIR="$TMP/e.conc"; mkdir -p "$CONC_DIR"; : > "$RUN_LOG"; : > "$ENV_LOG"
OUT="$(cd "$K" && DEVKIT_IMPACTED_DIRS=gates DEVKIT_TEST_JOBS=5 DEVKIT_TEST_POOL_DIR="$TMP/nowhere" bash tests/run_impacted.sh --all 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(peak "$TMP/e.run")" -gt 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^✔')" = 5 ] \
  && ok "e: a missing pool dir runs the tests as before (5 passed, $(peak "$TMP/e.run") at once)" || fail "e: rc $RC, peak $(peak "$TMP/e.run")"

# f. tests/lib/clean_git_env.sh unsets the pool variables (INSTINCT-046): a test that sources it never joins a pool it inherited
f="$(DEVKIT_TEST_POOL_DIR=/x DEVKIT_JOB_POOL=/y bash -c '. "$1"; echo "${DEVKIT_TEST_POOL_DIR:-}${DEVKIT_JOB_POOL:-}"' _ "$DEVKIT_DIR/tests/lib/clean_git_env.sh")"
[ -z "$f" ] && ok "f: clean_git_env.sh unsets DEVKIT_TEST_POOL_DIR / DEVKIT_JOB_POOL" || fail "f: after clean_git_env.sh: '$f'"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($FAILS)"; exit 1; }
