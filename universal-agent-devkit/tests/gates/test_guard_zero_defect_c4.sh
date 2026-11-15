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
# a home folder of its own (OCR review: 61 rows were red with HOME=/nonexistent): ~ is a real folder in every run, removed with TMP
# (TMPDIR moves beside it: a home folder under the temp root would be scratch the gate lets rm -rf remove)
# (ran under tests/run_impacted.sh, a home folder under $TMP was scratch the gate lets rm -rf remove: 7 rows red in the gate only):
# keep a real home folder when there is one, make one only when HOME is missing.
[ -d "${HOME:-}" ] || export HOME="$TMP/home"
export TMPDIR="$TMP/tmp"
mkdir -p "$HOME" "$TMPDIR"

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

echo "── C4f git: checkout / restore whose paths are the whole tree or come from a file list (round 2)"
printf 'dirty\n' >> "$P/src/a.kt"   # an uncommitted change: what these commands throw away
check 2 git 'git diff --name-only | xargs git checkout'
check 2 git 'git ls-files -m | xargs git checkout'
check 2 git 'git diff --name-only | xargs git checkout HEAD'
check 2 git 'git diff --name-only | xargs -n1 git checkout'
check 2 git 'git diff --name-only | xargs -I{} git checkout {}'
check 2 git 'git status --porcelain | xargs git checkout'
check 2 git 'git checkout $(git diff --name-only)'
check 2 git 'git checkout "$(git diff --name-only)"'
check 2 git 'git checkout `git ls-files -m`'
check 2 git 'git checkout $(git status --porcelain | cut -c4-)'
check 2 git 'git checkout $(find src -name "*.kt")'
check 2 git 'git checkout $(ls src)'
check 2 git 'git checkout -q $(git diff --name-only)'
check 2 git 'git checkout :/'
check 2 git "git checkout ':/*'"
check 2 git "git checkout ':(top)'"
check 2 git 'git checkout "$PWD"'
check 2 git 'git checkout $PWD'
check 2 git 'git checkout "${PWD}"'
check 2 git 'git checkout $(pwd)'
check 2 git 'git checkout "$(pwd)"'
check 2 git 'git checkout "$PWD/src/a.kt"'
check 2 git 'git checkout -- "$PWD"'
check 2 git 'git checkout -- :/'
check 2 git 'git checkout .'
check 2 git 'git checkout -- src/a.kt'
check 2 git 'git restore $(git diff --name-only)'
check 2 git 'git ls-files -m | xargs git restore'
check 2 git 'git diff --name-only | xargs git restore'
check 2 git 'git ls-files -m | xargs git restore README.md'   # the file named is backed up, the ones stdin adds are not
check 2 git 'echo main | xargs git checkout'   # closed rule: whatever feeds xargs, its operands are not read
check 2 git 'git restore :/'
check 2 git 'git restore "$PWD"'
check 2 git 'git restore .'
check 2 git "bash -c 'git diff --name-only | xargs git checkout'"
echo "── C4f git: controls, a branch switch and commands that lose nothing keep their verdict"
check 0 git 'git checkout main'
check 0 git 'git checkout feat'
check 0 git 'git checkout -'
check 2 git 'git checkout -b feature'   # the one-branch rule, as before
check 0 git 'DEVKIT_ALLOW_BRANCH=1 git checkout -b feature'
check 0 git 'git checkout $(git merge-base HEAD origin/main)'
check 0 git 'git checkout "$(git rev-parse HEAD~1)"'
check 0 git 'git checkout "$BRANCH"'
check 0 git 'git checkout $BRANCH'
check 0 git 'git switch main'
check 0 git 'git switch "$BRANCH"'
check 0 git 'git restore --staged src/a.kt'
check 0 git 'git restore --staged $(git diff --name-only --cached)'
check 0 git 'git diff --name-only | xargs git restore --staged'
check 0 git 'git diff --name-only | xargs git add'
check 0 git 'git ls-files -m | xargs wc -l'
check 0 git 'git ls-files -m | xargs git diff --stat'
check 0 git 'git ls-files -m | xargs git log --oneline --'
check 0 git 'git checkout :/init'   # :/text is a revision: the newest commit whose message matches
check 0 git 'git add $(git diff --name-only)'
check 0 git 'git diff $(git merge-base HEAD main)'
check 0 git 'echo "$PWD" && git status'

