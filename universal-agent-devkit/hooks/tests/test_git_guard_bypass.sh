#!/usr/bin/env bash
# Regression test: bypasses of block-dangerous-git.sh found 2026-09-28 — each returned exit 0.
#   1. abbreviated long options (git takes any unique prefix: `git reset --k HEAD~1` IS --keep);
#   2. one-shot config that forces a push (`-c remote.origin.push=+…`) or a mixed-case `Alias.`;
#   3. persistent `git config` of core.hooksPath / a dangerous alias / a +refspec;
#   4. `git branch -M/-C` (overwrite a branch) and `git update-ref refs/heads/…`.
# The allowed half pins that the fix did not turn everyday commands into blocks.
# Usage: bash hooks/tests/test_git_guard_bypass.sh — exit 0 = all cases hold. bash 3.2 compatible.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-dangerous-git.sh"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gitguard.XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT

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

echo "1. abbreviated long options"
check 2 'git reset --har HEAD~1'
check 2 'git reset --k HEAD~1'
check 2 'git push --force-w origin main'
check 2 'git push --force-w=main origin main'
check 2 'git push --delet origin main'
check 2 'git push --mirr origin'
check 2 'git commit --no-verif -m x'
check 2 'git clean --forc -d'
check 2 'git push --forc origin main'
check 2 'git -c alias.p="push --forc" p origin main'
check 0 'git merge --no-ff x'
check 0 'git push --follow-tags origin main'
check 0 'git push --dry-run origin main'
check 0 'git commit --no-edit'
check 0 'git push origin main'
check 0 'git reset --soft HEAD~1'
check 0 'git reset --mixed HEAD~1'
check 0 'git clean --dry-run'

echo "2. one-shot config"
check 2 'git -c remote.origin.push=+HEAD:refs/heads/main push origin'
check 2 'git -c Alias.p="push --force" p origin main'
check 2 'git -c ALIAS.P="reset --hard" p'
check 2 'git --config-env=core.hooksPath=HP commit -m x'
check 0 'git -c alias.st=status st'
check 0 'git -c user.name=x commit -m y'

echo "3. persistent config"
check 2 'git config core.hooksPath /dev/null'
check 2 'git config --global core.hookspath x'
check 2 'git config alias.p "push --force"'
check 2 'git config remote.origin.push +HEAD:main'
check 0 'git config user.name x'
check 0 'git config --get core.hooksPath'
check 0 'git config alias.st status'

echo "4. overwrite a branch"
check 2 'git branch -M tmp main'
check 2 'git branch -C a b'
check 2 'git branch -C a b' DEVKIT_ALLOW_BRANCH=1
check 2 'git update-ref refs/heads/main HEAD~1'
check 0 'git branch -m old new'
check 0 'git update-ref refs/tags/x HEAD'

echo "pass=${PASS} fail=${FAIL}"
[ "${FAIL}" -eq 0 ]
