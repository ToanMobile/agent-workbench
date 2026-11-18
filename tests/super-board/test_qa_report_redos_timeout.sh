#!/usr/bin/env bash
# #1300 (ReDoS + timeout): dựa trên harness của test_merge_gate_qa_report.sh. Gốc: merge gate từ chối PR khi report QA mới nhất còn "❌ Not done" có nội dung, hay AC [x] không có dòng bằng chứng "↳".
# Mỗi ca chạy gate thật với gh giả; lệnh verify in VERIFY-RAN rồi đỏ, nên "qua được cổng QA" nghĩa là log có VERIFY-RAN.
# Từ chối: exit 11 + dòng "qa-report:" + KHÔNG có VERIFY-RAN. Không đụng halt/slot thật: mọi trạng thái ở thư mục tạm.
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

AC_OK=$'## Acceptance criteria\n- [x] size message\\\n  ↳ `e2e/a.spec.ts:14`\n'
QA_CLEAN='[{"body":"[qa] [report] ✅ pass · v1\nDid: x\n✅ Done: AC1\nNext: reviewer"}]'
CHECKER="$ROOT/.claude/bin/super-board-qa-report.py"
now() { python3 -c 'import time; print(time.time())'; }
secs() { python3 -c 'import sys; print(int(float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"; }

# 1) Checker: dòng Not done `a.` x 32000 (không có `/`) xong dưới 5 s; vẫn exit 1 khi nêu AC, exit 0 khi không.
mkmeta() {  # mkmeta <file> <Not done text>
  python3 - "$1" "$2" <<'PY'
import json, sys
f, nd = sys.argv[1:3]
json.dump({"body": "## Acceptance criteria\n- [ ] size message still wrong on mobile\n", "author": {"login": "bot"},
           "comments": [{"author": {"login": "bot"}, "authorAssociation": "OWNER",
                         "body": "[qa] [report] ❌ failing · v1\n❌ Not done: " + nd + "\n"}]}, open(f, "w"))
PY
}
LONG=$(python3 -c 'print("a." * 32000)')
mkmeta "$TMP/long0.json" "$LONG"
t0=$(now); timeout 20 python3 "$CHECKER" --meta "$TMP/long0.json" >"$TMP/long0.out" 2>&1; rc0=$?; t1=$(now)
[ "$(secs "$t0" "$t1")" -lt 5 ] && [ "$rc0" -eq 0 ] && ok "checker: 'a.' x 32000 names no AC, done in $(secs "$t0" "$t1") s, exit 0" \
  || fail "checker: 'a.' x 32000 took $(secs "$t0" "$t1") s, exit $rc0 (want < 5 s, exit 0)"
mkmeta "$TMP/long1.json" "$LONG size message still wrong on mobile"
t0=$(now); timeout 20 python3 "$CHECKER" --meta "$TMP/long1.json" >"$TMP/long1.out" 2>&1; rc1=$?; t1=$(now)
[ "$(secs "$t0" "$t1")" -lt 5 ] && [ "$rc1" -eq 1 ] && grep -q '^qa-report:' "$TMP/long1.out" && ok "checker: long line that names an AC still exits 1 in $(secs "$t0" "$t1") s" \
  || fail "checker: long line naming an AC took $(secs "$t0" "$t1") s, exit $rc1 (want < 5 s, exit 1)"

# 2) Gate: checker treo thì gate không treo theo: exit 7 + 'qa-report: timeout' + không verify (cả lời gọi lần đầu).
cp -R "$(dirname "$GATE")" "$TMP/bin2"
printf '#!/usr/bin/env python3\nimport time; time.sleep(25)\n' > "$TMP/bin2/super-board-qa-report.py"
python3 -c 'import json,sys
print(json.dumps({"files":[{"path":"b"}],"labels":[],"body":sys.argv[1],"comments":json.loads(sys.argv[2]),"author":{"login":"owner"},"additions":1,"deletions":0,"changedFiles":1}))' "$AC_OK" "$QA_CLEAN" > "$TMP/pr5.meta"
t0=$(now)
( cd "$WT" && SB_QA_REPORT_TIMEOUT_S=3 bash "$TMP/bin2/super-board-merge-gate.sh" --config "$TMP/cfg.json" --pr 5 --expect-head "$H" ) >"$TMP/gt.log" 2>&1; rc=$?
t1=$(now)
if [ "$rc" -eq 7 ] && [ "$(secs "$t0" "$t1")" -lt 15 ] && grep -q '^qa-report: timeout' "$TMP/gt.log" && grep -q '^human-gate: qa-report' "$TMP/gt.log" && ! grep -q VERIFY-RAN "$TMP/gt.log"; then
  ok "gate: hung checker -> exit 7 + 'qa-report: timeout' in $(secs "$t0" "$t1") s"
else fail "gate: hung checker (exit $rc, $(secs "$t0" "$t1") s): $(grep -a -m3 -E 'human-gate|qa-report|merge-gate' "$TMP/gt.log" | tr '\n' '|')"; fi

# 3) names_ac: 3000 mục AC x 30000 vế `;` dưới 5 s.
python3 - "$TMP/many.json" <<'PY'
import json, sys
acs = "\n".join("- [ ] criterion number %05d that is long enough" % i for i in range(3000))
nd = ";".join(["x"] * 30000)
json.dump({"body": "## Acceptance criteria\n" + acs + "\n", "author": {"login": "bot"},
           "comments": [{"author": {"login": "bot"}, "authorAssociation": "OWNER", "body": "[qa] [report] ❌ failing · v1\n❌ Not done: " + nd + "\n"}]}, open(sys.argv[1], "w"))
PY
t0=$(now); timeout 30 python3 "$CHECKER" --meta "$TMP/many.json" >/dev/null 2>&1; rcm=$?; t1=$(now)
[ "$(secs "$t0" "$t1")" -lt 5 ] && [ "$rcm" -eq 0 ] && ok "checker: 3000 AC x 30000 clauses in $(secs "$t0" "$t1") s" || fail "checker: 3000 AC x 30000 clauses took $(secs "$t0" "$t1") s, exit $rcm"

# 4) AC_ID: `AC` + 32000 khoảng trắng + `x` (hai `\s*` liền nhau quanh `-?`) dưới 5 s; mã AC thật vẫn bị bắt (exit 1).
for pat in "AC"; do  # đuôi `x` để dòng không bị strip hết khoảng trắng; `AC -` + khoảng trắng đo 0 s nên không đưa vào
  SP=$(python3 -c 'import sys; print(sys.argv[1] + " " * 32000 + "x")' "$pat")
  mkmeta "$TMP/acsp.json" "$SP"
  t0=$(now); timeout 30 python3 "$CHECKER" --meta "$TMP/acsp.json" >/dev/null 2>&1; rca=$?; t1=$(now)
  [ "$(secs "$t0" "$t1")" -lt 5 ] && [ "$rca" -eq 0 ] && ok "checker: '$pat' + 32000 spaces + x in $(secs "$t0" "$t1") s, exit 0" \
    || fail "checker: '$pat' + 32000 spaces + x took $(secs "$t0" "$t1") s, exit $rca (want < 5 s, exit 0)"
done
for named in "AC2 chưa xong" "AC 2 chưa xong" "AC - 2 chưa xong" "AC-#2 chưa xong" "ac  -  3"; do
  mkmeta "$TMP/acnamed.json" "$named"
  timeout 10 python3 "$CHECKER" --meta "$TMP/acnamed.json" >/dev/null 2>&1; rcn=$?
  [ "$rcn" -eq 1 ] && ok "checker: '$named' still names an AC (exit 1)" || fail "checker: '$named' exit $rcn (want 1)"
done

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
