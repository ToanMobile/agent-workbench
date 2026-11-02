#!/usr/bin/env bash
# Test hồi quy #616 A: suite hết --timeout khi máy tải cao (≥ busy_load) thì gate KHÔNG kill mà gia hạn từng bước tới trần cứng 3 × timeout
# (REG-DK-ALL-01 TIMEOUT 3 lần liền ở tải 80–130 dù không test nào đỏ, 28/10). Tải thấp: TIMEOUT như cũ. Tải giả qua DEVKIT_CAPACITY_LOAD.
# (a) suite 2 s, --timeout 1, tải giả 999 → PASS, runs.jsonl extended_s > 0. (b) tải giả 0 → TIMEOUT (không gia hạn). (c) suite 30 s, tải 999 →
# trần 3 × 1 s vẫn kill: TIMEOUT, gate xong trong < 15 s.
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

R="$TMP/repo"; mkdir -p "$R/src"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 0 > "$R/src/a.txt"
# the gate runs the matrix at HEAD, so it is committed once; the suite reads its length from src/secs.txt (changed per run)
printf '{"project":"t","rules":[{"component":"S","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-SLOW","name":"slow","command":"sleep $(cat src/secs.txt)"}]}]}\n' > "$R/matrix.json"
echo 1 > "$R/src/secs.txt"
git -C "$R" add -A && git -C "$R" commit -qm init
# run_gate <load> <seconds>: một lượt gate trên src/a.txt đổi; in rc, extended_s của dòng runs.jsonl cuối, và giây chạy
run_gate() {
  echo "$2" > "$R/src/secs.txt"; echo "$RANDOM" > "$R/src/a.txt"; rm -f "$R/.git/postfix-gate/runs.jsonl"
  local t0=$SECONDS
  ( cd "$R" && DEVKIT_CAPACITY_LOAD="$1" FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" \
    --run-tests --timeout 1 --no-checklist >"$TMP/out" 2>&1 ); RC=$?
  WALL=$((SECONDS - t0))
  EXT="$(tail -n 1 "$R/.git/postfix-gate/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys
try: r=json.loads(sys.stdin.read())
except ValueError: r={}
print(r.get("extended_s") or 0)')"
}
run_gate 999 2
if [ "$RC" = 0 ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > 0 else 1)' "$EXT"; then ok "(a) tải 999, suite 2 s > timeout 1 s: PASS, extended_s=$EXT"
else fail "(a) muốn rc=0 và extended_s>0, được rc=$RC extended_s=$EXT: $(tail -4 "$TMP/out")"; fi
run_gate 0 2
if [ "$RC" != 0 ] && grep -q 'TIMEOUT' "$TMP/out" && [ "$EXT" = 0 ]; then ok "(b) tải 0: TIMEOUT như cũ, không gia hạn"
else fail "(b) muốn TIMEOUT rc≠0 extended_s=0, được rc=$RC extended_s=$EXT: $(tail -4 "$TMP/out")"; fi
run_gate 999 30
if [ "$RC" != 0 ] && grep -q 'TIMEOUT' "$TMP/out" && [ "$WALL" -lt 15 ]; then ok "(c) trần cứng 3 × timeout vẫn kill (${WALL}s < 15 s)"
else fail "(c) muốn TIMEOUT trong < 15 s, được rc=$RC wall=${WALL}s: $(tail -4 "$TMP/out")"; fi
# (d) sàn: --timeout dưới DEVKIT_GATE_EXTEND_MIN_S (mặc định 60 s: giờ của test, không phải suite thật) không gia hạn dù tải cao — các test có sẵn dùng
# --timeout 1-5 s không đổi nghĩa khi máy bận. Cùng suite 2 s, tải 999, sàn 60: TIMEOUT, extended_s=0.
DEVKIT_GATE_EXTEND_MIN_S=60 run_gate 999 2
if [ "$RC" != 0 ] && grep -q 'TIMEOUT' "$TMP/out" && [ "$EXT" = 0 ]; then ok "(d) timeout 1 s < sàn 60 s: không gia hạn, TIMEOUT"
else fail "(d) muốn TIMEOUT extended_s=0, được rc=$RC extended_s=$EXT: $(tail -4 "$TMP/out")"; fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
