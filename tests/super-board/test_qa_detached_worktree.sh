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
SW='git switch <PR branch>'
MG='git merge --ff-only <sha>'
BLOCK='Block the card'
WTL='git worktree list'
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
HOOK="$ROOT/universal-agent-devkit/hooks/block-dangerous-git.sh"
hk() { # cwd command -> exit code of the real block-dangerous-git hook (0 = allowed, 2 = refused)
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}\n' "$1" "$2" | bash "$HOOK" >/dev/null 2>&1; echo $?
}

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
RUNMD="$ROOT/.claude/skills/super-board/references/run.md"
QA="$ROOT/.claude/skills/super-qa/SKILL.md"

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
  *"$FF"*"$WTL"*) ok "qa hint: says how to find the build worktree" ;;
  *"$WTL"*"$FF"*) ok "qa hint: says how to find the build worktree" ;;
  *) fail "qa hint does not say how to find <build worktree> (git worktree list)" ;;
esac
case "$hint" in
  *"git rev-parse HEAD"*"before any git switch"*"$SW"*) ok "qa hint: <sha> is recorded with git rev-parse HEAD before the switch" ;;
  *) fail "qa hint does not say to record <sha> before git switch moves HEAD" ;;
esac
case "$hint" in
  *"checks out the local branch, or creates it from origin"*) ok "qa hint: git switch wording covers an existing local branch" ;;
  *) fail "qa hint says git switch only creates the branch" ;;
esac
case "$hint" in
  *"None holds it"*"$SW"*"$MG"*"$PUSH"*) ok "qa hint: no worktree holds the branch (removed or renamed) -> switch in the QA worktree, ff, plain push" ;;
  *) fail "qa hint lacks the git switch route for a branch no worktree holds" ;;
esac
case "$hint" in
  *"$LIT"*"redirect target"*) ok "qa hint: test output goes to literal paths, no variable in a redirect target" ;;
  *) fail "qa hint does not say to use literal redirect targets" ;;
esac
case "$hint" in
  *'>/tmp/qa-<repo>-7-<file>.log'*) ok "qa hint: the example log path carries the issue number (parallel QA lanes do not share it)" ;;
  *) fail "qa hint example log path has no issue number" ;;
esac
case "$hint" in
  *'/tmp/q-a.log'*) fail "qa hint still gives the shared fixed path /tmp/q-a.log" ;;
  *) ok "qa hint has no shared fixed log path" ;;
esac
for pair in "$WAVE|>/tmp/qa-<repo>-\${n}-<file>.log" "$RUNMD|>/tmp/qa-<repo>-<N>-<file>.log" "$QA|>/tmp/qa-<repo>-<N>-<file>.log"; do
  f="${pair%%|*}"; want="${pair#*|}"
  grep -qF -- "$want" "$f" && ! grep -qF '/tmp/q-a.log' "$f" \
    && ok "$(basename "$f"): per-issue example log path" || fail "$(basename "$f") example log path is shared or missing ($want)"
done
case "$hint" in
  *"Exit 1 naming a worktree that holds the branch"*) fail "qa hint still says to remove the worktree that holds the branch" ;;
  *) ok "qa hint does not tell the worker to remove the build worktree" ;;
esac

grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-qa --lane=qa --base=origin/<PR branch>' "$WAVE" \
  && ok "wave: qa arm is detached" || fail "wave qa arm still checks out the issue branch"
grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-${lane} issue-${n}-<slug> --lane=${lane}' "$WAVE" \
  && ok "wave: build arm still checks out the issue branch" || fail "wave build arm lost its branch checkout"
grep -qF "$FF" "$WAVE" && grep -qF "$PUSH" "$WAVE" && ! grep -qF "$OLD" "$WAVE" \
  && ok "wave: qa evidence push is the hook-accepted form" || fail "wave does not name the hook-accepted evidence push"
grep -qF "$WTL" "$WAVE" && grep -qF "$WTL" "$RUNMD" && grep -qF "$WTL" "$QA" \
  && ok "wave/run.md/super-qa: say how to find the build worktree" || fail "a copy lacks the git worktree list pointer"
grep -qF "$LIT" "$WAVE" && grep -qF 'redirect target' "$WAVE" \
  && ok "wave: qa literal redirect paths" || fail "wave lacks the literal redirect path rule"

grep -q 'agent-kit worktree add .claude/worktrees/issue-<N>-qa --lane=qa --base=origin/<PR branch>' "$RUNMD" \
  && grep -qF "$FF" "$RUNMD" && grep -qF "$PUSH" "$RUNMD" && ! grep -qF "$OLD" "$RUNMD" \
  && grep -qF "$LIT" "$RUNMD" && grep -qF 'redirect target' "$RUNMD" \
  && ok "run.md Tester: detached qa worktree, ff + plain push, literal redirects" || fail "run.md Tester is not the detached ff + plain push form"
