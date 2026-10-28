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

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $FAILS case(s)"; exit 1; fi
echo "PASS"