echo "── C4g hw: a backtick inside single quotes is data (the shell expands nothing there)"
check 0 hw "git commit -m 'fix(guard): \`rm -rf ~\` now blocked'"
check 0 hw "echo 'never \`rm -rf ~\`' >> docs/x.md"
check 0 hw "gh pr create --body 'note: \`rm -rf ~\` is refused'"
check 0 hw "git commit -m 'docs: \`npm publish\` is refused'"
check 0 hw "echo 'a' 'never \`rm -rf ~\`'"
echo "── C4g hw: controls, the shell does expand these"
check 2 hw 'echo "x `rm -rf ~`"'
check 2 hw 'git commit -m "fix: `rm -rf ~` now blocked"'
check 2 hw 'echo `rm -rf ~`'
check 2 hw 'echo x`rm -rf ~`'
check 2 hw 'echo "$(rm -rf ~)"'
check 2 hw "echo 'a'\`rm -rf ~\`'b'"
check 2 hw "echo 'a' \`rm -rf ~\` 'b'"
check 2 hw "echo \"it's\" \`rm -rf ~\` 'b'"
check 2 hw "echo \\'a \`rm -rf ~\` b\\'"
check 2 hw "echo 'x' && rm -rf ~"
check 2 hw "bash -c 'echo \`rm -rf ~\`'"
check 2 hw "eval 'echo \`rm -rf ~\`'"
check 2 hw "echo 'never \`rm -rf ~\`' | sh"
check 2 hw "echo 'never \`rm -rf ~\`' > x.sh && sh x.sh"
check 2 hw "echo 'never \`rm -rf ~\`' | tee x.sh | sh"
check 2 hw "echo 'never \`rm -rf ~\`' | xargs -I{} sh -c {}"
check 2 hw "X='echo \`rm -rf ~\`'; eval \"\$X\""
check 2 hw "alias x='echo \`rm -rf ~\`'; x"
check 2 hw "watch 'echo \`rm -rf ~\`'"
check 2 hw "trap 'echo \`rm -rf ~\`' EXIT"
check 2 hw "ssh host 'echo \`rm -rf ~\`'"
check 2 hw "docker run x sh -c 'echo \`rm -rf ~\`'"
check 2 hw "function echo { eval \"\$1\"; }; echo 'x \`rm -rf ~\`'"   # the data command is shadowed
check 2 hw "alias echo=eval; echo 'x \`rm -rf ~\`'"
check 2 hw "alias printf=eval; printf 'x \`rm -rf ~\`'"
check 2 hw "echo() { eval \"\$1\"; }; echo 'x \`rm -rf ~\`'"
check 2 hw "git -c alias.x='!echo \`rm -rf ~\`' x"
check 2 hw "echo 'a \`date\`' && echo \`rm -rf ~\`"
check 2 hw "( echo 'never \`rm -rf ~\`' )"   # a group: the old reading stays (not modeled)
echo "── C4g git: the same through the git guard"
check 0 git "git commit -m 'fix(guard): \`git reset --hard\` now blocked'"
check 0 git "echo 'never \`git reset --hard\`' >> docs/x.md"
check 0 git "gh pr create --body 'note: \`git reset --hard\` is refused'"
check 2 git 'echo "x `git reset --hard`"'
check 2 git 'echo `git reset --hard`'
check 2 git 'echo "$(git reset --hard)"'
check 2 git "echo 'a'\`git reset --hard\`'b'"
check 2 git "bash -c 'echo \`git reset --hard\`'"
check 2 git "eval 'echo \`git reset --hard\`'"

