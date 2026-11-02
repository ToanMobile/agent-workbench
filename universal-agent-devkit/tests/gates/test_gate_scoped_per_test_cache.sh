#!/usr/bin/env bash
# Test hồi quy (PR 1 gate kẹt và chậm, P4): lượt `post-fix-gate.py --run-tests --scoped` (PR, merge gate, train, integrate) bật sổ PASS theo
# từng test của run_impacted.sh (tests/lib/per_test_cache.py, B2) như lượt cưỡng bức: một test đỏ / TIMEOUT trong suite runner không còn bắt
# lượt sau trên ĐÚNG CÂY đó chạy lại mọi test đã PASS (merge gate TIMEOUT REG-DK-ALL-GATES-01 hai lần trong 7 ngày). Trước P4 lượt --scoped
# để DEVKIT_PER_TEST_CACHE = "0" (chỉ lượt --full / --force-full / CI… bật) ⇒ S2 ĐỎ.
#   S1. lượt --scoped đầu: diff (lib/shared.txt chưa commit) chọn test_a, test_b, test_c qua runner run_impacted.sh THẬT; test_c FAIL (cờ ngoài
#       cây) ⇒ exit ≠ 0, cả ba chạy (tiền đề: không leo full, runner thật chạy).
#   S2. cùng cây, cờ vẫn bật: test_a, test_b in "↺" (dùng lại PASS), chỉ test_c chạy; runs.jsonl ghi ptc_reuse > 0.
#   S3. --scoped --no-cache, và S4. DEVKIT_GATE_CACHE=0: chế độ "record" (chỉ ghi) ⇒ cả ba chạy thật, ptc_reuse = 0.
# Cờ FAIL bật suốt các lượt: lượt xanh ghi biên nhận scoped / PASS cả suite (#785, #851) thì runner không chạy nữa, không đo được gì.
# Python stdlib, bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY \
      DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS \
      DEVKIT_TEST_JOBS DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE DEVKIT_TEST_TIMEOUT_S \
      DEVKIT_FLAKY_QUARANTINE_S POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"   # bản của checkout đang kiểm (INSTINCT-057)
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1   # khoá slot riêng, không đụng gate thật của máy
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
counts() { echo "$(n a) $(n b) $(n c)"; }
delta()  { set -- $1; echo "$(( $(n a) - $1 )) $(( $(n b) - $2 )) $(( $(n c) - $3 ))"; }   # delta "<counts trước>"

# Kit giả: run_impacted.sh THẬT + helper THẬT (per_test_cache.py, run_bounded.py), bin/ là bin của checkout đang kiểm (helper nạp gate +
# suite_cache.py từ đó). Ba test đọc lib/shared.txt và ghi một dòng vào count.<tên> mỗi lần chạy; test_c thoát 1 khi có cờ $TMP/fail_c.
R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
echo 'true' > "$KIT/tests/verification/test_repo_consistency.sh"
echo v1 > "$KIT/lib/shared.txt"
for t in a b c; do
  printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\necho %s >> %s/count.%s\ngrep -q v "$DK/lib/shared.txt" || exit 1\n' "$t" "$TMP" "$t" \
    > "$KIT/tests/gates/test_$t.sh"
done
printf '[ -f %s/fail_c ] && exit 1\nexit 0\n' "$TMP" >> "$KIT/tests/gates/test_c.sh"
printf '.claude/\n' > "$R/.gitignore"
python3 - "$R/matrix.json" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [{"component": "K", "watch_files": ["universal-agent-devkit/*"],
           "mandatory_regression_tests": [{"id": "REG-ALL", "name": "all", "command": "bash universal-agent-devkit/tests/run_impacted.sh"}]}]},
          open(sys.argv[1], "w"))
PY
git -C "$R" add -A && git -C "$R" commit -qm init
echo v2 > "$KIT/lib/shared.txt"   # diff chưa commit (base HEAD): chọn ba test đọc file này
: > "$TMP/fail_c"
RUNS="$R/.git/postfix-gate/runs.jsonl"

