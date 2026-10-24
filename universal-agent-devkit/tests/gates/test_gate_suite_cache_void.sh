#!/usr/bin/env bash
# Test hồi quy (#377 / #344): vô hiệu PASS cũ THEO ID chỉ khi lần chạy thật không nói gì chắc chắn về nội dung đã PASS.
# Một FAIL thật (xác định, trên cây không đổi trong lúc chạy) đã dính vào khoá của nội dung đó (fail_n): nó không nói gì về một nội dung
# khác từng PASS, nên không được xoá PASS ấy (đo 24/10: dev sửa-đỏ-sửa-lại làm mọi PASS cùng id mất hiệu lực). TIMEOUT, hạ tầng, chập
# chờn (FLAKY) thì khoá nào cũng không còn tin được: mọi PASS cũ của id đó phải chạy lại.
# Mỗi ca: PASS nội dung A (worktree 1) → lần chạy thật không-PASS ở nội dung B (worktree 2) → nội dung A lần nữa (worktree 3, ĐÃ từng chạy
# gate: biên nhận anh em không cho mượn, chỉ cache theo khoá giải thích được một suite không chạy). Số lần chạy đo bằng file đếm.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" DEVKIT_SENTINEL_MAX_S=999999999
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# repo <tên>: src/x.py + ma trận một suite REG-V; lệnh đếm lần chạy rồi làm theo file chế độ ($TMP/<tên>.mode: fail | hang | flaky | ok)
repo() {
  local r="$TMP/$1"; mkdir -p "$r/src"
  git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  echo 'x = 1' > "$r/src/x.py"; echo ok > "$TMP/$1.mode"
  printf '{"project":"t","rules":[{"component":"X","watch_files":["src/x.py"],"mandatory_regression_tests":[{"id":"REG-V","name":"v","command":"echo run >> %s/%s.count; case $(cat %s/%s.mode) in fail) exit 1;; hang) sleep 4;; flaky) [ -f %s/%s.seen ] || { touch %s/%s.seen; echo ✖ flaky case; exit 1; };; esac"}]}]}\n' \
    "$TMP" "$1" "$TMP" "$1" "$TMP" "$1" "$TMP" "$1" > "$r/matrix.json"
  git -C "$r" add -A && git -C "$r" commit -qm init
}
# wt <repo> <worktree> <nội dung x.py> <chế độ>: worktree đã từng chạy gate, x.py đổi (chưa commit), file chế độ
wt() {
  git -C "$TMP/$1" worktree add -q --detach "$TMP/$2" HEAD || { echo "✖ setup: worktree $2"; exit 1; }
  mkdir -p "$TMP/$2/.claude/audit-gate"; : > "$TMP/$2/.claude/audit-gate/test_run.lock"
  echo "$3" > "$TMP/$2/src/x.py"; echo "$4" > "$TMP/$1.mode"
}
gate() { local d="$1"; shift; ( cd "$d" && FLAKY_RETRY="${FLAKY_RETRY_ON:-0}" VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" \
  --run-tests --full --no-checklist "$@" >"$TMP/out" 2>&1 ); }
runs() { [ -f "$TMP/$1.count" ] && wc -l < "$TMP/$1.count" | tr -d ' ' || echo 0; }

# V1. FAIL thật ở nội dung B không xoá PASS của nội dung A: A lần nữa dùng lại theo khoá, không chạy.
repo v1
wt v1 v1a 'x = 2' ok;   gate "$TMP/v1a"; r1=$?
wt v1 v1b 'x = 3' fail; gate "$TMP/v1b"; r2=$?
B=$(runs v1)
wt v1 v1c 'x = 2' ok;   gate "$TMP/v1c"; r3=$?
if [ "$r1 $r2 $r3" = "0 1 0" ] && [ "$(( $(runs v1) - B ))" = 0 ]; then ok "V1. FAIL thật ở khoá B: PASS của khoá A (cùng id) vẫn HIT, suite không chạy lại"
else fail "V1. exit $r1 $r2 $r3 (mong 0 1 0); nội dung A chạy thêm $(( $(runs v1) - B )) lần (mong 0)"; grep -E "REG-V|suite_cache" "$TMP/out" | tail -3; fi

# V2. TIMEOUT ở nội dung B vô hiệu mọi PASS cũ của id: A lần nữa phải chạy lại.
repo v2
wt v2 v2a 'x = 2' ok;   gate "$TMP/v2a"; r1=$?
wt v2 v2b 'x = 3' hang; gate "$TMP/v2b" --timeout 2; r2=$?
B=$(runs v2)
wt v2 v2c 'x = 2' ok;   gate "$TMP/v2c"; r3=$?
if [ "$r1 $r2 $r3" = "0 1 0" ] && [ "$(( $(runs v2) - B ))" = 1 ]; then ok "V2. TIMEOUT ở khoá B vô hiệu PASS của khoá A: A chạy lại"
else fail "V2. exit $r1 $r2 $r3 (mong 0 1 0); nội dung A chạy thêm $(( $(runs v2) - B )) lần (mong 1)"; grep -E "REG-V|suite_cache" "$TMP/out" | tail -3; fi

# V3. Chập chờn (FAIL rồi PASS khi chạy lại) ở nội dung B: mọi PASS cũ của id hết tin được, A lần nữa phải chạy lại.
repo v3
wt v3 v3a 'x = 2' ok;    gate "$TMP/v3a"; r1=$?
wt v3 v3b 'x = 3' flaky; FLAKY_RETRY_ON=1 gate "$TMP/v3b"; r2=$?
B=$(runs v3)
wt v3 v3c 'x = 2' ok;    gate "$TMP/v3c"; r3=$?
if [ "$r1 $r2 $r3" = "0 1 0" ] && [ "$(( $(runs v3) - B ))" = 1 ]; then ok "V3. chập chờn (FLAKY) ở khoá B vô hiệu PASS của khoá A: A chạy lại"
else fail "V3. exit $r1 $r2 $r3 (mong 0 1 0); nội dung A chạy thêm $(( $(runs v3) - B )) lần (mong 1)"; grep -E "REG-V|suite_cache|FLAKY" "$TMP/out" | tail -3; fi

# V4. Cùng khoá: FAIL thật dính khoá của chính nó (không HIT dù PASS cũ cùng id còn): sửa lại đúng nội dung đã FAIL vẫn chạy.
repo v4
wt v4 v4a 'x = 2' ok;   gate "$TMP/v4a"; r1=$?
wt v4 v4b 'x = 3' fail; gate "$TMP/v4b"; r2=$?
B=$(runs v4)
wt v4 v4c 'x = 3' ok;   gate "$TMP/v4c"; r3=$?
if [ "$r1 $r2 $r3" = "0 1 0" ] && [ "$(( $(runs v4) - B ))" = 1 ]; then ok "V4. FAIL dính khoá của nội dung đó: B lần nữa không HIT, chạy lại"
else fail "V4. exit $r1 $r2 $r3 (mong 0 1 0); nội dung B chạy thêm $(( $(runs v4) - B )) lần (mong 1)"; fi

# V5. Bảng quyết định của suite_cache.void_needed (stale_rerun gọi cùng hàm): TIMEOUT / UNTESTED / hạ tầng luôn vô hiệu; FAIL thật chỉ khi
#     nó xác định, cây không đổi và đã ghi được một khoá.
res5="$(python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from suite_cache import void_needed as v
rows = [(v("PASS"), False), (v("FAIL"), False), (v("TIMEOUT"), True), (v("UNTESTED"), True), (v("FAIL", flaky=True), True),
        (v("FAIL", vacuous=True), True), (v("FAIL", tree_unchanged=False), True), (v("FAIL", recorded=False), True)]
print("bad=%s" % [i for i, (got, want) in enumerate(rows) if got != want])
PY
)"
[ "$res5" = "bad=[]" ] && ok "V5. void_needed: PASS/FAIL thật không vô hiệu; TIMEOUT, UNTESTED, chập chờn, VACUOUS, cây đổi, FAIL không ghi được: vô hiệu" \
  || fail "V5. void_needed sai ở hàng $res5"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_suite_cache_void: all passed" || { echo "❌ test_gate_suite_cache_void: $FAILS failed"; exit 1; }
