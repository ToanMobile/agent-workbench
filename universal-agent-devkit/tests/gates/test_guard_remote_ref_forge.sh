#!/usr/bin/env bash
# hooks/block-dangerous-git.sh (#837): an agent must not forge the "landed" ref the gate trusts (#638: refs/remotes/<remote>/<trunk>
# and <remote>/HEAD). Blocked: update-ref on refs/remotes/*, remote set-head (except --auto: it restores the remote's truth),
# symbolic-ref writing refs/remotes/*. Allowed: fetch, pull, reads (rev-parse, symbolic-ref read, update-ref on a non-remote scratch ref is judged by the old rule).
# Only the hook runs here — never the command.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"

echo "── blocked (rc 2)"
check 2 git 'git update-ref refs/remotes/origin/main HEAD'
check 2 git 'git update-ref refs/remotes/origin/main abc1234 def5678'
check 2 git 'git -C . update-ref -m x refs/remotes/upstream/trunk HEAD'
check 2 git 'git update-ref --no-deref refs/remotes/origin/HEAD HEAD'
check 2 git 'git remote set-head origin feat'
check 2 git 'git remote set-head origin -d'
check 2 git 'git remote set-head origin --delete'
check 2 git 'git remote -v set-head origin feat'
check 2 git 'git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/feat'
check 2 git 'bash -c "git update-ref refs/remotes/origin/main HEAD"'
check 2 git 'git update-ref refs/remotes/origin/main HEAD && git status'
check 2 git 'git symbolic-ref -d refs/remotes/origin/HEAD'
check 2 git 'git symbolic-ref -m why refs/remotes/origin/HEAD refs/remotes/origin/feat'
check 2 git 'git symbolic-ref --del refs/remotes/origin/HEAD'
check 2 git 'git symbolic-ref --d refs/remotes/origin/HEAD'
check 2 git 'git symbolic-ref refs/scratch/x refs/remotes/origin/main'
check 2 git 'git remote set-head origin -a --no-auto'
check 2 git 'git remote set-head origin --auto -d'
check 2 git 'git remote set-head origin --auto --delete'
check 2 git 'git remote set-head origin --auto --no-a'
check 2 git 'git remote set-head origin feat > -a'
check 2 git 'git remote set-head origin feat > --auto'
check 2 git "python3 -c \"import subprocess; subprocess.run(['git','remote','set-head','origin','feat']); print('-a')\""
check 2 git 'git update-ref refs/Remotes/origin/main HEAD'
check 2 git 'git update-ref REFS/REMOTES/origin/main HEAD'
check 2 git 'git update-ref Refs/Heads/x HEAD'
check 2 git 'git symbolic-ref refs/Remotes/origin/HEAD refs/heads/feat'
check 2 git 'git symbolic-ref refs/remotes/origin/main HEAD'
check 2 git 'git symbolic-ref refs/remotes/origin/HEAD Refs/remotes/origin/feat'
check 2 git 'git symbolic-ref > -q refs/remotes/origin/HEAD refs/remotes/origin/feat'
check 2 git 'git remote > /dev/null set-head origin feat'
check 2 git 'git remote 2>/dev/null set-head origin feat'
check 2 git 'git remote set-head origin -- -a'
check 2 git "python3 -c \"import subprocess; subprocess.run(['git','update-ref','-m','git','refs/remotes/origin/main','HEAD'])\""
check 2 git "python3 -c \"import subprocess; subprocess.run(['git','symbolic-ref','refs/remotes/origin/main','HEAD'])\""
check 2 git 'git 2>/dev/null update-ref refs/remotes/origin/main HEAD'
check 2 git 'git >/dev/null remote set-head origin feat'
check 2 git 'git -C . 2>/dev/null update-ref refs/remotes/origin/main HEAD'
echo "── allowed (rc 0)"
check 0 git 'git 2>/dev/null remote set-head origin --auto'
check 0 git 'git remote -v set-head origin --auto'
check 0 git "python3 -c \"import subprocess; print(subprocess.run(['git','symbolic-ref','refs/remotes/origin/HEAD'], capture_output=True).stdout.decode('utf-8').removeprefix('refs/remotes/origin/'))\""
check 0 git 'git remote set-head origin --a'
check 0 git 'git remote set-head origin --no-auto --auto'
check 0 git "python3 -c \"import subprocess; print(subprocess.run(['git','symbolic-ref','refs/remotes/origin/HEAD'], capture_output=True).stdout.decode('utf-8'))\""
check 0 git "node -e \"console.log(require('child_process').execSync('git symbolic-ref refs/remotes/origin/HEAD','utf8'))\""
check 0 git 'git fetch origin'
check 0 git 'git pull --ff-only'
check 0 git 'git remote set-head origin --auto'
check 0 git 'git remote set-head origin -a'
check 0 git 'git remote -v'
check 0 git 'git symbolic-ref refs/remotes/origin/HEAD'
check 0 git 'git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null'
check 0 git 'git symbolic-ref --short refs/remotes/origin/HEAD > /dev/null 2>&1'
check 0 git 'git remote set-head origin --au'
check 0 git 'git symbolic-ref --short HEAD'
check 0 git 'git rev-parse refs/remotes/origin/main'
check 0 git 'git log refs/remotes/origin/main'
check 0 git 'git update-ref refs/scratch/x HEAD'

[ "$FAILS" = 0 ] && { echo "OK"; exit 0; }
echo "FAILS=$FAILS"; exit 1
