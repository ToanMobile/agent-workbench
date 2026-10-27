#!/usr/bin/env bash
# Test ĐỎ cho đợt tăng tốc gate (#472, mục 4) — XFAIL: mặc định in SKIP và thoát 0; GATE_SPEED_NEXT=1 chạy thật.
# per_test_cache hiện khoá theo CẢ CÂY (tests/gates/test_gate_per_test_cache.sh): sửa một file test không đọc cũng chạy lại test đó.
# Đợt sau: khoá theo hash các file test thực sự đọc. Kit giả như test_gate_per_test_cache.sh (run_impacted.sh + helper THẬT),
# test t1 đọc lib/in1.txt và ghi một dòng vào count.t1 mỗi lần chạy xong; gọi run_impacted.sh --all với DEVKIT_PER_TEST_CACHE=1.
#   tiền đề (đúng hôm nay): chạy lại trên cây y hệt thì t1 được bỏ qua;
#   ĐỎ hôm nay: sửa notes.txt (t1 không đọc) thì t1 vẫn phải được bỏ qua;
#   đối chứng (phải giữ mãi): sửa lib/in1.txt (t1 đọc) thì t1 chạy lại — không được xanh sai.
# Bỏ dòng skip khi #472 xong và test XANH.
if [ "${GATE_SPEED_NEXT:-0}" != 1 ]; then echo "SKIP (xfail #472): per_test_cache còn khoá theo cả cây — GATE_SPEED_NEXT=1 để chạy thật"; exit 0; fi
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_SUITE_CACHE \
  DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.t1" ] && wc -l < "$TMP/count.t1" | tr -d ' ' || echo 0; }

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"   # post-fix-gate.py + suite_cache.py mà helper nạp
echo one > "$KIT/lib/in1.txt"; echo 0 > "$KIT/notes.txt"
printf 'cat "$(dirname "$0")/../../lib/in1.txt" >/dev/null\necho 1 >> %s/count.t1\n' "$TMP" > "$KIT/tests/v/test_t1.sh"
git -C "$R" add -A && git -C "$R" commit -qm init
STORE="$R/.git/postfix-gate/suite_cache"
run() {
  mkdir -p "$STORE"; python3 -c 'import json, sys, time; json.dump({"last_real_full_at": time.time()}, open(sys.argv[1], "w"))' "$STORE/sentinel.json"
  ( cd "$R" && DEVKIT_PER_TEST_CACHE=1 bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/out" 2>&1 ); RC=$?
}

run; c0="$(n)"
[ "$RC" = 0 ] && [ "$c0" = 1 ] || fail "lượt đầu: t1 phải chạy một lần (rc=$RC, count=$c0): $(tail -3 "$TMP/out")"
run; c1="$(n)"
if [ "$c1" = "$c0" ]; then ok "tiền đề: cây y hệt thì t1 được bỏ qua"; else fail "tiền đề: cây y hệt mà t1 vẫn chạy lại (count $c0 → $c1)"; fi
echo 1 > "$KIT/notes.txt"
run; c2="$(n)"
if [ "$c2" = "$c1" ]; then ok "sửa notes.txt (t1 không đọc): t1 được bỏ qua"; else fail "sửa notes.txt (t1 không đọc): t1 vẫn chạy lại (count $c1 → $c2)"; fi
echo uno > "$KIT/lib/in1.txt"
run; c3="$(n)"
if [ "$c3" -gt "$c2" ]; then ok "đối chứng: sửa lib/in1.txt (t1 đọc) thì t1 chạy lại"; else fail "XANH SAI: sửa input của t1 mà t1 không chạy lại (count $c2 → $c3)"; fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
