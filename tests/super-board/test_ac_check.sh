#!/usr/bin/env bash
# T0054 (24/10): super-board-ac-check.py — AC bị nén, AC gián tiếp ("AC của thẻ #X"), Closes thẻ lạ, dòng AC chưa tick.
# Tình huống thật: #318 chỉ ghi "AC của thẻ #315 (xem thẻ đó)"; PR #343 nén 7 AC thành 3 dòng đã tick; #315 đóng mà AC cache
# REG-DK-ALL-01 chưa ai làm. AC của #315 viết "- Test: …" không có ô tích — vẫn phải đếm.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
AC="$HERE/../../.claude/bin/super-board-ac-check.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v, ensure_ascii=False) if isinstance(v,(list,bool)) or v is None else v)' "$1"; }

cat >"$T/issue.md" <<'EOF'
## Problem
- not an AC
## Acceptance Criteria
- [ ] Test: khoá B FAIL tra khoá A → HIT
- Test: hai lượt --full cùng diff → lượt 2 dùng lại REG-DK-ALL-01
  - chi tiết thụt lề không phải mục riêng
1. Đo runs.jsonl: tỷ lệ dùng lại ≥ 50%
* [X] Test: suite 2, 3 không chờ tải
```
- dòng trong code fence
```
2026. năm không phải mục
## Risk
- 🟡 Medium
EOF
cat >"$T/collapsed.md" <<'EOF'
> ✅ 2/2 AC · Closes #377
<!-- sb:ac -->
## Acceptance criteria
- [x] AC #344, #338 đạt\
  ↳ test_gate_suite_cache xanh
- [x] Gate --full exit 0
<!-- /sb:ac -->
EOF
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/collapsed.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field issue_ac)" = 4 ] && [ "$(printf '%s' "$out" | field collapsed)" = true ] \
  && ok "đếm 4 mục AC (-, -[ ], 1., *[X]; bỏ thụt lề, fence, năm, mục khác) — 2 dòng sb:ac → collapsed" || fail "count/collapsed: $out"

cat >"$T/full.md" <<'EOF'
Closes #377
<!-- sb:ac -->
- [x] Test: khoá B FAIL tra khoá A → HIT\
  ↳ ca 33h
- [x] Test: hai lượt --full cùng diff → lượt 2 dùng lại REG-DK-ALL-01
- [ ] Đo runs.jsonl: tỷ lệ dùng lại ≥ 50%\
  ↳ chỉ đo được sau merge
* [X] Test: suite 2, 3 không chờ tải
- [x] Gate --full exit 0
<!-- /sb:ac -->
EOF
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch loop/issue-377)
[ "$(printf '%s' "$out" | field collapsed)" = false ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] \
  && [ "$(printf '%s' "$out" | field unticked)" = '["Đo runs.jsonl: tỷ lệ dùng lại ≥ 50%"]' ] \
  && ok "mỗi AC một dòng: không collapsed; đúng 1 dòng chưa tick (bỏ dấu \\ cuối); Closes đúng thẻ" || fail "full block misread: $out"

# AC gián tiếp: dòng "AC của thẻ #315" thay bằng mọi AC của #315 khi merge gate đưa body #315 vào.
cat >"$T/i318.md" <<'EOF'
## Acceptance Criteria
- [ ] AC của thẻ #315 đạt (xem Acceptance Criteria trong thẻ đó)
- [ ] Gate --full exit 0
EOF
cat >"$T/i315.md" <<'EOF'
## Acceptance Criteria
- Test: khoá B → HIT
- Test: hai lượt --full cùng diff → lượt 2 dùng lại REG-DK-ALL-01
- Đo tỷ lệ dùng lại ≥ 50%
EOF
cat >"$T/pr343.md" <<'EOF'
<!-- sb:ac -->
- [x] AC #315 mục 3 đạt
- [x] Gate --full exit 0
<!-- /sb:ac -->
EOF
out=$(python3 "$AC" --issue-body "$T/i318.md" --pr-body "$T/pr343.md" --branch issue-318-build)
[ "$(printf '%s' "$out" | field indirect)" = "[315]" ] && [ "$(printf '%s' "$out" | field collapsed)" = false ] \
  && ok "chưa đọc thẻ tham chiếu: báo indirect [315]" || fail "indirect: $out"
out=$(python3 "$AC" --issue-body "$T/i318.md" --extra-issue-body "315=$T/i315.md" --pr-body "$T/pr343.md" --branch issue-318-build)
[ "$(printf '%s' "$out" | field issue_ac)" = 4 ] && [ "$(printf '%s' "$out" | field collapsed)" = true ] \
  && ok "đọc #315: 3 AC của #315 + 1 dòng gate = 4 > 2 dòng sb:ac → collapsed (đúng ca #318/#343)" || fail "indirect expand: $out"

