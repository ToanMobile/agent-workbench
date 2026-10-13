#!/usr/bin/env bash
# Regression (GeelyEx2, 2026-10-13: seven unregistered worktree folders, 150-200 MB each, left in /Volumes/Data/Toan):
# a keystore the user locked with `chflags uchg` (macOS user-immutable flag) was copied into every worktree by
# `worktree add` with shutil.copy2, which copies the flags too. The copy could then not be deleted: `git worktree remove --force`
# only WARNS, drops its own registration and exits 0, so `worktree remove` printed "removed", the folder stayed, no guard
# listed it, and the next session could not reuse the name (push-1013, -1013b, -1013c).
#   1  `worktree add` copies the ignored local config WITHOUT the immutable flag (the main checkout's own file keeps it)
#   2  `worktree remove` takes the folder away, also when a worktree made by older code holds an immutable file
#   3  a folder that cannot be taken away is an error (exit 1, the path named), never "removed"
# macOS only (chflags); elsewhere the test says it was not run.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
if ! command -v chflags >/dev/null 2>&1; then echo "SKIPPED (no chflags): immutable-copy test NOT RUN - macOS only"; echo "worktree immutable copy: SKIPPED - NOT RUN"; exit 0; fi
TMP="$(cd "$(mktemp -d)" && pwd -P)"
# a RED run leaves undeletable files behind: unlock before rm, or /tmp fills up with them
trap 'chflags -R nouchg "$TMP" 2>/dev/null; chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
flags() { stat -f %Sf "$1" 2>/dev/null; }   # "uchg" or "-"

R="$TMP/main"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
printf 'keystore.properties\nlocal.properties\n' > .gitignore
echo tracked > a.txt; G "$R" add -A && G "$R" commit -qm init
echo "storePassword=x" > keystore.properties; echo "sdk.dir=/x" > local.properties
chflags uchg keystore.properties
case "$(flags keystore.properties)" in *uchg*) ;; *) echo "SKIPPED (this filesystem keeps no uchg flag): NOT RUN"; echo "worktree immutable copy: SKIPPED - NOT RUN"; exit 0 ;; esac

# 1 + 2: add, then remove
bash "$KIT" worktree add ../wt1 --no-init >"$TMP/add1.out" 2>&1 || { fail "worktree add failed: $(cat "$TMP/add1.out")"; }
if [ -f "$TMP/wt1/keystore.properties" ] && [ -f "$TMP/wt1/local.properties" ]; then
  case "$(flags "$TMP/wt1/keystore.properties")" in
    *uchg*) fail "the copied keystore.properties kept the user-immutable flag (it can no longer be deleted)" ;;
    *) ok "worktree add: the copied keystore carries no immutable flag" ;;
  esac
else fail "worktree add did not copy the ignored local config (the test set-up is wrong): $(cat "$TMP/add1.out")"; fi
case "$(flags "$R/keystore.properties")" in *uchg*) ok "the main checkout's own keystore keeps its flag" ;; *) fail "the main checkout's keystore lost its uchg flag" ;; esac
bash "$KIT" worktree remove ../wt1 >"$TMP/rm1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt1" ] && ok "worktree remove: the folder is gone and no registration is left" \
  || fail "worktree remove left the folder (rc=$rc, exists=$([ -e "$TMP/wt1" ] && echo yes || echo no)): $(cat "$TMP/rm1.out")"
case "$(flags "$R/keystore.properties")" in *uchg*) ok "remove never touches the main checkout's flag" ;; *) fail "remove cleared the main checkout's uchg flag" ;; esac

# 2b: a worktree made by OLDER code (copy2) holds an immutable ignored file
bash "$KIT" worktree add ../wt2 --no-init >/dev/null 2>&1 || fail "add wt2"
chflags uchg "$TMP/wt2/keystore.properties" 2>/dev/null
bash "$KIT" worktree remove ../wt2 >"$TMP/rm2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt2" ] && ok "worktree remove: an immutable file left by an older version no longer strands the folder" \
  || fail "worktree with an immutable file survived remove (rc=$rc): $(cat "$TMP/rm2.out")"

# 3: something that really cannot be deleted must be an error, not "removed"
bash "$KIT" worktree add ../wt3 --no-init >/dev/null 2>&1 || fail "add wt3"
mkdir -p "$TMP/wt3/stuck" && echo x > "$TMP/wt3/stuck/ignored.out" && chmod 555 "$TMP/wt3/stuck"
printf 'stuck/\n' >> "$(G "$R" rev-parse --git-common-dir)/info/exclude"
bash "$KIT" worktree remove ../wt3 >"$TMP/rm3.out" 2>&1; rc=$?
if [ -e "$TMP/wt3" ]; then
  [ "$rc" != 0 ] && grep -q "wt3" "$TMP/rm3.out" && ! grep -q "^✔" "$TMP/rm3.out" && ok "a folder that survives is exit $rc and names the path, never 'removed'" \
    || fail "the folder survived but remove said success or named nothing (rc=$rc): $(cat "$TMP/rm3.out")"
else ok "worktree remove: even the read-only directory went (nothing left to report)"; fi
chmod -R u+rwX "$TMP/wt3" 2>/dev/null

if [ "$FAILS" -ne 0 ]; then echo "worktree immutable copy: $FAILS FAILED"; exit 1; fi
echo "worktree immutable copy: all checks passed"
