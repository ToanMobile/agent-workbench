#!/usr/bin/env bash
# bin/post-fix-gate.py (04/11, Việc 2): the #616 shards of the kit runner (DEVKIT_IMPACTED_DIRS=<dir> bash …/tests/run_impacted.sh) ran one after
# another; they now run side by side as one group sharing ONE pool of test slots (tests/lib/job_pool.py via DEVKIT_TEST_POOL_DIR).
#   1. two flagged shards that each wait for the other to START both pass (only when they overlap; the sequential gate fails the first: RED)
#   2. both get the same DEVKIT_TEST_POOL_DIR and DEVKIT_TEST_JOBS = what the runner's `--jobs` says (3 here); the pool dir is gone afterwards
#   3. the group holds ONE heavy slot while its members run (each shard is a cpu suite: three would fill heavy_max)
#   4. a red shard does not skip a sibling of its group (fail-fast #647 spares the group), the gate still fails
#   5. DEVKIT_GATE_PARALLEL=0: one after another, no pool
#   7. the group's heavy slot follows its heaviest member: a first shard whose selection is light beside a cpu one still holds one slot
#   8. a Stop-like run (GATE_TOTAL_BUDGET_S: its budget stops new suites) keeps the shards one after another, no pool
#   9. every member gets the SUM of the members' timeouts: two shards of 7 s each pass under --timeout 5 (each waits on the other's slots)
#  10. DEVKIT_TEST_JOBS set by the user: a fixed pool of that size, as many workers
#  11. the pool follows capacity: about every POOL_REFRESH_S (5 s) the gate rewrites its size; with no other gate it grows to the workers
#   6. a run_impacted.sh suite without the DEVKIT_IMPACTED_DIRS= prefix (not a shard) never joins: no pool; a DEVKIT_TEST_POOL_DIR /
#      DEVKIT_JOB_POOL in the caller's env never reaches a suite (suite_env drops them, INSTINCT-046)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
unset DEVKIT_GATE_PARALLEL DEVKIT_CAPACITY DEVKIT_TEST_JOBS DEVKIT_TEST_POOL_DIR DEVKIT_JOB_POOL
export DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0 DEVKIT_SLOT_CPU_S=60
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo 0 > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD   # clean_git_env.sh holds them for nested gates: this test needs the real heavy pool
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0
# a stand-in for the kit runner: --jobs and --list answer like it; a run logs its env, counts the heavy slots held, and waits up to 8 s
# for $WANT shards to have started (only possible when they overlap); dir "red" fails at once
make_repo() {
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests/lib" "$R/tests/x" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '999 tests/x/test_long.sh\n1 tests/x/test_short.sh\n' > tests/lib/test_durations.txt   # light: 1 s selection, cpu: 999 s
  printf 'exit 0\n' > tests/x/test_long.sh; printf 'exit 0\n' > tests/x/test_short.sh
  cat > tests/run_impacted.sh <<'SH'
# devkit-selection-list: (the marker bin/suite_cache.py needs before it asks --list: heavy_slot then classes each shard by its selection)
case "${1:-}" in --jobs) echo "${DEVKIT_TEST_JOBS:-3}"; exit 0 ;; --list) if [ "${DEVKIT_IMPACTED_DIRS:-}" = light ]; then echo tests/x/test_short.sh; else echo tests/x/test_long.sh; fi; exit 0 ;; esac
d="${DEVKIT_IMPACTED_DIRS:-none}"
held="$(python3 -c '
import fcntl, glob, os, sys
n = 0
for p in glob.glob(os.path.join(sys.argv[1], "heavy-*.lock")):
    fd = os.open(p, os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB); fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        n += 1
    os.close(fd)
