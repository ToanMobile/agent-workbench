#!/usr/bin/env bash
# Issue #14: after a conflict is resolved and staged in the worktree, the next `worktree finish` concluded the open merge with a bare
# `git commit --no-edit` (scripts/git/worktree.py _automerge_locked) BEFORE _commit_pending's _secret_like / symlink scan, so a secret
# or a new symlink that was staged next to the resolution was committed (and then fast-forwarded into main).
#   1 a staged secret-like file beside a resolved conflict: finish is refused (exit 1), the file is named, the merge stays open, nothing committed
#   2 a staged NEW symlink is refused the same way
#   3 control: only the resolved file staged -> the merge concludes and lands in main
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

conflicted() {   # conflicted <name>: main + a worktree $W whose finish left a merge open on a.txt
  P="$TMP/$1"; W="$TMP/wl-$1"; mkdir -p "$P" && G "$P" init -q -b main . || return 1
  echo base > "$P/a.txt"; G "$P" add -A && G "$P" commit -qm init
  (cd "$P" && python3 "$WTPY" add "$W" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1"
  echo theirs > "$W/a.txt"; G "$W" commit -qam "worktree edit"
  echo mine > "$P/a.txt"; G "$P" commit -qam "main edit"
  (cd "$P" && python3 "$WTPY" finish "$W" >"$TMP/out" 2>&1)   # conflict: merge left open in $W
  [ -n "$(G "$W" diff --name-only --diff-filter=U)" ] || fail "setup: no open conflict in $1: $(cat "$TMP/out")"
  echo resolved > "$W/a.txt"
}
fin() { (cd "$P" && python3 "$WTPY" finish "$W" >"$TMP/out" 2>&1); return $?; }
merge_open() { [ -n "$(G "$W" rev-parse -q --verify MERGE_HEAD)" ]; }

conflicted s1; echo secret > "$W/release.jks"; G "$W" add a.txt release.jks
WH="$(G "$W" rev-parse HEAD)"; MH="$(G "$P" rev-parse HEAD)"
fin; rc=$?
[ "$rc" = 1 ] && grep -q "release.jks" "$TMP/out" && [ "$(G "$W" rev-parse HEAD)" = "$WH" ] && [ "$(G "$P" rev-parse HEAD)" = "$MH" ] && merge_open \
  && ok "1: a staged secret beside the resolution is refused, named, nothing committed, merge still open" || fail "1: (rc=$rc): $(cat "$TMP/out")"

conflicted s2; ln -s /etc/passwd "$W/evil-link"; G "$W" add a.txt evil-link
WH="$(G "$W" rev-parse HEAD)"
fin; rc=$?
[ "$rc" = 1 ] && grep -q "evil-link" "$TMP/out" && [ "$(G "$W" rev-parse HEAD)" = "$WH" ] && merge_open \
  && ok "2: a staged new symlink is refused, named, nothing committed" || fail "2: (rc=$rc): $(cat "$TMP/out")"

conflicted s3; G "$W" add a.txt
fin; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$P/a.txt")" = resolved ] && ok "3: control: a plain resolution concludes and lands in main" || fail "3: (rc=$rc): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_automerge_staged_secret: all passed" || { echo "❌ test_worktree_automerge_staged_secret: $FAILS failed"; exit 1; }
