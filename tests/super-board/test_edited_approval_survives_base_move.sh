#!/usr/bin/env bash
# #1200: duyệt test sửa bằng comment approved-head + edited-tests không được mất hiệu lực chỉ vì main tiến ở file KHÁC.
# Lời duyệt còn hiệu lực khi blob mọi file test sửa ở base mới == blob ở merge-base(base, head) (main không đổi file đó); head đã ghim sẵn.
#  H1 gate: main tiến file khác, verify có gate -> không stale, merge.   H2 train: như H1 -> merge.
#  H3 gate: main đổi CHÍNH file test (vùng khác, merge sạch) -> vẫn exit 2 stale (không nới).  H4 train: như H3 -> gate-exit-2.
#  H5 gate: main tiến file khác nhưng verify không chạy gate -> vẫn exit 2.
# Chạy offline với gh giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-edited-move.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
unset DEVKIT_AGENT_ID CLAUDECODE CLAUDE_CODE_SESSION_ID GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
mkdir -p "$R/tests" && { printf '#!/bin/sh\n'; seq 1 20; echo end; } > "$R/tests/t.sh" && printf '/.claude/worktrees/\n' > "$R/.gitignore" && echo a > "$R/a"
git -C "$R" add .gitignore a tests/t.sh && git -C "$R" commit -qm init
git -C "$R" remote add origin "$O" && git -C "$R" push -q origin main
mkdir -p "$W" && git -C "$R" worktree add -q --detach "$W/review" origin/main

card() {   # card <n>: nhánh issue-<n>-x sửa DÒNG ĐẦU tests/t.sh; comment approved-head + edited-tests
  local n="$1" sha
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q -b "issue-$n-x" "$W/issue-$n-build" origin/main
  sed -i.bak "1s/.*/#!\/bin\/sh # card $n/" "$W/issue-$n-build/tests/t.sh" && rm -f "$W/issue-$n-build/tests/t.sh.bak"
  git -C "$W/issue-$n-build" commit -qam "card $n sửa test"
  git -C "$R" push -q origin "issue-$n-x"
  sha=$(git -C "$R" rev-parse "issue-$n-x"); echo "$sha" > "$TMP/pr$n.head"
  git -C "$R" diff origin/main "issue-$n-x" > "$TMP/pr$n.diff"
  python3 -I -c '
import hashlib, json, sys
dest, sha, task, test = sys.argv[1:5]
dig = hashlib.sha256(open(test, "rb").read()).hexdigest()
body = ("approved-head:%s\napproved-by: {\"reviewer\":\"grok\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"grok\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"r\"}]\n" % (sha, task, dig, task))
meta = {"files": [{"path": "tests/t.sh"}], "labels": [], "body": "", "additions": 1, "deletions": 1, "changedFiles": 1,
        "author": {"login": "builder"}, "comments": [{"authorAssociation": "OWNER", "body": body}]}
json.dump(meta, open(dest, "w"))
' "$TMP/pr$n.meta" "$sha" "T300$n-card" "$W/issue-$n-build/tests/t.sh"
}
advance_main() {   # advance_main [t]: main tiến một commit; mặc định chạm file khác (a), "t" chạm dòng cuối tests/t.sh
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q --detach "$W/adv" origin/main
  if [ "${1:-a}" = t ]; then sed -i.bak "\$s/.*/end main $RANDOM$RANDOM/" "$W/adv/tests/t.sh" && rm -f "$W/adv/tests/t.sh.bak"; else echo adv >> "$W/adv/a"; fi
  git -C "$W/adv" commit -qam "main moves" && git -C "$W/adv" push -q origin HEAD:main
  git -C "$R" worktree remove --force "$W/adv"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *"--json labels,files,comments"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr view "*"title"*) printf 'card\n' ;;
  *" pr view "*"body"*) printf '\n' ;;
  *" pr comment "*) exit 0 ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE
export GH_TOKEN=fake-token
mkdir -p "$TMP/kit/bin" && printf '#!/bin/sh\necho x >> "%s/verify.count"\n' "$TMP" > "$TMP/kit/bin/post-fix-gate.py"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/kit/bin/post-fix-gate.py --run-tests --scoped"]}\n' "$TMP" > "$TMP/cfg.json"
printf '#!/bin/sh\necho x >> "%s/verify.count"\n' "$TMP" > "$TMP/verify.sh"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/verify.sh"]}\n' "$TMP" > "$TMP/cfg-nogate.json"
merged() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/halt.json"; }
run_gate() { ( cd "$W/review" && bash "$GATE" --config "$1" --pr "$2" --expect-head "$(cat "$TMP/pr$2.head")" --subject card --lock-timeout 20 ) >"$TMP/g$2.log" 2>&1; }
run_train() { ( cd "$W/review" && bash "$TRAIN" --config "$1" --prs "$2" --lock-timeout 20 ) >"$TMP/g$2.log" 2>&1; }

card 1; advance_main; reset_run; run_gate "$TMP/cfg.json" 1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(merged)" = "1 " ] && ! grep -q "stale before fast-forward" "$TMP/g1.log"; then ok "H1: comment duyệt + main tiến file khác -> không stale, merge"
else fail "H1: exit $rc merged='$(merged)': $(tail -4 "$TMP/g1.log" | tr '\n' ' ')"; fi

card 2; advance_main; reset_run; run_train "$TMP/cfg.json" 2; rc=$?
if [ "$rc" -eq 0 ] && [ "$(merged)" = "2 " ] && ! grep -q "gate-exit-2" "$TMP/g2.log"; then ok "H2: train, comment duyệt + main tiến file khác -> merge"
else fail "H2: exit $rc merged='$(merged)': $(grep -E 'train-|stale' "$TMP/g2.log" | tail -3 | tr '\n' ' ')"; fi

card 3; advance_main t; reset_run; run_gate "$TMP/cfg.json" 3; rc=$?
if [ "$rc" -eq 2 ] && grep -q "edited-test review is stale before fast-forward" "$TMP/g3.log"; then ok "H3: main đổi chính file test -> vẫn exit 2"
else fail "H3: exit $rc: $(tail -4 "$TMP/g3.log" | tr '\n' ' ')"; fi

card 4; advance_main t; reset_run; run_train "$TMP/cfg.json" 4; rc=$?
if [ "$rc" -eq 2 ] && grep -q "^train-result: 4 gate-exit-2$" "$TMP/g4.log"; then ok "H4: train, main đổi chính file test -> gate-exit-2"
else fail "H4: exit $rc: $(grep -E 'train-|stale' "$TMP/g4.log" | tail -3 | tr '\n' ' ')"; fi

card 5; advance_main; reset_run; run_gate "$TMP/cfg-nogate.json" 5; rc=$?
if [ "$rc" -eq 2 ] && grep -q "edited-test review is stale before fast-forward" "$TMP/g5.log"; then ok "H5: verify không chạy gate -> vẫn exit 2"
else fail "H5: exit $rc: $(tail -4 "$TMP/g5.log" | tr '\n' ' ')"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
