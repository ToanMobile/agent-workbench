#!/usr/bin/env bash
# Regression test: two holes in block-dangerous-git.sh found 2026-09-28 — each case below
# with want=2 returned exit 0.
#   1. git inside a nested command ($(…), backticks, bash|sh -c, eval) met only the raw
#      fallback regex, which knows no abbreviated option (`--har`, `--forc`); git called from
#      python -c / node -e as a list of quoted words (['git','push','--force']) met nothing.
#   2. git configuration through the environment (GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT +
#      KEY_n/VALUE_n, GIT_CONFIG_GLOBAL/SYSTEM) and `git config include.path|includeIf.*`
#      (an external config file the hook cannot read) skipped the config checks.
# The allowed half pins that the fix did not turn everyday commands into blocks.
# Usage: bash hooks/tests/test_git_guard_nested.sh — exit 0 = all cases hold. bash 3.2 compatible.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-dangerous-git.sh"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gitguardnest.XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT
# A real repo with one commit and no .agents/regression_matrix.active.json (the push gate does not apply).
git -C "${SANDBOX}" init -q -b main && git -C "${SANDBOX}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || exit 1

PASS=0; FAIL=0
payload() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "${SANDBOX}"; }

# check <expected_exit> <command> [ENV=VAL ...]
check() {
  want="$1"; cmd="$2"; shift 2
  out="$(payload "${cmd}" | env CLAUDE_PROJECT_DIR="${SANDBOX}" "$@" bash "${HOOK}" 2>&1)"
  got=$?
  if [ "${got}" -eq "${want}" ]; then
    PASS=$((PASS + 1)); printf '  ok   want=%s  %s\n' "${want}" "${cmd}"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL want=%s got=%s  %s  %s\n' "${want}" "${got}" "${cmd}" "$(printf '%s' "${out}" | head -1)"
  fi
}

echo "1. git inside nested commands"
check 2 'echo $(git reset --har HEAD~1)'
check 2 'echo `git push --force-w origin main`'
check 2 'bash -c "git push --forc origin main"'
check 2 "sh -c 'git reset --hard HEAD~1'"
check 2 'eval "git push --delet origin main"'
check 2 "python3 -c \"import subprocess; subprocess.run(['git','push','--force','origin','main'])\""
check 2 "node -e \"require('child_process').execSync('git push --force-w origin main')\""
check 2 'echo "$(git clean --forc -d)"'
check 2 'x=$(echo `git reset --k HEAD~1`)'
# the raw regex happens to catch --force-w / --forc as a substring; these it does not:
check 2 'echo `git reset --har HEAD~1`'
check 2 'echo $(git push --delet origin main)'
check 2 'echo "$(git commit --no-verif -m x)"'
check 2 "node -e \"require('child_process').execSync('git reset --har HEAD~1')\""
check 2 "python3 -c \"import os; os.system('git reset --k HEAD~1')\""
check 0 'echo "$(git rev-parse HEAD)"'
check 0 'git log $(git merge-base main HEAD)..HEAD'
check 0 'git push origin $(git rev-parse --abbrev-ref HEAD)'
check 0 'git push -u origin "$(git branch --show-current)"'
check 0 'bash -c "git status"'
check 0 'python3 -c "print(1)"'
check 0 "python3 -c \"import subprocess; subprocess.run(['git','status','--short'])\""
check 0 $'git commit -m "$(cat <<\'EOF\'\nfix: x\nEOF\n)"'
check 0 $'git commit -m "$(cat <<\'EOF\'\nfix: never git push --forc or git reset --har\nEOF\n)"'
check 0 'echo "git push --force is dangerous"'

echo "2. git configuration through the environment"
check 2 "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git commit -m x"
check 2 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'
check 2 'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.p GIT_CONFIG_VALUE_0="push --force"'
check 2 'GIT_CONFIG_GLOBAL=/tmp/evil git push origin main'
check 2 'env GIT_CONFIG_SYSTEM=/tmp/evil git commit -m x'
check 2 'git config include.path /tmp/evil'
check 2 'git config includeIf.gitdir:~/.path /tmp/x'
check 2 'git -c include.path=/tmp/evil commit -m x'
check 0 'GIT_PAGER=cat git log'
check 0 'GIT_TERMINAL_PROMPT=0 git fetch'
check 0 'git config user.email a@b'
check 0 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=x git log'

echo "pass=${PASS} fail=${FAIL}"
[ "${FAIL}" -eq 0 ]
