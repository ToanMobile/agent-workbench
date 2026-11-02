#!/usr/bin/env bash
# #155: a `.merge-scratch-*` worktree (super-board-merge-gate.sh's proof tree, left behind when the gate is SIGKILLed) never blocks
# `worktree add`: three orphans must not make it exit 4. #607: there is no count of worktrees, so real worktrees are made too.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
add() { (cd "$TMP/main" && env -u WORKTREE_MAX WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add "$TMP/main-$1" --no-init > "$TMP/out" 2>&1); }

mkdir -p "$TMP/main/.claude/worktrees" && G "$TMP/main" init -q -b main "$TMP/main" && echo base > "$TMP/main/app.txt" \
  && G "$TMP/main" add -A && G "$TMP/main" commit -qm base
for s in aaa bbb ccc; do G "$TMP/main" worktree add -q --detach "$TMP/main/.claude/worktrees/.merge-scratch-$s"; done
add w1; rc=$?
[ "$rc" = 0 ] && ok "three orphan .merge-scratch-* worktrees do not block add" || fail "add refused next to merge scratches (rc $rc): $(cat "$TMP/out")"
add w2; add w3; add w4; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/main-w4" ] && ok "#607: a fourth real worktree is made too (no count)" || fail "fourth real worktree refused (rc $rc): $(cat "$TMP/out")"
[ "$FAILS" = 0 ]
