#!/usr/bin/env bash
# T0054 (24/10): super-board-ac-check.py — AC bị nén, Closes thẻ lạ, dòng AC chưa tick, PR tay bị bỏ qua.
# Tình huống thật: PR #343 (Closes #318) nén 10+ AC thành 3 dòng tóm tắt đã tick; #315 đóng mà AC cache chưa ai làm.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
AC="$HERE/../../.claude/bin/super-board-ac-check.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(json.dumps(v, ensure_ascii=False) if isinstance(v,(list,bool)) else v)' "$1"; }

cat >"$T/issue.md" <<'EOF'
## Acceptance Criteria
- [ ] Test: khoá B FAIL tra khoá A → HIT
- [ ] Test: hai lượt --full cùng diff → lượt 2 dùng lại REG-DK-ALL-01
- [ ] Đo runs.jsonl: tỷ lệ dùng lại ≥ 50%
## Gộp thêm: #338
- [ ] Test: suite 2, 3 không chờ tải
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
[ "$(printf '%s' "$out" | field collapsed)" = true ] && [ "$(printf '%s' "$out" | field issue_ac)" = 4 ] \
  && ok "4 AC của thẻ nén thành 2 dòng sb:ac → collapsed" || fail "collapsed not caught: $out"

cat >"$T/full.md" <<'EOF'
Closes #377
<!-- sb:ac -->
- [x] Test: khoá B FAIL tra khoá A → HIT\
  ↳ ca 33h
- [x] Test: hai lượt --full cùng diff → lượt 2 dùng lại REG-DK-ALL-01
- [ ] Đo runs.jsonl: tỷ lệ dùng lại ≥ 50%\
  ↳ chỉ đo được sau merge
- [x] Test: suite 2, 3 không chờ tải
- [x] Gate --full exit 0
<!-- /sb:ac -->
EOF
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch loop/issue-377)
[ "$(printf '%s' "$out" | field collapsed)" = false ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] \
  && printf '%s' "$out" | field unticked | grep -q 'Đo runs.jsonl' \
  && ok "mỗi AC một dòng: không collapsed; dòng chưa tick được liệt kê; Closes đúng thẻ" || fail "full block misread: $out"

printf 'bullets\n\nCloses #318\nFixes ToanMobile/agent-workbench#315\n' > "$T/msg.md"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --msg "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[315, 318]" ] \
  && ok "Closes/Fixes thẻ khác (cả dạng owner/repo#N) trong message squash → foreign_closes" || fail "foreign closes: $out"

out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/msg.md" --branch issue-377-perf)
[ "$(printf '%s' "$out" | field skip)" = true ] && ok "PR không có khối sb:ac → skip (PR tay giữ hành vi cũ)" || fail "no-block not skipped: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch fix-githooks-main-fallback)
[ "$(printf '%s' "$out" | field skip)" = true ] && ok "nhánh không mang issue-<N> → skip" || fail "non-card branch not skipped: $out"
out=$(python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/full.md" --branch issue-3770-x)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[377]" ] && ok "issue-3770 không bị đọc thành thẻ 377" || fail "card number prefix: $out"

cp "$T/full.md" "$T/rw.md"; cp "$T/msg.md" "$T/rw-msg.md"; printf 'closes: #377\n' >> "$T/rw-msg.md"
python3 "$AC" --rewrite-closes "$T/rw.md" --card 377 >/dev/null
python3 "$AC" --rewrite-closes "$T/rw-msg.md" --card 377 >/dev/null
grep -q '^Refs #377$' "$T/rw.md" && grep -q '^Refs: #377$' "$T/rw-msg.md" && grep -q '^Closes #318$' "$T/rw-msg.md" \
  && ! python3 "$AC" --issue-body "$T/issue.md" --pr-body "$T/rw.md" --msg "$T/rw-msg.md" --branch issue-377 | grep -q '"foreign_closes": \[[^]]*377' \
  && ok "--rewrite-closes đổi Closes #377 thành Refs, không đụng #318" || fail "rewrite: $(cat "$T/rw.md" "$T/rw-msg.md")"

[ "$FAILS" -eq 0 ] && { echo "ac-check: all checks passed"; exit 0; }
echo "ac-check: $FAILS FAILED"; exit 1