echo "── C4h hw: an interpreter that removes a folder it builds from the temp root (replay of 12,000 real commands, 14/11)"
N="const fs=require('fs'),os=require('os'),p=require('path');"
check 0 hw "node -e \"${N}const t=os.tmpdir();let n=0;for(const f of fs.readdirSync(t)){if(f.startsWith('probe-')){fs.rmSync(p.join(t,f),{recursive:true,force:true});n++}}console.log('removed',n)\""
check 0 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'probe-1'),{recursive:true,force:true})\""
check 0 hw "node -e \"${N}const d=p.join(os.tmpdir(),'probe-1');fs.rmSync(d,{recursive:true,force:true})\""
check 0 hw "node -e \"${N}fs.rmSync(os.tmpdir()+'/probe-1',{recursive:true,force:true})\""
check 0 hw "node -e \"${N}const t=os.tmpdir();fs.rmSync(\\\`\\\${t}/probe-1\\\`,{recursive:true,force:true})\""
check 0 hw "node -e \"${N}const d=fs.mkdtempSync(p.join(os.tmpdir(),'x-'));fs.rmSync(d,{recursive:true,force:true})\""
check 0 hw "node -e \"${N}const d=fs.mkdtempSync(p.join(os.tmpdir(),'x-'));fs.rmSync(p.join(d,'sub'),{recursive:true,force:true})\""
check 0 hw "node -e \"${N}fs.rmSync(p.join(process.env.TMPDIR,'probe-1'),{recursive:true,force:true})\""
check 0 hw "node -e \"${N}const t=os.tmpdir();fs.readdirSync(t).filter(f=>f.startsWith('probe-')).forEach(f=>fs.rmSync(p.join(t,f),{recursive:true,force:true}))\""
check 0 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),'probe-1'))\""
check 0 hw "python3 -c \"import shutil,tempfile,os; t=tempfile.gettempdir(); d=os.path.join(t,'probe-1'); shutil.rmtree(d, ignore_errors=True)\""
check 0 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(tempfile.gettempdir()+'/probe-1')\""
check 0 hw "python3 -c \"import shutil,tempfile,os; t=tempfile.gettempdir(); shutil.rmtree(f'{t}/probe-1')\""
check 0 hw "python3 -c \"import shutil,os; shutil.rmtree(os.path.join(os.environ['TMPDIR'],'probe-1'))\""
check 0 hw "python3 -c \"import shutil,tempfile,os; d=tempfile.mkdtemp(); shutil.rmtree(os.path.join(d,'sub'))\""
check 0 hw "python3 -c \"
import shutil,tempfile,os
t=tempfile.gettempdir()
for n in os.listdir(t):
    if n.startswith('probe-'): shutil.rmtree(os.path.join(t,n))
\""
check 0 hw "ruby -e \"require 'fileutils'; require 'tmpdir'; FileUtils.rm_rf(File.join(Dir.tmpdir,'probe-1'))\""
check 0 hw "node -e \"${N}const tmpdir=os.tmpdir();fs.rmSync(p.join(tmpdir,'probe-1'),{recursive:true,force:true})\""
check 0 hw "python3 -c \"import shutil,tempfile,os; tmpdir=tempfile.gettempdir(); shutil.rmtree(os.path.join(tmpdir,'probe-1'))\""
echo "── C4h hw: controls, the temp root itself, a way out of it and a path of unknown origin are still refused"
check 2 hw "node -e \"${N}fs.rmSync(os.tmpdir(),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}const t=os.tmpdir();fs.rmSync(t,{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'..'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'a','..','..'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir()),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'.'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(os.tmpdir(),x),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(p.join(base,'probe-1'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}let d=p.join(os.tmpdir(),'probe-1');d=os.homedir();fs.rmSync(d,{recursive:true,force:true})\""
check 2 hw "node -e \"${N}let d=p.join(os.tmpdir(),'probe-1');d+='/../..';fs.rmSync(d,{recursive:true,force:true})\""
check 2 hw "node -e \"${N}let t=os.tmpdir();t='/';fs.rmSync(p.join(t,'usr'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(os.tmpdir()+'/..',{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(os.tmpdir()+'x',{recursive:true,force:true})\""
check 2 hw "node -e \"${N}fs.rmSync(os.tmpdir()+'/',{recursive:true,force:true})\""
check 2 hw "node -e \"${N}const t=os.tmpdir();fs.rmSync(\\\`\\\${t}/../x\\\`,{recursive:true,force:true})\""
check 2 hw "node -e \"${N}const t=os.tmpdir();fs.rmSync(\\\`\\\${t}\\\`,{recursive:true,force:true})\""
check 2 hw "node -e \"${N}const t=os.tmpdir();for(const f of fs.readdirSync(os.homedir())){fs.rmSync(p.join(t,f),{recursive:true,force:true})}\""
check 2 hw "node -e \"${N}const t=os.tmpdir();for(const f of ['..']){fs.rmSync(p.join(t,f),{recursive:true,force:true})}\""
check 2 hw "node -e \"${N}for(const f of fs.readdirSync(os.homedir())){fs.rmSync(p.join(os.homedir(),f),{recursive:true,force:true})}\""
check 2 hw "TMPDIR=/ node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'usr'),{recursive:true,force:true})\""
check 2 hw "export TMPDIR=\$HOME; node -e \"${N}fs.rmSync(p.join(os.tmpdir(),'Documents'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}process.env.TMPDIR='/';fs.rmSync(p.join(process.env.TMPDIR,'usr'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}os.tmpdir=()=>'/';fs.rmSync(p.join(os.tmpdir(),'usr'),{recursive:true,force:true})\""
check 2 hw "python3 -c \"import shutil,tempfile; shutil.rmtree(tempfile.gettempdir())\""
check 2 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),'..'))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),'/'))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),'a','/etc'))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),x))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; t=tempfile.gettempdir(); t=os.path.expanduser('~'); shutil.rmtree(os.path.join(t,'x'))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; tempfile.tempdir='/'; shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "python3 -c \"import shutil,tempfile,os; t=tempfile.gettempdir(); shutil.rmtree(f'{t}/../x')\""
check 2 hw "python3 -c \"import shutil,os; shutil.rmtree(os.path.join(os.environ['HOME'],'probe-1'))\""
check 2 hw "ruby -e \"require 'fileutils'; require 'tmpdir'; FileUtils.rm_rf(Dir.tmpdir)\""
check 2 hw "ruby -e \"require 'fileutils'; require 'tmpdir'; FileUtils.rm_rf(File.join(Dir.tmpdir,'..'))\""

