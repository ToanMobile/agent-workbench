#!/usr/bin/env bash
# QA gặp gate impacted exit 2 chỉ vì test có sẵn bị sửa (luật #605: agent khác duyệt chéo) thì chuyển thẻ
# sang Review để Reviewer chạy audit Antigravity, không Blocked + needs-you (#531 kẹt ngày 29/10).
# Kiểm ba chỗ lane đọc: Tester và Reviewer trong run.md, và super-qa chạy riêng.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_REF="$REPO_ROOT/.claude/skills/super-board/references/run.md"
QA_GREEN="$REPO_ROOT/.claude/skills/super-qa/references/findings-and-green.md"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# In một mục của run.md: từ heading $1 tới heading cùng cấp kế tiếp.
section() { awk -v h="$1" 'index($0,h)==1{on=1;print;next} on&&/^###? /{exit} on' "$RUN_REF"; }

tester="$(section '### Tester (first pass')"
reviewer="$(section '### Reviewer')"

if grep -q 'edited-test exit 2' <<<"$tester" && grep -q 'QA → Review' <<<"$tester" \
  && grep -q 'never `Blocked`' <<<"$tester"; then
  pass "Tester: exit 2 chỉ vì test sửa thì sang Review, không Blocked"
else
  fail "Tester (run.md) chưa có luật edited-test exit 2 → Review, không Blocked"
fi

if grep -q 'edited-test exit 2' <<<"$reviewer" && grep -q 'Antigravity audit' <<<"$reviewer"; then
  pass "Reviewer: nhận edited-test exit 2 của QA, audit Antigravity duyệt chéo test đó"
else
  fail "Reviewer (run.md) vẫn coi edited-test exit 2 của QA là Verification miss"
fi

if grep -q 'edited-test exit 2' "$QA_GREEN"; then
  pass "super-qa chạy riêng: edited-test exit 2 không phải QA fail"
else
  fail "findings-and-green.md chưa có luật edited-test exit 2"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
