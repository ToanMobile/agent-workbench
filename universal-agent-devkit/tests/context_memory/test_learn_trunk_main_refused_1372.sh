#!/usr/bin/env bash
# Regression (#1372, 19/11): in trunk mode the main checkout is merge-only. `agent-kit learn` run from the main checkout wrote its lesson into main's tracked
# .agents/instincts.md and left it dirty, so `git merge --ff-only origin/main` failed and the board runner reloaded only super-board-run.sh ("self-reload:
# main stays 7e242e3, behind origin/main"). Now the default instincts.md of a trunk-mode MAIN checkout is refused (exit 2, nothing written):
#  A: devkit.trunkMode=true (agent-kit worktree trunk on) + main checkout -> refused, main's file untouched, git status clean
#  F: no devkit.trunkMode key                            -> still written (a main session writes to main, test_learn_worktree_root)
#  B: devkit.trunkMode=false                             -> still written
#  C: WORKTREE_TRUNK_MODE=0                              -> still written
#  D: --dry-run in a trunk-mode main checkout            -> allowed (nothing is written)
#  E: an explicit --file elsewhere                       -> allowed (only the default file is guarded)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset TARGET_DIR WORKTREE_TRUNK_MODE
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_main() {   # new_main <dir>: a main checkout with a tracked instincts.md
  mkdir -p "$1/.agents" && cd "$1" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf '# instincts\n' > .agents/instincts.md
  git add -A && git commit -qm init
}

# A
new_main "$TMP/a"; git config devkit.trunkMode true
export CLAUDE_PROJECT_DIR="$TMP/a"
out="$(bash "$KIT" learn "Trunk lesson A" --cause c --rule r 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "A: learn in a trunk-mode main checkout is refused (rc=$rc)" || fail "A: learn was accepted (rc=0): $out"
[ "$(cat .agents/instincts.md)" = "# instincts" ] && ok "A: main's instincts.md is untouched" || fail "A: main's instincts.md was modified"
[ -z "$(git status --porcelain)" ] && ok "A: main stays clean" || fail "A: main is dirty: $(git status --porcelain)"
printf '%s' "$out" | grep -qiE 'trunk|worktree' && ok "A: the message names trunk mode / a worktree" || fail "A: message does not explain: $out"

# B
new_main "$TMP/b"; git config devkit.trunkMode false
export CLAUDE_PROJECT_DIR="$TMP/b"
bash "$KIT" learn "Trunk lesson B" --cause c --rule r >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'Trunk lesson B' .agents/instincts.md; } && ok "B: devkit.trunkMode=false still writes" || fail "B: not written (rc=$rc)"

# F: a repo that never switched trunk mode on keeps the old behaviour (a main session writes to main)
new_main "$TMP/f"
export CLAUDE_PROJECT_DIR="$TMP/f"
bash "$KIT" learn "Trunk lesson F" --cause c --rule r >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'Trunk lesson F' .agents/instincts.md; } && ok "F: no devkit.trunkMode key -> still written (old behaviour)" || fail "F: not written (rc=$rc)"

# C
new_main "$TMP/c"; git config devkit.trunkMode true
export CLAUDE_PROJECT_DIR="$TMP/c"
WORKTREE_TRUNK_MODE=0 bash "$KIT" learn "Trunk lesson C" --cause c --rule r >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'Trunk lesson C' .agents/instincts.md; } && ok "C: WORKTREE_TRUNK_MODE=0 still writes" || fail "C: not written (rc=$rc)"

# D
new_main "$TMP/d"; git config devkit.trunkMode true
export CLAUDE_PROJECT_DIR="$TMP/d"
bash "$KIT" learn "Trunk lesson D" --cause c --rule r --dry-run >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$(git status --porcelain)" ]; } && ok "D: --dry-run is allowed and writes nothing" || fail "D: dry-run rc=$rc status=$(git status --porcelain)"

# E
new_main "$TMP/e"; git config devkit.trunkMode true
export CLAUDE_PROJECT_DIR="$TMP/e"
bash "$KIT" learn "Trunk lesson E" --cause c --rule r --file "$TMP/elsewhere.md" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q 'Trunk lesson E' "$TMP/elsewhere.md"; } && ok "E: an explicit --file elsewhere is allowed" || fail "E: not written (rc=$rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_learn_trunk_main_refused_1372: PASS"; exit 0; } || { echo "test_learn_trunk_main_refused_1372: FAIL ($FAILS)"; exit 1; }
