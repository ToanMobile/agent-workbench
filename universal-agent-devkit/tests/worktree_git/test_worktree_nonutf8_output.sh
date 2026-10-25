#!/usr/bin/env bash
# worktree.py read every git output as strict UTF-8 (subprocess text=True). A commit whose content holds a byte that is not
# UTF-8 (a Latin-1 file, a binary-ish fixture) made `git show --cc` in _clean_merges raise UnicodeDecodeError, and the Stop
# hook worktree_merge_gate.sh then held EVERY worktree with "gate error: UnicodeDecodeError … byte 0xe1" (2026-10-26): the
# automatic merge of all agent worktrees stopped. Git output is decoded with surrogateescape: no byte is lost, nothing raises.
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
r = wt.git(repo, "show", "--format=", sha, check=False)
print("show-rc", r.returncode, "has-byte", "\udce1" in r.stdout)
print("clean", sorted(wt._clean_merges(repo, {sha})))
PY
)"
case "$out" in *UnicodeDecodeError*) fail "git output with a non-UTF-8 byte raises UnicodeDecodeError: $(echo "$out" | tail -1)" ;; esac
echo "$out" | grep -q "show-rc 0 has-byte True" && ok "git() returns the output, the 0xe1 byte kept (surrogateescape)" \
  || fail "git() output wrong: $out"
# The resolution edits the file, so `show --cc` prints a hunk: the merge is NOT a clean merge (nothing is vouched for).
echo "$out" | grep -qx "clean \[\]" && ok "_clean_merges judges the merge (has a hunk: not clean) instead of crashing" \
  || fail "_clean_merges: $out"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
