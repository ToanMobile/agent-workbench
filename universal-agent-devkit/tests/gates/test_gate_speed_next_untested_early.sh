#!/usr/bin/env bash
# Test ĐỎ cho đợt tăng tốc gate (#472, mục 2) — XFAIL: mặc định in SKIP và thoát 0; GATE_SPEED_NEXT=1 chạy thật.
# Test đã commit bị sửa (không chỉ thêm) và chưa ai duyệt: gate trả UNTESTED (exit_reason edited_test) TRƯỚC khi chạy suite nào.
# Baseline 24-27/10: 29/55 lượt edited_test đã chạy suite rồi mới bị loại (8,3 giờ). Suite ghi một dòng vào marker khi chạy.
# Bỏ dòng skip khi #472 xong và test XANH.
if [ "${GATE_SPEED_NEXT:-0}" != 1 ]; then echo "SKIP (xfail #472): test sửa chưa duyệt vẫn chạy suite trước khi UNTESTED — GATE_SPEED_NEXT=1 để chạy thật"; exit 0; fi
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME/.claude/projects" "$SB_HEAVY_SLOT_DIR"

R="$TMP/work"
mkdir -p "$R/src" "$R/tests" && git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s/ran; sh tests/test_old.sh"}]}]}\n' "$TMP" > "$R/matrix.json"
echo 'fun ok()=1' > "$R/src/Core.kt"
printf '#!/bin/sh\nexit 0\n' > "$R/tests/test_old.sh"
git -C "$R" add -A && git -C "$R" commit -qm init
echo 'fun ok()=2' > "$R/src/Core.kt"
printf '#!/bin/sh\ntrue\n' > "$R/tests/test_old.sh"   # sửa một dòng có sẵn: không phải chỉ thêm
: > "$TMP/empty.jsonl"                                 # transcript rỗng: không ai duyệt
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --transcript "$TMP/empty.jsonl" 2>&1)"; RC=$?

FAILS=0
LAST="$(tail -n 1 "$R/.git/postfix-gate/runs.jsonl" 2>/dev/null)"
V="$(printf '%s' "$LAST" | python3 -c 'import json,sys
try: r=json.loads(sys.stdin.read())
except ValueError: r={}
print(r.get("verdict",""), r.get("exit_reason",""))')"
# điều kiện tiền đề (đúng cả hôm nay): gate nhận ra test sửa chưa duyệt — không thì ca dưới không chứng minh gì
if [ "$V" = "UNTESTED edited_test" ] && [ "$RC" != 0 ]; then echo "✔ gate trả UNTESTED edited_test (rc=$RC)"
else echo "✖ tiền đề: gate không trả UNTESTED edited_test (rc=$RC, log: $V): $(printf '%s' "$OUT" | tail -3)"; FAILS=$((FAILS + 1)); fi
if [ ! -f "$TMP/ran" ]; then echo "✔ không suite nào chạy trước khi trả UNTESTED"
else echo "✖ suite đã chạy ($(wc -l < "$TMP/ran" | tr -d ' ') lần) rồi mới trả UNTESTED"; FAILS=$((FAILS + 1)); fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
