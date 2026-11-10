#!/usr/bin/env bash
# #557: QA (and the brief Review already uses) adds a detached worktree at origin/<PR branch>.
# The build worktree keeps the branch, even after a rename (#526) and with uncommitted
# agent-memory (#473). The DevKit hook (push_gate / block-dangerous-git) refuses git push origin HEAD:<PR branch> from a detached
# worktree ("không suy ra được nhánh đích") and a push whose src the local branch does not hold: the evidence commit is fast-forwarded
# into the local PR branch (git -C <build worktree> merge --ff-only <sha>, its own command), then pushed as plain git push origin <PR branch>.
# The trunk-mode guard also refuses a redirect target that holds a variable: QA writes test output to LITERAL paths.
FF='git -C <build worktree> merge --ff-only <sha>'
PUSH='git push origin <PR branch>'
OLD='git push origin HEAD:<PR branch>'
LIT='LITERAL path'
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
WT="$ROOT/universal-agent-devkit/scripts/git/worktree.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e

hint="$(lane_worktree_hint qa 7)"
case "$hint" in
  *"agent-kit worktree add .claude/worktrees/issue-7-qa --lane=qa --base=origin/<PR branch>"*)
    ok "qa hint: detached at origin/<PR branch>, no branch argument" ;;
  *) fail "qa hint is not detached: ${hint:0:280}" ;;
esac
case "$hint" in
  *"issue-7-<slug>"*) fail "qa hint still names a branch to check out" ;;
  *) ok "qa hint does not check out issue-7-<slug>" ;;
esac
case "$hint" in
  *"$FF"*"$PUSH"*) ok "qa hint: evidence commit is fast-forwarded into the PR branch, then plain push" ;;
  *) fail "qa hint does not say how to push a detached evidence commit the hook accepts" ;;
esac
case "$hint" in
  *"$OLD"*) fail "qa hint still tells the worker to push HEAD:<PR branch> (the hook refuses it)" ;;
  *) ok "qa hint does not give the refused HEAD:<PR branch> push" ;;
esac
case "$hint" in
  *"$LIT"*"redirect target"*) ok "qa hint: test output goes to literal paths, no variable in a redirect target" ;;
  *) fail "qa hint does not say to use literal redirect targets" ;;
esac
case "$hint" in
  *"Exit 1 naming a worktree that holds the branch"*) fail "qa hint still says to remove the worktree that holds the branch" ;;
  *) ok "qa hint does not tell the worker to remove the build worktree" ;;
esac

WAVE="$ROOT/.claude/workflows/super-board-wave.js"
grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-qa --lane=qa --base=origin/<PR branch>' "$WAVE" \
  && ok "wave: qa arm is detached" || fail "wave qa arm still checks out the issue branch"
grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-${lane} issue-${n}-<slug> --lane=${lane}' "$WAVE" \
  && ok "wave: build arm still checks out the issue branch" || fail "wave build arm lost its branch checkout"
grep -qF "$FF" "$WAVE" && grep -qF "$PUSH" "$WAVE" && ! grep -qF "$OLD" "$WAVE" \
  && ok "wave: qa evidence push is the hook-accepted form" || fail "wave does not name the hook-accepted evidence push"
grep -qF "$LIT" "$WAVE" && grep -qF 'redirect target' "$WAVE" \
  && ok "wave: qa literal redirect paths" || fail "wave lacks the literal redirect path rule"

RUNMD="$ROOT/.claude/skills/super-board/references/run.md"
QA="$ROOT/.claude/skills/super-qa/SKILL.md"
grep -q 'agent-kit worktree add .claude/worktrees/issue-<N>-qa --lane=qa --base=origin/<PR branch>' "$RUNMD" \
  && grep -qF "$FF" "$RUNMD" && grep -qF "$PUSH" "$RUNMD" && ! grep -qF "$OLD" "$RUNMD" \
  && grep -qF "$LIT" "$RUNMD" && grep -qF 'redirect target' "$RUNMD" \
  && ok "run.md Tester: detached qa worktree, ff + plain push, literal redirects" || fail "run.md Tester is not the detached ff + plain push form"
