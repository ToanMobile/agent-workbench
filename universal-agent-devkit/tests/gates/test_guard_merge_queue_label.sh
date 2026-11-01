#!/usr/bin/env bash
# hooks/block-dangerous-git.sh (#536): 28/10 một phiên agent tự gắn nhãn `merge-queue` (gh pr edit --add-label / gh pr create
# --label) cho PR chưa có `approved-head:<sha40>`; hàng đợi chỉ phát hiện lúc chạy, PR nằm im ~3 giờ. Guard nay hỏi helper của
# project (`$CLAUDE_PROJECT_DIR/.claude/bin/super-board-queue-label.sh --check <pr>`) trước khi cho gắn nhãn đó.
# Hành vi mà test này đòi (mục A-H bên dưới): helper exit 0 → cho qua; khác 0 / treo → chặn kèm lý do helper in ra;
# `gh pr create … --label merge-queue` → chặn (ca B); thêm nhãn khác / gỡ nhãn → cho qua và file calls của helper rỗng (ca C);
# project không có file helper (ca H: repo tạm chưa cài) → cho qua.
# Helper ở đây là stub (ghi argv, exit theo file rc). Chỉ chạy hook, không chạy lệnh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
P="$TMP/proj"; FAKE="$TMP/fake"; BARE="$TMP/bare"
mkdir -p "$P/.claude/bin" "$FAKE/.claude/bin" "$BARE"
git -C "$P" init -q -b feat .; git -C "$FAKE" init -q -b feat .; git -C "$BARE" init -q -b feat .
# stub helper: argv → <dir>/calls, exit = nội dung <dir>/rc (mặc định 3), lý do ra stderr; <dir>/sleep > 0 thì ngủ trước
stub() {
  cat > "$1/.claude/bin/super-board-queue-label.sh" <<'SH'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/../.." && pwd)"
printf '%s\n' "$*" >> "$d/calls"
s=$(cat "$d/sleep" 2>/dev/null || echo 0); [ "$s" = 0 ] || sleep "$s"
sel=""; [ "$1" = --check ] && [ $# -ge 2 ] && sel="$2"
rc=$(cat "$d/rc-$sel" 2>/dev/null || cat "$d/rc" 2>/dev/null || echo 3)
[ "$rc" = 0 ] || echo "PR #5 head 1111111; approved-head: không có — bước đúng: qua lane Review" >&2
exit "$rc"
SH
  chmod +x "$1/.claude/bin/super-board-queue-label.sh"
}
stub "$P"; stub "$FAKE"; echo 0 > "$FAKE/rc"
printf '{"labels":["merge-queue"]}' > "$P/labels.json"
printf '{"labels":["bug"]}' > "$P/other.json"
printf '[{"name":"merge-queue"}]' > "$P/named.json"
printf '{"labels":"merge-queue"}' > "$P/str.json"
printf '{"title":"fix, merge-queue, cleanup"}' > "$P/patch_title.json"
printf 'mutation($in: UpdatePullRequestInput!) { updatePullRequest(input: $in) { clientMutationId } }' > "$P/q.graphql"

# check <want rc> <command> [project dir]
check() {
  local want="$1" c="$2" proj="${3:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$proj" > "$TMP/in.json"
  ( cd "$proj" && CLAUDE_PROJECT_DIR="$proj" DEVKIT_QUEUE_LABEL_TIMEOUT=2 bash "$GG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: ${s:0:110}"
  else echo "✖ rc $rc (want $want): ${s:0:110} — $(head -c 240 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}
calls() { cat "$P/calls" 2>/dev/null; }
reset() { rm -f "$P/calls" "$FAKE/calls" "$P"/rc-*; echo "${1:-3}" > "$P/rc"; echo 0 > "$P/sleep"; }
expect_call() {   # expect_call <regex trên dòng argv của helper> | none
  if [ "$1" = none ]; then
    [ ! -s "$P/calls" ] && echo "  ✔ helper not called" || { echo "  ✖ helper called: $(calls)"; FAILS=$((FAILS + 1)); }
  else
    calls | grep -qE -- "$1" && echo "  ✔ helper called: $(calls | head -1)" || { echo "  ✖ helper call '$1' missing: $(calls)"; FAILS=$((FAILS + 1)); }
  fi
}
no_bang() { ! grep -q 'prefix "!"' "$TMP/err" && echo "  ✔ no '!' prefix hint" || { echo "  ✖ message hands the user a ! command"; FAILS=$((FAILS + 1)); }; }
grep_err() { grep -q -- "$1" "$TMP/err" && echo "  ✔ reason shown" || { echo "  ✖ reason '$1' missing: $(head -c 200 "$TMP/err")"; FAILS=$((FAILS + 1)); }; }

echo "A. gh pr edit --add-label merge-queue: hỏi helper"
reset 3; check 2 "gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'; grep_err 'approved-head: không có'; no_bang
reset 0; check 0 "gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "gh pr edit 5 --add-label=bug,Merge-Queue"; expect_call '^--check 5$'
reset 3; check 2 "gh pr edit 5 --add-label bug --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "gh -R acme/widgets pr edit 5 --add-label merge-queue"; expect_call '^--check 5 --repo acme/widgets$'
reset 3; check 2 "gh pr edit https://github.com/acme/widgets/pull/5 --repo acme/widgets --add-label merge-queue"; expect_call '^--check https://github.com/acme/widgets/pull/5 --repo acme/widgets$'
reset 3; check 2 "gh issue edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "gh pr edit \$PR --add-label merge-queue"; expect_call none

reset 3; check 2 "gh pr edit --add-label merge-queue 42"; expect_call '^--check 42$'
reset 3; check 2 "gh pr edit -t foo 42 --add-label merge-queue"; expect_call '^--check 42$'
reset 0; check 2 "gh pr edit --add-label merge-queue"; expect_call none
reset 0; check 0 "gh pr edit --remove-milestone 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 0; check 0 "gh pr edit 5 --attach shot.png --add-label merge-queue"; expect_call '^--check 5$'
reset 0; check 2 "echo 5 | xargs gh pr edit --add-label merge-queue"; expect_call none
reset 0; check 2 "python3 -c \"import subprocess; n = 5; subprocess.run(['gh', 'pr', 'edit', str(n), '--add-label', 'merge-queue'])\""; expect_call none
reset 0; check 2 "export GH_REPO=acme/w; gh pr edit 5 --add-label merge-queue"; expect_call none
reset 0; check 2 "GH_REPO=acme/w; export GH_REPO; gh pr edit 5 --add-label merge-queue"; expect_call none
reset 0; check 2 "( export GH_REPO=acme/w ); gh pr edit 5 --add-label merge-queue"; expect_call none
reset 0; check 2 "GH_REPO=acme/w; gh pr edit 5 --add-label merge-queue"; expect_call none
reset 0; check 2 "echo 6 | xargs gh issue edit 5 --add-label merge-queue"; expect_call none
reset 0; check 0 "gh pr comment 5 --body \"note about xargs\" && gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 0; check 0 "printf a | xargs echo && gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 0; check 0 "gh pr edit 5 -t -R --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "gh pr edit 5 -R other/repo -R acme/widgets --add-label merge-queue"; expect_call '^--check 5 --repo acme/widgets$'
reset 0; check 2 "cd \$OTHER && gh pr edit 5 --add-label merge-queue"; expect_call none
reset 0; check 0 "cd \$OTHER && gh pr edit 5 --repo acme/widgets --add-label merge-queue"; expect_call '^--check 5 --repo acme/widgets$'
reset 3; check 2 "GH_REPO=acme/widgets gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5 --repo acme/widgets$'
reset 0; echo 3 > "$P/rc-11"; check 2 "gh issue edit 10 11 --add-label merge-queue"; expect_call '^--check 11$'
reset 3; check 2 "cd \$X && gh pr edit --add-label merge-queue"; expect_call none

echo "B. gh pr create --label merge-queue: chặn luôn"
reset 0; check 2 "gh pr create --title t --body b --label merge-queue"; expect_call none
reset 0; check 2 "gh pr create -t t -b b -l bug,merge-queue"; expect_call none
reset 0; check 0 "gh pr create --title t --body b --label bug"; expect_call none
reset 0; check 2 "gh pr new -l merge-queue"; expect_call none
reset 0; check 2 "gh pr create -t t -b b -lmerge-queue"; expect_call none
reset 0; check 2 "gh pr create -dl merge-queue -t t -b b"; expect_call none
reset 0; check 2 "gh pr create -t -H --label merge-queue -b body"; expect_call none
reset 0; check 0 "gh pr create -dfl bug"; expect_call none

echo "C. nhãn khác / gỡ nhãn: không gọi helper"
reset 3; check 0 "gh pr edit 5 --add-label bug"; expect_call none
reset 3; check 0 "gh pr edit 5 --remove-label merge-queue"; expect_call none
reset 3; check 0 "gh pr list --label merge-queue"; expect_call none
reset 3; check 0 "gh issue edit 5 --add-label merge-queue-later"; expect_call none

echo "D. gh api"
reset 3; check 2 "gh api repos/acme/widgets/issues/5/labels -f 'labels[]=merge-queue'"; expect_call '^--check 5 --repo acme/widgets$'
reset 0; check 0 "gh api -X POST repos/acme/widgets/issues/5/labels -f 'labels[]=merge-queue'"; expect_call '^--check 5'
reset 3; check 2 "gh api -X POST repos/acme/widgets/issues/5/labels --input labels.json"; expect_call '^--check 5'
reset 3; check 0 "gh api -X POST repos/acme/widgets/issues/5/labels --input other.json"; expect_call none
reset 3; check 2 "gh api -X POST repos/acme/widgets/issues/5/labels --input missing.json"; expect_call none
reset 3; check 0 "gh api repos/acme/widgets/issues/5/labels"; expect_call none
reset 3; check 0 "gh api -X DELETE repos/acme/widgets/issues/5/labels/merge-queue"; expect_call none
reset 3; check 2 "gh api repos/{owner}/{repo}/issues/5/labels -f 'labels[][name]=merge-queue'"; expect_call '^--check 5$'
reset 3; check 2 "gh api repos/acme/widgets/issues/5/labels --input - <<'EOF'
[\"merge-queue\"]
EOF"; expect_call '^--check 5 --repo acme/widgets$'
reset 3; check 2 "gh api repos/acme/widgets/issues/5/labels --input named.json"; expect_call '^--check 5'
reset 0; check 2 "gh api graphql -F query=@q.graphql -f 'in[labelIds][]=LA_y'"; expect_call none
reset 0; check 2 "gh api graphql -f query='mutation(\$id:ID!,\$l:[ID!]!){ addLabelsToLabelable(input:{labelableId:\$id,labelIds:\$l}){clientMutationId} }' -f id=PR_x -f 'l[]=LA_y'"; expect_call none
reset 0; check 0 "gh api graphql -f query='mutation(\$t:ID!){resolveReviewThread(input:{threadId:\$t}){thread{isResolved}}}' -f t=\"\$T\""; expect_call none
reset 0; check 2 "gh api graphql -f query='mutation(\$in:UpdatePullRequestInput!){updatePullRequest(input:\$in){clientMutationId}}' -F in=\"\$IN\""; expect_call none
reset 0; check 2 "gh api graphql -f query=\"\$Q\""; expect_call none
reset 0; check 0 "gh api graphql -f query='mutation { createIssue(input: {repositoryId: \"R\", title: \"t\", labelIds: [\"LA_y\"]}) { issue { number } } }'"; expect_call none
reset 3; check 2 "gh api repos/acme/widgets/issues/\$PR/labels -f 'labels[]=merge-queue'"; expect_call none
reset 3; check 2 "gh api -X GET -X POST repos/acme/widgets/issues/5/labels -f 'labels[]=merge-queue'"; expect_call '^--check 5 --repo acme/widgets$'
reset 3; check 2 "gh api repos/acme/widgets/issues/5/labels --input other.json --input labels.json"; expect_call '^--check 5 --repo acme/widgets$'
reset 0; check 2 "L=merge-queue; gh api repos/acme/widgets/issues/5/labels --input - <<EOF
[\"\$L\"]
EOF"; expect_call none
reset 0; check 0 "gh api -X PATCH repos/acme/widgets/issues/5 --input patch_title.json"; expect_call none
reset 0; check 2 "M=addLabelsToLabelable; gh api graphql -f \"query=mutation { \${M}(input:{labelableId:\\\"PR_x\\\",labelIds:[\\\"LA_y\\\"]}){clientMutationId} }\""; expect_call none
reset 3; check 2 "gh api repos/acme/widgets/issues/5/labels -if 'labels[]=merge-queue'"; expect_call '^--check 5 --repo acme/widgets$'
reset 3; check 2 "gh api -f note=x/issues/1 repos/acme/widgets/issues/5/labels -f 'labels[]=merge-queue'"; expect_call '^--check 5 --repo acme/widgets$'
reset 0; check 2 "gh api repositories/123/issues/5/labels -f 'labels[]=merge-queue'"; expect_call none
reset 3; check 2 "gh api -X POST repos/acme/widgets/issues/5/labels --input str.json"; expect_call '^--check 5'
reset 3; check 2 "python3 -c \"import subprocess; n = 5; subprocess.run(['gh', 'api', f'repos/acme/widgets/issues/{n}/labels', '-f', 'labels[]=merge-queue'])\""; expect_call none
reset 0; check 0 "gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { labels(first: 5) { nodes { name } } } }'"; expect_call none
reset 0; check 2 "gh api graphql -f query='mutation { addLabelsToLabelable(input: {labelableId: \"PR_x\", labelIds: [\"LA_y\"]}) { clientMutationId } }'"; expect_call none

echo "E. interpreter gọi gh"
reset 3; check 2 "python3 -c \"import subprocess; subprocess.run(['gh', 'pr', 'edit', '5', '--add-label', 'merge-queue'])\""; expect_call '^--check 5$'
reset 3; check 2 "bash -c 'gh pr edit 5 --add-label merge-queue'"; expect_call '^--check 5$'

echo "F. helper của project, không theo cwd của lệnh"
reset 3; check 2 "cd $FAKE && gh pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
[ ! -s "$FAKE/calls" ] && echo "  ✔ fake helper in the cd target not used" || { echo "  ✖ fake helper used"; FAILS=$((FAILS + 1)); }

echo "G. helper treo → chặn trong thời hạn"
reset 0; echo 30 > "$P/sleep"; t0=$(date +%s)
check 2 "gh pr edit 5 --add-label merge-queue"; t1=$(date +%s); grep_err 'trong 2 s'
[ $((t1 - t0)) -lt 5 ] && echo "  ✔ blocked after $((t1 - t0)) s (timeout 2 s)" || { echo "  ✖ took $((t1 - t0)) s"; FAILS=$((FAILS + 1)); }
echo 0 > "$P/sleep"

echo "I. project là linked worktree: dùng helper của checkout chính; helper là file bảo vệ"
M="$TMP/main"; W="$TMP/wt"
git -C "$TMP" init -q -b main main && git -C "$M" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
git -C "$M" worktree add -q --detach "$W" 2>/dev/null
mkdir -p "$M/.claude/bin" "$W/.claude/bin"; stub "$M"; stub "$W"; echo 3 > "$M/rc"; echo 0 > "$W/rc"
check 2 "gh pr edit 5 --add-label merge-queue" "$W"
[ -s "$M/calls" ] && [ ! -s "$W/calls" ] && echo "  ✔ main checkout's helper used" || { echo "  ✖ wrong helper (main=$(cat "$M/calls" 2>/dev/null) wt=$(cat "$W/calls" 2>/dev/null))"; FAILS=$((FAILS + 1)); }
check 2 "rm .claude/bin/super-board-queue-label.sh" "$W"

echo "H. project chưa có helper (super-board cũ): luật không chạy"
check 0 "gh pr edit 5 --add-label merge-queue" "$BARE"

echo "J. helper git đã theo dõi mà bị mv / ghi đè (chỉ rm là file bảo vệ): chặn, không mở cửa (OCR #826)"
T="$TMP/tracked"; TW="$TMP/tracked-wt"; H=.claude/bin/super-board-queue-label.sh
git -C "$TMP" init -q -b main tracked; mkdir -p "$T/.claude/bin"; stub "$T"; echo 0 > "$T/rc"
printf '"luat duyet"\n' > "$T/.claude/bin/super-board-approved-head.jq"; printf 'import sys\n' > "$T/.claude/bin/super-board-audit-check.py"
git -C "$T" add "$H" .claude/bin/super-board-approved-head.jq .claude/bin/super-board-audit-check.py \
  && git -C "$T" -c user.email=t@example.invalid -c user.name=t commit -q -m helper
check 0 "gh pr edit 5 --add-label merge-queue" "$T"
[ -s "$T/calls" ] && echo "  ✔ tracked helper matching HEAD is used" || { echo "  ✖ tracked helper not called"; FAILS=$((FAILS + 1)); }
mv "$T/$H" "$TMP/moved-helper"
check 2 "gh pr edit 5 --add-label merge-queue" "$T"; grep_err 'checkout --'
mv "$TMP/moved-helper" "$T/$H"; echo 3 > "$T/rc"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/$H"
check 2 "gh pr edit 5 --add-label merge-queue" "$T"; grep_err 'khác bản HEAD'
check 2 "gh api repos/acme/widgets/issues/5/labels -f 'labels[]=merge-queue'" "$T"; grep_err 'khác bản HEAD'
# helper khớp HEAD nhưng luật duyệt nó dùng (jq / audit-check) bị sửa trong cây → cũng chặn (OCR final)
git -C "$T" checkout -q -- "$H"; printf '"ok\\t\\(.headRefOid)\\towner"\n' > "$T/.claude/bin/super-board-approved-head.jq"
check 2 "gh pr edit 5 --add-label merge-queue" "$T"; grep_err 'khác bản HEAD'
git -C "$T" checkout -q -- .claude/bin/super-board-approved-head.jq; printf 'import sys; sys.exit(0)\n' > "$T/.claude/bin/super-board-audit-check.py"
check 2 "gh pr edit 5 --add-label merge-queue" "$T"; grep_err 'khác bản HEAD'
git -C "$T" checkout -q -- .claude/bin/super-board-audit-check.py
git -C "$T" checkout -q -- "$H"; git -C "$T" worktree add -q --detach "$TW" 2>/dev/null; echo 0 > "$TW/rc"
mv "$T/$H" "$TMP/moved-helper"
check 2 "gh pr edit 5 --add-label merge-queue" "$TW"; grep_err 'checkout --'
[ ! -s "$TW/calls" ] && echo "  ✔ worktree's own helper not used while main's tracked helper is gone" || { echo "  ✖ worktree helper used"; FAILS=$((FAILS + 1)); }

echo "K. tên chương trình khác hoa/thường / glob (APFS mặc định chạy GH = gh, như GIT = git) — review #826 P1"
reset 3; check 2 "GH pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "Gh issue edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "g[h] pr edit 5 --add-label merge-queue"; expect_call '^--check 5$'
reset 3; check 2 "python3 -c \"import subprocess; subprocess.run(['GH', 'pr', 'edit', '5', '--add-label', 'merge-queue'])\""; expect_call '^--check 5$'
reset 3; check 2 "python3 -c \"import os; os.system('GH pr edit 5 --add-label merge-queue')\""; expect_call '^--check 5$'
reset 0; check 2 "gh api repos/acme/widgets/issues/5/labels -f \"labels[]=\$L\""; expect_call none

[ "$FAILS" -eq 0 ] && echo "PASS test_guard_merge_queue_label" || { echo "FAIL test_guard_merge_queue_label ($FAILS)"; exit 1; }
