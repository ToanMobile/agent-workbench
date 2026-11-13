#!/usr/bin/env bash
# bin/post-fix-gate.py (#976, OCR finding on PR #971): a keyed shard-group member's inflight marker (suite_cache.inflight, deadline
# est×1.5+60 s) must carry the GROUP's estimate, not the member's own sequential one: side by side a member's wall is about the group's (it
# waits on its siblings' slots and alone tests), so a second gate on the same key could take the live marker as stale and run the suite
# twice. The members get the group's summed timeout as their marker estimate: two shards under --timeout 100 ⇒ est_s 200 in each marker.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0 FLAKY_RETRY=0 DEVKIT_SENTINEL_MAX_S=999999999 DEVKIT_GATE_EXTEND_MIN_S=100000
unset DEVKIT_GATE_PARALLEL DEVKIT_CAPACITY DEVKIT_TEST_JOBS DEVKIT_TEST_POOL_DIR DEVKIT_JOB_POOL DEVKIT_TEST_JOBS_BUSY CI
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S
export DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0 DEVKIT_SLOT_CPU_S=60
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo 0 > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD
R="$TMP/repo"
export MARK="$TMP/mark"
mkdir -p "$R/src" "$R/tests/lib" "$R/tests/x" "$MARK"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo "fun ok() = 1" > "$R/src/Core.kt"
printf '999 tests/x/test_long.sh\n' > "$R/tests/lib/test_durations.txt"
printf 'exit 0\n' > "$R/tests/x/test_long.sh"
# a stand-in for the kit runner: both shards wait for each other (only a group overlaps them), then copy the inflight markers they see
cat > "$R/tests/run_impacted.sh" <<'SH'
# devkit-selection-list: (the marker bin/suite_cache.py needs before it asks --list)
case "${1:-}" in --jobs) echo 3; exit 0 ;; --list) echo tests/x/test_long.sh; exit 0 ;; esac
d="${DEVKIT_IMPACTED_DIRS:-none}"
touch "$MARK/start.$d"
i=0; while [ "$(ls "$MARK" | grep -c '^start\.')" -lt 2 ] && [ $i -lt 80 ]; do sleep 0.1; i=$((i + 1)); done
[ "$(ls "$MARK" | grep -c '^start\.')" -ge 2 ] || exit 1
[ -n "${DEVKIT_TEST_POOL_DIR:-}" ] && touch "$MARK/grouped"
for f in .git/postfix-gate/suite_cache/*.run; do [ -f "$f" ] && cp "$f" "$MARK/$d.$(basename "$f")"; done
exit 0
SH
shard() { printf '{"id":"%s","name":"%s","command":"DEVKIT_IMPACTED_DIRS=%s bash tests/run_impacted.sh","parallel_safe":true}' "$1" "$1" "$2"; }
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s,%s]}]}\n' \
  "$(shard REG-S-A a)" "$(shard REG-S-B b)" > "$R/matrix.json"
git -C "$R" add -A && git -C "$R" commit -qm init
echo "fun ok() = 2" > "$R/src/Core.kt" && git -C "$R" commit -qam change
run() { ( cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests --full --diff HEAD~1 \
  --no-checklist --timeout 100 >"$1" 2>&1 ); }
# the repo's first run is the sentinel run (no content key, no marker): run once, then change the tree so the next run is keyed
run "$TMP/out1"
rm -rf "$MARK"; mkdir -p "$MARK"
echo "fun ok() = 3" > "$R/src/Core.kt"
run "$TMP/out2"; rc=$?
ests="$(python3 - "$MARK" <<'PY'
import glob, json, os, sys
out = []
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.run"))):
    try:
        est = json.load(open(p)).get("est_s")
        out.append(f"{os.path.basename(p).split('.')[0]}:{float(est) if est is not None else None}")
    except (OSError, ValueError, TypeError) as exc:
        out.append(f"{p}:{exc}")
print(" ".join(out))
PY
)"
# each member sees its own marker (and maybe its sibling's): every est_s must be the group's 200
if [ "$rc" = 0 ] && [ -e "$MARK/grouped" ] && [ -n "$ests" ] && ! printf '%s\n' "$ests" | tr ' ' '\n' | grep -qv ':200.0$' \
   && printf '%s\n' "$ests" | grep -q '^a:' && printf '%s\n' "$ests" | grep -q ' b:\|^b:'; then
  echo "✔ keyed shard-group members mark inflight with the group's summed timeout (est_s 200 = 2 × --timeout 100): $ests"; echo "ALL PASS"; exit 0
fi
echo "✖ exit $rc, grouped=$([ -e "$MARK/grouped" ] && echo yes || echo no), marker est_s seen: '$ests' (want every one 200.0)"
grep -E 'REG-S|FAIL|Traceback' "$TMP/out2" | tail -6
exit 1
