#!/usr/bin/env bash
# bin/post-fix-gate.py, the shard group's pool sizer (#976; the group itself: test_gate_shard_group.sh):
#   1. the pool SHRINKS when another gate is busy: DEVKIT_TEST_JOBS_BUSY=2 on 12 simulated cores, the runners get the workers of a machine
#      with no other gate (capacity.test_jobs(busy=1) = 16) but the late pool size is capacity.test_jobs() = 8, below the worker count
#      (test_gate_shard_group.sh case 11 only proves it grows: DEVKIT_CAPACITY_CORES makes busy 1 there)
#   2. capacity.test_jobs() broken: ONE warning, no sizer thread (no "pool size kept" every POOL_REFRESH_S), a fixed pool of the runner's
#      --jobs, and the shards still pass
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
unset DEVKIT_GATE_PARALLEL DEVKIT_CAPACITY DEVKIT_TEST_JOBS DEVKIT_TEST_POOL_DIR DEVKIT_JOB_POOL DEVKIT_TEST_JOBS_BUSY
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
# a stand-in for the kit runner (as in test_gate_shard_group.sh): --jobs says 3; a run waits for both shards to start, sleeps SLEEP_S and
# logs the pool size it sees then (late=) and its worker count (jobs=)
make_repo() {
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests/lib" "$R/tests/x" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '999 tests/x/test_long.sh\n' > tests/lib/test_durations.txt
  printf 'exit 0\n' > tests/x/test_long.sh
  cat > tests/run_impacted.sh <<'SH'
# devkit-selection-list: (the marker bin/suite_cache.py needs before it asks --list)
case "${1:-}" in --jobs) echo "${DEVKIT_TEST_JOBS:-3}"; exit 0 ;; --list) echo tests/x/test_long.sh; exit 0 ;; esac
d="${DEVKIT_IMPACTED_DIRS:-none}"
touch "$MARK/start.$d"
i=0; while [ "$(ls "$MARK" | grep -c '^start\.')" -lt 2 ] && [ $i -lt 80 ]; do sleep 0.1; i=$((i + 1)); done
[ "$(ls "$MARK" | grep -c '^start\.')" -ge 2 ] || exit 1
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
passed() { printf '%s\n' "$OUT" | grep -qE "\[x\].*$1"; }

# 1. shrink: another gate busy (DEVKIT_TEST_JOBS_BUSY=2), the late size is below the workers
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
OUT="$(CLAUDE_PROJECT_DIR="$R" DEVKIT_TEST_JOBS_BUSY=2 SLEEP_S=7 python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
late="$(sed -n 's/.* late=\([0-9]*\) jobs=\([0-9]*\)$/\1:\2/p' "$MARK/late" 2>/dev/null | sort -u | head -1)"
want="$(DEVKIT_TEST_JOBS_BUSY=2 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import capacity as c; print(f"{c.test_jobs()}:{c.test_jobs(busy=1)}")' "$DEVKIT_DIR/bin")"
if [ "$RC" = 0 ] && [ -n "$late" ] && [ "$late" = "$want" ] && [ "${late%%:*}" -lt "${late##*:}" ]; then
  ok "1: another gate busy (DEVKIT_TEST_JOBS_BUSY=2): the pool is ${late%%:*} slots, below the ${late##*:} workers"
else bad "1: exit $RC, late size:workers '$late' (want '$want', size below workers)"; fi

# 2. capacity.test_jobs() broken: one warning, no sizer, a fixed pool of the runner's --jobs (3)
cat > "$TMP/broken_capacity.py" <<'PY'
# runs post-fix-gate.py with a capacity module whose test_jobs() raises (every other function is the real one)
import importlib.util, os, runpy, sys
gate = sys.argv[1]
spec = importlib.util.spec_from_file_location("capacity", os.path.join(os.path.dirname(gate), "capacity.py"))
cap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cap)
def _broken(*_a, **_k):
    raise RuntimeError("capacity broken (test)")
cap.test_jobs = _broken
sys.modules["capacity"] = cap
sys.argv = sys.argv[1:]
runpy.run_path(gate, run_name="__main__")
PY
make_repo "$(shard REG-S-A a),$(shard REG-S-B b)"
OUT="$(CLAUDE_PROJECT_DIR="$R" SLEEP_S=7 python3 "$TMP/broken_capacity.py" "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
warns="$(printf '%s\n' "$OUT" | grep -c 'shard group: capacity.test_jobs')"
late="$(sed -n 's/.* late=\([0-9]*\) jobs=\([0-9]*\)$/\1:\2/p' "$MARK/late" 2>/dev/null | sort -u | tr '\n' ' ')"
if [ "$RC" = 0 ] && passed REG-S-A && passed REG-S-B && [ "$warns" = 1 ] && [ "$late" = "3:3 " ]; then
  ok "2: capacity.test_jobs() broken: one warning, no sizer (pool still 3 of 3 after 7 s), both shards pass"
else bad "2: exit $RC, warnings $warns (want 1), late size:workers '$late' (want '3:3 ')"
  printf '%s\n' "$OUT" | grep -E 'capacity|REG-S|Traceback' | tail -8; fi

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($FAILS)"; exit 1; }
