#!/usr/bin/env bash
# Regression test (issue #7, #8): payloads that desync the comment/quote scanner from the shell
# must not hide a live `git reset --hard` / `rm -rf` — each returned exit 0 before the fix.
#   1. ANSI-C quote `$'\''` (an escaped quote inside $'…') followed by a lone backslash;
#   2. `\<newline>` before a `#` (line continuation, so the `#` is not a comment start);
#   3. `\${ # '` (escaped dollar, so no brace expansion);
#   4. merged POSIX flags / `--flag=value` on an inline interpreter script.
# Usage: bash hooks/tests/test_git_guard_ansi_c_quote.sh — exit 0 = all cases hold. bash 3.2 compatible.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gitguard7.XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT

PASS=0; FAIL=0
payload() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "${SANDBOX}"; }

# blocked <hook> <command>: exit must be 1 or 2
blocked() {
  hook="$1"; cmd="$2"
  out="$(payload "${cmd}" | env -u DEVKIT_ALLOW_BRANCH CLAUDE_PROJECT_DIR="${SANDBOX}" bash "${HERE}/${hook}" 2>&1)"
  got=$?
  if [ "${got}" -eq 1 ] || [ "${got}" -eq 2 ]; then
    PASS=$((PASS + 1)); printf '  ok   %s got=%s  %s\n' "${hook}" "${got}" "${cmd}"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s got=%s (want 1/2)  %s\n' "${hook}" "${got}" "${cmd}"
  fi
}

# allowed <hook> <command>: exit must be 0
allowed() {
  hook="$1"; cmd="$2"
  out="$(payload "${cmd}" | env -u DEVKIT_ALLOW_BRANCH CLAUDE_PROJECT_DIR="${SANDBOX}" bash "${HERE}/${hook}" 2>&1)"
  got=$?
  if [ "${got}" -eq 0 ]; then
    PASS=$((PASS + 1)); printf '  ok   %s got=0  %s\n' "${hook}" "${cmd}"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s got=%s (want 0)  %s  %s\n' "${hook}" "${got}" "${cmd}" "$(printf '%s' "${out}" | head -1)"
  fi
}

NL='
'
echo "1. ANSI-C quote"
blocked block-dangerous-git.sh "echo \$'\\''; git reset --hard HEAD; echo \\'"
blocked hardware_safety_gate.sh "echo \$'\\''; rm -rf /Users; echo \\'"
blocked block-dangerous-git.sh "echo \$'a\\'b'; git reset --hard HEAD; echo \$'\\''"
blocked block-dangerous-git.sh "echo \"\\\"\" \$'\\''; git reset --hard HEAD; echo \\'"
blocked hardware_safety_gate.sh "echo \"\\\"\" \$'\\''; rm -rf /Users; echo \\'"
blocked block-dangerous-git.sh "echo \$\$'\\'; git reset --hard HEAD; echo '\\'"
blocked hardware_safety_gate.sh "echo \$\$'\\'; rm -rf /Users; echo '\\'"
blocked hardware_safety_gate.sh "echo \$\$'\\' ' # ' ; rm -rf /Users"
allowed block-dangerous-git.sh "echo \$'it\\'s'; git status"

echo "2. backslash-newline before a hash"
blocked block-dangerous-git.sh "echo x \\${NL}# '${NL}git reset --hard HEAD${NL}# '"
blocked hardware_safety_gate.sh "echo x \\${NL}# '${NL}rm -rf /Users${NL}# '"

echo "3. escaped dollar-brace"
blocked block-dangerous-git.sh "echo \\\${ # '${NL}git reset --hard HEAD${NL}echo '"
blocked hardware_safety_gate.sh "echo \\\${ # '${NL}rm -rf /Users${NL}echo '"

echo "4. merged inline-script flags"
blocked block-dangerous-git.sh "python3 -ISc \"import os; os.system('git reset --hard')\""
blocked block-dangerous-git.sh "node --eval=\"require('child_process').execSync('git reset --hard')\""
blocked block-dangerous-git.sh "python3 -c \"import subprocess; subprocess.run(['git','checkout','-b','x'])\""
allowed block-dangerous-git.sh "python3 -ISc \"print(1)\""

echo "5. a flag that is not the script must not hide the real one"
blocked block-dangerous-git.sh "perl -Isrc -e 'system(\"git reset --hard\")'"
blocked block-dangerous-git.sh "python3 -Wonce -c \"import os; os.system('git reset --hard')\""
blocked block-dangerous-git.sh "python3 -E -c \"import os; os.system('git reset --hard')\""
blocked block-dangerous-git.sh "node -r x -e \"require('child_process').execSync('git reset --hard')\""
blocked block-dangerous-git.sh "python3 -c\"import os; os.system('git reset --hard')\""

echo "6. a script that names git harmlessly, and the user's own switch"
allowed block-dangerous-git.sh "python3 -c \"import subprocess; subprocess.run(['git','checkout','main'], cwd='repo'); print('ok')\""
allowed block-dangerous-git.sh "python3 -c \"import subprocess; subprocess.run(['git','branch']); print('done')\""
allowed block-dangerous-git.sh "python3 -c \"import subprocess; subprocess.run(['git','checkout','main']); subprocess.run(['ls','-t'])\""
allowed block-dangerous-git.sh "DEVKIT_ALLOW_BRANCH=1 python3 -c \"import subprocess; subprocess.run(['git','checkout','-b','x'])\""

echo "pass=${PASS} fail=${FAIL}"
[ "${FAIL}" -eq 0 ]
