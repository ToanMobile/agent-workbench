#!/usr/bin/env bash
# W1 R6 (docs/workflow-improvements.md I.0): a Unity project's Library (Goods 9.7 GB / 44 085 files, Neighbours 7.8 GB, 14/10) is git-ignored,
# so a new worktree had none and Unity re-imported everything from scratch (tens of minutes) before an agent could build or test there.
# `worktree add` now clones it from the main checkout with clonefile (`cp -Rc`: no data copied on APFS), clears the copy's user flags
# (clonefile keeps uchg / uappnd and the worktree could then never be deleted: INSTINCT-038) and drops the Editor's lock files of the
# main checkout's Library (ArtifactDB-lock, SourceAssetDB-lock, DataStore/*.lock, Search/*-lock), for the project at the root and one
# level down (Neighbours keeps it in unity/). A Library git tracks is left to git. The worktree is still removed in one step.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_MAX WORKTREE_DISK_MIN_GIB WORKTREE_DISK_WARN_GIB
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'chflags -R nouchg,nouappnd "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
[ "$(uname)" = Darwin ] || { echo "• not macOS: clonefile / chflags cases skipped"; echo "test_worktree_unity_library: PASS"; exit 0; }

unity() {   # unity <repo> <project dir relative or ''>: a Unity project whose Library git ignores, with locks and a uchg file in it
  local r="$TMP/$1" p="$TMP/$1${2:+/$2}"
  mkdir -p "$p/ProjectSettings" "$p/Assets" "$p/Library/DataStore" "$p/Library/Search" "$p/Library/PackageCache/pkg"
  [ -d "$r/.git" ] || G "$r" init -q -b main
  echo "m_EditorVersion: 6000.0.1f1" > "$p/ProjectSettings/ProjectVersion.txt"; echo "a" > "$p/Assets/a.cs"
  printf '/%s[Ll]ibrary/\n' "${2:+$2/}" > "$r/.gitignore"
  echo artifacts > "$p/Library/ArtifactDB"; : > "$p/Library/ArtifactDB-lock"; : > "$p/Library/SourceAssetDB-lock"
  echo db > "$p/Library/DataStore/uds.db"; : > "$p/Library/DataStore/uds.lock"; : > "$p/Library/DataStore/uds.db-lock"
  : > "$p/Library/Search/abc.index-lock"; echo pkg > "$p/Library/PackageCache/pkg/a.cs"
  echo frozen > "$p/Library/PackageCache/pkg/frozen.cs" && chflags uchg "$p/Library/PackageCache/pkg/frozen.cs"
  G "$r" add -A && G "$r" commit -qm i
}
flags() { stat -f '%Sf' "$1" 2>/dev/null; }

# 1 the project at the root
unity a ""
(cd "$TMP/a" && python3 -I "$WT" add "$TMP/a-w" --no-init > "$TMP/out" 2>&1); rc=$?
L="$TMP/a-w/Library"
if [ "$rc" = 0 ] && [ "$(cat "$L/ArtifactDB" 2>/dev/null)" = artifacts ] && [ "$(cat "$L/PackageCache/pkg/frozen.cs" 2>/dev/null)" = frozen ] \
    && [ -f "$L/DataStore/uds.db" ]; then
  ok "add: the root project's Library is in the worktree (cloned from the main checkout)"
else
  fail "Library not cloned (rc $rc): $(ls "$L" 2>&1 | head -3 | tr '\n' ' ') $(tail -2 "$TMP/out")"
fi
case "$(flags "$L/PackageCache/pkg/frozen.cs")" in *uchg*) fail "the copy kept uchg (it could never be deleted)" ;; *) [ -f "$L/PackageCache/pkg/frozen.cs" ] && ok "  … the copy's uchg / uappnd flags are cleared (INSTINCT-038)" ;; esac
case "$(flags "$TMP/a/Library/PackageCache/pkg/frozen.cs")" in *uchg*) ok "  … the main checkout's own flags are left alone" ;; *) fail "the main checkout's flag was cleared" ;; esac
locks=""; for f in ArtifactDB-lock SourceAssetDB-lock DataStore/uds.lock DataStore/uds.db-lock Search/abc.index-lock; do [ -e "$L/$f" ] && locks="$locks $f"; done
[ -z "$locks" ] && [ -d "$L" ] && ok "  … the Editor's lock files are not in the copy" || fail "lock files copied:$locks"
[ -z "$(G "$TMP/a-w" status --porcelain)" ] && ok "  … nothing of it shows in git status (ignored)" || fail "the Library copy shows in git status"
(cd "$TMP/a" && python3 -I "$WT" remove "$TMP/a-w" > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/a-w" ] && ok "  … and the worktree is removed in one step" || fail "removal with the Library copy (rc $rc): $(tail -2 "$TMP/out")"

# 2 the project one level down (unity/), as in Neighbours-From-Hell
unity b unity
(cd "$TMP/b" && python3 -I "$WT" add "$TMP/b-w" --no-init > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(cat "$TMP/b-w/unity/Library/ArtifactDB" 2>/dev/null)" = artifacts ] && [ ! -e "$TMP/b-w/unity/Library/ArtifactDB-lock" ] \
  && ok "a project in unity/: its Library cloned, locks dropped" || fail "unity/ project (rc $rc): $(tail -2 "$TMP/out")"

# 3 a Library git tracks is git's business: not cloned over it
mkdir -p "$TMP/c/ProjectSettings" "$TMP/c/Library" && G "$TMP/c" init -q -b main && echo v > "$TMP/c/ProjectSettings/ProjectVersion.txt"
echo tracked > "$TMP/c/Library/T.asset" && echo untracked > "$TMP/c/Library/U.asset" && G "$TMP/c" add ProjectSettings Library/T.asset && G "$TMP/c" commit -qm i
(cd "$TMP/c" && python3 -I "$WT" add "$TMP/c-w" --no-init > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/c-w/Library/T.asset" ] && [ ! -e "$TMP/c-w/Library/U.asset" ] && ok "a Library git tracks: left to git (nothing cloned over it)" || fail "tracked Library (rc $rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_unity_library: PASS"; exit 0; } || { echo "test_worktree_unity_library: FAIL ($FAILS)"; exit 1; }
