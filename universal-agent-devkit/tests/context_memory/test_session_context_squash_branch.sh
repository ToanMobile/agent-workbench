#!/usr/bin/env bash
# Regression test: hooks/session_context.sh must not call a SQUASH-merged branch "chưa merge".
# A squash PR leaves one single-parent commit on main, so `git branch --merged` never lists the task branch
# although main holds all its content (agent-workbench 2026-11-08: dozens of finished branches reported as unmerged).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
ctx() { printf '{"session_id":"sc","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$1" WORKTREE_GC=0 bash "$HOOK" 2>/dev/null; }

mkdir -p "$TMP/r" && cd "$TMP/r" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo base > a.txt && git add -A && git commit -qm init

git checkout -q -b feat/squashed
echo one > b.txt && git add -A && git commit -qm one
echo two >> b.txt && git add -A && git commit -qm two
git checkout -q -b feat/real-unmerged main
echo keep > c.txt && git add -A && git commit -qm unmerged-work
git checkout -q main
git merge --squash -q feat/squashed && git commit -qm "squash feat (#1)"

out="$(ctx "$TMP/r")"
line="$(printf '%s' "$out" | grep -o 'nhánh chưa merge[^;]*')"

printf '%s' "$line" | grep -q "feat/squashed" \
  && fail "squash-merged branch still reported as unmerged: $line" \
  || ok "squash-merged branch is not reported as unmerged"
printf '%s' "$line" | grep -q "feat/real-unmerged" \
  && ok "a branch with work main lacks is still reported" \
  || fail "real unmerged branch lost from the report: $(printf '%s' "$out" | grep -o 'Nhánh (luật[^.]*')"
printf '%s' "$out" | grep -q "git branch -D feat/squashed" \
  && ok "the squash-merged branch gets a delete hint" \
  || fail "no delete hint for the squash-merged branch"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
