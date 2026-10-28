#!/usr/bin/env bash
# Test hồi quy #472 mục D: đo hit-rate của per_test_cache (chưa đổi khoá). run_impacted.sh in một dòng "per_test_cache: reuse=<N> ran=<M>" khi
# sổ per-test bật; post-fix-gate ghi ptc_reuse / ptc_ran (cộng qua các suite của lượt) vào dòng runs.jsonl để gate_speed_report đo được.
# Kit giả: run_impacted.sh THẬT + helper THẬT, hai test. Lượt gate đầu (cây lạnh): reuse=0 ran=2. run_impacted.sh chạy lại trên CÙNG cây: reuse=2 ran=0.
# Đối chứng: không bật sổ per-test (agent-kit test) thì không in dòng đó.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_SUITE_CACHE \
  DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
echo one > "$KIT/lib/in1.txt"; echo 0 > "$KIT/notes.txt"
printf 'cat "$(dirname "$0")/../../lib/in1.txt" >/dev/null\n' > "$KIT/tests/v/test_t1.sh"
printf 'true\n' > "$KIT/tests/v/test_t2.sh"
printf '{"project":"t","rules":[{"component":"K","watch_files":["universal-agent-devkit/*"],"mandatory_regression_tests":[{"id":"REG-ALL","name":"all","command":"bash universal-agent-devkit/tests/run_impacted.sh --all"}]}]}\n' > "$R/matrix.json"
git -C "$R" add -A && git -C "$R" commit -qm init
STORE="$R/.git/postfix-gate/suite_cache"
echo 1 > "$KIT/notes.txt"; mkdir -p "$STORE"
python3 -c 'import json, sys, time; json.dump({"last_real_full_at": time.time()}, open(sys.argv[1], "w"))' "$STORE/sentinel.json"
( cd "$R" && DEVKIT_PER_TEST_CACHE=1 FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" \
  --run-tests --full --no-checklist >"$TMP/out" 2>&1 ); RC=$?
V="$(tail -n 1 "$R/.git/postfix-gate/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys
try: r=json.loads(sys.stdin.read())
except ValueError: r={}
print(r.get("ptc_reuse"), r.get("ptc_ran"))')"
if [ "$RC" = 0 ] && [ "$V" = "0 2" ]; then ok "lượt gate cây lạnh: runs.jsonl ptc_reuse=0 ptc_ran=2"
else fail "runs.jsonl ptc_reuse/ptc_ran = '$V' (muốn '0 2', gate rc=$RC): $(tail -3 "$TMP/out")"; fi
( cd "$R" && DEVKIT_PER_TEST_CACHE=1 bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/again" 2>&1 )
if grep -qx 'per_test_cache: reuse=2 ran=0' "$TMP/again"; then ok "chạy lại trên cùng cây: dòng 'reuse=2 ran=0'"
else fail "không thấy 'per_test_cache: reuse=2 ran=0': $(tail -4 "$TMP/again")"; fi
( cd "$R" && bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/plain" 2>&1 )
if ! grep -q '^per_test_cache:' "$TMP/plain"; then ok "đối chứng: không bật sổ per-test thì không in dòng đó"
else fail "đối chứng: sổ tắt mà vẫn in dòng per_test_cache"; fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
