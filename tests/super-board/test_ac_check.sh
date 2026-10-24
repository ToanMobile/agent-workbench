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
out=$(python3 "$AC" --issue-body "$T/i318.md" --extra-issue-body "$T/i315.md" --pr-body "$T/pr343.md" --branch issue-318-build)
[ "$(printf '%s' "$out" | field issue_ac)" = 4 ] && [ "$(printf '%s' "$out" | field collapsed)" = true ] \
  && ok "đọc #315: 3 AC của #315 + 1 dòng gate = 4 > 2 dòng sb:ac → collapsed (đúng ca #318/#343)" || fail "indirect expand: $out"

printf 'bullets\n\nCloses #318\nFixes: ToanMobile/agent-workbench#315\nresolved #377\n' > "$T/msg.md"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --msg "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[315, 318]" ] \
  && ok "Closes/Fixes:/owner/repo#N thẻ khác trong message squash → foreign_closes" || fail "foreign closes: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field ac)" = false ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[315, 318]" ] \
  && [ "$(printf '%s' "$out" | field collapsed)" = null ] \
  && ok "PR không có sb:ac: vẫn kiểm Closes lạ, không đếm AC" || fail "no-block: $out"
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
