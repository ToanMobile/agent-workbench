#!/usr/bin/env bash
# docs/issues-bugs.md A.4 (reported 14/10 by session agent-workbench-16): `worktree finish` / the Stop hook's automerge
# (scripts/git/worktree.py _commit_pending) committed the worktree's UNTRACKED files, symlinks too. A `node_modules` link made in a
# worktree to run `npm test` against main's packages was committed (512b07d) and the fast-forward replaced main's real, git-ignored
# node_modules/ directory with that link, pointing at itself: the packages were deleted (`.gitignore` had `node_modules/`, which matches
# a directory, not a link). git merge overwrites ignored files by default (--overwrite-ignore). Each case has a main checkout of its own.
#   1 an untracked symlink is never committed: the merge is refused before anything is committed or merged, the link is named
#   2 a link committed by hand that would replace main's ignored directory: the fast-forward is refused (--no-overwrite-ignore), nothing
#     moves, main's folder and its files intact, the reason names it (not "main kept moving", not "UNCOMMITTED edits")
#   3 a tracked file that would overwrite main's git-ignored local file: refused the same way, main's file intact
#   4 control: a committed link that replaces nothing merges as before; an untracked link git IGNORES is no work (no refusal)
#   5 a tracked regular file replaced by a symlink is refused like a new link; a link HEAD holds as a link, retargeted, is ordinary work
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

new_main() {   # new_main <name>: a main checkout with a real, git-ignored node_modules/ and an ignored config/local.json of its own
  P="$TMP/$1"; mkdir -p "$P" && G "$P" init -q -b main . || return 1
  printf 'node_modules/\nconfig/local.json\nvendor-link\n' > "$P/.gitignore"; echo a > "$P/a.txt"
  G "$P" add -A && G "$P" commit -qm init
  mkdir -p "$P/node_modules/pkg" "$P/config" && echo 'module.exports = 1' > "$P/node_modules/pkg/index.js" && echo '{"mine": true}' > "$P/config/local.json"
}
wt() { (cd "$P" && python3 "$WTPY" add "$1" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1"; }
fin() { (cd "$P" && python3 "$WTPY" finish "$@" >"$TMP/out" 2>&1); return $?; }
main_intact() { [ -d "$P/node_modules" ] && [ ! -L "$P/node_modules" ] && [ "$(cat "$P/node_modules/pkg/index.js" 2>/dev/null)" = 'module.exports = 1' ]; }

# 1: an untracked symlink to main's node_modules (made to run npm test in the worktree)
new_main m1; W="$TMP/wl-a"; wt "$W"; ln -s "$P/node_modules" "$W/node_modules"; echo work > "$W/w.txt"
H1="$(G "$P" rev-parse HEAD)"; WH1="$(G "$W" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && grep -q "node_modules" "$TMP/out" && grep -qi "link" "$TMP/out" \
  && ok "1: an untracked symlink stops the merge (exit 1) and is named" || fail "1: (rc=$rc): $(cat "$TMP/out")"
[ "$(G "$P" rev-parse HEAD)" = "$H1" ] && [ "$(G "$W" rev-parse HEAD 2>&1)" = "$WH1" ] && [ -f "$W/w.txt" ] \
  && ok "  … nothing was committed in the worktree or merged into main" || fail "  … something moved: main '$(G "$P" log -1 --format=%s)'"
main_intact && ok "  … main's real node_modules/ and its files are intact" || fail "  … main's node_modules was replaced: $(ls -la "$P" | grep node_modules)"
if [ -d "$W" ]; then
  rm -f "$W/node_modules"
  fin "$W"; rc=$?; [ "$rc" = 0 ] && [ -f "$P/w.txt" ] && main_intact && ok "  … without the link the rest goes through" || fail "  … after removing the link (rc=$rc): $(cat "$TMP/out")"
fi

# 2: the same link committed by hand: the fast-forward must not replace main's ignored directory
new_main m2; W="$TMP/wl-b"; wt "$W"; ln -s "$P/node_modules" "$W/node_modules" && G "$W" add node_modules && G "$W" commit -qm "link committed by hand"
H2="$(G "$P" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H2" ] && main_intact \
  && ok "2: a committed link over main's ignored node_modules/: refused (exit 1), main did not move, its folder is intact" \
  || fail "2: (rc=$rc, main moved: $([ "$(G "$P" rev-parse HEAD)" = "$H2" ] && echo no || echo yes)): $(cat "$TMP/out"); $(ls -la "$P" | grep node_modules)"
grep -q "node_modules" "$TMP/out" && ! grep -q "kept moving" "$TMP/out" && ! grep -q "UNCOMMITTED" "$TMP/out" \
  && ok "  … the reason names node_modules (not 'main kept moving', not 'UNCOMMITTED edits')" || fail "  … reason: $(cat "$TMP/out")"
[ -d "$W" ] && ok "  … the worktree is kept" || fail "  … the worktree was removed"

# 3: a tracked file of the worktree that would overwrite main's git-ignored local file
new_main m3; W="$TMP/wl-c"; wt "$W"; mkdir -p "$W/config" && echo '{"theirs": true}' > "$W/config/local.json"
G "$W" add -f config/local.json && G "$W" commit -qm "track local.json"
H3="$(G "$P" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H3" ] && [ "$(cat "$P/config/local.json")" = '{"mine": true}' ] && grep -q "config/local.json" "$TMP/out" \
  && ok "3: a tracked file over main's ignored local file: refused, main's file intact, named" || fail "3: (rc=$rc) local.json=$(cat "$P/config/local.json"): $(cat "$TMP/out")"

