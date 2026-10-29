#!/usr/bin/env bash
# #607 QA P2: with no count of worktrees the add lock must stay. Four `worktree add` of the same path at once give exactly one
# success and one registration; with the lock dropped 3 of 12 rounds gave 2 of each.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

for round in 1 2 3 4 5 6 7 8 9 10 11 12; do
  r="$TMP/r$round"; mkdir -p "$r" && G "$r" init -q -b main . && echo base > "$r/app.txt" && G "$r" add -A && G "$r" commit -qm base
  for i in 1 2 3 4; do
    (cd "$r" && env -u WORKTREE_MAX WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add "$r-wt" --no-init > "$r.out$i" 2>&1; echo $? > "$r.rc$i") &
  done
  wait
  okc=$(cat "$r".rc* | grep -cx 0)
  reg=$(G "$r" worktree list --porcelain | grep -c "^worktree $r-wt\$")
  [ "$okc" = 1 ] && [ "$reg" = 1 ] || { fail "round $round: $okc successes and $reg registrations of one path (want 1 and 1)"; tail -n 2 "$r".out*; }
done
[ "$FAILS" -eq 0 ] && ok "12 rounds of 4 concurrent adds of one path: one success, one registration each"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_add_race: PASS"; exit 0; } || { echo "test_worktree_add_race: FAIL ($FAILS)"; exit 1; }
