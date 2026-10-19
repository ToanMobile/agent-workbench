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

# 4 a worktree on ANOTHER volume (OCR 2, 14/10): `cp -Rc` does not fail there, it copies every byte (measured on this machine: 300 MB across two APFS
#   volumes -> rc 0, 302 MB used; same volume 4 MB), i.e. GBs of Library inside a hook that has 300 s. Not cloned across volumes; same volume as before.
#   The two volumes are simulated (the test machine may have one): os.stat reports another st_dev for everything under the worktree.
unity d ""; mkdir -p "$TMP/d-w" "$TMP/d-x"
python3 -I -c 'import contextlib, io, os, sys
sys.path.insert(0, sys.argv[1] + "/scripts/git"); import worktree
main, wt, same = sys.argv[2:5]
real = os.stat
def other_volume(p, *a, **k):
    r = real(p, *a, **k)
    if os.fspath(p).startswith(wt):
        t = tuple(r)[:10]
        return os.stat_result((t[0], t[1], t[2] + 1) + t[3:])
    return r
buf = io.StringIO(); os.stat = other_volume
try:
    with contextlib.redirect_stdout(buf):
        got = worktree.copy_unity_library(main, wt)
finally:
    os.stat = real
assert got == [] and not os.path.exists(os.path.join(wt, "Library")), f"cloned across volumes: {got}"
assert "another volume" in buf.getvalue(), buf.getvalue()
assert worktree.copy_unity_library(main, same) == ["Library"] and os.path.isfile(os.path.join(same, "Library", "ArtifactDB")), "the same volume no longer clones"' \
  "$DEVKIT_DIR" "$TMP/d" "$TMP/d-w" "$TMP/d-x" > "$TMP/out" 2>&1 \
  && ok "a worktree on another volume: the Library is not cloned (cp -c would copy every byte), the user is told; on the same volume it still is" \
  || fail "cross-volume Library: $(tail -3 "$TMP/out" | tr '\n' ' ')"

# 5 cp -Rc fails AFTER it cloned files (ENOSPC, an interrupted copy; OCR2 13): what it cloned keeps its uchg flag, rmtree(ignore_errors) cannot delete
#   such a file and says nothing, and the half Library left behind makes the worktree impossible to remove (INSTINCT-038). The copy's flags are
#   cleared before the clean-up. The failure is injected after a real clone (the copy runs, then its result is replaced by rc 1): deterministic.
unity e ""; mkdir -p "$TMP/e-w"
python3 -I -c 'import contextlib, io, os, subprocess, sys
sys.path.insert(0, sys.argv[1] + "/scripts/git"); import worktree
main, wt = sys.argv[2:4]
real = worktree._run
def cp_fails_after_cloning(argv, *a, **k):
    r = real(argv, *a, **k)
    return subprocess.CompletedProcess(argv, 1, r.stdout, "injected: no space left") if argv[:2] == ["cp", "-Rc"] else r
worktree._run = cp_fails_after_cloning
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    got = worktree.copy_unity_library(main, wt)
assert got == [], f"a failed copy was reported as cloned: {got}"
assert "could not be cloned" in buf.getvalue(), buf.getvalue()
assert not os.path.lexists(os.path.join(wt, "Library")), "the half-cloned Library was left behind (uchg files survive the clean-up)"' "$DEVKIT_DIR" "$TMP/e" "$TMP/e-w" > "$TMP/out" 2>&1 \
  && ok "cp -Rc fails after cloning: the copy's flags are cleared and the half Library is gone (the worktree stays removable)" \
  || fail "failed copy left a half Library: $(tail -3 "$TMP/out" | tr '\n' ' ') $(ls "$TMP/e-w" 2>&1 | tr '\n' ' ')"

# 6. Hai lần clone không được cp -Rc cùng lúc. Khóa riêng UNITY_LIBRARY_COPY_LOCK, không phải khóa batch của Editor.
unity f ""
mkdir -p "$TMP/f-w"
COPY_LOCK="$TMP/unity-library-copy.lock"
python3 - "$COPY_LOCK" "$TMP/copy-held" "$TMP/copy-release" <<'PY' &
import fcntl, os, sys, time
path, held, release = sys.argv[1:]
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(held, "w").close()
while not os.path.exists(release):
    time.sleep(0.05)
os.close(fd)
PY
HPID=$!
i=0
while [ ! -f "$TMP/copy-held" ] && [ "$i" -lt 50 ]; do sleep 0.05; i=$((i + 1)); done
if [ -f "$TMP/copy-held" ]; then
  UNITY_LIBRARY_COPY_LOCK="$COPY_LOCK" python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1] + "/scripts/git")
import worktree
raise SystemExit(0 if worktree.copy_unity_library(sys.argv[2], sys.argv[3]) == ["Library"] else 1)' \
    "$DEVKIT_DIR" "$TMP/f" "$TMP/f-w" >"$TMP/copy-wait.out" 2>&1 &
  CPID=$!
  sleep 0.4
  if [ -d "$TMP/f-w/Library" ]; then
    fail "Library cloned while UNITY_LIBRARY_COPY_LOCK was held"
  else
    ok "second Library clone waits while the copy lock is held"
  fi
  touch "$TMP/copy-release"
  wait "$CPID"; rc=$?
  [ "$rc" = 0 ] && [ -f "$TMP/f-w/Library/ArtifactDB" ] \
    && ok "Library clone finishes after the copy lock is released" \
    || fail "clone after release rc=$rc $(tail -3 "$TMP/copy-wait.out" | tr '\n' ' ')"
else
  fail "could not take the copy lock for the test"
fi
touch "$TMP/copy-release"
wait "$HPID" 2>/dev/null || true

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_unity_library: PASS"; exit 0; } || { echo "test_worktree_unity_library: FAIL ($FAILS)"; exit 1; }
