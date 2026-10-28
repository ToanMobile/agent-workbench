#!/usr/bin/env bash
# hooks/block-dangerous-git.sh (#605 Lane H): agent đăng comment GitHub bằng chung tài khoản OWNER, nên một worker có thể tự
# duyệt bằng `approved-head:<sha>` trơn (không kèm `approved-by:`) hoặc một dòng `done`. Hook chặn các comment đó
# (gh pr comment / gh issue comment / gh api …/comments, body qua --body, -b, --body-file, -F/-f body=); chỉ người chủ repo gõ tay.
# `approved-head` + `approved-by:` và `cross-review-approved:` vẫn qua (việc của lane reviewer). Chỉ chạy hook, không chạy lệnh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
P="$TMP/proj"
mkdir -p "$P"
git -C "$P" init -q -b feat .
SHA=0123456789abcdef0123456789abcdef01234567
BY='{"reviewer":"antigravity","builder":"claude-builder","task_id":"T1","gate_receipt":"r1"}'
printf 'approved-head:%s\n' "$SHA" > "$P/bare.md"
printf 'approved-head:%s\napproved-by: %s\n' "$SHA" "$BY" > "$P/ok.md"
printf '[reviewer] [report] ✅ pass\n' > "$P/note.md"
FRAG='chỉ người chủ repo'

# check <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  if [ "$rc" = 2 ] && [ "$want" = 2 ] && ! grep -q -- "$FRAG" "$TMP/err"; then rc="2 (other reason)"; fi
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: ${s:0:110}"
  else echo "✖ rc $rc (want $want): ${s:0:110} — $(head -c 240 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}

echo "A. approved-head trơn / done: chặn"
check 2 "gh pr comment 5 --body \"approved-head:$SHA\""
check 2 "gh pr comment 5 -b 'approved-head:$SHA'"
check 2 "gh pr comment 5 --body=\"approved-head:$SHA\""
check 2 "gh -R o/r pr comment 5 --body \"[reviewer] ok
approved-head:$SHA\""
check 2 "gh pr comment 5 --body-file bare.md"
check 2 "gh pr comment 5 -F bare.md"
check 2 "gh pr comment 5 --body-file - <<'EOF'
approved-head:$SHA
EOF"
check 2 "gh pr comment 5 --body \"\$(cat <<'EOF'
approved-head:$SHA
EOF
)\""
check 2 'gh issue comment 7 --body done'
check 2 'gh issue comment 7 -b "Done!"'
check 2 "gh issue comment 7 --body \"looks good
done\""
check 2 'gh api repos/o/r/issues/7/comments -f body=done'
check 2 "gh api repos/o/r/issues/5/comments -F body=@bare.md"
check 2 "gh api -X POST repos/o/r/issues/5/comments --raw-field body=approved-head:$SHA"
check 2 'gh pr comment 5 --body-file missing.md'
check 2 'gh pr comment 5 --body-file "$F"'
check 2 "bash -c \"gh pr comment 5 --body 'approved-head:$SHA'\""

