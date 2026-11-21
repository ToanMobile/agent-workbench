#!/usr/bin/env bash
# Owner 21/11/2026: "trong báo cáo mỗi khi xong bổ sung tôi thêm nguyên nhân". Every acceptance report states the cause
# on its own "Nguyên nhân:" line under item 1 (a bug: root cause + mechanism; not a bug: why the change was needed).
# The item labels stay as they are (hooks/proof_gate.sh and its tests read them); the hook does not check the line yet
# (ponytail line in core-rules §2.3).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
CORE="$DK/rules/core-rules.md"
fail() { echo "✖ $1" >&2; exit 1; }

step5="$(awk '/^5\. The reply/{on=1} on&&/^## /{exit} on' "$ESS")"
[ -n "$step5" ] || fail "essentials step 5 not found"
printf '%s' "$step5" | grep -q 'Nguyên nhân:' || fail "essentials step 5 does not ask for a 'Nguyên nhân:' line"

item1="$(grep -E '^ +1\. \*\*Đã làm gì / Đã fix gì' "$CORE")"
[ -n "$item1" ] || fail "core-rules §2.3 item 1 not found"
printf '%s' "$item1" | grep -q 'Nguyên nhân:' || fail "core-rules §2.3 item 1 does not ask for a 'Nguyên nhân:' line"
grep -q 'ponytail: hook proof_gate chưa kiểm dòng "Nguyên nhân:"' "$CORE" || fail "core-rules §2.3 lacks the ponytail line for the unchecked cause line"
echo "✅ test_report_cause_line: essentials step 5 + core-rules §2.3 ask for the cause line"
