#!/usr/bin/env bash
# #974: kit tests must find clean_git_env.sh and super_board_all.py under .agents/devkit too
# (app repos carry the DevKit there), so a byte copy of a kit test never skips the env reset.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(basename "$0")"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

bad=""
for f in "$ROOT"/tests/super-board/*.sh; do
  [ "$(basename "$f")" = "$SELF" ] && continue
  # a bare `. <kit path>/clean_git_env.sh` line (no loop) has no .agents/devkit fallback
  if grep -q '^\. ".*universal-agent-devkit/tests/lib/clean_git_env.sh"' "$f"; then bad="$bad $(basename "$f")"; continue; fi
  if grep -q 'universal-agent-devkit/scripts/governance/super_board_all.py' "$f" \
     && ! grep -q '\.agents/devkit/scripts/governance/super_board_all.py' "$f"; then
    bad="$bad $(basename "$f")"
  fi
done
[ -z "$bad" ] && ok "every kit test that sources clean_git_env.sh / super_board_all.py has a .agents/devkit fallback" \
  || fail "no .agents/devkit fallback in:$bad"

# behaviour: with only .agents/devkit present, the loop used by the tests still sources the lib
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.agents/devkit/tests/lib"
echo 'CLEAN_ENV_LOADED=1' > "$T/.agents/devkit/tests/lib/clean_git_env.sh"
snippet=$(grep -h -A2 '^for _dk in' "$ROOT/tests/super-board/test_ac_check_cross_repo.sh" | head -3)
if [ -n "$snippet" ]; then
  out=$(ROOT="$T" bash -c "$snippet"'; echo "${CLEAN_ENV_LOADED:-0}"' 2>&1)
  [ "$out" = "1" ] && ok "fallback sources clean_git_env.sh from .agents/devkit" || fail "fallback did not source it: $out"
else
  fail "test_ac_check_cross_repo.sh has no fallback loop"
fi
[ "$FAILS" -eq 0 ]