print(n)' "$SB_HEAVY_SLOT_DIR")"
size="$(cat "${DEVKIT_TEST_POOL_DIR:-/nonexistent}/size" 2>/dev/null)"
echo "$d pool=${DEVKIT_TEST_POOL_DIR:-} jobs=${DEVKIT_TEST_JOBS:-} size=${size:-} heavy=$held" >> "$MARK/env"
[ -n "${DEVKIT_TEST_POOL_DIR:-}" ] && [ -d "$DEVKIT_TEST_POOL_DIR" ] && echo "$DEVKIT_TEST_POOL_DIR" > "$MARK/pooldir"
touch "$MARK/start.$d"
[ "$d" = red ] && exit 1
i=0; while [ "$(ls "$MARK" | grep -c '^start\.')" -lt "${WANT:-2}" ] && [ $i -lt 80 ]; do sleep 0.1; i=$((i + 1)); done
[ "$(ls "$MARK" | grep -c '^start\.')" -ge "${WANT:-2}" ] || exit 1
sleep "${SLEEP_S:-0}"
[ -n "${DEVKIT_TEST_POOL_DIR:-}" ] && echo "$d late=$(cat "$DEVKIT_TEST_POOL_DIR/size" 2>/dev/null) jobs=${DEVKIT_TEST_JOBS:-}" >> "$MARK/late"
exit 0
SH
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
}
shard() { # id dir: a flagged shard of the runner
  printf '{"id":"%s","name":"%s","command":"DEVKIT_IMPACTED_DIRS=%s bash tests/run_impacted.sh","parallel_safe":true}' "$1" "$1" "$2"
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests "$@" 2>&1)"; RC=$?; }
passed()  { printf '%s\n' "$OUT" | grep -qE "\[x\].*$1"; }
failed()  { printf '%s\n' "$OUT" | grep -qE "\[ \] (FAIL|TIMEOUT).*$1"; }

# 1–3. two shards side by side, one pool, one heavy slot
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=2 run_gate
if [ "$RC" = 0 ] && passed REG-S-A && passed REG-S-B; then ok "1: two shards that wait for each other run side by side (exit 0)"
else bad "1: the shards did not overlap (exit $RC)"; printf '%s\n' "$OUT" | grep -E 'REG-S|FAIL|✖' | tail -8; fi
pools="$(sed -n 's/.* pool=\([^ ]*\) .*/\1/p' "$MARK/env" | sort -u)"
jobs="$(sed -n 's/.* jobs=\([^ ]*\) .*/\1/p' "$MARK/env" | sort -u)"
size="$(sed -n 's/.* size=\([^ ]*\) .*/\1/p' "$MARK/env" | sort -u)"
if [ "$(printf '%s\n' "$pools" | wc -l | tr -d ' ')" = 1 ] && [ -n "$pools" ] && [ "$size" = 3 ] && [ "$jobs" -ge 3 ] 2>/dev/null; then
  ok "2: both shards got the same pool, sized 3 now (the runner's --jobs), with $jobs workers (no other gate on the machine)"
else bad "2: pools '$(printf '%s' "$pools" | tr '\n' ' ')' size '$size' jobs '$(printf '%s' "$jobs" | tr '\n' ' ')'"; cat "$MARK/env"; fi
[ -s "$MARK/pooldir" ] && [ ! -e "$(cat "$MARK/pooldir")" ] && ok "2: the pool dir is removed after the group" \
  || bad "2: pool dir '$(cat "$MARK/pooldir" 2>/dev/null)' still there or never made"
heavy="$(sed -n 's/.* heavy=\([0-9]*\)$/\1/p' "$MARK/env" | sort -u | tr '\n' ' ')"
[ "$heavy" = "1 " ] && ok "3: one heavy slot held for the whole group" || bad "3: heavy slots held seen by the shards: '$heavy'"

# 4. a red shard does not skip its sibling
make_repo "$(shard REG-S-RED red),$(shard REG-S-B b)"
WANT=2 run_gate
if [ "$RC" != 0 ] && failed REG-S-RED && passed REG-S-B && [ -e "$MARK/start.b" ]; then ok "4: a red shard fails the gate, its sibling still ran and passed"
else bad "4: exit $RC"; printf '%s\n' "$OUT" | grep -E 'REG-S|UNTESTED|Not run' | tail -6; fi

