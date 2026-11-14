#!/usr/bin/env bash
# hooks/block-dangerous-git.sh + hooks/hardware_safety_gate.sh: the Zero-Defect holes three reviewers reproduced on 5db81236 (14/11),
# each one a two-way case: the command that slipped through (HEAD exit 0, must be 2) or was refused by mistake (HEAD exit 2, must
# be 0), next to a similar command whose verdict must NOT change.
#  C4a git, fail-open: git tag -d / --delete / -f / --force (a tag that is deleted or moved is not recoverable from the working tree).
#  C4b both, fail-open: a shell that reads its script on stdin: echo "…" | bash, printf … | zsh, bash <<< "…" (the same script
#      through bash -c or a heredoc is refused).
#  C4c hw, fail-open: an interpreter one-liner that removes / , home or ..: python -c shutil.rmtree(…), node -e fs.rmSync(…).
#  C4d hw, false positive: the dangerous words are only data (a commit message, a grep pattern, an echo argument).
#  C4e hw, false positive: rm -rf of a regenerable cache folder at the project top level (.venv, venv, .mypy_cache, .ruff_cache,
#      htmlcov) is refused while rm -rf build passes. tmp stays refused (its content is not known to be regenerable).
#      Fail-open found while writing these cases: rm -rf .agents/local (agent memory, two levels deep) and rm of a secret .env file.
#  find (Antigravity audit T0479): a -name / -path filter switched the start-point check off, so find ~ -name "*.py" -delete,
#      … | xargs rm -rf, -execdir rm and find / -name x -exec rm passed; -name "[!.]*" counted as a filter that narrows.
# Only the hooks run here, never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, the scratch repo $P (src/, build/, README.md, branch feat), check

# the scratch project of the lib, plus what these cases name: a tag, docs/, the cache folders (git-ignored, with a file in each),
# an ignored secret file and the ignored agent memory folder
CACHES=".venv venv .mypy_cache .ruff_cache htmlcov __pycache__ .pytest_cache node_modules dist coverage"
mkdir -p "$P/docs" "$P/.agents/local/memory" "$P/tmp" "$P/src/old"
printf 'doc\n' > "$P/docs/x.md"
printf 'note\n' > "$P/.agents/local/memory/note.md"
printf 'x\n' > "$P/tmp/f"
printf 'K=v\n' > "$P/.env"
printf 'K=v\n' > "$P/.env.production.local"
printf 'K=\n' > "$P/.env.example"
: > "$P/.gitignore"
for d in $CACHES; do mkdir -p "$P/$d" && printf 'x\n' > "$P/$d/f" && printf '%s/\n' "$d" >> "$P/.gitignore"; done
printf '.env\n.env.*\n!.env.example\n.agents/local/\nbuild/\ntmp/\n' >> "$P/.gitignore"
git -C "$P" add .gitignore docs && git -C "$P" commit -qm fixtures && git -C "$P" tag v1

echo "── C4a git: deleting or moving a tag"
check 2 git 'git tag -d v1'
check 2 git 'git tag --delete v1'
check 2 git 'git tag -f v1'
check 2 git 'git tag --force v1 HEAD~1'
check 2 git 'git -C x tag -d v1'
check 2 git "bash -c 'git tag -d v1'"
check 0 git 'git tag'
check 0 git "git tag -l 'v*'"
check 0 git 'git tag v2'
check 0 git 'git tag -a v2 -m "release"'
check 0 git 'git tag --contains HEAD'

echo "── C4b hw: a shell that reads its script on stdin"
check 2 hw 'echo "rm -rf ~" | bash'
check 2 hw "echo 'rm -rf ..' | sh"
check 2 hw 'bash <<< "rm -rf ~"'
check 2 hw "printf 'rm -rf /\\n' | zsh"
check 2 hw $'cat <<EOF | bash\nrm -rf ~\nEOF'
check 0 hw 'echo "hello" | bash'
check 0 hw 'echo "ls -la" | sh'
check 0 hw 'echo "rm -rf ~" | cat'
check 0 hw 'echo "rm -rf ~" > notes.txt'
echo "── C4b git: the same through the git guard"
check 2 git 'echo "git reset --hard" | bash'
check 2 git 'bash <<< "git push --force origin main"'
check 0 git 'echo "git status" | bash'
check 0 git 'echo "git reset --hard" | cat'