grep -q -- '--lane=qa' "$QA" && grep -qF "$FF" "$QA" && grep -qF "$PUSH" "$QA" && ! grep -qF "$OLD" "$QA" \
  && grep -qF "$LIT" "$QA" && grep -qF 'redirect target' "$QA" \
  && ! grep -q 'issue-<N>-qa issue-<N>-<slug> --lane=qa' "$QA" \
  && ok "super-qa SKILL: detached, does not check out the branch" || fail "super-qa SKILL still checks out the issue branch"

# Round 3 of the review of #1105: every QA step that pushes must use the hook-accepted form, not a bare "Commit + push".
EVID="$ROOT/.claude/skills/super-qa/references/tester-verifiers-evidence.md"
LSR='git ls-remote origin <PR branch>'
case "$hint" in
  *"$LSR"*"do not retry or force"*) ok "qa hint: push must be verified with ls-remote; non-zero or mismatch means Block, no retry or force" ;;
  *) fail "qa hint lacks the push-verification rule" ;;
esac
for pair in "$WAVE|1" "$RUNMD|3" "$QA|3" "$EVID|1"; do
  f="${pair%%|*}"; need="${pair#*|}"
  [ "$(grep -oF "$LSR" "$f" | wc -l | tr -d ' ')" -ge "$need" ] && grep -qF 'do not retry or force' "$f" \
    && ok "$(basename "$f"): push verification stated at each push step" || fail "$(basename "$f") lacks the ls-remote push verification (need $need)"
done
for f in "$WAVE" "$RUNMD" "$QA"; do
  grep -qF 'before any git switch' "$f" && grep -qF 'checks out the local branch, or creates it from origin' "$f" \
    && grep -qF 'None holds it' "$f" && grep -qF "$SW" "$f" && ok "$(basename "$f"): git switch route for a branch no worktree holds" \
    || fail "$(basename "$f") lacks the git switch route"
done
! grep -qF 'as in step 2' "$QA" && grep -qF 'push it as in step 1' "$QA" \
  && ok "super-qa SKILL: evidence push points at step 1" || fail "super-qa SKILL step 5 does not point at the step that holds the push rule"
for f in "$RUNMD" "$QA"; do
  ! grep -E 'Commit \+ push\.? Verify ALL `\[qa\]`' "$f" >/dev/null \
    && ok "$(basename "$f"): rebuild Tester step has no bare Commit + push" || fail "$(basename "$f") rebuild Tester step still says bare Commit + push"
done
! grep -qF 'screenshots to the issue branch' "$RUNMD" && grep -qF 'Commit the screenshots in the QA worktree' "$RUNMD" \
  && ok "run.md Tester step 5: screenshots are committed in the QA worktree" || fail "run.md Tester step 5 still commits screenshots to the issue branch"
! grep -qF 'screenshots to the issue branch' "$EVID" && grep -qF 'Commit the screenshots in the QA worktree' "$EVID" \
  && ok "tester-verifiers-evidence: screenshots committed in the QA worktree" || fail "tester-verifiers-evidence still commits screenshots to the issue branch"

# #526 + #473: build worktree holds a renamed branch and an uncommitted agent-memory file.
# The command is the one the qa hint actually gives, so this is red while that hint checks out a branch.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO" && G "$REPO" init -q -b main . && G "$REPO" config user.email t@t && G "$REPO" config user.name t
mkdir -p "$REPO/.agents" && echo '{"project":"t","rules":[]}' > "$REPO/.agents/regression_matrix.active.json"
echo base > "$REPO/a.txt" && G "$REPO" add a.txt .agents && G "$REPO" commit -qm base
git init -q --bare "$TMP/origin.git"
G "$REPO" remote add origin "$TMP/origin.git"
G "$REPO" push -q origin main
G "$REPO" remote set-head origin main >/dev/null 2>&1
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
# the hint's real commands, un-renamed branch: ff the local PR branch in the build worktree, then a plain push of <PR branch>
if [ "$rc" = 0 ]; then
  B8=issue-8-slug
  G "$REPO" checkout -q -b $B8 main && echo pr8 > "$REPO/pr8.txt" && G "$REPO" add pr8.txt && G "$REPO" commit -qm pr8 \
    && G "$REPO" push -q origin $B8 && G "$REPO" checkout -q main
  (cd "$REPO" && python3 "$WT" add "$REPO/.claude/worktrees/issue-8-build" $B8 --lane=build --base=origin/main --no-init >/dev/null 2>&1) \
    || fail "setup: issue-8 build worktree"
  (cd "$REPO" && python3 "$WT" add "$REPO/.claude/worktrees/issue-8-qa" --lane=qa --base=origin/$B8 --no-init >/dev/null 2>&1) \
    || fail "setup: issue-8 qa worktree"
  QA8="$REPO/.claude/worktrees/issue-8-qa"
  B8WT="$REPO/.claude/worktrees/issue-8-build"
  mkdir -p "$B8WT/.claude/agent-memory" && echo 'keep-me-8' > "$B8WT/.claude/agent-memory/note.txt"
  echo evidence8 > "$QA8/evidence8.txt" && G "$QA8" add evidence8.txt && G "$QA8" commit -qm evidence8
  sha8="$(G "$QA8" rev-parse HEAD)"
  # the two commands come out of the hint text, so a wrong hint fails here
  ffcmd="${hint#*git -C }"; ffcmd="${ffcmd%% (*}"
  pushbr="${hint#*then git push origin }"; pushbr="${pushbr%%[.;]*}"
  ffcmd="${ffcmd//<build worktree>/$B8WT}"; ffcmd="${ffcmd//<sha>/$sha8}"; pushbr="${pushbr//<PR branch>/$B8}"
  [ "$(hk "$QA8" "git push origin HEAD:$B8")" = 2 ] && [ "$(hk "$QA8" "git -C $ffcmd")" = 0 ] \
    && ok "hook: the held-branch ff is allowed and HEAD:<PR branch> is refused" || fail "hook verdicts differ for the held-branch commands"
  set -- $ffcmd
  if [ "$pushbr" = "$B8" ] && [ "${2:-}" = merge ] && G "$1" "${@:2}" >/dev/null 2>&1 \
      && [ "$(hk "$QA8" "git push origin $pushbr")" = 0 ] && G "$QA8" push -q origin $pushbr \
      && [ "$(G "$REPO" ls-remote origin $B8 2>/dev/null | cut -f1)" = "$sha8" ] \
      && [ "$(cat "$B8WT/.claude/agent-memory/note.txt" 2>/dev/null)" = "keep-me-8" ]; then
    ok "hint commands for real: ff in the build worktree, plain git push origin <PR branch> moves origin, build memory file survives"
  else
    fail "the commands taken from the hint did not move origin/$B8 (ff='$ffcmd' push='$pushbr') or lost the build memory file"
  fi
