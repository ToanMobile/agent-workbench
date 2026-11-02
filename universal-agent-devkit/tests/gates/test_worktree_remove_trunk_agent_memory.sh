#!/usr/bin/env bash
# #416 (agent-workbench): in trunk mode a lane worktree whose only unsaved change is an edit of a TRACKED
# .claude/agent-memory note (a subagent such as principal-code-reviewer writes it) could not be removed: `worktree remove` told the
# agent to `worktree diff | git apply --3way` into main, and main is merge-only in trunk mode (session_lock refuses that write), so
# the card was parked. The way out is a commit on the lane's own branch (the PR carries the note).
#   1 trunk mode + branch worktree + tracked agent-memory edit: remove refuses, and the advice is a commit on the branch, not `git apply`
#   2 after that commit, `worktree remove` succeeds (the branch keeps the commit)
#   3 control: a tracked edit that is NOT agent-memory keeps the old advice (`git apply --3way`)
#   4 control: trunk mode off keeps the old advice for agent-memory too
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P/.claude/agent-memory/rev" && G "$P" init -q -b main . \
  && printf '1\n' > "$P/.claude/agent-memory/rev/note.md" && printf '1\n' > "$P/a.txt" && G "$P" add -A && G "$P" commit -qm init
add_wt() { (cd "$P" && python3 "$WTPY" add --no-init "$1" "$2" >/dev/null 2>&1); }   # add_wt <path> <branch>
remove() { (cd "$P" && python3 "$WTPY" remove "$1") >"$TMP/rm.out" 2>&1; }

W1="$P/.claude/worktrees/lane1"; add_wt "$W1" issue-1-memory || fail "setup: worktree add failed"
printf '2\n' > "$W1/.claude/agent-memory/rev/note.md"
remove "$W1"; rc=$?
[ "$rc" != 0 ] && grep -q "not in the main checkout" "$TMP/rm.out" && ok "setup: remove refuses an uncommitted agent-memory edit" \
  || fail "setup: remove did not refuse (rc=$rc): $(cat "$TMP/rm.out")"
if grep -q "git apply --3way" "$TMP/rm.out"; then fail "1: trunk mode advice still says git apply into main: $(cat "$TMP/rm.out")"
elif grep -q "git -C .*commit" "$TMP/rm.out"; then ok "1: the advice is a commit on the lane's branch"
else fail "1: no commit advice: $(cat "$TMP/rm.out")"; fi

G "$W1" add .claude/agent-memory/rev/note.md && G "$W1" commit -qm "docs: agent-memory note"
remove "$W1"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W1" ] && ok "2: after the commit on the branch, remove succeeds" || fail "2: remove still refuses (rc=$rc): $(cat "$TMP/rm.out")"

W3="$P/.claude/worktrees/lane3"; add_wt "$W3" issue-3-other || fail "setup3: worktree add failed"
printf '2\n' > "$W3/a.txt"
remove "$W3"
grep -q "git apply --3way" "$TMP/rm.out" && ok "3: a non-memory edit keeps the git apply advice" || fail "3: $(cat "$TMP/rm.out")"
rm -f "$W3/a.txt"; G "$W3" checkout -q -- a.txt; remove "$W3" >/dev/null 2>&1

W4="$P/.claude/worktrees/lane4"; add_wt "$W4" issue-4-off || fail "setup4: worktree add failed"
printf '2\n' > "$W4/.claude/agent-memory/rev/note.md"
(cd "$P" && WORKTREE_TRUNK_MODE=0 python3 "$WTPY" remove "$W4") >"$TMP/rm.out" 2>&1
grep -q "git apply --3way" "$TMP/rm.out" && ok "4: trunk mode off keeps the git apply advice" || fail "4: $(cat "$TMP/rm.out")"

[ "$FAILS" = 0 ] && echo "ALL PASS" && exit 0
echo "FAILS=$FAILS"; exit 1
