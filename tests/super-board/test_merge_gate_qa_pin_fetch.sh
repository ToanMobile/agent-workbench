#!/usr/bin/env bash
# #1000 mục 2: merge gate bỏ ghim sha QA (T0255) khi `git fetch origin <head-ref> <base>` lỗi = fail-open (report QA cũ qua cổng).
#  F1 fetch lỗi MỘT lần: gate thử lại, ghim sha QA vẫn áp dụng -> report QA cũ bị từ chối (exit 11, dòng qa-report:, verify không chạy)
#     (code cũ: "QA head pin skipped", tới verify).
#  F2 fetch luôn lỗi: gate dừng exit 1 TRƯỚC verify, log nêu fetch (code cũ: bỏ ghim rồi chết ở fetch sau với mã của git).
# Harness như test_merge_gate_qa_head_pin.sh (gate thật, gh giả, git thật) + shim git chỉ làm hỏng đúng lệnh fetch đó. Offline.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REAL_GIT="$(command -v git)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qapin-fetch.XXXXXX")"
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
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm "card: first build"
Q1=$(git -C "$WT" rev-parse HEAD)
echo b2 > "$WT/b"; git -C "$WT" commit -qam "fix: code after QA"
git -C "$WT" push -q -f origin issue-5-x
H=$(git -C "$WT" rev-parse HEAD); echo "$H" > "$TMP/pr5.head"
git -C "$R" diff main "$H" > "$TMP/pr5.diff"
python3 -c 'import json,sys
print(json.dumps({"files":[{"path":"b"}],"labels":[],"author":{"login":"owner"},"additions":1,"deletions":0,"changedFiles":1,
  "body":"## Acceptance criteria\n- [x] size message\n  ↳ `e2e/a.spec.ts:14`\n",
  "comments":[{"authorAssociation":"OWNER","author":{"login":"owner"},
    "body":"[qa] [report] ✅ pass · PR #5 @ %s\nDid: ran tests\n✅ Done: AC1\nNext: reviewer" % sys.argv[1][:8]}]}))' "$Q1" > "$TMP/pr5.meta"

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
# shim git: hỏng `fetch origin issue-5-x main` (lần đầu, hoặc mọi lần khi SHIM_MODE=always); mọi lệnh khác tới git thật
cat > "$TMP/bin/git" <<SH
#!/usr/bin/env bash
case " \$* " in
  *" fetch origin issue-5-x main "*)
    n=\$(cat "$TMP/fetch.n" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$TMP/fetch.n"
    if [ "\${SHIM_MODE:-once}" = always ] || [ "\$n" -eq 1 ]; then echo "fatal: shim: fetch failed" >&2; exit 128; fi ;;
esac
exec "$REAL_GIT" "\$@"
SH
chmod +x "$TMP/bin/gh" "$TMP/bin/git"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
python3 -c 'import json; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo VERIFY-RAN; exit 1"]}))' > "$TMP/cfg.json"

# F1
rm -f "$TMP/fetch.n" "$TMP/halt.json"
( cd "$WT" && SHIM_MODE=once bash "$GATE" --config "$TMP/cfg.json" --pr 5 --expect-head "$H" ) >"$TMP/f1.log" 2>&1; rc=$?
if [ "$rc" -eq 11 ] && grep -q '^qa-report: .*QA phải chạy lại trên head' "$TMP/f1.log" && ! grep -q VERIFY-RAN "$TMP/f1.log" \
    && ! grep -q 'QA head pin skipped' "$TMP/f1.log"; then
  ok "F1: fetch lỗi một lần -> thử lại, ghim sha QA vẫn áp dụng, report cũ bị từ chối"
else fail "F1: exit $rc: $(grep -a -m4 -E 'qa-report|VERIFY|fetch|merge-gate' "$TMP/f1.log" | tr '\n' '|')"; fi

# F2
rm -f "$TMP/fetch.n" "$TMP/halt.json"
( cd "$WT" && SHIM_MODE=always bash "$GATE" --config "$TMP/cfg.json" --pr 5 --expect-head "$H" ) >"$TMP/f2.log" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'fetch origin issue-5-x main failed' "$TMP/f2.log" && ! grep -q VERIFY-RAN "$TMP/f2.log" \
    && ! grep -q 'QA head pin skipped' "$TMP/f2.log"; then
  ok "F2: fetch luôn lỗi -> exit 1 trước verify, không bỏ ghim lặng lẽ"
else fail "F2: exit $rc: $(grep -a -m4 -E 'qa-report|VERIFY|fetch|merge-gate' "$TMP/f2.log" | tr '\n' '|')"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
