#!/usr/bin/env bash
# Regression test (issue #5) for bin/push_gate.py in Trunk Mode: the gate runs in a linked worktree and writes its receipt under
# <common>/worktrees/<name>/postfix-gate/, the work is merged into main, and `git push` from main looked only at <common>/postfix-gate/.
#  L1 a receipt of a linked worktree whose head is in the history of main's pushed commit (ff merge) covers the push.
#  L2 an ungated commit made on main after that merge is still refused.
#  L3 a linked worktree whose receipt head is NOT in the pushed history covers nothing.
#  L4 a forged receipt in a linked worktree (invented fingerprint) is refused like one in main.
#  L5/L6 a linked worktree whose folder is gone, or that has no regression matrix, vouches for nothing.
#  L7 the issue's own flow: gate in the worktree, `worktree finish` merges it into main and REMOVES it (its git dir and receipt go
#     with it): the push from main is still covered. L8 an ungated commit on main after that is refused.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"; W="$TMP/wt"
expect() {   # expect <name> <exit> [text the output must contain]
  OUT="$(python3 "$PG" "$R" 2>&1)"; RC=$?
  if [ "$RC" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$OUT" | grep -qF -- "$3"; }; then ok "$1 (exit $RC)"
  else bad "$1: exit $RC, expected $2${3:+ with \"$3\"} — $(printf '%s' "$OUT" | head -c 300)"; fi
}
newrepo() {
  git -C "$R" worktree prune 2>/dev/null; rm -rf "$R" "$W" "$TMP/origin.git"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > .gitignore   # gate bookkeeping
  git add -A && git commit -qm init
  git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
  git worktree add -q -b task "$W" main
}
gated_worktree_commit() {   # edit code in the worktree, run the full gate there, commit
  echo "fun ok() = $1" > "$W/src/Core.kt"
  CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief > "$TMP/gate.out" 2>&1 \
    || bad "setup: gate --full in the worktree failed (exit $?): $(tail -3 "$TMP/gate.out")"
  git -C "$W" commit -qam "task work $1"
}

newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task
expect "L1: worktree gated, merged ff into main: the push from main is covered" 0

echo "fun ok() = 3" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main"
expect "L2: an ungated commit on main after the merge is refused" 2

newrepo
gated_worktree_commit 2
git -C "$W" commit -q --amend -m "reworded"; echo "fun ok() = 9" > "$W/src/Core.kt"; git -C "$W" commit -qam "changed after gate"
git -C "$R" merge -q --ff-only task
expect "L3: code changed in the worktree after its gate: refused" 2

newrepo
gated_worktree_commit 2
RW="$(git -C "$W" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
python3 - "$RW" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r["fingerprint"] = "0123456789abcdef01234567"; json.dump(r, open(sys.argv[1], "w"))
PY
git -C "$R" merge -q --ff-only task
expect "L4: a forged worktree receipt (invented fingerprint): refused" 2

# A linked worktree with no receipt must never vouch for main: its own early "nothing to check" answers are not coverage.
newrepo
echo "fun ok() = 4" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main"; rm -rf "$W"
expect "L5: a linked worktree whose folder is gone (prunable) does not cover an ungated push" 2

newrepo
git -C "$W" rm -q .agents/regression_matrix.active.json && git -C "$W" commit -qm "no matrix on this branch"
echo "fun ok() = 5" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main"
expect "L6: a linked worktree without a regression matrix does not cover an ungated push" 2

newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L7 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
[ -d "$W" ] && bad "L7 setup: worktree finish left the worktree in place: $(tail -3 "$TMP/finish.out")"
expect "L7: worktree gated, then merged and removed by worktree finish: the push from main is covered" 0

echo "fun ok() = 6" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main"
expect "L8: an ungated commit on main after worktree finish is refused" 2

# the next task: main keeps the (now stale) receipt the first finish carried; a new worktree gated and merged by hand still covers
newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L9 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
git -C "$R" worktree add -q -b task2 "$W" main
gated_worktree_commit 7
git -C "$R" merge -q --ff-only task2
expect "L9: main holds a stale valid receipt, a linked worktree's receipt covers the new head: the push is covered" 0

[ "$FAILS" = 0 ] && echo "ALL OK" && exit 0
echo "$FAILS FAILED"; exit 1