echo "── C4i hw (round 3): text that reaches a shell through a group or several pipe stages is a command"
check 2 hw "{ echo 'rm -rf ~'; } | sh"
check 2 hw '{ echo "rm -rf ~"; } > x.sh'
check 2 hw "echo 'rm -rf ~' | cat | bash"
check 2 hw "echo 'rm -rf ~' | tee /dev/stderr | sh"
check 2 hw 'echo "rm -rf $HOME" | bash'
check 2 hw "(echo 'rm -rf ~') | bash"
check 2 hw "( echo ok; echo 'rm -rf ~' ) | cat | sudo sh"
check 2 hw "{ printf 'rm -rf ~\\n'; } | bash -s"
check 2 hw "echo 'rm -rf ~' 2>&1 | cat | sh"
check 2 hw "echo 'rm -rf ~' | cat | xargs -I{} sh -c {}"
check 2 hw "(echo 'rm -rf ~') > x.sh"
check 2 hw "{ echo 'npm publish'; } | sh"
check 2 hw '{ echo "npm publish"; } > x.sh'
check 2 hw "{ echo 'firebase deploy'; } | cat | bash"
check 2 hw "{ echo 'never \`rm -rf ~\`'; } | sh"
check 2 hw "{ echo 'never \`rm -rf ~\`'; }"   # a group: no data exemption, the old reading stays
echo "── C4i hw: controls, text that reaches no shell"
check 0 hw "echo 'rm -rf ~' | cat"
check 0 hw 'echo "rm -rf ~" | tee notes.txt'
check 0 hw '{ echo a; echo b; } > out.txt'
check 0 hw 'echo "never rm -rf ~" >> docs/x.md'
check 0 hw '{ echo a; echo b; } | sh'
check 0 hw "echo 'ls -la' | cat | bash"
check 0 hw "echo 'rm -rf build' | cat | bash"
check 0 hw '{ echo "rm -rf ~"; }'
check 0 hw "echo 'rm -rf ~'; echo ok | sh"
check 0 hw "echo 'rm -rf ~' && ls | cat | sh"
check 0 hw "echo 'rm -rf ~' | cat; echo 'ls' | sh"

