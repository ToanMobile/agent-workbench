#!/usr/bin/env bash
# Regression (GeelyEx2, 2026-10-13: seven unregistered worktree folders, 150-200 MB each, left in /Volumes/Data/Toan):
# a keystore the user locked with `chflags uchg` (macOS user-immutable flag) was copied into every worktree by
# `worktree add` with shutil.copy2, which copies the flags too. The copy could then not be deleted: git 2.55 `worktree remove`
# fails ("error: failed to delete ... Operation not permitted", exit 255) but STILL drops its own registration, so the folder stayed,
# no guard listed it, nothing could retry, and the next session could not reuse the name (push-1013, -1013b, -1013c).
#   1  `worktree add` copies the ignored local config WITHOUT the immutable flag (the main checkout's own file keeps it)
#   2  `worktree remove` takes the folder AND its registration away, also when a worktree made by older code holds an immutable file
#   3  a folder that cannot be taken away is an error (exit 1, the path named), never "removed"
#   4  a removal git REFUSES (a locked worktree) must not strip the user's flags: unlock only once git has committed to the removal
#   5  an ignored symlink to the main checkout's keystore inside a worktree: the main file keeps its flag and exists
#   6  a path spelled as a symlink to a registered worktree still removes it (git's own spelling is used)
#   7  the worktree_sandbox.py copy of .worktreeinclude files (cp -c clones flags) carries no immutable flag either
# macOS only (chflags); elsewhere the test says it was not run.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
if ! command -v chflags >/dev/null 2>&1; then echo "SKIPPED (no chflags): immutable-copy test NOT RUN - macOS only"; echo "worktree immutable copy: SKIPPED - NOT RUN"; exit 0; fi
# a failing mktemp must never leave TMP at the cwd (`cd ""` stays put, and the EXIT trap below deletes TMP)
mk_tmp() { local t; t="$(mktemp -d 2>/dev/null)" || return 1; case "$t" in /?*) [ -d "$t" ] || return 1 ;; *) return 1 ;; esac; (cd "$t" && pwd -P); }
TMP="$(mk_tmp)" || { echo "✖ cannot make a scratch dir"; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "✖ cannot make a scratch dir"; exit 1; }
# a RED run leaves undeletable files behind: unlock before rm, or /tmp fills up with them
trap 'chflags -R nouchg "$TMP" 2>/dev/null; chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
flags() { stat -f %Sf "$1" 2>/dev/null; }   # "uchg" or "-"
has_uchg() { case "$(flags "$1")" in *uchg*) return 0 ;; *) return 1 ;; esac; }

R="$TMP/main"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
printf 'keystore.properties\nlocal.properties\n.sandboxes/\n' > .gitignore
echo tracked > a.txt; G "$R" add -A && G "$R" commit -qm init
echo "storePassword=x" > keystore.properties; echo "sdk.dir=/x" > local.properties
chflags uchg keystore.properties
has_uchg keystore.properties || { echo "SKIPPED (this filesystem keeps no uchg flag): NOT RUN"; echo "worktree immutable copy: SKIPPED - NOT RUN"; exit 0; }
printf 'stuck/\nlink-to-main-keystore\n' >> "$R/.git/info/exclude"
reg() { git -C "$R" worktree list --porcelain | grep -c "/$1\$"; }   # registrations of <name> (0 = none)

# 1 + 2: add, then remove
bash "$KIT" worktree add ../wt1 --no-init >"$TMP/add1.out" 2>&1 || { fail "worktree add failed: $(cat "$TMP/add1.out")"; }
if [ -f "$TMP/wt1/keystore.properties" ] && [ -f "$TMP/wt1/local.properties" ]; then
  if has_uchg "$TMP/wt1/keystore.properties"; then fail "the copied keystore.properties kept the user-immutable flag (it can no longer be deleted)"
  else ok "worktree add: the copied keystore carries no immutable flag"; fi
else fail "worktree add did not copy the ignored local config (the test set-up is wrong): $(cat "$TMP/add1.out")"; fi
has_uchg "$R/keystore.properties" && ok "the main checkout's own keystore keeps its flag" || fail "the main checkout's keystore lost its uchg flag"
bash "$KIT" worktree remove ../wt1 >"$TMP/rm1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt1" ] && [ "$(reg wt1)" = 0 ] && ok "worktree remove: the folder is gone and no registration is left" \
  || fail "worktree remove left the folder or its registration (rc=$rc, exists=$([ -e "$TMP/wt1" ] && echo yes || echo no), reg=$(reg wt1)): $(cat "$TMP/rm1.out")"
has_uchg "$R/keystore.properties" && ok "remove never touches the main checkout's flag" || fail "remove cleared the main checkout's uchg flag"

