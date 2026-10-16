# tests/lib/clean_git_env.sh — source this FIRST in every test that runs git (the ratchet in
# tests/verification/test_git_env_isolation.sh enforces it).
#
# git exports GIT_* variables to its hooks and honours them for EVERY repository it touches: a test that builds
# scratch repos with GIT_INDEX_FILE set (a pre-commit run, or a hand-run copy-pasted from one) writes its files
# into that index — on 2026-10-03 that destroyed the workbench's own index (repair: `git read-tree HEAD`); an
# inherited GIT_AUTHOR_* / GIT_COMMITTER_* / `git -c` config gives every scratch commit the same identity and
# made tests/gates/test_gate_friction.sh fail only inside `git commit`. bin/post-fix-gate.py suite_env() clears
# the same set for the suites it starts; this file covers a test run by hand or by agent-kit.
# bash 3.2 compatible; sourced, so it must not set options or exit.
for _v in GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
          GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE \
          GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT \
          POSTFIX_GATE_FORCE_FULL WORKTREE_MERGE_GATE DEVKIT_ALLOW_BRANCH; do
  unset "$_v"
done
for _v in $(env | grep -E '^GIT_CONFIG_(KEY|VALUE)_[0-9]+=' | cut -d= -f1); do unset "$_v"; done
unset _v
# Host policy a test must not inherit (W1 R5c): on a host under 10 GiB free every `worktree add` would run gc over the test's own
# fixture siblings, and under 3 GiB refuse. tests/worktree_git/test_worktree_limits.sh sets these itself.
export WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 WORKTREE_MAX=0
# The user's own ~/.antigravity-pm.json must not steer a test: `giaoDefault: true` there makes the prompt hook add the standing "GIAO MẶC ĐỊNH BẬT"
# order to every prompt it sees (2026-10-14). A test that wants a flag sets this variable itself after sourcing. The path can never hold
# a file (/dev/null is no directory): the guessable ${TMPDIR:-/tmp}/agpm-test-no-global-config/… it replaces could be created in a shared
# /tmp by another user or an old run, and then steered every test that sources this file (OpenCodeReview 14/10).
export ANTIGRAVITY_PM_GLOBAL_CONFIG=/dev/null/agpm-test-no-global-config/.antigravity-pm.json
export DEVKIT_LANG="${DEVKIT_LANG:-vi}"
