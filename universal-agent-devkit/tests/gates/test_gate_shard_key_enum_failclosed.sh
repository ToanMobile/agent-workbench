#!/usr/bin/env bash
# Test hồi quy #994 (P1, gate báo xanh sai): khoá chính xác shard run_impacted.sh (#851) theo đồ thị tĩnh chỉ thấy import / source / tên
# file được nhắc, KHÔNG thấy file test liệt kê lúc chạy (`for f in "$DK"/data/*`). Kit nháp có run_impacted.sh THẬT (dấu
# devkit-selection-inputs), test_g.sh source bin/lib_g.sh rồi duyệt mọi file dưới data/ (ngoài đồ thị) và ĐỎ khi một file có "BAD".
#   F0. lane đổi lib_g.sh, gate thật `--run-tests --scoped --diff main`: shard chạy, PASS.
#   F1. main đổi data/ok.txt thành BAD; merge H+main, gate lại: shard phải CHẠY LẠI và ĐỎ (exit ≠ 0).
# Trước #994: khoá chính xác của shard không gồm data/ok.txt ⇒ dùng lại PASS của lane, gate exit 0 (PASS sai) ⇒ F1 ĐỎ. Python stdlib, bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY \
      DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS \
      DEVKIT_TEST_JOBS DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SENTINEL_MAX_S=999999999   # khoá slot riêng, không đụng gate thật
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.G" ] && wc -l < "$TMP/count.G" | tr -d ' ' || echo 0; }
SHARD='DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh'

R="$TMP/r"; K="$R/universal-agent-devkit"
mkdir -p "$K/tests/gates" "$K/tests/verification" "$K/tests/lib" "$K/bin" "$K/data"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/run_impacted.sh"; echo '# trống' > "$K/tests/impact_map.txt"
grep -q 'devkit-selection-inputs:' "$K/tests/run_impacted.sh" || { echo "✖ setup: run_impacted.sh không có dấu devkit-selection-inputs"; exit 1; }
echo 'true' > "$K/tests/verification/test_repo_consistency.sh"
printf 'g() { :; }\n' > "$K/bin/lib_g.sh"
cat > "$K/tests/gates/test_g.sh" <<T
DK="\$(cd "\$(dirname "\$0")/../.." && pwd)"
. "\$DK/bin/lib_g.sh"
echo g >> "$TMP/count.G"
for f in "\$DK"/data/*; do grep -q BAD "\$f" && exit 1; done
exit 0
T
echo 'ok' > "$K/data/ok.txt"; printf '.claude/\n' > "$R/.gitignore"
python3 - "$R/matrix.json" "$SHARD" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [{"component": "K", "watch_files": ["universal-agent-devkit/*"],
           "mandatory_regression_tests": [{"id": "REG-SHARD", "name": "shard", "command": sys.argv[2]}]}]}, open(sys.argv[1], "w"))
PY
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" worktree add -q -b feat "$TMP/lane" main || { echo "✖ setup: worktree lane"; exit 1; }
printf 'g2() { :; }\n' >> "$TMP/lane/universal-agent-devkit/bin/lib_g.sh"; git -C "$TMP/lane" commit -qam "lane: lib_g"
gate() { mkdir -p "$1/.claude/audit-gate"; : > "$1/.claude/audit-gate/test_run.lock"   # worktree đã từng chạy gate
  ( cd "$1" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --run-tests --scoped \
    --diff main --no-checklist >"$TMP/out" 2>&1 ); }

gate "$TMP/lane"; r0=$?; c0=$(n)
if [ "$r0" = 0 ] && [ "$c0" = 1 ]; then ok "F0. lane --scoped: shard chạy, PASS (test_g chạy $c0 lần)"
else fail "F0. lane exit $r0 (mong 0), test_g chạy $c0 lần (mong 1)"; grep -E "REG-SHARD|scoped|suite_cache" "$TMP/out" | tail -5; fi

echo 'BAD' > "$K/data/ok.txt"; git -C "$R" commit -qam "main: data/ok.txt (chỉ được glob)"
git -C "$R" worktree add -q --detach "$TMP/m1" main && git -C "$TMP/m1" merge -q --no-edit feat >/dev/null || { echo "✖ setup: merge m1"; exit 1; }
gate "$TMP/m1"; r1=$?; c1=$(n)
if [ "$r1" != 0 ] && [ "$c1" -gt "$c0" ]; then ok "F1. merge H+main (main đổi file test_g chỉ glob): shard chạy lại ($c0 → $c1) và ĐỎ (exit $r1)"
else fail "F1. merge exit $r1 (mong ≠ 0), test_g chạy $c0 → $c1 (mong tăng): PASS cũ bị dùng lại theo khoá thiếu file được glob"
  grep -E "REG-SHARD|khoá nội dung|content key" "$TMP/out" | tail -5; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_shard_key_enum_failclosed: all passed" || { echo "❌ test_gate_shard_key_enum_failclosed: $FAILS failed"; exit 1; }
