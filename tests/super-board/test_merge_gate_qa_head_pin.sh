#!/usr/bin/env bash
# T0255: merge gate từ chối PR khi report QA mới nhất nêu sha của nhánh PR mà head còn commit code sau sha đó
# (QA chưa chạy lại trên code cuối). Đo 21/10–04/11: 9/174 PR board merge với commit code sau sha QA cuối.
# Cùng harness với test_merge_gate_qa_report.sh: gate thật, gh giả, git thật; verify in VERIFY-RAN rồi đỏ, nên
# "qua cổng QA" = log có VERIFY-RAN. Từ chối = exit 11 + dòng "qa-report:" + KHÔNG có VERIFY-RAN. Offline.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_TEST_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qapin-test.XXXXXX")"
trap '[ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/issue-5-review"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
BASE0=$(git -C "$R" rev-parse main)
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm "card: first build"
Q1=$(git -C "$WT" rev-parse HEAD)          # sha QA đã kiểm

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

AC_OK=$'## Acceptance criteria\n- [x] size message\\\n  ↳ `e2e/a.spec.ts:14`\n'
i=0
# run_case <comments-json>: đẩy nhánh, ghi head/diff/meta PR rồi chạy gate; log ở $TMP/g$i.log, mã thoát ở $rc
run_case() {
  i=$((i + 1))
  git -C "$WT" push -q -f origin issue-5-x
  H=$(git -C "$WT" rev-parse HEAD); echo "$H" > "$TMP/pr5.head"
  OM=$(git --git-dir="$O" rev-parse main)   # main thật trên origin (ref origin/main cục bộ có thể bị làm cũ cố ý)
  git -C "$R" diff "$OM" "$H" > "$TMP/pr5.diff"
  rm -f "$TMP/halt.json"   # một ca halt không được chặn các ca sau
  python3 -c 'import json,sys
num=[l.split("\t") for l in sys.argv[3].splitlines() if l]
files=[{"path":n[2]} for n in num]
cs=json.loads(sys.argv[2])
for c in cs:
    c.setdefault("authorAssociation","OWNER"); c.setdefault("author",{"login":"owner"})
print(json.dumps({"files":files,"labels":[],"body":sys.argv[1],"comments":cs,"author":{"login":"owner"},
  "additions":sum(int(n[0]) for n in num),"deletions":sum(int(n[1]) for n in num),"changedFiles":len(files)}))' \
    "$AC_OK" "$1" "$(git -C "$R" diff --numstat "$OM" "$H")" > "$TMP/pr5.meta"
  ( cd "$WT" && bash "$GATE" --config "$TMP/cfg.json" --pr 5 --expect-head "$H" ) >"$TMP/g$i.log" 2>&1; rc=$?
}
qa() { printf '[{"body":"[qa] [report] ✅ pass · PR #5 @ %s\\nDid: ran tests\\n✅ Done: AC1\\nNext: reviewer"}]' "$1"; }
refused() {  # refused <label>
  if [ "$rc" -eq 11 ] && grep -q '^qa-report: .*QA phải chạy lại trên head' "$TMP/g$i.log" && ! grep -q VERIFY-RAN "$TMP/g$i.log"; then ok "refused: $1"
  else fail "want exit 11 + 'qa-report: … QA phải chạy lại trên head' before verify for: $1 (exit $rc): $(grep -a -m3 -E 'qa-report|VERIFY|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}
passed() {  # passed <label>
  if grep -q VERIFY-RAN "$TMP/g$i.log" && ! grep -q '^qa-report:' "$TMP/g$i.log"; then ok "not refused: $1"
  else fail "must reach verify for: $1 (exit $rc): $(grep -a -m3 -E 'qa-report|merge-gate' "$TMP/g$i.log" | tr '\n' '|')"; fi
}

# b. QA nêu đúng head (sha ngắn) ⇒ qua.
run_case "$(qa "${Q1:0:8}")";                passed "QA names the current head"
# f. QA không nêu sha nào ⇒ qua (hành vi cũ).
run_case '[{"body":"[qa] [report] ✅ pass\nDid: ran tests\n✅ Done: AC1"}]'; passed "QA report names no sha"
# c. Sau sha QA chỉ có commit bằng chứng dưới docs/super-board/runs/ ⇒ qua.
mkdir -p "$WT/docs/super-board/runs/issue-5-qa-v1"; echo ok > "$WT/docs/super-board/runs/issue-5-qa-v1/summary.md"
git -C "$WT" add docs; git -C "$WT" commit -qm "qa evidence"
run_case "$(qa "${Q1:0:8}")";                passed "only a QA evidence commit after the QA sha"
# d. Gộp main (main có commit code riêng) vào nhánh sau sha QA ⇒ qua.
echo m > "$R/m"; git -C "$R" add m; git -C "$R" commit -qm "main: other work"; git -C "$R" push -q origin main
git -C "$WT" fetch -q origin main; git -C "$WT" merge -q --no-edit origin/main
run_case "$(qa "${Q1:0:8}")";                passed "only a merge of main after the QA sha"
# d2. Ref origin/main cục bộ cũ (trước commit main vừa gộp; head đã có cục bộ) ⇒ vẫn qua (Grok T0255 P1: không đếm commit main).
git -C "$R" update-ref refs/remotes/origin/main "$BASE0"
run_case "$(qa "${Q1:0:8}")";                passed "a stale local origin/main does not count merged main commits"
# e. QA chỉ nêu sha của main (ví dụ 'đỏ y hệt trên origin/main <sha>') ⇒ không phải sha nhánh, qua.
run_case "$(qa "${BASE0:0:8}")";             passed "QA names only a base-branch sha"
# a. Builder đẩy commit sửa code sau sha QA ⇒ từ chối, QA phải chạy lại trên head.
echo b2 > "$WT/b"; git -C "$WT" commit -qam "fix: rebuild after review"
run_case "$(qa "${Q1:0:8}")";                refused "a code commit after the sha the newest QA report tested"
# Report QA mới hơn nêu head mới ⇒ qua.
H2=$(git -C "$WT" rev-parse HEAD)
run_case "[$(qa "${Q1:0:8}" | sed 's/^\[//;s/\]$//'),$(qa "${H2:0:10}" | sed 's/^\[//;s/\]$//')]"; passed "a newer QA report names the new head"
# g. Sha chỉ nằm trong dòng trích dẫn '> ' (không phải lời khai của QA) ⇒ coi như không nêu sha.
run_case "[{\"body\":\"[qa] [report] ✅ pass\\n> earlier round @ ${Q1:0:8}\\n✅ Done: AC1\"}]"; passed "a sha only in a quoted line is ignored"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