echo "── C4j hw (round 3): del / delete that does not touch the temp folder variable changes nothing"
check 0 hw "python3 -c \"d={'a':1}; del d['a']; print(d)\""
check 0 hw "node -e \"const o={a:1}; delete o.a; console.log(o)\""
check 0 hw "python3 -c \"import requests; requests.delete(url)\""
check 0 hw "python3 -c \"import shutil,tempfile,os; d={'a':1}; del d['a']; shutil.rmtree(os.path.join(tempfile.gettempdir(),'probe-1'))\""
check 0 hw "node -e \"${N}const o={a:1};delete o.a;fs.rmSync(p.join(os.tmpdir(),'probe-1'),{recursive:true,force:true})\""
check 0 hw "python3 -c \"import shutil,tempfile,os; os.environ['LANG']='C'; shutil.rmtree(os.path.join(tempfile.gettempdir(),'probe-1'))\""
check 0 hw "node -e \"${N}process.env.FOO='1';fs.rmSync(p.join(os.tmpdir(),'probe-1'),{recursive:true,force:true})\""
echo "── C4j hw: controls, the program sets or drops the temp folder variable"
check 2 hw "python3 -c \"import os,shutil,tempfile; os.environ['TMPDIR']='/'; shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "python3 -c \"import os,shutil,tempfile; del os.environ['TMPDIR']; os.environ['TEMP']='/'; shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "python3 -c \"import os,shutil,tempfile; os.environ.pop('TMPDIR'); shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "python3 -c \"import os,shutil,tempfile; os.environ.update({'TMPDIR':'/'}); shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "node -e \"${N}delete process.env.TMPDIR;fs.rmSync(p.join(os.tmpdir(),'usr'),{recursive:true,force:true})\""
check 2 hw "node -e \"${N}process.env={TMPDIR:'/'};fs.rmSync(p.join(os.tmpdir(),'usr'),{recursive:true,force:true})\""
check 2 hw "unset TMPDIR; TMP=/ python3 -c \"import shutil,tempfile,os; shutil.rmtree(os.path.join(tempfile.gettempdir(),'usr'))\""
check 2 hw "ruby -e \"require 'fileutils'; require 'tmpdir'; ENV['TMPDIR']='/'; FileUtils.rm_rf(File.join(Dir.tmpdir,'usr'))\""

echo "── C4k hw (OCR review): the data exemption does not cover text that is stored and then run"
check 2 hw 'printf -v X "npm publish"; $X'
check 2 hw 'printf -v X "npm publish"; eval "$X"'
check 2 hw "printf -v X 'echo \`rm -rf ~\`'; \$X"
check 2 hw 'echo "npm publish" | sort -o x.sh; sh x.sh'
check 2 hw 'echo "adb remount" | sort -o x.sh'
check 2 hw 'echo "npm publish" | sort --output=x.sh'
check 2 hw 'echo "npm publish" | sort -uo x.sh'
check 2 hw 'echo "npm publish" | uniq - x.sh'
check 2 hw 'echo "npm publish" | less -o x.sh'
check 2 hw "echo 'x \`rm -rf ~\`' | sort -o x.sh"
check 2 hw "echo 'never \`rm -rf ~\`' > x.sh; sh ./x*.sh"
check 2 hw "echo 'never \`rm -rf ~\`' > x.sh; . ./x.s?"
check 2 hw "echo 'never \`rm -rf ~\`' > a.py; python3 *.py"
check 2 hw "echo 'never \`rm -rf ~\`' > x; chmod +x x*; ./[x]"
check 2 hw "echo 'never \`rm -rf ~\`' >> run.sh && bash -x run*"
echo "── C4k hw: controls, text that is only printed, filtered or stored"
check 0 hw 'printf "%s\n" "npm publish"'
check 0 hw 'echo "npm publish" | sort'
check 0 hw 'echo "npm publish" | sort -u | uniq -c | head -3'
check 0 hw "echo 'never \`rm -rf ~\`' >> docs/x.md"
check 0 hw "echo 'never \`rm -rf ~\`' >> docs/x.md; git status; ls docs"
check 0 hw "echo 'x \`rm -rf ~\`' | sort | uniq"

echo "── C4l hw (OCR review): only the inline program of an interpreter is read, not a script name or another argument"
check 0 hw 'python3 tools/rm_rf.py build'
check 0 hw 'python3 -m pytest -k "rm_rf or tmp"'
check 0 hw "python3 -c \"print('never rm_rf anything')\""
check 0 hw 'node scripts/clean.js --mode rm_rf'
check 0 hw 'uv run pytest tests/test_rm_rf.py'
check 0 hw "ruby -e \"puts File.read('a.rb').scan(/rm_rf/).size\""
check 0 hw "python3 -c \"import shutil; help(shutil.rmtree)\""
echo "── C4l hw: controls, the inline program is still read"
check 2 hw "python3 -c \"import shutil; shutil.rmtree('/')\""
check 2 hw "python3 -Ic \"import shutil; shutil.rmtree('/')\""
check 2 hw "python3 -c\"import shutil; shutil.rmtree('/')\""
check 2 hw "node --eval \"require('fs').rmSync('/',{recursive:true,force:true})\""
check 2 hw "node -p \"require('fs').rmSync('/',{recursive:true,force:true})\""
check 2 hw "uv run python -c \"import shutil; shutil.rmtree('/')\""
check 2 hw "ruby -e \"require 'fileutils'; FileUtils.rm_rf '/'\""
check 2 hw "ruby -rfileutils -e \"FileUtils.rm_rf('/')\""
check 2 hw "perl -MFile::Path -e \"remove_tree('/')\" ; ruby -e \"require 'fileutils'; FileUtils.rm_r '..'\""