# 2b: a worktree made by OLDER code (copy2) holds an immutable ignored file
bash "$KIT" worktree add ../wt2 --no-init >/dev/null 2>&1 || fail "add wt2"
chflags uchg "$TMP/wt2/keystore.properties" 2>/dev/null
bash "$KIT" worktree remove ../wt2 >"$TMP/rm2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt2" ] && [ "$(reg wt2)" = 0 ] && ok "worktree remove: an immutable file left by an older version no longer strands the folder" \
  || fail "worktree with an immutable file survived remove (rc=$rc, reg=$(reg wt2)): $(cat "$TMP/rm2.out")"

# 3: something that really cannot be deleted must be an error, not "removed"
bash "$KIT" worktree add ../wt3 --no-init >/dev/null 2>&1 || fail "add wt3"
mkdir -p "$TMP/wt3/stuck" && echo x > "$TMP/wt3/stuck/ignored.out" && chmod 555 "$TMP/wt3/stuck"
bash "$KIT" worktree remove ../wt3 >"$TMP/rm3.out" 2>&1; rc=$?
if [ -e "$TMP/wt3" ]; then
  [ "$rc" != 0 ] && grep -q "wt3" "$TMP/rm3.out" && ! grep -q "^✔" "$TMP/rm3.out" && ok "a folder that survives is exit $rc and names the path, never 'removed'" \
    || fail "the folder survived but remove said success or named nothing (rc=$rc): $(cat "$TMP/rm3.out")"
else ok "worktree remove: even the read-only directory went (nothing left to report)"; fi
chmod -R u+rwX "$TMP/wt3" 2>/dev/null

# 4: git refuses (locked worktree): the user's flag on the file must still be there afterwards
bash "$KIT" worktree add ../wt4 --no-init >/dev/null 2>&1 || fail "add wt4"
chflags uchg "$TMP/wt4/keystore.properties" 2>/dev/null
G "$R" worktree lock "$TMP/wt4" 2>/dev/null
bash "$KIT" worktree remove ../wt4 >"$TMP/rm4.out" 2>&1; rc=$?
if [ "$rc" != 0 ] && [ -e "$TMP/wt4" ] && [ "$(reg wt4)" = 1 ]; then
  has_uchg "$TMP/wt4/keystore.properties" && ok "a removal git refuses leaves the user's uchg flag alone (unlock only after git commits)" \
    || fail "a REFUSED removal stripped the uchg flag (flags were unlocked before git committed to the removal)"
else fail "locked worktree: expected a refusal that keeps folder and registration (rc=$rc, reg=$(reg wt4)): $(cat "$TMP/rm4.out")"; fi
G "$R" worktree unlock "$TMP/wt4" 2>/dev/null

# 5: an ignored symlink to the main checkout's flagged keystore inside the worktree
bash "$KIT" worktree add ../wt5 --no-init >/dev/null 2>&1 || fail "add wt5"
ln -s "$R/keystore.properties" "$TMP/wt5/link-to-main-keystore"
bash "$KIT" worktree remove ../wt5 >"$TMP/rm5.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt5" ] && [ -f "$R/keystore.properties" ] && has_uchg "$R/keystore.properties" \
  && ok "a symlink to the main checkout's keystore is removed as a link: the main file exists and keeps its flag" \
  || fail "symlink to main's keystore (rc=$rc, main flag='$(flags "$R/keystore.properties")'): $(cat "$TMP/rm5.out")"

# 6: the worktree named through a symlink
bash "$KIT" worktree add ../wt6 --no-init >/dev/null 2>&1 || fail "add wt6"
ln -s wt6 "$TMP/link6"
bash "$KIT" worktree remove ../link6 >"$TMP/rm6.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt6" ] && [ "$(reg wt6)" = 0 ] && ok "remove through a symlink to the worktree still removes it" \
  || fail "remove through a symlink (rc=$rc, exists=$([ -e "$TMP/wt6" ] && echo yes || echo no)): $(cat "$TMP/rm6.out")"
rm -f "$TMP/link6"

# 7: worktree_sandbox.py copies .worktreeinclude files with cp -c (clonefile), which keeps the flag
SB="$DEVKIT_DIR/scripts/git/worktree_sandbox.py"; [ -f "$SB" ] || SB="$DEVKIT_DIR/scripts/worktree_sandbox.py"
printf 'keystore.properties\n' > "$R/.worktreeinclude"
python3 "$SB" create sb7 --port-offset 21 >"$TMP/sb7.out" 2>&1
if [ -f "$R/.sandboxes/sb7/keystore.properties" ]; then
  if has_uchg "$R/.sandboxes/sb7/keystore.properties"; then fail "worktree_sandbox.py copied the keystore WITH the uchg flag (the sandbox can never be cleaned)"
  else ok "worktree_sandbox.py: the copied keystore carries no immutable flag"; fi
