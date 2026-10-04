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
          GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT; do
  unset "$_v"
done
for _v in $(env | grep -E '^GIT_CONFIG_(KEY|VALUE)_[0-9]+=' | cut -d= -f1); do unset "$_v"; done
unset _v