echo "── C4n hw (OCR delta): a flag that ends in c/e/p/E/r without a program of its own does not hide the -c / -e after it"
check 2 hw "python3 -E -c 'import shutil; shutil.rmtree(\"/\")'"
check 2 hw "python3 -Ec 'import shutil; shutil.rmtree(\"/\")'"
check 2 hw "perl -p -e 'use File::Path; rmtree(\"/\")' f"
check 2 hw "perl -i -p -e 'use File::Path; rmtree(\"/\")' f"
check 2 hw "perl -ip -e 'use File::Path; rmtree(\"/\")' f"
check 2 hw "perl -pe 'use File::Path; rmtree(\"/\")' f"
check 2 hw "ruby -p -e 'FileUtils.rm_rf(\"/\")' f"
check 2 hw "node -p -e 'require(\"fs\").rmSync(\"/\",{recursive:true})'"
check 2 hw "node -c -e 'require(\"fs\").rmSync(\"/\",{recursive:true})'"
check 2 hw "python3 -c 'exec(sys.argv[1])' 'shutil.rmtree(\"/\")'"
check 2 hw "ruby -e 'eval ARGV[0]' 'FileUtils.rm_rf \"/\"'"
echo "── C4n hw: a call name inside a string may be code (eval, instance_eval, send :eval …): refused (OCR delta 2; residual: puts of it)"
check 2 hw "ruby -rfileutils -e 'eval \"FileUtils.rm_rf \\\"/\\\"\"'"
check 2 hw "ruby -e 'x = \"FileUtils.rm_rf \\\"/\\\"\"; eval x'"
check 2 hw "ruby -e 'Object.new.instance_eval \"FileUtils.rm_rf Dir.home\"'"
check 2 hw "ruby -e 'Kernel.send :eval, \"FileUtils.rm_rf Dir.home\"'"
check 2 hw "ruby -e 'puts \"FileUtils.rm_rf /\"'"
check 0 hw "perl -ne 'print if /rm_rf \\//' f"
check 2 hw "ruby -e 'puts \"#{FileUtils.rm_rf \"/\"}\"'"
check 2 hw "ruby -e \"x = /'/; rm_rf '/'\""
check 2 hw "ruby -e 'true && rm_rf \"/\"'"
check 2 hw "ruby -e 'x = rm_rf \"/\"'"
check 2 hw "ruby -e 'begin rm_rf \"/\" end'"
check 2 hw "ruby -e 'p 1 if rm_rf \"/\"'"
check 2 hw "ruby -e 'def f = rm_rf \"/\"; f'"
check 2 hw "ruby -e 'puts \"x\"; FileUtils.rm_rf \"/\"'"

echo "── C4m hw (OCR review): many delete calls in one program are read in linear time"
python3 -I - "$HW" "$P" <<'PY' && ok "30 KB / ~700 rmSync calls: within 15x the 3 KB program and under 1.5 s" || fail "the interpreter rule is not linear in the number of delete calls"
import json, os, subprocess, sys, time
hw, proj = sys.argv[1], sys.argv[2]
env = {k: v for k, v in os.environ.items() if k not in ("HARDWARE_SAFETY_GATE", "HARDWARE_OVERRIDE")}
env.update(CLAUDE_PROJECT_DIR=proj)
def cost(kb):
    unit = "fs.rmSync(p.join(t,'a'),{recursive:true});"
    cmd = "node -e \"const t=os.tmpdir();" + unit * (kb * 1024 // len(unit)) + "\""
    inp = json.dumps({"session_id": "s", "transcript_path": "", "cwd": proj, "hook_event_name": "PreToolUse", "tool_name": "Bash",
                      "tool_input": {"command": cmd, "description": "d"}})
    best = None
    for _ in range(3):
        t = time.time()
        rc = subprocess.run(["bash", hw], input=inp, capture_output=True, text=True, cwd=proj, env=env).returncode
        best = min(best or 99, time.time() - t)
    return rc, best
(rc3, t3), (rc30, t30) = cost(3), cost(30)
print("  3 KB: rc %s %.2fs   30 KB: rc %s %.2fs" % (rc3, t3, rc30, t30))
sys.exit(0 if rc3 == 0 and rc30 == 0 and t30 <= 15 * t3 and t30 < 1.5 else 1)
PY

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
