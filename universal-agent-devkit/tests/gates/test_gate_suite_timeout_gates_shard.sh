#!/usr/bin/env bash
# Test hồi quy: shard REG-DK-ALL-GATES-01 (tests/gates) được trần gấp đôi --timeout (900 → 1800 s). PASS của nó p90 758 s, p95 860 s sát trần
# 900 s; 12 TIMEOUT từ 31/10 (runs.jsonl), chủ repo 02/11 "nâng trần timeout REG-DK-ALL-GATES-01". Máy rảnh (tải giả 0, không gia hạn #616 A):
# (a) suite REG-DK-ALL-GATES-01 3 s, --timeout 2 → PASS (trần 4 s). (b) cùng suite tên khác → TIMEOUT như cũ. (c) --timeout dưới sàn
# DEVKIT_GATE_EXTEND_MIN_S (giờ của test, không phải suite thật) không nâng → TIMEOUT.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_SUITE_CACHE \
  DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S DEVKIT_CAPACITY_LOAD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_CAPACITY_CORES=4 DEVKIT_GATE_EXTEND_STEP_S=1 DEVKIT_GATE_EXTEND_MIN_S=0
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# run_gate <suite id>: repo mới, ma trận một suite `sleep 3` mang id đó, gate --timeout 2 ở tải 0; in rc
run_gate() {
  local R="$TMP/repo-$RANDOM"; mkdir -p "$R/src"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  echo 0 > "$R/src/a.txt"
  printf '{"project":"t","rules":[{"component":"S","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"%s","name":"slow","command":"sleep 3"}]}]}\n' "$1" > "$R/matrix.json"
  git -C "$R" add -A && git -C "$R" commit -qm init
  echo 1 > "$R/src/a.txt"
  ( cd "$R" && DEVKIT_CAPACITY_LOAD=0 FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" \
    --run-tests --timeout 2 --no-checklist >"$TMP/out" 2>&1 ); RC=$?
}
run_gate REG-DK-ALL-GATES-01
if [ "$RC" = 0 ] && ! grep -q 'TIMEOUT' "$TMP/out"; then ok "(a) REG-DK-ALL-GATES-01 3 s, --timeout 2: trần 4 s, PASS"
else fail "(a) muốn rc=0 không TIMEOUT, được rc=$RC: $(tail -4 "$TMP/out")"; fi
run_gate REG-OTHER-01
if [ "$RC" != 0 ] && grep -q 'TIMEOUT' "$TMP/out"; then ok "(b) suite khác: trần --timeout như cũ, TIMEOUT"
else fail "(b) muốn TIMEOUT rc≠0, được rc=$RC: $(tail -4 "$TMP/out")"; fi
DEVKIT_GATE_EXTEND_MIN_S=60 run_gate REG-DK-ALL-GATES-01
if [ "$RC" != 0 ] && grep -q 'TIMEOUT' "$TMP/out"; then ok "(c) --timeout 2 < sàn 60 s: không nâng, TIMEOUT"
else fail "(c) muốn TIMEOUT rc≠0, được rc=$RC: $(tail -4 "$TMP/out")"; fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