# gate [args]: lượt --scoped trên cây hiện có; ra $TMP/out, RC
gate() { ( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --scoped \
  --no-checklist "$@" >"$TMP/out" 2>&1 ); RC=$?; }
# ptc: "reuse ran" của dòng runs.jsonl cuối ("- -" khi lượt không ghi trường ptc)
ptc() { tail -1 "$RUNS" 2>/dev/null | python3 -c 'import json,sys
r = json.loads(sys.stdin.read() or "{}"); print(r.get("ptc_reuse", "-"), r.get("ptc_ran", "-"))' 2>/dev/null || echo "? ?"; }

# S1. lượt đầu: ba test chạy, test_c đỏ
B="$(counts)"; gate; r1=$RC; d1="$(delta "$B")"
if grep -q -- "--scoped → full" "$TMP/out" || ! grep -q -- "--scoped:" "$TMP/out"; then
  fail "S1. tiền đề: lượt không phải --scoped thuần"; grep -E -- "--scoped" "$TMP/out" | head -3
elif [ "$r1" != 0 ] && [ "$d1" = "1 1 1" ]; then ok "S1. --scoped đầu: test_a, test_b, test_c chạy qua runner thật, test_c đỏ (exit $r1)"
else fail "S1. exit $r1 (mong ≠0), chạy thêm a b c = $d1 (mong 1 1 1)"; grep -E "REG-ALL|scoped|per_test" "$TMP/out" | tail -5; fi

# S2. cùng cây: PASS của test_a, test_b dùng lại, chỉ test_c chạy
B="$(counts)"; gate; r2=$RC; d2="$(delta "$B")"; p2="$(ptc)"
if [ "$r2" != 0 ] && [ "$d2" = "0 0 1" ] && [ "${p2%% *}" != "-" ] && [ "${p2%% *}" -gt 0 ] 2>/dev/null; then
  ok "S2. --scoped cùng cây: test_a, test_b dùng lại PASS theo test (↺), chỉ test_c chạy; runs.jsonl ptc_reuse ran = $p2"
else fail "S2. exit $r2 (mong ≠0), chạy thêm a b c = $d2 (mong 0 0 1), runs.jsonl ptc_reuse ran = $p2 (mong reuse > 0)"
  grep -E "↺|per_test_cache|REG-ALL" "$TMP/out" | tail -5; fi

# S3. --no-cache: chỉ ghi, mọi test chạy thật
B="$(counts)"; gate --no-cache; r3=$RC; d3="$(delta "$B")"; p3="$(ptc)"
if [ "$r3" != 0 ] && [ "$d3" = "1 1 1" ] && [ "${p3%% *}" = 0 ]; then
  ok "S3. --scoped --no-cache: không dùng lại PASS nào, ba test chạy thật (ptc_reuse ran = $p3)"
else fail "S3. exit $r3 (mong ≠0), chạy thêm a b c = $d3 (mong 1 1 1), ptc_reuse ran = $p3 (mong reuse 0)"; fi

# S4. DEVKIT_GATE_CACHE=0: như --no-cache
B="$(counts)"; DEVKIT_GATE_CACHE=0 gate; r4=$RC; d4="$(delta "$B")"; p4="$(ptc)"
if [ "$r4" != 0 ] && [ "$d4" = "1 1 1" ] && [ "${p4%% *}" = 0 ]; then
  ok "S4. DEVKIT_GATE_CACHE=0: không dùng lại PASS nào, ba test chạy thật (ptc_reuse ran = $p4)"
else fail "S4. exit $r4 (mong ≠0), chạy thêm a b c = $d4 (mong 1 1 1), ptc_reuse ran = $p4 (mong reuse 0)"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_scoped_per_test_cache: all passed" || { echo "❌ test_gate_scoped_per_test_cache: $FAILS failed"; exit 1; }