# 4: control: a committed link that replaces nothing in main, and an untracked link git ignores
new_main m4; W="$TMP/wl-d"; wt "$W"; ln -s a.txt "$W/a-link.txt" && G "$W" add a-link.txt && G "$W" commit -qm "a link that is work"
ln -s /tmp "$W/vendor-link"   # ignored by main's .gitignore (no trailing slash): not work, never committed, no refusal
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ -L "$P/a-link.txt" ] && [ ! -e "$P/vendor-link" ] && [ ! -d "$W" ] && main_intact \
  && ok "4: a committed link that replaces nothing merges; an ignored untracked link is left out" || fail "4: (rc=$rc): $(cat "$TMP/out")"

# 5 (principal review A1): the rule looked at NAMES in HEAD, not at what they are: a tracked regular file the worktree replaced by a symlink
#   (to main's own copy: the fast-forward would turn main's config.json into a link pointing at itself, ELOOP) went through as "a link HEAD
#   already holds". Only a path HEAD holds AS A LINK (mode 120000) may be retargeted without a word.
new_main m5; echo '{"k": 1}' > "$P/config.json"; ln -s a.txt "$P/cur"; G "$P" add config.json cur && G "$P" commit -qm "config and a tracked link"
W="$TMP/wl-e"; wt "$W"; rm "$W/config.json" && ln -s "$P/config.json" "$W/config.json"
H5="$(G "$P" rev-parse HEAD)"; WH5="$(G "$W" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && grep -q "config.json" "$TMP/out" && grep -qi "link" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$H5" ] && [ "$(G "$W" rev-parse HEAD)" = "$WH5" ] \
  && [ -f "$P/config.json" ] && [ ! -L "$P/config.json" ] && [ "$(cat "$P/config.json")" = '{"k": 1}' ] \
  && ok "5: a tracked file replaced by a symlink is refused like a new one: named, nothing committed or merged, main's config.json intact" \
  || fail "5: (rc=$rc, main moved: $([ "$(G "$P" rev-parse HEAD)" = "$H5" ] && echo no || echo yes), main's config.json: $(ls -la "$P/config.json" 2>&1)): $(cat "$TMP/out")"
if [ -d "$W" ]; then
  rm "$W/config.json" && echo '{"k": 2}' > "$W/config.json" && ln -sfn b.txt "$W/cur"   # settled: a real edit, and a link HEAD holds as a link retargeted
  fin "$W"; rc=$?
  [ "$rc" = 0 ] && [ ! -L "$P/config.json" ] && [ "$(cat "$P/config.json")" = '{"k": 2}' ] && [ "$(readlink "$P/cur")" = b.txt ] && [ ! -d "$W" ] \
    && ok "  … a real edit of it and a retargeted tracked link are ordinary work: merged, the worktree removed" || fail "  … after settling (rc=$rc): $(cat "$TMP/out")"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_automerge_symlink: all passed" || { echo "❌ test_worktree_automerge_symlink: $FAILS failed"; exit 1; }