echo "B. việc của lane reviewer và comment thường: qua"
check 0 "gh pr comment 5 --body \"approved-head:$SHA
approved-by: {\\\"reviewer\\\":\\\"antigravity\\\",\\\"builder\\\":\\\"claude-builder\\\",\\\"task_id\\\":\\\"T1\\\",\\\"gate_receipt\\\":\\\"r1\\\"}\""
check 0 'gh pr comment 5 --body-file ok.md'
check 0 "gh pr comment 5 --body-file - <<'EOF'
approved-head:$SHA
approved-by: $BY
EOF"
check 0 "gh issue comment 7 --body 'cross-review-approved: {\"repo\":\"o/r\",\"pr\":5}'"
check 0 'gh issue comment 7 --body "[reviewer] [report] ✅ merge-ready · queued PR #5"'
check 0 'gh pr comment 5 --body-file note.md'
check 0 'gh issue comment 7 --body "done with the refactor, next: tests"'
check 0 'gh pr view 5 --json comments'
check 0 'gh api repos/o/r/issues/7/comments'
check 0 'gh pr create --title x --body done'
check 0 'for i in 1 2; do
  gh issue comment $i --body "[builder] ok"
done'

echo "C. (#605 audit T0066 vòng 2) các đường lách đã thực nghiệm: chặn"
check 2 'gh issue comment 7 -bdone'
check 2 "gh pr comment 5 -b'approved-head:$SHA'"
check 2 'gh pr comment 5 -Fbare.md'
check 2 'gh pr comment 5 -Fmissing.md'
check 2 'gh pr -R o/r comment 5 --body done'
check 2 'gh pr comment 5 -R o/r --body done'
check 2 'gh pr --repo=o/r comment 5 --body done'
check 2 'gh issue --repo o/r comment 7 -b done'
check 2 'gh --hostname github.com issue comment 7 --body done'
check 2 'gh -H github.com pr comment 5 --body done'
check 2 'gh api --hostname github.com repos/o/r/issues/7/comments -f body=done'
check 2 'gh api repos/o/r/issues/7/comments -Fbody=@bare.md'
check 2 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"done\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"[reviewer] ok\\napproved-head:$SHA\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query='mutation(\$b:String!) { addComment(input:{subjectId:\"I_1\", body:\$b}) { clientMutationId } }' -f b=done"
check 2 "gh api graphql -F query=@missing.graphql"
check 2 "gh api graphql -f query='mutation { addPullRequestReviewComment(input:{pullRequestId:\"P_1\", body:\"done\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query=\"\$Q\""
check 2 "python3 -c \"import subprocess; subprocess.run(['gh','issue','comment','7','--body','done'])\""
check 2 "python3 -c \"import subprocess; subprocess.run('gh pr comment 5 --body approved-head:$SHA', shell=True)\""
check 2 "node -e \"require('child_process').execSync('gh issue comment 7 -b done')\""
check 2 "python3 -c \"import os; os.system('gh pr comment 5 --body-file bare.md')\""

echo "D. lệnh gh / interpreter bình thường: không chặn oan"
check 0 'gh pr -R o/r comment 5 --body "[builder] ok"'
check 0 'gh --hostname github.com pr view 5'
check 0 "gh api graphql -f query='query { viewer { login } }'"
check 0 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"[reviewer] ok\"}) { clientMutationId } }'"
check 0 "python3 -c \"import subprocess; subprocess.run(['gh','pr','view','5'])\""
check 0 "python3 -c \"import subprocess; subprocess.run(['gh','issue','comment','7','--body','[builder] ok'])\""
check 0 "python3 -c \"print('done')\""

echo "E. ANTIGRAVITY_PM_STATE_HOME chỉ dành cho test: agent tự đặt trên dòng lệnh thì chặn"
FRAG='chỉ dành cho test'
check 2 'ANTIGRAVITY_PM_STATE_HOME=/tmp/fake python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief'
check 2 'export ANTIGRAVITY_PM_STATE_HOME=/tmp/fake'
check 2 'ANTIGRAVITY_PM_STATE_HOME=/tmp/fake; export ANTIGRAVITY_PM_STATE_HOME'
check 2 'export ANTIGRAVITY_PM_STATE_HOME'
check 2 'env ANTIGRAVITY_PM_STATE_HOME=/tmp/fake agent-kit integrate'
check 2 'bash -c "ANTIGRAVITY_PM_STATE_HOME=/tmp/fake git push origin feat"'
check 2 'DEVKIT_PM_HOME_TEST=1 python3 .agents/devkit/bin/push_gate.py'
check 2 'export DEVKIT_PM_HOME_TEST=1'
check 2 'export DEVKIT_PM_HOME_TEST'
check 2 'env DEVKIT_PM_HOME_TEST=1 git push origin feat'
check 2 'bash -c "DEVKIT_PM_HOME_TEST=1 agent-kit integrate"'
check 0 'bash universal-agent-devkit/tests/gates/test_push_gate.sh'
check 0 'python3 tests/super-board/test_approval_cross_review.py'

echo "F. (audit T0066 vòng 3) tên biến pm trong mã interpreter, HOME= trên lệnh gate/push: chặn"
check 2 "python3 -c \"import os,subprocess; os.environ['ANTIGRAVITY_PM_STATE_HOME']='/tmp/f'; subprocess.run(['git','push','origin','feat'])\""
check 2 "python3 -c \"import os; os.environ['DEVKIT_PM_HOME_TEST']='1'; import push_gate\""
check 2 "node -e \"process.env.ANTIGRAVITY_PM_STATE_HOME='/tmp/f'; require('child_process').execSync('agent-kit integrate')\""
check 2 "python3 - <<'EOF'
import os
os.environ['ANTIGRAVITY_PM_STATE_HOME'] = '/tmp/f'
os.environ['DEVKIT_PM_HOME_TEST'] = '1'
import push_gate
EOF"
check 2 'HOME=/tmp/fake bash .claude/bin/super-board-merge-gate.sh --config c.json --pr 5'
check 2 'HOME=/tmp/fake .claude/bin/super-board-merge-queue.sh --config c.json'
check 2 "HOME=/tmp/fake python3 .claude/bin/super-board-audit-check.py T0001-x $SHA"
check 2 'env HOME=/tmp/fake python3 .agents/devkit/bin/push_gate.py'
check 2 'HOME=/tmp/fake python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief'
check 2 'HOME=/tmp/fake agent-kit integrate'
check 2 'HOME=/tmp/fake git push origin feat'
check 2 'HOME=/tmp/fake git -C . push origin feat'
check 2 'export HOME=/tmp/fake; git push origin feat'
check 2 'HOME=/tmp/fake bash -c "git push origin feat"'
check 0 'HOME=/tmp/fake ls'
check 0 'HOME=/tmp/fake python3 tests/super-board/test_approval_cross_review.py'
check 0 "python3 -c \"import os; print(os.environ.get('HOME'))\""

echo "G. (audit T0066 vòng 3) gh api graphql: endpoint /graphql, URL đầy đủ, chuỗi khối \"\"\"…\"\"\", body không đọc được: chặn"
FRAG='chỉ người chủ repo'
check 2 "gh api /graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"done\"}) { clientMutationId } }'"
check 2 "gh api graphql/ -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"done\"}) { clientMutationId } }'"
check 2 "gh api https://api.github.com/graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"done\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"\"\"done\"\"\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"\"\"[reviewer] ok
approved-head:$SHA\"\"\"}) { clientMutationId } }'"
check 2 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body: \$b}) { clientMutationId } }'"
check 2 'gh api repos/o/r/issues/7/comments -f body=done -f x=a/graphql'
check 0 "gh api graphql -f query='mutation { addComment(input:{subjectId:\"I_1\", body:\"\"\"[reviewer] ok\"\"\"}) { clientMutationId } }'"
check 0 "gh api /graphql -f query='query { viewer { login } }'"

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $FAILS case(s)"; exit 1; fi
echo "PASS"