echo "── C4c hw: an interpreter one-liner that removes /, home or .."
check 2 hw "python3 -c \"import shutil; shutil.rmtree('/')\""
check 2 hw "python3 -c \"import shutil,os; shutil.rmtree(os.path.expanduser('~'))\""
check 2 hw "python -c \"import shutil; shutil.rmtree('..')\""
check 2 hw "node -e \"require('fs').rmSync('/',{recursive:true,force:true})\""
check 2 hw 'node -e "fs.rmSync(os.homedir(),{recursive:true})"'
check 0 hw "python3 -c \"import shutil; shutil.rmtree('build')\""
check 0 hw "python3 -c \"print('hi')\""
check 0 hw "node -e \"require('fs').rmSync('dist',{recursive:true,force:true})\""
# a recursive delete whose target is not a literal cannot be judged: refused (fail closed); a safe relative literal passes
check 2 hw "python3 -c \"import shutil,sys; shutil.rmtree(sys.argv[1])\" build"
check 2 hw 'node -e "fs.rmSync(dir,{recursive:true,force:true})"'
check 2 hw "python3 -c \"import shutil; shutil.rmtree('src')\""
check 2 hw "python3 -c \"import shutil,pathlib; shutil.rmtree(pathlib.Path.home())\""
check 2 hw "ruby -e \"require 'fileutils'; FileUtils.rm_rf('/')\""
check 0 hw "python3 -c \"import shutil; shutil.rmtree('src/old')\""
check 0 hw "python3 -c \"import shutil; shutil.rmtree('build/tmp', ignore_errors=True)\""
check 0 hw "python3 -c \"import os; os.remove('build/a.o')\""
# a variable that the same program fills from tempfile is a temp folder; a variable of unknown origin stays refused
check 0 hw "python3 -c \"import shutil,tempfile; d=tempfile.mkdtemp(); shutil.rmtree(d)\""
check 0 hw "python3 -c \"import shutil,tempfile; d = tempfile.mkdtemp(prefix='x'); print(d); shutil.rmtree(d, ignore_errors=True)\""
check 2 hw "python3 -c \"import shutil,tempfile; d=tempfile.mkdtemp(); d='/'; shutil.rmtree(d)\""
check 2 hw "python3 -c \"import shutil,tempfile; t=tempfile.mkdtemp(); shutil.rmtree(d)\""

echo "── C4c hw: an interpreter that hands a command line to a shell or starts rm (judged like bash -c)"
check 2 hw "python3 -c \"import os; os.system('rm -rf ~')\""
check 2 hw "python3 -c \"import subprocess; subprocess.run(['rm','-rf','/'])\""
check 2 hw "python3 -c \"import subprocess; subprocess.run('rm -rf ~', shell=True)\""
check 2 hw "python3 -c \"import subprocess; subprocess.call(['rm', '-rf', '..'])\""
check 2 hw "python3 -c \"import subprocess; subprocess.check_call('rm -rf ~', shell=True)\""
check 2 hw "python3 -c \"import subprocess; subprocess.check_output(['rm','-rf','src'])\""
check 2 hw "python3 -c \"from subprocess import Popen; Popen(['rm','-rf','/']).wait()\""
check 2 hw "python3 -c \"import os; os.popen('rm -rf ~').read()\""
check 2 hw "node -e \"require('child_process').execSync('rm -rf ~')\""
check 2 hw "ruby -e \"system('rm -rf ~')\""
check 2 hw "perl -e 'system(\"rm -rf /\")'"
check 2 hw "perl -e 'system(\"rm\", \"-rf\", \"/\")'"
check 0 hw "python3 -c \"import subprocess; subprocess.run(['ls','-la'])\""
check 0 hw "python3 -c \"import os; os.system('echo hi')\""
check 0 hw "python3 -c \"import os; os.system('rm -rf build')\""
check 0 hw "node -e \"require('child_process').execSync('git status')\""
check 0 hw "python3 -c \"print('rm -rf ~')\""
echo "── C4c git: the same through the git guard"
check 2 git "python3 -c \"import os; os.system('git reset --hard')\""
check 2 git "python3 -c \"import subprocess; subprocess.run(['git','push','--force','origin','main'])\""
check 2 git "python3 -c \"import subprocess; subprocess.run('git reset --hard', shell=True)\""
check 2 git "python3 -c \"import os; os.popen('git push --force origin main')\""
check 2 git "node -e \"require('child_process').execSync('git reset --hard')\""
check 2 git "ruby -e \"system('git reset --hard')\""
check 2 git "perl -e 'system(\"git push --force origin main\")'"
check 0 git "python3 -c \"import subprocess; subprocess.run(['ls','-la'])\""
check 0 git "python3 -c \"import os; os.system('echo hi')\""
check 0 git "node -e \"require('child_process').execSync('git status')\""
check 0 git "python3 -c \"print('rm -rf ~')\""

