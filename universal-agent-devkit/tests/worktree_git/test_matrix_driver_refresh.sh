#!/usr/bin/env bash
# Regression (agent-workbench #291): the matrix merge driver command is written only by `githooks install`, so a repo
# installed before a kit change (#282) kept the old command and the merge gate's scratch worktree fell back to a text
# merge. `githooks.sh refresh-matrix-driver` (run at SessionStart) rewrites a STALE command and nothing else:
#   1. a repo with an old driver command: the command is rewritten to what `install` writes
#   2. the command is already current: nothing printed, .git/config not rewritten
#   3. a repo that never installed the driver: nothing written (the refresh does not opt a repo in)
#   4. session_context.sh calls the refresh
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/scripts/git/githooks.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
mk() { mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
  && echo x > "$1/a" && git -C "$1" add a && git -C "$1" commit -qm init; }
DRV='merge.devkit-matrix.driver'

mk "$TMP/ref"; bash "$KIT" install "$TMP/ref" >/dev/null 2>&1
want="$(git -C "$TMP/ref" config --get $DRV)"
[ -n "$want" ] || fail "reference install wrote no driver"

mk "$TMP/old"; git -C "$TMP/old" config merge.devkit-matrix.name x
git -C "$TMP/old" config $DRV 'python3 .agents/devkit/scripts/git/matrix_merge_driver.py %O %A %B %P'
out="$(bash "$KIT" refresh-matrix-driver "$TMP/old" 2>&1)"
[ "$(git -C "$TMP/old" config --get $DRV)" = "$want" ] && ok "1: stale driver command rewritten to the current one" \
  || fail "1: command is '$(git -C "$TMP/old" config --get $DRV)'"

before="$(cksum < "$TMP/old/.git/config")"
out="$(bash "$KIT" refresh-matrix-driver "$TMP/old" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && [ "$(cksum < "$TMP/old/.git/config")" = "$before" ] \
  && ok "2: current command: silent, config untouched" || fail "2: rc=$rc out='$out'"

mk "$TMP/none"; bash "$KIT" refresh-matrix-driver "$TMP/none" >/dev/null 2>&1
[ -z "$(git -C "$TMP/none" config --get $DRV)" ] && [ ! -e "$TMP/none/.gitattributes" ] \
  && ok "3: a repo without the driver is left alone" || fail "3: refresh opted the repo in"

grep -q "refresh-matrix-driver" "$DEVKIT_DIR/hooks/session_context.sh" \
  && ok "4: SessionStart runs the refresh" || fail "4: session_context.sh does not call refresh-matrix-driver"
[ "$FAILS" -eq 0 ]