grep -q -- '--lane=qa' "$QA" && grep -qF "$FF" "$QA" && grep -qF "$PUSH" "$QA" && ! grep -qF "$OLD" "$QA" \
  && grep -qF "$LIT" "$QA" && grep -qF 'redirect target' "$QA" \
  && ! grep -q 'issue-<N>-qa issue-<N>-<slug> --lane=qa' "$QA" \
  && ok "super-qa SKILL: detached, does not check out the branch" || fail "super-qa SKILL still checks out the issue branch"

# #526 + #473: build worktree holds a renamed branch and an uncommitted agent-memory file.
# The command is the one the qa hint actually gives, so this is red while that hint checks out a branch.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO" && G "$REPO" init -q -b main . && G "$REPO" config user.email t@t && G "$REPO" config user.name t
echo base > "$REPO/a.txt" && G "$REPO" add a.txt && G "$REPO" commit -qm base
git init -q --bare "$TMP/origin.git"
G "$REPO" remote add origin "$TMP/origin.git"
G "$REPO" push -q origin main
G "$REPO" checkout -q -b issue-7-slug
echo pr > "$REPO/pr.txt" && G "$REPO" add pr.txt && G "$REPO" commit -qm pr
G "$REPO" push -q origin issue-7-slug
G "$REPO" checkout -q main
(cd "$REPO" && python3 "$WT" add "$REPO/.claude/worktrees/issue-7-build" issue-7-slug --lane=build --base=origin/main --no-init >/dev/null 2>&1) \
  || fail "setup: build worktree"
G "$REPO/.claude/worktrees/issue-7-build" branch -m issue-7-slug-renamed
mkdir -p "$REPO/.claude/worktrees/issue-7-build/.claude/agent-memory"
echo 'keep-me' > "$REPO/.claude/worktrees/issue-7-build/.claude/agent-memory/note.txt"
origin_sha="$(G "$REPO" rev-parse origin/issue-7-slug)"

args="${hint#*agent-kit worktree add }"
args="${args%% (*}"
args="${args//.claude\/worktrees\/issue-7-qa/$REPO/.claude/worktrees/issue-7-qa}"
args="${args//issue-7-<slug>/issue-7-slug-renamed}"
args="${args//origin\/<config.base_branch>/origin/issue-7-slug}"
args="${args//origin\/<PR branch>/origin/issue-7-slug}"
(cd "$REPO" && python3 "$WT" add $args --no-init > "$TMP/add.out" 2>&1); rc=$?
QAWT="$REPO/.claude/worktrees/issue-7-qa"
if [ "$rc" = 0 ] && [ -d "$QAWT" ] && [ "$(G "$QAWT" rev-parse HEAD)" = "$origin_sha" ] \
    && ! G "$QAWT" symbolic-ref -q HEAD >/dev/null \
    && [ -f "$REPO/.claude/worktrees/issue-7-build/.claude/agent-memory/note.txt" ] \
    && [ "$(G "$REPO/.claude/worktrees/issue-7-build" branch --show-current)" = "issue-7-slug-renamed" ]; then
  ok "#526/#473: qa worktree detached at origin/issue-7-slug; build worktree and its memory file stay"
else
  fail "#526/#473: rc=$rc head=$(G "$QAWT" rev-parse HEAD 2>/dev/null) $(tail -3 "$TMP/add.out")"
fi
if [ "$rc" = 0 ]; then
  echo evidence > "$QAWT/evidence.txt" && G "$QAWT" add evidence.txt && G "$QAWT" commit -qm evidence
  # the exact two commands the hint gives: ff the local PR branch to the evidence sha, then a plain push of the branch
  G "$REPO/.claude/worktrees/issue-7-build" merge -q --ff-only "$(G "$QAWT" rev-parse HEAD)" \
    && G "$QAWT" push -q origin issue-7-slug-renamed:issue-7-slug && [ "$(G "$REPO" rev-parse origin/issue-7-slug)" = "$(G "$QAWT" rev-parse HEAD)" ] \
    && [ -f "$REPO/.claude/worktrees/issue-7-build/.claude/agent-memory/note.txt" ] \
    && ok "qa evidence commit pushed to the PR branch; build memory file still there" \
    || fail "qa evidence push did not land on origin/issue-7-slug"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_qa_detached_worktree: PASS"; exit 0; }
echo "test_qa_detached_worktree: FAIL ($FAILS)"; exit 1
