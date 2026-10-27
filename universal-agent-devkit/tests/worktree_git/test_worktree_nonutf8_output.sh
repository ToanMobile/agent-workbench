#!/usr/bin/env bash
# worktree.py read every git output as strict UTF-8 (subprocess text=True). A commit whose content holds a byte that is not
# UTF-8 (a Latin-1 file, a binary-ish fixture) made `git show --cc` in _clean_merges raise UnicodeDecodeError, and the Stop
# hook worktree_merge_gate.sh then held EVERY worktree with "gate error: UnicodeDecodeError … byte 0xe1" (2026-10-26): the
# automatic merge of all agent worktrees stopped. _clean_merges reads that diff as bytes. git()'s text decode stays STRICT: a
# non-UTF-8 PATH must still make removal refuse (a global surrogateescape made `remove` delete an index-only entry with such a
# name on APFS — review 26/10; tests/worktree_git/test_worktree_remove_safety.sh guards that side).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R"
G() { git -C "$R" -c user.email=t@example.invalid -c user.name=t "$@"; }
G init -q -b main
printf 'base\n' > "$R/f.txt"; G add f.txt; G commit -qm base
G checkout -q -b side; printf 'side\n' > "$R/f.txt"; G commit -qam side
G checkout -q main; printf 'main\n' > "$R/f.txt"; G commit -qam main
G merge -q side >/dev/null 2>&1
printf 'caf\xe1 latin-1 resolution\n' > "$R/f.txt"; G add f.txt; G commit -qm "merge with a non-UTF-8 resolution"
merge="$(G rev-parse HEAD)"

out="$(python3 - "$DEVKIT_DIR/scripts/git" "$R" "$merge" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import worktree as wt
repo, sha = sys.argv[2], sys.argv[3]
r = wt._git_bytes(repo, "show", "--format=", sha)
print("show-rc", r.returncode, "has-byte", b"\xe1" in r.stdout)
print("clean", sorted(wt._clean_merges(repo, {sha})))
try:   # the strict side stays strict: text git output with that byte still raises (the removal checks rely on it)
    wt.git(repo, "show", "--format=", sha, check=False)
    print("strict", "no-raise")
except UnicodeDecodeError:
    print("strict", "raises")
PY
)"
case "$out" in *Traceback*) fail "a non-UTF-8 byte crashed the check: $(echo "$out" | tail -1)" ;; esac
echo "$out" | grep -q "show-rc 0 has-byte True" && ok "_git_bytes returns the diff with the 0xe1 byte" \
  || fail "_git_bytes output wrong: $out"
echo "$out" | grep -qx "strict raises" && ok "git()'s text decode stays strict (removal refuses on a non-UTF-8 path)" \
  || fail "git() no longer strict: $out"
# The resolution edits the file, so `show --cc` prints a hunk: the merge is NOT a clean merge (nothing is vouched for).
echo "$out" | grep -qx "clean \[\]" && ok "_clean_merges judges the merge (has a hunk: not clean) instead of crashing" \
  || fail "_clean_merges: $out"

# The HEAD reflog keeps the raw bytes of a `git commit -m` message: a Latin-1 subject made _reflog_only's text `git log -g` raise
# UnicodeDecodeError, its caller turned that into "reflog could not be read" and HELD a worktree whose commits main already has
# (review 26/10). That one read is bytes, decoded with "replace" (only the subject is read from it, never a path).
G worktree add -q --detach "$R/.claude/worktrees/latin" main
printf 'caf\351 latin-1 subject\n' > "$TMP/msg"
git -C "$R/.claude/worktrees/latin" -c user.email=t@example.invalid -c user.name=t -c i18n.commitEncoding=ISO-8859-1 commit -q --allow-empty -F "$TMP/msg"
LAT="$(git -C "$R/.claude/worktrees/latin" rev-parse HEAD)"
G merge -q --ff-only "$LAT"
git -C "$R/.claude/worktrees/latin" log -g --format=%gs HEAD | LC_ALL=C grep -q "$(printf 'caf\351')" \
  && ok "setup: the worktree's HEAD reflog holds the Latin-1 byte" || fail "setup: no Latin-1 byte in the HEAD reflog"
(cd "$R" && DEVKIT_LANG=en python3 "$DEVKIT_DIR/scripts/git/worktree.py" remove "$R/.claude/worktrees/latin" >"$TMP/latin.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$R/.claude/worktrees/latin" ] && ! grep -qi "reflog" "$TMP/latin.out" \
  && ok "a worktree whose reflog has a Latin-1 subject and whose commits main holds is removed (not held as an unreadable reflog)" \
  || fail "Latin-1 reflog subject: remove rc=$rc: $(tail -3 "$TMP/latin.out")"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
