#!/usr/bin/env bash
# Test hồi quy (03/11, merge gate PR #940): scratch của merge gate bị xoá giữa lượt ⇒ mọi file test "biến mất", vòng thu kết quả của
# tests/run_impacted.sh bỏ qua chúng (`[ -f "$t" ] || continue`) và shard ra PASS exit 0 với ran=0 dù test đã chạy rc=1 — gate báo xanh sai.
# Bản kit tối giản trong thư mục tạm: tests/zz/test_a.sh chạy rồi xoá cả kit và exit 1.
#   t1. run_impacted exit khác 0 (test đã chạy rc=1 vẫn tính, dù file không còn);
#   t2. output có dòng ✖ cho test_a.sh;
#   t3. test chưa từng tồn tại (tên scoped của test bị xoá trong PR) vẫn bỏ qua lặng lẽ: kit còn nguyên, chỉ test_ok.sh ⇒ exit 0.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/ri-vanish.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

mkkit() {   # mkkit <dir>: kit tối giản (runner + lib + bin) để chạy run_impacted.sh
  mkdir -p "$1/tests/zz"
  cp -R "$DEVKIT_DIR/tests/lib" "$1/tests/lib"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/run_impacted.sh"
  cp -R "$DEVKIT_DIR/bin" "$1/bin"
}

K="$T/kit"
mkkit "$K"
printf '#!/usr/bin/env bash\nsleep 1\nrm -rf "%s"\nexit 1\n' "$K" >"$K/tests/zz/test_a.sh"
OUT="$(cd "$T" && DEVKIT_TEST_JOBS=2 DEVKIT_SCOPED_TESTS="tests/zz/test_a.sh" bash "$K/tests/run_impacted.sh" 2>&1)"; rc=$?
if [ "$rc" != 0 ]; then ok "t1. kit biến mất giữa lượt, test rc=1: run_impacted exit $rc (không PASS)"; else bad "t1. run_impacted exit 0 dù test đã chạy rc=1 và kit biến mất" "$(printf '%s' "$OUT" | tail -5 | tr '\n' ' ')"; fi
if printf '%s\n' "$OUT" | grep -q "✖.*test_a.sh"; then ok "t2. có dòng ✖ cho test_a.sh"; else bad "t2. không có dòng ✖ cho test_a.sh" "$(printf '%s' "$OUT" | tail -5 | tr '\n' ' ')"; fi

K2="$T/kit2"
mkkit "$K2"
printf '#!/usr/bin/env bash\nexit 0\n' >"$K2/tests/zz/test_ok.sh"
OUT="$(cd "$T" && DEVKIT_TEST_JOBS=2 DEVKIT_SCOPED_TESTS="tests/zz/test_ok.sh tests/zz/test_gone.sh" bash "$K2/tests/run_impacted.sh" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok "t3. tên scoped không tồn tại vẫn bỏ qua, test còn lại PASS: exit 0"; else bad "t3. exit $rc" "$(printf '%s' "$OUT" | tail -5 | tr '\n' ' ')"; fi

echo
[ "$fails" -eq 0 ] && { echo "PASS test_run_impacted_vanished_tree"; exit 0; }
echo "FAIL test_run_impacted_vanished_tree ($fails)"; exit 1
