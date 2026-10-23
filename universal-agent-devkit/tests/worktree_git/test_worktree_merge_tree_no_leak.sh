#!/usr/bin/env bash
# #309: a `git merge-tree --write-tree` probe killed by its time budget while an external merge driver (the matrix driver) runs left
# 3 `.merge_file_*` temp files in git's cwd = the repo's working tree. The probe must run with a scratch cwd, and still reach the
# same verdict (the driver still applies) when it finishes in time.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$TMP/main" -c user.email=t@t -c user.name=t "$@"; }

git init -q -b main "$TMP/main"
echo '*.json merge=mx' > "$TMP/main/.gitattributes"; echo '{"a":1}' > "$TMP/main/m.json"; G add -A; G commit -qm base
G checkout -q -b side; echo '{"a":2}' > "$TMP/main/m.json"; G commit -qam side
G checkout -q main; echo '{"a":3}' > "$TMP/main/m.json"; G commit -qam main
MAIN_HEAD=$(G rev-parse HEAD); SIDE=$(G rev-parse side)

probe() {   # probe <git timeout s>: prints the verdict of _adds_nothing_to_main (main, main HEAD, side)
  (cd "$TMP/main" && DEVKIT_WORKTREE_GIT_TIMEOUT_S="$1" python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wt", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m._adds_nothing_to_main(sys.argv[2], sys.argv[3], sys.argv[4]))' "$WT" "$TMP/main" "$MAIN_HEAD" "$SIDE")
}
leaks() { find "$TMP/main" -maxdepth 1 -name '.merge_file_*' | wc -l | tr -d ' '; }

# 1. slow driver, probe killed: nothing left in the working tree (RED before the fix: 3 files)
G config merge.mx.driver 'sleep 5'
probe 1 > /dev/null
n=$(leaks)
[ "$n" = 0 ] && ok "killed merge-tree leaves no .merge_file_* in the working tree" || fail "killed merge-tree left $n .merge_file_* file(s) in the working tree"

# 2. fast driver keeping main's side: the verdict is unchanged (the worktree adds nothing to main)
G config merge.mx.driver 'true'
v=$(probe 20)
[ "$v" = True ] && ok "the driver still applies: an integrated worktree is still recognised" || fail "verdict with a fast driver was '$v', expected True"
[ "$(leaks)" = 0 ] && ok "a finished probe leaves no files either" || fail "a finished probe left .merge_file_* files"

# 4. heal sweeps the leftovers of earlier kills: untracked top-level .merge_file_* older than 10 minutes, nothing else
for n in aaaaaa bbbbbb; do echo '{}' > "$TMP/main/.merge_file_$n"; done
echo '{}' > "$TMP/main/.merge_file_new123"; echo keep > "$TMP/main/notes.merge_file_aaaaaa"
touch -t 202001010000 "$TMP/main/.merge_file_aaaaaa" "$TMP/main/.merge_file_bbbbbb" "$TMP/main/notes.merge_file_aaaaaa"
(cd "$TMP/main" && python3 "$WT" heal > "$TMP/heal.out" 2>&1)
{ [ ! -e "$TMP/main/.merge_file_aaaaaa" ] && [ ! -e "$TMP/main/.merge_file_bbbbbb" ]; } && ok "heal removes old untracked .merge_file_*" || fail "heal left old .merge_file_* files: $(cat "$TMP/heal.out")"
[ -e "$TMP/main/.merge_file_new123" ] && ok "a file younger than 10 minutes stays (a driver may still be writing it)" || fail "heal removed a fresh .merge_file_*"
[ -e "$TMP/main/notes.merge_file_aaaaaa" ] && ok "a file that only contains the name stays" || fail "heal removed an unrelated file"
[ "$FAILS" = 0 ]
