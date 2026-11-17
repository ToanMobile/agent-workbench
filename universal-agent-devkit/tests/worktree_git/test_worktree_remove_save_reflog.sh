#!/usr/bin/env bash
# #1234: `worktree remove --save-reflog` — a worktree whose ONLY blocker is UNREACHABLE (commits only the reflog names, e.g. QA evidence v1
# replaced by v2) is removed after the commits are kept under refs/devkit/discarded/*. Any other blocker still refuses.
#   A. clean worktree, 1 reflog-only commit: plain remove refuses (UNREACHABLE); --save-reflog removes it, commit reachable from a discarded ref
#   B. --save-reflog + a really modified tracked file: refused, kept
#   C. --save-reflog + a merge in progress (busy): refused, kept
#   D. no flag: refused as before, nothing changed (also a detached HEAD that is itself unheld stays refused with the flag)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

git init -q --bare -b main "$TMP/origin.git"
R="$TMP/rd"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true; G "$R" remote add origin "$TMP/origin.git"
printf 'a1\n' > a.txt; printf 'c\n' > c.txt
G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
mk() { bash "$KIT" worktree add "../$1" >/dev/null 2>&1 || fail "add $1"; }
# a commit only the reflog names: commit on the detached HEAD, then go back to the integrated base
lone() { G "$TMP/$1" checkout -q --detach; printf "$1\n" > "$TMP/$1/lone.txt"; G "$TMP/$1" add lone.txt; G "$TMP/$1" commit -qm "lone $1"
         G "$TMP/$1" rev-parse HEAD > "$TMP/$1.sha"; G "$TMP/$1" reset -q --hard main; }
mk w-a; mk w-b; mk w-c; mk w-d; mk w-e; lone w-a; lone w-b; lone w-c; lone w-d

bash "$KIT" worktree remove ../w-a >"$TMP/a1.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-a" ] && grep -q UNREACHABLE "$TMP/a1.out" && ok "A1 plain remove refuses UNREACHABLE (rc=$rc)" || { fail "A1 (rc=$rc)"; cat "$TMP/a1.out"; }
bash "$KIT" worktree remove --save-reflog ../w-a >"$TMP/a2.out" 2>&1; rc=$?
SHA=$(cat "$TMP/w-a.sha"); kept=0
for r in $(G "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/*'); do G "$R" merge-base --is-ancestor "$SHA" "$r" 2>/dev/null && kept=1; done
[ "$rc" = 0 ] && [ ! -d "$TMP/w-a" ] && [ "$kept" = 1 ] && ok "A2 --save-reflog removes it, commit reachable from refs/devkit/discarded (rc=$rc)" || { fail "A2 (rc=$rc kept=$kept)"; cat "$TMP/a2.out"; }

printf 'edited\n' > "$TMP/w-b/c.txt"
bash "$KIT" worktree remove --save-reflog ../w-b >"$TMP/b.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-b" ] && [ "$(cat "$TMP/w-b/c.txt")" = edited ] && ok "B modified tracked file still refused (rc=$rc)" || { fail "B (rc=$rc)"; cat "$TMP/b.out"; }

# C: merge in progress (conflict)
G "$TMP/w-c" checkout -q -b side main; printf 's\n' > "$TMP/w-c/c.txt"; G "$TMP/w-c" commit -qam side
G "$TMP/w-c" checkout -q --detach main; printf 'm\n' > "$TMP/w-c/c.txt"; G "$TMP/w-c" commit -qam other
G "$TMP/w-c" merge side >/dev/null 2>&1
G "$TMP/w-c" rev-parse -q --verify MERGE_HEAD >/dev/null || fail "C setup: no merge in progress"
bash "$KIT" worktree remove --save-reflog ../w-c >"$TMP/c.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-c" ] && ok "C merge in progress still refused (rc=$rc)" || { fail "C (rc=$rc)"; cat "$TMP/c.out"; }

bash "$KIT" worktree remove ../w-d >"$TMP/d.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-d" ] && grep -q UNREACHABLE "$TMP/d.out" && [ -z "$(G "$R" for-each-ref 'refs/devkit/discarded/*' | grep -c w-d | grep -v '^0$')" ] \
  && ok "D no flag: refused, kept (rc=$rc)" || { fail "D (rc=$rc)"; cat "$TMP/d.out"; }

# E: detached HEAD sits on a commit no ref holds (real work, not a replaced one): the flag must NOT drop it
G "$TMP/w-e" checkout -q --detach; printf 'real\n' > "$TMP/w-e/real.txt"; G "$TMP/w-e" add real.txt; G "$TMP/w-e" commit -qm "real work"
bash "$KIT" worktree remove --save-reflog ../w-e >"$TMP/e.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-e" ] && [ -f "$TMP/w-e/real.txt" ] && ok "E detached HEAD on an unheld commit still refused with the flag (rc=$rc)" || { fail "E (rc=$rc)"; cat "$TMP/e.out"; }

[ "$FAILS" -eq 0 ] && { echo "✅ test_worktree_remove_save_reflog: all passed"; exit 0; }
echo "❌ test_worktree_remove_save_reflog: $FAILS failed"; exit 1