else fail "sandbox did not copy the keystore (set-up wrong): $(tail -3 "$TMP/sb7.out")"; fi

# 7b: the same for a DIRECTORY in .worktreeinclude (cp -c -R and copytree's copy2 keep the flag too)
mkdir -p "$R/signing" && echo "jks" > "$R/signing/release.jks" && chflags uchg "$R/signing/release.jks"
printf 'signing\n' > "$R/.worktreeinclude"
python3 "$SB" create sb7b --port-offset 22 >"$TMP/sb7b.out" 2>&1
if [ -f "$R/.sandboxes/sb7b/signing/release.jks" ]; then
  if has_uchg "$R/.sandboxes/sb7b/signing/release.jks"; then fail "worktree_sandbox.py copied a signing DIRECTORY with the uchg flag on its files"
  else ok "worktree_sandbox.py: a copied directory carries no immutable flag"; fi
else fail "sandbox did not copy the signing directory (set-up wrong): $(tail -3 "$TMP/sb7b.out")"; fi
has_uchg "$R/signing/release.jks" && ok "  … and the main checkout's own jks keeps its flag" || fail "  … the main checkout's jks lost its flag"

# 8: `finish` on a folder git could not take away says the by-hand way out even when the reason is long (it was cut off at 600 chars)
bash "$KIT" worktree add ../wt8 --no-init >/dev/null 2>&1 || fail "add wt8"
printf 'stuck8/\n' >> "$R/.git/info/exclude"
mkdir -p "$TMP/wt8/stuck8"
for i in 1 2 3 4 5; do : > "$TMP/wt8/stuck8/$(printf 'n%.0s' $(seq 1 150))$i"; done
chmod 555 "$TMP/wt8/stuck8"
bash "$KIT" worktree finish ../wt8 >"$TMP/rm8.out" 2>&1; rc=$?
if [ -e "$TMP/wt8" ]; then
  [ "$rc" != 0 ] && grep -q "chflags -R nouchg" "$TMP/rm8.out" && grep -q "chmod -R u+rwX" "$TMP/rm8.out" \
    && ok "finish on an undeletable folder blocks (rc=$rc) and carries the full by-hand command (unlock, make writable, delete)" \
    || fail "finish: the by-hand command is missing or incomplete (rc=$rc): $(head -c 700 "$TMP/rm8.out")"
else ok "finish: even the read-only directory went (nothing left to report)"; fi
chmod -R u+rwX "$TMP/wt8" 2>/dev/null

# 9: a copied keystore is never readable by others, not even while it is being written (shutil.copy creates the file with the
# umask's mode and fixes it afterwards: the mode is recorded at the moment copymode runs)
python3 - "$DEVKIT_DIR" "$TMP" "$R" <<'PY' >"$TMP/mode9.out" 2>&1
import os, shutil, stat, sys
dk, tmp, main = sys.argv[1:4]
sys.path[:0] = [os.path.join(dk, "scripts", "git"), os.path.join(dk, "scripts")]
import worktree as w, worktree_sandbox as sb
src = os.path.join(tmp, "k9"); open(src, "w").write("x"); os.chmod(src, 0o600)
seen = []
orig = shutil.copymode
def spy(s, d, **kw):
    seen.append(stat.S_IMODE(os.stat(d).st_mode)); return orig(s, d, **kw)
shutil.copymode = spy
os.umask(0o022)
from pathlib import Path
sb.copy_with_apfs_cow(Path(src), Path(tmp) / "out9-sandbox")
wt9 = os.path.join(tmp, "wt9")
os.system(f"git -C '{main}' worktree add -q --detach '{wt9}' >/dev/null 2>&1")
w._copy(main, wt9, "keystore.properties")   # the mode recorded is the one the file has BEFORE copymode: the umask's, unless the copy is made private
print("modes at copymode time:", [oct(m) for m in seen])
sys.exit(0 if len(seen) == 2 and all(m & 0o077 == 0 for m in seen) else 1)
PY
if [ "$?" = 0 ]; then ok "copies of a keystore are created private (no group/other bits, even before copymode runs)"
else fail "a keystore copy is briefly created with the umask's mode (group/other readable): $(cat "$TMP/mode9.out")"; fi

if [ "$FAILS" -ne 0 ]; then echo "worktree immutable copy: $FAILS FAILED"; exit 1; fi
echo "worktree immutable copy: all checks passed"