fi


# no worktree holds the PR branch: run the hint's git switch / ff / plain push in the QA worktree
qa_switch_push() { # name branch qadir
  local name="$1" br="$2" qa="$3" sha sw mg
  echo "ev-$name" > "$qa/ev-$name.txt" && G "$qa" add "ev-$name.txt" && G "$qa" commit -qm "ev-$name"
  sha="$(G "$qa" rev-parse HEAD)"
  sw="${SW//<PR branch>/$br}"; mg="${MG//<sha>/$sha}"
  case "$hint" in *"$SW"*"$MG"*) ;; *) fail "$name: hint lacks the switch / ff commands"; return ;; esac
  [ "$(hk "$qa" "git push origin HEAD:$br")" = 2 ] || { fail "$name: hook did not refuse git push origin HEAD:$br"; return; }
  [ "$(hk "$qa" "$sw")" = 0 ] || { fail "$name: hook refused $sw"; return; }
  set -- ${sw#git }; G "$qa" "$@" >/dev/null 2>&1 || { fail "$name: $sw failed"; return; }
  [ "$(hk "$qa" "$mg")" = 0 ] || { fail "$name: hook refused $mg"; return; }
  set -- ${mg#git }; G "$qa" "$@" >/dev/null 2>&1 || { fail "$name: $mg failed"; return; }
  [ "$(hk "$qa" "git push origin $br")" = 0 ] || { fail "$name: hook refused git push origin $br"; return; }
  G "$qa" push -q origin "$br" || { fail "$name: plain push of $br failed"; return; }
  [ "$(G "$REPO" ls-remote origin "$br" | cut -f1)" = "$sha" ] && [ "$(G "$qa" rev-parse HEAD)" = "$sha" ] \
    && ok "$name: hook allows switch + ff + plain push (and refuses HEAD:); origin/$br is the evidence sha" \
    || fail "$name: origin/$br is not the evidence sha"
}
if [ "$rc" = 0 ]; then
  # #526 renamed: the build worktree holds issue-7-slug-renamed, so nobody holds issue-7-slug
  qa_switch_push renamed issue-7-slug "$QAWT"
  [ "$(cat "$REPO/.claude/worktrees/issue-7-build/.claude/agent-memory/note.txt" 2>/dev/null)" = "keep-me" ] \
    && ok "renamed: build worktree memory file survives" || fail "renamed: build worktree memory file lost"
  # the Builder removed its worktree before QA (run.md Builder step 9): the local ref survives
  B9=issue-9-slug
  G "$REPO" checkout -q -b $B9 main && echo pr9 > "$REPO/pr9.txt" && G "$REPO" add pr9.txt && G "$REPO" commit -qm pr9 \
    && G "$REPO" push -q origin $B9 && G "$REPO" checkout -q main
  (cd "$REPO" && python3 "$WT" add "$REPO/.claude/worktrees/issue-9-build" $B9 --lane=build --base=origin/main --no-init >/dev/null 2>&1) \
    && G "$REPO" worktree remove --force "$REPO/.claude/worktrees/issue-9-build" || fail "setup: issue-9 build worktree removal"
  (cd "$REPO" && python3 "$WT" add "$REPO/.claude/worktrees/issue-9-qa" --lane=qa --base=origin/$B9 --no-init >/dev/null 2>&1) \
    || fail "setup: issue-9 qa worktree"
  qa_switch_push removed $B9 "$REPO/.claude/worktrees/issue-9-qa"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_qa_detached_worktree: PASS"; exit 0; }
echo "test_qa_detached_worktree: FAIL ($FAILS)"; exit 1
