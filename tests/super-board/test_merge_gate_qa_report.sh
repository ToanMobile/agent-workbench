#!/usr/bin/env bash
# #364: merge gate từ chối PR khi report QA mới nhất còn "❌ Not done" có nội dung, hay AC [x] không có dòng bằng chứng "↳".
# Mỗi ca chạy gate thật với gh giả; lệnh verify in VERIFY-RAN rồi đỏ, nên "qua được cổng QA" nghĩa là log có VERIFY-RAN.
# Từ chối: exit 11 + dòng "qa-report:" + KHÔNG có VERIFY-RAN. Không đụng halt/slot thật: mọi trạng thái ở thư mục tạm.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_TEST_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qareport-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/issue-5-review"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
python3 -c 'import json; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo VERIFY-RAN; exit 1"]}))' > "$TMP/cfg.json"

i=0
# run_case <body> <comments-json>: ghi meta PR rồi chạy gate; log ở $TMP/g$i.log, mã thoát ở $rc
run_case() {
  i=$((i + 1))
  # Comment không ghi tác giả mặc định là OWNER (đáng tin); ca nào cần người lạ ghi authorAssociation/author rõ trong JSON.
  python3 -c 'import json,sys
cs=json.loads(sys.argv[2])
for c in cs:
    c.setdefault("authorAssociation","OWNER"); c.setdefault("author",{"login":"owner"})
print(json.dumps({"files":[{"path":"b"}],"labels":[],"body":sys.argv[1],"comments":cs,"author":{"login":"owner"},"additions":1,"deletions":0,"changedFiles":1}))' "$1" "$2" > "$TMP/pr5.meta"
  ( cd "$WT" && bash "${GATE_OVERRIDE:-$GATE}" --config "$TMP/cfg.json" --pr 5 --expect-head "$H" ) >"$TMP/g$i.log" 2>&1; rc=$?
}
refused() {  # refused <label> <qa-report text that must appear>
  if [ "$rc" -eq 11 ] && grep -q "^qa-report: .*$2" "$TMP/g$i.log" && ! grep -q VERIFY-RAN "$TMP/g$i.log"; then ok "refused: $1"
  else fail "want exit 11 + 'qa-report: $2' before verify for: $1 (exit $rc): $(grep -a -m2 -E 'qa-report|VERIFY|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}
passed() {  # passed <label>: qua cổng QA, chạy tới verify
  if grep -q VERIFY-RAN "$TMP/g$i.log" && ! grep -q '^qa-report:' "$TMP/g$i.log"; then ok "not refused: $1"
  else fail "must reach verify for: $1 (exit $rc): $(grep -a -m2 -E 'qa-report|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}

AC_OK=$'## Acceptance criteria\n- [x] size message\\\n  ↳ `e2e/a.spec.ts:14`\n- [ ] deploy check\\\n  ↳ not verified: needs prod\n'
QA_BAD='[{"body":"[qa] [report] ✅ pass · v1\nDid: x\n✅ Done: AC1\n❌ Not done: AC2 mobile message hidden\nNext: reviewer"}]'
QA_CLEAN='[{"body":"[qa] [report] ✅ pass · v1\nDid: x\n✅ Done: AC1 AC2\nNext: reviewer"}]'
QA_OLD_BAD_NEW_CLEAN='[{"body":"[qa] [report] ❌ failing · v1\n❌ Not done: AC1 broken"},{"body":"[qa] [report] ✅ pass · v2\n✅ Done: AC1"}]'
QA_NEW_BAD='[{"body":"[qa] [report] ✅ pass · v1\n✅ Done: AC1"},{"body":"[reviewer] [report] ✅ ok"},{"body":"[qa] [report] ✅ pass · v2\n❌ Not done: AC3 not run"}]'
QA_EMPTY_VALUE='[{"body":"[qa] [report] ✅ pass · v1\n❌ Not done: none\n✅ Done: all"}]'

run_case "$AC_OK" "$QA_BAD";            refused "latest QA report has a '❌ Not done' item" "AC2 mobile message hidden"
run_case "$AC_OK" "$QA_NEW_BAD";        refused "newest QA report is the unfinished one (reviewer comment in between)" "AC3 not run"
run_case "$AC_OK" "$QA_CLEAN";          passed "clean QA report + AC with proof"
run_case "$AC_OK" "$QA_OLD_BAD_NEW_CLEAN"; passed "an older QA report with ❌ is superseded by a clean newer one"
run_case "$AC_OK" "$QA_EMPTY_VALUE";    passed "'❌ Not done: none' is empty"
run_case "$AC_OK" "[]";                 passed "no QA comment at all"
run_case $'## Acceptance criteria\n- [x] size message\n- [x] other\\\n  ↳ `e2e/b.spec.ts:2`\n' "$QA_CLEAN"
refused "AC ticked [x] with no proof line" "size message"
run_case $'## Acceptance criteria\n- [x] size message\\\n  ↳ \n' "$QA_CLEAN"
refused "AC proof line is empty" "size message"
run_case $'## Notes\n- [x] unrelated checklist\n' "$QA_CLEAN"; passed "a [x] outside the Acceptance criteria section is ignored"

# Ghi chú phạm vi không nêu AC của PR (thật từ #343/#345/#348/#350/#357) không bị từ chối.
QA_SCOPE='[{"body":"[qa] [report] ✅ pass · v1\n✅ Done: all\n❌ Not done: #299 đã tách sang #352. Không có ảnh (không có UI)\nNext: reviewer"}]'
run_case "$AC_OK" "$QA_SCOPE";          passed "'Not done' that is only a scope/split note (#N, no UI) names no AC"
# AC được nêu bằng nguyên văn trong khối AC (không có mã AC) vẫn là AC.
QA_TEXT='[{"body":"[qa] [report] ❌ failing · v1\n❌ Not done: size message still wrong on mobile\nNext: builder"}]'
run_case "$AC_OK" "$QA_TEXT";           refused "Not done quotes an AC by its listed text" "size message still wrong"
# Mục nhiều dòng: bullet / dòng thụt lề dưới "❌ Not done:" thuộc mục đó dù dòng đầu rỗng.
QA_MULTI='[{"body":"[qa] [report] ❌ failing · v1\n❌ Not done:\n- AC2 mobile message hidden\n  (second line)\nNext: builder"}]'
run_case "$AC_OK" "$QA_MULTI";          refused "multi-line 'Not done' with bullets naming an AC" "AC2 mobile message hidden"
QA_MULTI_SCOPE='[{"body":"[qa] [report] ✅ pass · v1\n❌ Not done:\n- #299 đã tách sang #352\n- không có ảnh (không có UI)\nNext: reviewer"}]'
run_case "$AC_OK" "$QA_MULTI_SCOPE";    passed "multi-line 'Not done' that is all scope notes"
# Ai cũng comment được: report sạch của người lạ / dòng trích dẫn / khối code không được thay report đỏ của người đáng tin.
QA_FAIL_FIRST='{"body":"[qa] [report] ❌ failing · v1\n❌ Not done: AC1 broken"}'
QA_STRANGER='{"body":"[qa] [report] ✅ pass · v2\n✅ Done: AC1","authorAssociation":"NONE","author":{"login":"rando"}}'
QA_QUOTED='{"body":"> [qa] [report] ✅ pass · v2\n> ✅ Done: AC1\nlooks fine to me"}'
QA_FENCED='{"body":"```\n[qa] [report] ✅ pass · v2\n```"}'
run_case "$AC_OK" "[$QA_FAIL_FIRST,$QA_STRANGER]"; refused "a clean report from a non-collaborator does not supersede a failing one" "AC1 broken"
run_case "$AC_OK" "[$QA_FAIL_FIRST,$QA_QUOTED]";   refused "a quoted '[qa] [report]' line does not supersede a failing one" "AC1 broken"
run_case "$AC_OK" "[$QA_FAIL_FIRST,$QA_FENCED]";   refused "a fenced code block does not supersede a failing report" "AC1 broken"
QA_QUOTE_ND='[{"body":"[qa] [report] ✅ pass · v2\n❌ Not done: #299 đã tách sang #352\n  > AC3 not run (quoted from the previous round)\n✅ Done: AC3"}]'
run_case "$AC_OK" "$QA_QUOTE_ND";                  passed "a quoted '❌ Not done' line inside a clean report is not a claim"
QA_AUTHOR='{"body":"[qa] [report] ✅ pass · v2\n✅ Done: AC1","authorAssociation":"CONTRIBUTOR","author":{"login":"owner"}}'
run_case "$AC_OK" "[$QA_FAIL_FIRST,$QA_AUTHOR]";   passed "the PR author's clean report supersedes (author counts as trusted)"
# Bằng chứng ↳ phải liền sau mục AC: dừng ở dòng trống, ↳ ở đoạn văn bên dưới không tính.
run_case $'## Acceptance criteria\n- [x] size message\n\nsome prose\n  ↳ `e2e/a.spec.ts:14`\n' "$QA_CLEAN"
refused "a ↳ line after a blank line is not this AC's proof" "size message"
# Khối "## AC + proof" (PR #345/#374 đã merge): nhận ra AC cho Not done, mục [x] mang bằng chứng ngay trên dòng nên không cần ↳.
AC_PLUS=$'## AC + proof\n- [x] Test ĐỎ→XANH cho hook, đã chạy đột biến\n- [ ] Nhánh resume chưa thử thật\n'
run_case "$AC_PLUS" "$QA_CLEAN"; passed "'## AC + proof' heading: [x] with inline proof, no ↳ needed"
QA_PLUS='[{"body":"[qa] [report] ❌ failing · v1\n❌ Not done: Nhánh resume chưa thử thật\nNext: builder"}]'
run_case "$AC_PLUS" "$QA_PLUS"; refused "'## AC + proof' heading is read as an AC list" "Nhánh resume"

# Checker không quyết định được (metadata hỏng) hay crash: KHÔNG phải lỗi build (11) mà là cổng người duyệt (exit 7 + human-gate:).
printf '[1,2]' > "$TMP/notobj.json"
python3 "$(dirname "$GATE")/super-board-qa-report.py" --meta "$TMP/notobj.json" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "checker: metadata that is not an object exits 2" || fail "checker: non-object metadata did not exit 2"
python3 "$(dirname "$GATE")/super-board-qa-report.py" --meta "$TMP/missing.json" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "checker: unreadable meta path exits 2" || fail "checker: unreadable meta did not exit 2"
cp -R "$(dirname "$GATE")" "$TMP/bin2"
undecided() {  # undecided <label>: exit 7, dòng human-gate: qa-report, không 11, không verify
  if [ "$rc" -eq 7 ] && grep -q '^human-gate: qa-report' "$TMP/g$i.log" && ! grep -q VERIFY-RAN "$TMP/g$i.log"; then ok "human gate (not back-to-Build): $1"
  else fail "want exit 7 + 'human-gate: qa-report' for: $1 (exit $rc): $(grep -a -m3 -E 'human-gate|qa-report|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}
printf '#!/usr/bin/env python3\nimport sys; sys.exit(2)\n' > "$TMP/bin2/super-board-qa-report.py"
GATE_OVERRIDE="$TMP/bin2/super-board-merge-gate.sh" run_case "$AC_OK" "$QA_CLEAN"; undecided "checker exit 2 (metadata unreadable)"
printf '#!/usr/bin/env python3\nraise RuntimeError("boom")\n' > "$TMP/bin2/super-board-qa-report.py"
GATE_OVERRIDE="$TMP/bin2/super-board-merge-gate.sh" run_case "$AC_OK" "$QA_CLEAN"; undecided "checker crashed with a traceback"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