# Nhiều thẻ trên một dòng, "AC của #X" không chữ "thẻ"; thẻ không đọc được vẫn tính ít nhất 1 AC (không bao giờ giảm).
printf '## Acceptance Criteria\n- [ ] AC của #344, #338 đạt\n- [ ] Gate\n' > "$T/i319.md"
out=$(python3 "$AC" --issue-body "$T/i319.md" --extra-issue-body "344=$T/i315.md" --pr-body "$T/pr343.md" --branch issue-319-x)
[ "$(printf '%s' "$out" | field indirect)" = "[338, 344]" ] && [ "$(printf '%s' "$out" | field issue_ac)" = 5 ] \
  && ok "AC của #344, #338: 3 (đọc được) + 1 (#338 chưa đọc) + 1 gate = 5" || fail "multi indirect: $out"

# Chỉ số thẻ liền sau "AC của": "(xem PR #343)" không phải thẻ tham chiếu. sb:ac đánh số "1. [x]" vẫn là dòng AC.
printf '## Acceptance Criteria\n- [ ] AC của thẻ #315 đạt (xem PR #343, như #300)\n' > "$T/i320.md"
printf '<!-- sb:ac -->\n1. [x] a\n2) [ ] b\n<!-- /sb:ac -->\n' > "$T/num.md"
out=$(python3 "$AC" --issue-body "$T/i320.md" --pr-body "$T/num.md" --branch issue-320-x)
[ "$(printf '%s' "$out" | field indirect)" = "[315]" ] && [ "$(printf '%s' "$out" | field pr_ac)" = 2 ] \
  && [ "$(printf '%s' "$out" | field unticked)" = '["b"]' ] \
  && ok "chỉ #315 là thẻ tham chiếu; sb:ac '1. [x]' / '2) [ ]' được đếm" || fail "refs/numbered: $out"

# "## …" trong code fence của mục AC không cắt mục AC.
printf '## Acceptance Criteria\n- [ ] A\n```\n## không phải heading\n- trong fence\n```\n- [ ] B\n## Risk\n- r\n' > "$T/fence.md"
out=$(python3 "$AC" --issue-body "$T/fence.md" --pr-body "$T/pr343.md" --branch issue-1-x)
[ "$(printf '%s' "$out" | field issue_ac)" = 2 ] && ok "## trong code fence không kết thúc mục AC (đếm A và B)" || fail "fence heading: $out"

printf 'bullets\n\nCloses #318\nFixes: ToanMobile/agent-workbench#315\nresolved #377\n' > "$T/msg.md"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --msg "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[315, 318]" ] \
  && ok "Closes/Fixes:/owner/repo#N thẻ khác trong message squash → foreign_closes" || fail "foreign closes: $out"
out=$(python3 "$AC" --pr-body "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field ac)" = false ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[315, 318]" ] \
  && [ "$(printf '%s' "$out" | field collapsed)" = null ] && [ "$(printf '%s' "$out" | field closes_own)" = true ] \
  && ok "PR không có sb:ac, chưa đưa body issue: vẫn kiểm Closes lạ, báo closes_own, không đếm AC" || fail "no-block: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field collapsed)" = true ] && [ "$(printf '%s' "$out" | field pr_ac)" = 0 ] \
  && ok "không có sb:ac mà đóng thẻ có 4 AC: collapsed (nén về 0 dòng)" || fail "no-block collapsed: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch fix-githooks-main-fallback)
[ "$(printf '%s' "$out" | field skip)" = true ] && ok "nhánh không mang issue-<N> → skip" || fail "non-card branch not skipped: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch issue-3770-x)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[377]" ] && ok "issue-3770 không bị đọc thành thẻ 377" || fail "card number prefix: $out"

cp "$T/full.md" "$T/rw.md"; cp "$T/msg.md" "$T/rw-msg.md"; printf 'Fixes: ToanMobile/agent-workbench#377\n' >> "$T/rw-msg.md"
python3 "$AC" --rewrite-closes "$T/rw.md" --card 377 >/dev/null
python3 "$AC" --rewrite-closes "$T/rw-msg.md" --card 377 >/dev/null
grep -q '^Refs #377$' "$T/rw.md" && grep -q '^Refs ToanMobile/agent-workbench#377$' "$T/rw-msg.md" && grep -q '^Refs #377$' "$T/rw-msg.md" \
  && grep -q '^Closes #318$' "$T/rw-msg.md" \
  && [ "$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/rw.md" --msg "$T/rw-msg.md" --branch issue-377 | field foreign_closes)" = "[315, 318]" ] \
  && ok "--rewrite-closes đổi mọi dạng đóng #377 thành Refs, không đụng #318/#315" || fail "rewrite: $(cat "$T/rw.md" "$T/rw-msg.md")"

[ "$FAILS" -eq 0 ] && { echo "ac-check: all checks passed"; exit 0; }
echo "ac-check: $FAILS FAILED"; exit 1