# 5. kill switch
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=1 DEVKIT_GATE_PARALLEL=0 run_gate
if [ "$RC" = 0 ] && ! grep -q 'pool=/' "$MARK/env"; then ok "5: DEVKIT_GATE_PARALLEL=0 runs the shards one after another, no pool"
else bad "5: exit $RC, env: $(tr '\n' ' ' < "$MARK/env")"; fi

# 6. not a shard (no DEVKIT_IMPACTED_DIRS= prefix): never grouped
make_repo "$(printf '{"id":"REG-P-1","name":"p","command":"bash tests/run_impacted.sh","parallel_safe":true}'),$(printf '{"id":"REG-P-2","name":"p","command":"bash tests/run_impacted.sh --all","parallel_safe":true}')"
WANT=1 DEVKIT_TEST_POOL_DIR="$TMP" DEVKIT_JOB_POOL=x run_gate   # 6b (INSTINCT-046): a pool variable of the caller never reaches a suite
if [ "$RC" = 0 ] && ! grep -q 'pool=/' "$MARK/env"; then ok "6: a run_impacted.sh suite that is not a shard does not join a group, nor the caller's pool"
else bad "6: exit $RC, env: $(tr '\n' ' ' < "$MARK/env")"; fi

# 10. a user pin is a fixed pool
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=2 DEVKIT_TEST_JOBS=2 run_gate
pinned="$(sed -n 's/.* jobs=\([^ ]*\) size=\([^ ]*\) .*/\1:\2/p' "$MARK/env" | sort -u)"
[ "$RC" = 0 ] && [ "$pinned" = "2:2" ] && ok "10: DEVKIT_TEST_JOBS=2 from the user: 2 workers, pool size 2" || bad "10: exit $RC, jobs:size '$pinned'"

# 11. the pool grows while the group runs
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=2 SLEEP_S=7 run_gate
late="$(sed -n 's/.* late=\([0-9]*\) jobs=\([0-9]*\)$/\1:\2/p' "$MARK/late" 2>/dev/null | sort -u | head -1)"
if [ "$RC" = 0 ] && [ -n "$late" ] && [ "${late%%:*}" = "${late##*:}" ] && [ "${late%%:*}" -gt 3 ]; then
  ok "11: the pool grew from 3 to ${late%%:*} slots while the group ran (capacity re-read)"
else bad "11: exit $RC, late size:jobs '$late'"; fi

# 7. a light first member beside a cpu one: the group still holds one heavy slot
make_repo "$(shard REG-S-L light),$(shard REG-S-B b)"
WANT=2 run_gate
heavy="$(sed -n 's/.* heavy=\([0-9]*\)$/\1/p' "$MARK/env" | sort -u | tr '\n' ' ')"
[ "$RC" = 0 ] && [ "$heavy" = "1 " ] && ok "7: a light first shard beside a cpu one: the group holds one heavy slot" \
  || bad "7: exit $RC, heavy slots seen: '$heavy'"

# 8. Stop-like run: sequential, no pool
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=1 GATE_TOTAL_BUDGET_S=600 run_gate
if [ "$RC" = 0 ] && ! grep -q 'pool=/' "$MARK/env"; then ok "8: a Stop-like run (GATE_TOTAL_BUDGET_S) keeps the shards sequential, no pool"
else bad "8: exit $RC, env: $(tr '\n' ' ' < "$MARK/env")"; fi

# 9. summed timeout: 7 s each, side by side, --timeout 5
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
WANT=2 SLEEP_S=7 DEVKIT_GATE_EXTEND_MIN_S=100000 run_gate --timeout 5
if [ "$RC" = 0 ] && passed REG-S-A && passed REG-S-B; then ok "9: members get the sum of the timeouts (two 7 s shards pass under --timeout 5)"
else bad "9: exit $RC"; printf '%s\n' "$OUT" | grep -E 'REG-S|TIMEOUT' | tail -6; fi

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($FAILS)"; exit 1; }
