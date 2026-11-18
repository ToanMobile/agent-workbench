#!/usr/bin/env bash
# #1175/#1176: một [orchestrator] [decision] hợp lệ đăng trên ISSUE của thẻ (nơi decision-policy.md bảo đăng) phải gỡ mục
# "❌ Not done" của report QA cũ hơn nó ở preflight qa-report của merge gate, như decision đăng trên PR. Luật hợp lệ giữ nguyên
# (super-board-decision.py) và so thời gian createdAt: cũ hơn QA, người lạ, marker lane khác, không có thời gian, DANH SÁCH DỪNG,
# đọc issue lỗi, decision_policy tắt ⇒ vẫn exit 11. Chạy gate thật với gh giả; "qua cổng QA" = log có VERIFY-RAN.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_TEST_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qadecision-test.XXXXXX")"
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
head=$(cat "$FAKE_DIR/pr$n.head" 2>/dev/null)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" issue view "*"comments"*)
    [ -f "$FAKE_DIR/issue$n.fail" ] && { echo "fake gh: HTTP 502" >&2; exit 1; }
    [ -f "$FAKE_DIR/issue$n.garbage" ] && { echo "<html>not json"; exit 0; }
    echo "issue-comments $n" >> "$FAKE_DIR/calls.log"
    python3 -c 'import json,sys; print(json.dumps({"comments":json.load(open(sys.argv[1]))}))' "$FAKE_DIR/issue$n.comments" ;;
  *" pr merge "*) echo "fake gh: must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
mkcfg() { python3 -c 'import json,sys
c={"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo VERIFY-RAN; exit 1"]}
if sys.argv[1]=="off": c["decision_policy"]={"enabled":False}
print(json.dumps(c))' "$1"; }
mkcfg on > "$TMP/cfg.json"; mkcfg off > "$TMP/cfg-off.json"

AC_OK=$'## Acceptance criteria\n- [x] size message\\\n  ↳ `e2e/a.spec.ts:14`\n- [ ] AC3 measured after merge\\\n  ↳ not verified: after merge\n'
QA_ND='[{"body":"[qa] [report] ✅ pass · v1\n✅ Done: AC1 AC2\n❌ Not done: AC3 measured after merge\nNext: reviewer","createdAt":"2026-11-14T03:40:00Z"}]'
QA="$QA_ND"
MK='<!-- sb-decision:orchestrator -->'
i=0
# run_case <issue-comments-json> [cfg]: comment không ghi tác giả = OWNER "owner".
run_case() {
  i=$((i + 1))
  python3 -c 'import json,sys
cs=json.loads(sys.argv[2])
for c in cs:
    c.setdefault("authorAssociation","OWNER"); c.setdefault("author",{"login":"owner"})
print(json.dumps({"files":[{"path":"b"}],"labels":[],"body":sys.argv[1],"comments":cs,"author":{"login":"owner"},"additions":1,"deletions":0,"changedFiles":1}))' "$AC_OK" "$QA" > "$TMP/pr5.meta"
  python3 -c 'import json,sys
cs=json.loads(sys.argv[1])
for c in cs:
    c.setdefault("authorAssociation","OWNER"); c.setdefault("author",{"login":"owner"})
print(json.dumps(cs))' "$1" > "$TMP/issue5.comments"
  ( cd "$WT" && bash "$GATE" --config "${2:-$TMP/cfg.json}" --pr 5 --expect-head "$H" ) >"$TMP/g$i.log" 2>&1; rc=$?
}
refused() {
  if [ "$rc" -eq 11 ] && grep -q '^qa-report: .*AC3' "$TMP/g$i.log" && ! grep -q VERIFY-RAN "$TMP/g$i.log"; then ok "refused: $1"
  else fail "want exit 11 + qa-report AC3 for: $1 (exit $rc): $(grep -a -m3 -E 'qa-report|VERIFY|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}
passed() {
  if grep -q VERIFY-RAN "$TMP/g$i.log" && ! grep -q '^qa-report:' "$TMP/g$i.log"; then ok "not refused: $1"
  else fail "must reach verify for: $1 (exit $rc): $(grep -a -m3 -E 'qa-report|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}
# dec <createdAt-json> [extra json fields] [marker line]: một comment decision trên issue (JSON).
dec() {
  local mk="${3-$MK}"
  python3 -c 'import json,sys
created, extra, mk = sys.argv[1], sys.argv[2], sys.argv[3]
body = (mk + "\n" if mk else "") + "[orchestrator] [decision] AC3 is a post-merge measurement (rule 20)\nQuyết định cuối, không hỏi lại"
c = {"body": body, "createdAt": json.loads(created)}
c.update(json.loads("{" + extra + "}"))
print(json.dumps(c))' "$1" "${2:-}" "$mk"
}

run_case "[$(dec '"2026-11-14T04:05:42Z"')]";          passed "valid orchestrator decision on the card issue, newer than the QA report (#1176)"
run_case "[$(dec '"2026-11-14T04:05:42Z"' '' '')]";    passed "plain owner decision (no marker) on the card issue"
run_case "[$(dec '"2026-11-14T03:30:00Z"')]";          refused "issue decision older than the QA report"
run_case "[$(dec '"2026-11-14T04:05:42Z"' '"authorAssociation":"CONTRIBUTOR","author":{"login":"rando"}')]"
refused "issue decision by a non-owner"
run_case "[$(dec '"2026-11-14T04:05:42Z"' '' '<!-- sb-write -->')]"; refused "issue decision carrying another lane's marker"
run_case "[$(dec 'null')]";                            refused "issue decision without a timestamp (cannot be ordered)"
run_case "[]";                                         refused "no decision anywhere"
run_case "[$(dec '"2026-11-14T04:05:42Z"')]" "$TMP/cfg-off.json"; refused "decision_policy.enabled=false"
touch "$TMP/issue5.fail"
run_case "[$(dec '"2026-11-14T04:05:42Z"')]";          refused "issue comments unreadable (fail closed)"
rm -f "$TMP/issue5.fail"
touch "$TMP/issue5.garbage"
run_case "[$(dec '"2026-11-14T04:05:42Z"')]";          refused "issue comments not JSON: still exit 11, not the human gate"
rm -f "$TMP/issue5.garbage"
# QA report không có thời gian (fixture cũ): không xếp được thứ tự ⇒ không gỡ.
QA='[{"body":"[qa] [report] ✅ pass · v1\n❌ Not done: AC3 measured after merge\nNext: reviewer"}]'
run_case "[$(dec '"2026-11-14T04:05:42Z"')]";          refused "QA report without a timestamp (cannot be ordered)"
# DANH SÁCH DỪNG: mục Not done nêu secret thì decision không gỡ.
QA='[{"body":"[qa] [report] ✅ pass · v1\n❌ Not done: AC3 needs the prod api key\nNext: reviewer","createdAt":"2026-11-14T03:40:00Z"}]'
run_case "[$(dec '"2026-11-14T04:05:42Z"')]";          refused "stop-list item (api key) is not lifted by a decision"
# Report sạch: không đọc issue (không thêm lời gọi GitHub trên đường bình thường).
QA='[{"body":"[qa] [report] ✅ pass · v1\n✅ Done: AC1 AC2\nNext: reviewer","createdAt":"2026-11-14T03:40:00Z"}]'
: > "$TMP/calls.log"
run_case "[]"
if grep -q VERIFY-RAN "$TMP/g$i.log" && ! [ -s "$TMP/calls.log" ]; then ok "clean QA report: issue comments never read"
else fail "clean QA report read issue comments or did not reach verify (exit $rc)"; fi

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
