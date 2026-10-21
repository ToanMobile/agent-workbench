#!/usr/bin/env bash
# Regression test: the environment the gate gives a test suite (bin/post-fix-gate.py suite_env) carries none of
# the variables `git commit` sets for its hook:
#   - where the repository is: GIT_INDEX_FILE, GIT_DIR, GIT_WORK_TREE ... (2026-09-28: a suite that built scratch
#     repos wrote into the commit's own index);
#   - config injected with `git -c k=v` (GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT/KEY_n/VALUE_n): it outranks a scratch
#     repo's own user.name / user.email;
#   - who the author is: GIT_AUTHOR_*, GIT_COMMITTER_* (2026-10-03: inside `git commit`, tests/gates/
#     test_gate_friction.sh could no longer tell a teammate's commit from ours, because the identity came from the
#     environment and not from each scratch repo's config, so the pre-commit gate REJECTed a clean commit while the
#     same suite passed everywhere else).
# Everything else (PATH, HOME, the caller's own variables) must still reach the suite.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# probe <NAME=value>… → the names suite_env() keeps, one per line, when those variables are set
probe() {
  env "$@" python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print("\n".join(sorted(mod.suite_env())))
PY
}

kept="$(probe GIT_INDEX_FILE=/nowhere/index GIT_DIR=/nowhere/.git GIT_WORK_TREE=/nowhere GIT_PREFIX=sub/ \
  GIT_COMMON_DIR=/nowhere/.git GIT_AUTHOR_NAME=Hook GIT_AUTHOR_EMAIL=hook@example.invalid GIT_AUTHOR_DATE=1700000000 \
  GIT_COMMITTER_NAME=Hook GIT_COMMITTER_EMAIL=hook@example.invalid GIT_COMMITTER_DATE=1700000000 \
  GIT_CONFIG_PARAMETERS="'user.name=Q'" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=Q DEVKIT_PROBE_KEEP=1)" \
  || { echo "✖ could not import $GATE"; exit 1; }
[ -n "$kept" ] || { echo "✖ suite_env() returned nothing"; exit 1; }

for v in GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR; do
  printf '%s\n' "$kept" | grep -qx "$v" && fail "suite_env keeps $v (where the repository is)" || ok "suite_env drops $v"
done
for v in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE; do
  printf '%s\n' "$kept" | grep -qx "$v" && fail "suite_env keeps $v (who the author is)" || ok "suite_env drops $v"
done
# `git -c user.name=Q commit` reaches its hook as GIT_CONFIG_PARAMETERS; it outranks every scratch repo's own config
for v in GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
  printf '%s\n' "$kept" | grep -qx "$v" && fail "suite_env keeps $v (config injected with git -c)" || ok "suite_env drops $v"
done
for v in PATH HOME DEVKIT_PROBE_KEEP; do
  printf '%s\n' "$kept" | grep -qx "$v" && ok "suite_env keeps $v" || fail "suite_env lost $v"
done

# The caller's own gate switches are for THIS gate run, not for the suites it starts (2026-10-16: the super-board
# runner exports DEVKIT_ALLOW_BRANCH=1 to its workers, so REG-DK-HOOK-01 saw "checkout -b blocked want=2 got=0"; a
# worker's POSTFIX_GATE_FORCE_FULL=1 turned test_busy_keeps_receipt's partial-run controls into full runs; both reds
# made every merge-gate verify exit 2 and parked reviewed cards in Blocked).
switches="$(probe DEVKIT_ALLOW_BRANCH=1 WORKTREE_MERGE_GATE=0 POSTFIX_GATE_FORCE_FULL=1 POSTFIX_GATE_FULL=1 DEVKIT_GATE_MERGE_CHECK=1 DEVKIT_PROBE_KEEP=1)"
printf '%s\n' "$switches" | grep -qx DEVKIT_PROBE_KEEP || { echo "✖ switch probe returned no environment"; exit 1; }
# DEVKIT_GATE_MERGE_CHECK (#154): the merge gate of `worktree finish` — a gate a suite starts on its own scratch repo is never one
for v in DEVKIT_ALLOW_BRANCH WORKTREE_MERGE_GATE POSTFIX_GATE_FORCE_FULL POSTFIX_GATE_FULL DEVKIT_GATE_MERGE_CHECK; do
  printf '%s\n' "$switches" | grep -qx "$v" && fail "suite_env keeps $v (the caller's gate switch)" || ok "suite_env drops $v"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_suite_env: all passed" || { echo "❌ test_suite_env: $FAILS failed"; exit 1; }
