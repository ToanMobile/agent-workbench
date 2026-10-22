#!/usr/bin/env bash
# #157: in a LINKED worktree devkit_place must not replace a git-TRACKED project file whose bytes differ from the kit's
# (GeelyEx2 / Goods / NFH track .claude/hooks/guard-protected-push.py): the swap made the worktree's tree differ from the tree
# main pushes, so the gate's receipt never covered the push. Main checkout and untracked files keep the old behaviour.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

SRC="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

KIT="$TMP/kit"; R="$TMP/repo"; W="$TMP/wt"
mkdir -p "$KIT" "$R/.claude/hooks"
printf '#!/usr/bin/env python3\nprint("kit guard v2 with more bytes")\n' > "$KIT/x.py"; chmod 755 "$KIT/x.py"
printf '#!/usr/bin/env python3\nprint("guard")\n' > "$R/.claude/hooks/x.py"; chmod 755 "$R/.claude/hooks/x.py"
git -C "$R" init -q -b main && git -C "$R" config user.email t@t && git -C "$R" config user.name t \
  && git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" worktree add -q --detach "$W" \
  || { echo "setup failed"; exit 1; }

place() {   # place <target dir> <relative dst>: devkit_place as the installer calls it
  ( export DEVKIT_ROOT="$KIT" TARGET_DIR="$1"; cd "$1" && . "$SRC/scripts/git/backup_conflict.sh" \
    && devkit_place "$KIT/x.py" "$1/$2" symlink ) >/dev/null 2>&1
}

place "$W" .claude/hooks/x.py
[ -f "$W/.claude/hooks/x.py" ] && [ ! -L "$W/.claude/hooks/x.py" ] && ok "worktree: the tracked hook stays a regular file" || fail "worktree: tracked hook was replaced by a link"
[ -z "$(git -C "$W" status --porcelain)" ] && ok "worktree: git status clean after the install" || fail "worktree dirty: $(git -C "$W" status --porcelain | tr '\n' ' ')"
[ ! -e "$W/.agents/local/hooks/x.py" ] && ok "worktree: no backup copy left in .agents/local/hooks" || fail "worktree: backup copy created"

# control: an UNTRACKED file with other bytes is still the user's -> backed up and linked, as before
mkdir -p "$W/.claude/hooks"; echo 'print("mine")' > "$W/.claude/hooks/mine.py"
cp "$KIT/x.py" "$KIT/mine.py"
( export DEVKIT_ROOT="$KIT" TARGET_DIR="$W"; cd "$W" && . "$SRC/scripts/git/backup_conflict.sh" && devkit_place "$KIT/mine.py" "$W/.claude/hooks/mine.py" symlink ) >/dev/null 2>&1
[ -L "$W/.claude/hooks/mine.py" ] && [ -f "$W/.agents/local/hooks/mine.py" ] && ok "control: untracked project file still goes to the project tier and the kit link is installed" || fail "control: untracked file handling changed"

# control: the main checkout keeps the old behaviour (swap + backup)
place "$R" .claude/hooks/x.py
[ -L "$R/.claude/hooks/x.py" ] && [ -f "$R/.agents/local/hooks/x.py" ] && ok "control: main checkout unchanged (kit link + project-tier backup)" || fail "control: main checkout behaviour changed"

if [ "$FAILS" -ne 0 ]; then echo "place keeps tracked in worktree: $FAILS FAILED"; exit 1; fi
echo "place keeps tracked in worktree: all checks passed"
