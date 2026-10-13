#!/usr/bin/env bash
# Old script paths an installed repo committed a link to must keep resolving (2026-10-13, /devkit-audit item 6, health):
# GeelyEx2 tracks `scripts/red_proof.py -> ../.agents/devkit/scripts/red_proof.py`, made before scripts/ was split into groups
# (red_proof.py now lives in scripts/testing/). The link has been broken since: agent-health scores the repo 96/100 ("a committed
# symlink points at a target that does not exist: clones and CI break"). The kit keeps a relative link at the old path, so every
# repo's old link resolves again without a commit in that repo.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# old path -> current file (relative to the kit)
check_path() {
  local old="$1" new="$2"
  if [ -e "$DEVKIT_DIR/$old" ] && [ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DEVKIT_DIR/$old")" = \
       "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DEVKIT_DIR/$new")" ]; then
    ok "$old resolves to $new"
  else
    fail "$old does not resolve to $new"
  fi
}
check_path scripts/red_proof.py scripts/testing/red_proof.py

# the repo-side link GeelyEx2 committed, in a symlink-mode install
R="$TMP/repo"; mkdir -p "$R/.agents" "$R/scripts"
ln -s "$DEVKIT_DIR" "$R/.agents/devkit"
ln -s ../.agents/devkit/scripts/red_proof.py "$R/scripts/red_proof.py"
[ -e "$R/scripts/red_proof.py" ] && ok "a repo's committed scripts/red_proof.py link resolves" || fail "a repo's committed scripts/red_proof.py link is broken"
# and runs the real tool: the same refusal for a project with no checklist as the current path gives
a="$(python3 "$R/scripts/red_proof.py" "$TMP/nowhere" --pending 2>&1 | head -1)"
b="$(python3 "$DEVKIT_DIR/scripts/testing/red_proof.py" "$TMP/nowhere" --pending 2>&1 | head -1)"
[ -n "$b" ] && [ "$a" = "$b" ] && ok "the old path runs the same tool ($b)" || fail "old path output '$a' differs from '$b'"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