echo "── C4d hw: dangerous words that are only data"
check 0 hw 'git commit -m "test: npm publish guard"'
check 0 hw 'grep -rn "npm publish" docs/'
check 0 hw 'git commit -m "refuse rm -rf /"'
check 0 hw 'echo "never run firebase deploy from here"'
check 0 hw 'echo "rm -rf /system/ is dangerous"'
check 0 hw 'grep -n "rm -rf /system/*" docs/x.md'
check 0 hw 'grep -rn "npm publish" docs/ | head -5'
check 0 hw 'git commit -q -m "fix #12: firebase deploy is refused" && git status'
echo "── C4d hw: controls, the same words as a command are still refused"
check 2 hw 'echo "npm publish" | sh'
check 2 hw 'bash <<< "firebase deploy"'
check 2 hw 'echo "adb remount" > x.sh && sh x.sh'
check 2 hw 'echo "npm publish" | xargs -I{} sh -c {}'
check 2 hw 'echo "x $(npm publish)"'
check 2 hw 'eval echo "x"; npm publish'
check 2 hw 'git -c alias.x="!npm publish" commit -m "npm publish"'
check 2 hw 'echo "a" # x
npm publish'
check 2 hw 'npm publish'
check 2 hw 'echo ok && npm publish'
check 2 hw 'firebase deploy'
check 2 hw 'git commit -m x && rm -rf ~'
check 2 hw 'echo "$(rm -rf ~)"'
check 2 hw 'grep x docs/ ; rm -rf /'

echo "── C4e hw: a regenerable, git-ignored cache folder at the top level"
for d in $CACHES; do check 0 hw "rm -rf $d"; done
check 0 hw 'rm -rf build'
check 0 hw 'rm -rf htmlcov .mypy_cache .ruff_cache'
echo "── C4e hw: controls, source, agent state, secrets and the roots are still refused"
check 2 hw 'rm -rf .git'
check 2 hw 'rm -rf .agents'
check 2 hw 'rm -rf src'
check 2 hw 'rm -rf .'
check 2 hw 'rm -rf ..'
check 2 hw 'rm -rf ~'
check 2 hw 'rm -rf /'
check 2 hw 'rm -rf tmp'
check 2 hw 'rm -rf .venv src'
check 0 hw 'rm -f README.md'
# agent memory and secret files: the rule is the protected_delete list of block-dangerous-git.sh (#605, tests/gates/test_guard_protected_delete.sh),
# which runs on the same Bash call; the hardware gate lets these through, so the pair is what is pinned here
check 2 git 'rm -rf .agents/local'
check 2 git 'rm -rf .agents/local/memory'
check 2 git 'rm -rf .env'
check 2 git 'rm -f .env'
check 2 git 'rm .env.production.local'
check 2 git "python3 -c \"import os; os.remove('.env')\""
check 0 git 'rm -rf .agents/local/stage'

echo "── find: a name filter does not switch the start-point check off"
check 2 hw 'find ~ -name "*.py" -delete'
check 2 hw 'find ~ -name "*.py" | xargs rm -rf'
check 2 hw 'find ~ -name "*.py" -execdir rm -rf {} +'
check 2 hw "bash -c \"find ~ -name '*.py' -delete\""
check 2 hw 'find . -name "[!.]*" -delete'
check 2 hw 'find / -name x -exec rm {} \;'
check 0 hw 'find build -name "*.o" -delete'
check 0 hw 'find . -name "*.pyc" -delete'
check 0 hw 'find . -name __pycache__ -type d -exec rm -rf {} +'
check 0 hw 'find . -name "*.py"'
check 0 hw 'find ~ -name "*.py"'
check 0 hw 'find . -name "*.log" | xargs rm'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
