#!/usr/bin/env bash
# Regression test + ratchet: a test that runs git in scratch repos must not inherit GIT_* from its caller.
# git exports GIT_INDEX_FILE / GIT_AUTHOR_* / GIT_CONFIG_PARAMETERS ... to its hooks and honours them for every repo
# it touches, so such a test run inside `git commit` (or by hand with the variables exported) writes into the real
# index or gives every scratch commit one identity — 2026-10-03: the workbench's index was overwritten, and
# test_gate_friction failed only inside `git commit`. tests/lib/clean_git_env.sh clears them; every test that uses git
# must source it BEFORE its first git command (the 74 existing ones were red here before the sweep).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
LIB="$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# 1. the library clears every variable a hook run hands on (a fresh process gets them, sources the lib, reports survivors)
left="$(env GIT_INDEX_FILE=/x GIT_DIR=/x GIT_WORK_TREE=/x GIT_PREFIX=x GIT_COMMON_DIR=/x GIT_OBJECT_DIRECTORY=/x \
  GIT_ALTERNATE_OBJECT_DIRECTORIES=/x GIT_NAMESPACE=x GIT_AUTHOR_NAME=a GIT_AUTHOR_EMAIL=a@a GIT_AUTHOR_DATE=1 \
  GIT_COMMITTER_NAME=c GIT_COMMITTER_EMAIL=c@c GIT_COMMITTER_DATE=1 GIT_CONFIG_PARAMETERS="'k=v'" GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=k GIT_CONFIG_VALUE_0=v KEEP_ME=1 bash -c '. "$1"; env | grep -E "^(GIT_(INDEX_FILE|DIR|WORK_TREE|PREFIX|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|NAMESPACE|AUTHOR_[A-Z]+|COMMITTER_[A-Z]+|CONFIG_[A-Z_0-9]+)|KEEP_ME)=" | cut -d= -f1' _ "$LIB")"
[ "$left" = "KEEP_ME" ] && ok "the library clears every GIT_* variable a hook run hands on and keeps the rest" || fail "survivors after sourcing: $(printf '%s' "$left" | tr '\n' ' ')"

# 2. ratchet: every test that runs git in scratch repos sources the library before its first git command — also one that
# reaches git through install.sh / agent-kit init|githooks|worktree (they run `git -C "$TARGET" …` themselves).
# ponytail: a test that unpacks a ready-made repo and then runs only `git commit` escapes this pattern; add the verb
# when one shows up.
GITRE='(^|[^a-zA-Z_./-])git +(init|clone|-C)( |$)|install\.sh|agent-kit +(init|githooks|worktree)'
offenders=""; n=0
for f in "$DEVKIT_DIR"/tests/*/test_*.sh "$DEVKIT_DIR"/hooks/tests/*.sh; do
  first="$(grep -nE "$GITRE" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1)"
  [ -n "$first" ] || continue
  n=$((n + 1))
  src="$(grep -nE '^[[:space:]]*(\.|source)[[:space:]].*clean_git_env\.sh' "$f" | head -1 | cut -d: -f1)"
  if [ -z "$src" ] || [ "$src" -ge "$first" ]; then offenders="$offenders
    ${f#$DEVKIT_DIR/} (first git at line $first, library ${src:-never sourced})"; fi
done
[ "$n" -gt 0 ] || fail "found no test that uses git (the pattern is broken)"
[ -z "$offenders" ] && ok "all $n tests that run git source the library first" \
  || { fail "$(printf '%s' "$offenders" | grep -c .) of $n tests that run git do not source tests/lib/clean_git_env.sh before their first git command:$(printf '%s' "$offenders" | head -6)"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_git_env_isolation: all passed" || { echo "❌ test_git_env_isolation: $FAILS failed"; exit 1; }
