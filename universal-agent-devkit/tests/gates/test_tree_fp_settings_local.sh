#!/usr/bin/env bash
# bin/tree_fp.py, #691: the kit install adds hooks to .claude/settings.json of every worktree and never commits it, so
# tree_fingerprint() of the gated tree differed from commit_fingerprint(HEAD) and the gate receipt did not match the pushed head
# (PR #690: tree 48c35c95, head 34406c88). An UNCOMMITTED edit of that one file must not move the fingerprint; the COMMITTED content
# still counts (so EXCLUDE must not name it: a PR that really changes settings.json would reuse the old receipt); every other
# tracked file still counts.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

fp()  { python3 -I "$TFP" "$1"; }
cfp() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2]))' "$(dirname "$TFP")" "$1"; }
newrepo() {
    git -C "$1" init -q -b main . && git -C "$1" config user.email t@t && git -C "$1" config user.name t && git -C "$1" config commit.gpgsign false
}

R="$TMP/repo"
mkdir -p "$R/src" "$R/.claude"
newrepo "$R"
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
git -C "$R" add -A && git -C "$R" commit -qm init
HEAD0="$(cfp "$R")"
[ -n "$HEAD0" ] && [ "$(fp "$R")" = "$HEAD0" ] && ok "clean checkout: tree fingerprint = commit fingerprint" || { bad "clean tree differs from commit fp (or empty)"; exit 1; }

# 1. uncommitted edit of settings.json (what the kit install does): the fingerprint stays the HEAD one
printf '{"hooks":{"PreToolUse":["instincts_file_context.sh"]}}\n' > "$R/.claude/settings.json"
[ "$(fp "$R")" = "$HEAD0" ] && ok "uncommitted settings.json edit: tree fingerprint = commit_fingerprint(HEAD)" || bad "uncommitted settings.json edit moved the fingerprint away from HEAD's"

# 2. committing a change of settings.json: commit fingerprint moves, tree fingerprint follows it
git -C "$R" add .claude/settings.json && git -C "$R" commit -qm "settings change"
HEAD1="$(cfp "$R")"
[ "$HEAD1" != "$HEAD0" ] && ok "committed settings.json change: commit_fingerprint moves" || bad "commit_fingerprint did not move (settings.json is excluded?)"
[ "$(fp "$R")" = "$HEAD1" ] && ok "after the commit: tree fingerprint = new commit fingerprint" || bad "tree fingerprint differs from the new commit fingerprint"
printf '{"hooks":{"local":"again"}}\n' > "$R/.claude/settings.json"
[ "$(fp "$R")" = "$HEAD1" ] && ok "a second uncommitted edit on top of the new commit: still the HEAD one" || bad "second uncommitted settings.json edit moved the fingerprint"
git -C "$R" checkout -q -- .claude/settings.json

# 3. any other tracked file still counts, with settings.json dirty or not
printf 'fun ok() = 2\n' > "$R/src/Core.kt"
[ "$(fp "$R")" != "$HEAD1" ] && ok "other tracked file edited: fingerprint moves" || bad "an edit of src/Core.kt did not move the fingerprint"
printf '{"hooks":{"local":"again"}}\n' > "$R/.claude/settings.json"
F3="$(fp "$R")"
git -C "$R" checkout -q -- src/Core.kt
[ "$F3" != "$HEAD1" ] && [ "$(fp "$R")" = "$HEAD1" ] && ok "settings.json dirty + other file edited: moves; reverted: back to HEAD's" || bad "mixed edit case wrong"
git -C "$R" checkout -q -- .claude/settings.json

# 4. HEAD has no settings.json: a new untracked one is left out too
R2="$TMP/repo2"
mkdir -p "$R2/src"
newrepo "$R2"
printf 'fun ok() = 1\n' > "$R2/src/Core.kt"
git -C "$R2" add -A && git -C "$R2" commit -qm init
H2="$(cfp "$R2")"
mkdir -p "$R2/.claude" && printf '{"hooks":{}}\n' > "$R2/.claude/settings.json"
[ "$(fp "$R2")" = "$H2" ] && ok "HEAD without settings.json, untracked one added: fingerprint = HEAD's" || bad "untracked settings.json moved the fingerprint"

# 5. project_dir below the repo root: the path is relative to project_dir, like EXCLUDE
R3="$TMP/repo3"
mkdir -p "$R3/app/.claude" "$R3/app/src"
newrepo "$R3"
printf 'x\n' > "$R3/app/src/a.kt"; printf '{}\n' > "$R3/app/.claude/settings.json"
git -C "$R3" add -A && git -C "$R3" commit -qm init
H3="$(cfp "$R3/app")"
printf '{"local":1}\n' > "$R3/app/.claude/settings.json"
[ "$(fp "$R3/app")" = "$H3" ] && ok "sub-folder project: uncommitted app/.claude/settings.json edit ignored" || bad "sub-folder project: settings.json edit moved the fingerprint"
printf 'y\n' > "$R3/app/src/a.kt"
[ "$(fp "$R3/app")" != "$H3" ] && ok "sub-folder project: other edit moves" || bad "sub-folder project: other edit did not move"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
