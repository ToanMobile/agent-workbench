#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh: one normalisation step per hook (audit 2026-10-13, every case
# reproduced on the real hooks of HEAD first). Each group: the commands that slipped through (HEAD exit 0, must be 2) or were
# refused by mistake (HEAD exit 2, must be 0), next to a similar command whose verdict must NOT change.
#  hardware, fail-open: a device command string (adb shell / ssh host / su -c) was never walked like a host command, so brace
#    expansion, /./ and .. in a path, a $VAR target, `cd /system && rm -rf *` and `find /system -delete` were out of sight; five
#    partitions were missing; `bash -lc` / `sh -ec` (the -c inside a flag cluster), wrapper option values (sudo -u X, timeout -s SIG N,
#    env -u NAME), gtimeout, arch -arm64 and a redirect before the command hid the rm; an rm reached through find's recursion
#    (find -exec rm {} +, find | xargs rm) without -r; rsync --delete into / or home; npx rimraf; fastboot -w; remount of /;
#    dd of=$VAR; pm uninstall of a package glob.
#  git, fail-open: `git checkout <path>` / `git checkout <tree-ish> <path>` without --, an interpreter reading a heredoc that runs
#    git, git submodule foreach, a forced fetch into a local branch, git pull --rebase (the law blocks rebase), arch / gtimeout /
#    a leading redirect before git.
#  false positives: npm publish --dry-run, terraform destroy -help, kubectl delete --dry-run=client|server, git clean -n with -f,
#    git rm -f --cached, rm -rf "$PWD/build".
# 14/10 (workflow-improvements.md I.0 W3 / I.1 Việc 2): the reading of both hooks is ONE module, hooks/shell_norm.py, and
#  heredocs are found the way the shell finds them. A body nothing runs is data (block-dangerous-git refused a quoted python heredoc
#    whose body held a backtick; hardware_safety_gate read `cat > notes.md <<'EOF'` lines as rm commands); a body a shell runs is
#    still judged, and an unquoted body keeps its $(…) / `…`. A <<'EOF' inside quotes or a comment no longer hides the next lines.
#  git, fail-open: su -c / su USER -c, adb shell, an ssh option value read as the host (ssh -E log host CMD).
#  hardware: ~ as a device rm target (the device shell HOME is not known), xargs -i (GNU: no separate value), the script of
#    bash -lc / su -c for the device policy.
# 03/11 (shard REG-DK-ALL-GATES-01, lane 2): file này chạy riêng 341-686 s và giữ cả shard; các nhóm của nó nay là năm file
#  shard chạy cùng lúc, mọi ca và assertion giữ nguyên: file này (các nhóm tới dòng 14/10), test_guard_shell_norm_reader.sh
#  (chính shell_norm.py, heredoc ghi ra file, bảng dùng chung), test_guard_shell_norm_r4.sh (15/10 r4 P0-A..P3),
#  test_guard_shell_norm_r5.sh và test_guard_shell_norm_r6.sh. Helper dùng chung: tests/lib/guard_shell_norm_lib.sh.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, check / check_mcp / check_deny / pair / r5_rows

echo "── hw: brace expansion in a device path"
check 2 hw 'adb shell "rm -rf /{system,vendor}"'
check 2 hw 'adb shell rm -rf /{system,vendor}'
check 2 hw 'adb shell "rm -rf /{system,data}/*"'
check 0 hw 'adb shell "rm -rf /sdcard/{a,b}"'
check 0 hw 'adb shell rm -rf /sdcard/Download/{x,y}.log'

echo "── hw: /./, .. and // in a device path"
check 2 hw 'adb shell "rm -rf /./system"'
check 2 hw 'adb shell rm -rf /./system/*'
check 2 hw 'adb shell rm -rf /sdcard/../system'
check 0 hw 'adb shell rm -rf /sdcard/./Download/old'
check 0 hw 'adb shell rm -rf /sdcard/x/../y'

echo "── hw: a device target the shell fills in at run time"
check 2 hw 'adb shell rm -rf $ANDROID_ROOT'
check 2 hw "adb shell 'rm -rf \$ANDROID_ROOT/*'"
check 2 hw "adb shell 'rm -rf /system/\$X'"
check 2 hw "ssh u@h 'rm -rf \$TARGET'"
check 0 hw "adb shell 'rm -rf /sdcard/\$X'"
check 0 hw "ssh u@h 'rm -rf /srv/app/\$X'"

echo "── hw: cd on the device, then rm"
check 2 hw 'adb shell "cd /system && rm -rf *"'
check 2 hw 'ssh u@h "cd /system && rm -rf *"'
check 2 hw 'adb shell "cd /vendor; rm -rf app"'
check 2 hw 'adb shell "rm -rf *"'
check 0 hw 'adb shell "cd /sdcard/Download && rm -rf *"'
check 0 hw 'ssh u@h "cd /tmp/x && rm -rf *"'

echo "── hw: find -delete / -exec rm on the device"
check 2 hw 'adb shell "find /system -delete"'
check 2 hw 'adb shell find /vendor -exec rm -rf {} +'
check 0 hw "adb shell \"find /sdcard/Download -name '*.tmp' -delete\""
check 0 hw 'adb shell "find /sdcard/x -delete"'

echo "── hw: the same device command through replicant-mcp adb-shell"
check_mcp 2 'cd /system && rm -rf *'
check_mcp 2 'rm -rf /{system,vendor}'
check_mcp 2 'find /vendor -delete'
check_mcp 0 'rm -rf /sdcard/Download/x'
check_mcp 0 'cd /sdcard && rm -rf old'

echo "── hw: the device policy sees adb behind a wrapper option value"
check_deny 2 'sudo -u me adb -s DENIED1 reboot'
check_deny 2 'timeout -s KILL 5 adb -s DENIED1 shell ls'
check_deny 2 'adb -s DENIED1 reboot'
check_deny 0 'sudo -u me adb -s OK1 reboot'

echo "── hw: partitions that were missing"
check 2 hw 'adb shell rm -rf /cache'
check 2 hw 'adb shell rm -rf /system_root'
check 2 hw 'adb shell rm -rf /product_services'
check 2 hw 'adb shell rm -rf /mnt/vendor/persist'
check 2 hw 'adb shell rm -rf /dev/block'
check 0 hw 'adb shell rm -rf /cachex'
check 0 hw 'adb shell rm -rf /mnt/media_rw/usb/x'

echo "── hw: -c inside a shell flag cluster"
check 2 hw "bash -lc 'rm -rf ~'"
check 2 hw "zsh -lc 'rm -rf ~'"
check 2 hw "sh -ec 'rm -rf ~'"
check 0 hw "bash -lc 'rm -rf build'"
check 0 hw "sh -ec 'rm -rf /tmp/x'"

echo "── hw: wrapper option values, gtimeout, arch, a leading redirect"
check 2 hw 'sudo -u root rm -rf ~'
check 2 hw 'timeout -s KILL 5 rm -rf ~'
check 2 hw 'gtimeout 5 rm -rf ~'
check 2 hw 'env -u HOME rm -rf ~'
check 2 hw '2>/dev/null rm -rf ~'
check 2 hw 'arch -arm64 rm -rf ~'
check 0 hw 'sudo -u root rm -rf build'
check 0 hw 'timeout -s KILL 5 rm -rf build'
check 0 hw '2>/dev/null rm -rf build'
check 0 hw 'arch -arm64 rm -rf build'

echo "── hw: rm reached through find's recursion (no -r)"
check 2 hw 'find . -type f -exec rm {} +'
check 2 hw 'find ~ -type f -exec rm -f {} \;'
check 2 hw 'find / -type f | xargs rm'
check 2 hw 'find ~ -type f -print0 | xargs -0 rm -f'
check 0 hw "find . -name '*.pyc' -exec rm {} +"
check 0 hw 'find build -type f -exec rm {} +'
check 0 hw "find . -name '*.log' | xargs rm"
check 0 hw 'ls *.log | xargs rm'

echo "── hw: rsync --delete into /, home or the project root"
check 2 hw 'rsync -a --delete /tmp/empty/ ~/'
check 2 hw 'rsync -a --delete empty/ /'
check 2 hw 'rsync -av --del src/ .'
check 0 hw 'rsync -a --delete src/ build/'
check 0 hw 'rsync -a --delete dist/ host:/srv/www/'
check 0 hw 'rsync -a ~/x/ /tmp/y/'

echo "── hw: rimraf is rm -rf"
check 2 hw 'npx rimraf ~'
check 2 hw 'npx rimraf src'
check 2 hw 'npx rimraf .'
check 2 hw 'npx -y rimraf@5 /'
check 0 hw 'npx rimraf build'
check 0 hw 'npx rimraf node_modules'

echo "── hw: fastboot -w wipes userdata"
check 2 hw 'fastboot -w'
check 2 hw 'fastboot -s ABC -w reboot'
check 0 hw 'fastboot devices'
check 0 hw 'fastboot -s ABC getvar all'
check 0 hw 'grep -rn "fastboot -w\|rsync" tests/'

echo "── hw: remount / read-write"
check 2 hw 'adb shell mount -o remount,rw /'
check 2 hw 'adb shell "mount -o rw,remount /"'
check 0 hw 'adb shell mount -o remount,ro /'
check 0 hw 'adb shell mount -o rw /dev/block/sda1 /mnt/usb'

echo "── hw: dd of= a target the shell fills in"
check 2 hw 'dd if=/tmp/x.img of=$DISK bs=1m'
check 2 hw 'sudo dd if=x.img of="${DISK}"'
check 2 hw 'dd if=a.img of=$(diskutil list | tail -1)'
check 0 hw 'dd if=/dev/zero of=/tmp/x.img bs=1m count=1'
check 0 hw 'dd if=a.img of=out/$NAME.img'

echo "── hw: a backslash-newline continuation splits no pattern (15/10, adversarial pass: it hid dd of=/dev/…)"
check 2 hw $'dd \\\nif=a.img of=/dev/sda bs=1m'
check 2 hw $'dd if=a.img \\\n  of=/dev/sda bs=1m'
check 2 hw $'adb \\\n  remount'
check 2 hw $'fastboot \\\n -w'
check 0 hw $'dd \\\nif=/dev/zero of=/tmp/x.img bs=1m count=1'

echo "── hw: pm uninstall / disable of a package glob"
check 2 hw 'adb shell pm uninstall com.ecarx.*'
check 2 hw 'adb shell "pm disable-user com.android.*"'
check 0 hw 'adb shell pm uninstall com.example.myapp'
check 0 hw 'adb shell pm list packages com.android.*'

echo "── git: checkout of a path without --"
check 2 git 'git checkout src/a.kt'
check 2 git 'git checkout HEAD src/'
check 2 git 'git checkout HEAD README.md'
check 2 git 'git checkout src'
check 0 git 'git checkout feat'
check 0 git 'git checkout feat 2>/dev/null'
check 0 git 'git checkout HEAD'
check 0 git 'git checkout no-such-branch'

echo "── git: an interpreter reading a heredoc that runs git"
check 2 git $'python3 - <<EOF\nimport subprocess\nsubprocess.run([\'git\', \'reset\', \'--hard\'])\nEOF'
check 2 git $'node - <<\'EOF\'\nrequire(\'child_process\').execSync(\'git reset --hard HEAD~1\')\nEOF'
check 2 git $'cat <<\'EOF\' | python3 -\nimport os\nos.system("git clean -fdx")\nEOF'
check 0 git $'python3 - <<\'EOF\'\ncases = ["git reset --hard", "git push --force"]\nprint(len(cases))\nEOF'
check 0 git $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'git\', \'status\'])\nEOF'
# (policy 15/10, review of ebf9623) the interpreter judgement is the old one again, on the raw text: a comment that mentions the danger and
# the literals of two calls count, which blocks these three harmless programs. ACCEPTED false positives, pinned blocked on purpose.
check 2 git $'python3 - <<\'EOF\'\nimport subprocess\n# never run: git reset --hard\nsubprocess.run([\'git\',\'status\'])\nEOF'
check 2 git $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'git\',\'checkout\',\'main\'])\nsubprocess.run([\'rm\',\'-f\',\'t\'])\nEOF'
check 2 git $'node - <<\'EOF\'\nconst {spawn} = require(\'child_process\');\n// git reset --hard is dangerous\nspawn(\'git\', [\'status\']);\nEOF'
check 2 git $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'git\',\'status\'])\nsubprocess.run([\'git\',\'reset\',\'--hard\'])\nEOF'
check 2 git $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\n  \'git\', \'reset\',\n  \'--hard\',\n])\nEOF'
check 2 git $'python3 - <<\'EOF\'\n# note\nimport os\nos.system("git reset --hard # x")\nEOF'
check 2 git $'node - <<\'EOF\'\nconst {spawn} = require(\'child_process\');\nspawn(\'git\', [\'reset\', \'--hard\']);\nEOF'
check 2 git $'ruby <<\'EOF\'\nsystem "git reset --hard"\nEOF'
check 2 git $'ruby <<\'EOF\'\nexec \'git\', \'reset\', \'--hard\'\nEOF'
check 2 git $'perl <<\'EOF\'\nsystem("git", "clean", "-fdx");\nEOF'
check 2 git $'uv run python - <<EOF\nimport subprocess\nsubprocess.run([\'git\', \'reset\', \'--hard\'])\nEOF'
check 0 git $'poetry run python - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'git\', \'status\'])\nEOF'

echo "── git: submodule foreach runs a command"
check 2 git "git submodule foreach 'git reset --hard'"
check 2 git 'git submodule foreach --recursive git clean -fdx'
check 0 git "git submodule foreach 'git status'"
check 0 git 'git submodule update --init'

echo "── git: forced fetch into a local branch"
check 2 git 'git fetch -f origin main:main'
check 2 git 'git fetch origin +main:main'
check 2 git 'git fetch --force origin refs/heads/main:refs/heads/main'
check 2 git 'git fetch --forc origin main:main'
check 0 git 'git fetch --filter=blob:none origin main:main'
check 0 git 'git fetch origin main:main'
check 0 git 'git fetch -f origin'
check 0 git "git fetch origin '+refs/heads/*:refs/remotes/origin/*'"

echo "── git: pull --rebase (the law blocks rebase)"
check 2 git 'git pull --rebase'
check 2 git 'git pull -r origin main'
check 2 git 'git pull --rebase=merges'
check 0 git 'git pull --no-rebase'
check 0 git 'git pull --ff-only'
check 0 git 'git pull --rebase=false'

echo "── git: wrappers and a redirect before git"
check 2 git 'arch -arm64 git reset --hard'
check 2 git 'gtimeout 5 git reset --hard'
check 2 git '2>/dev/null git reset --hard'
check 0 git 'arch -arm64 git status'
check 0 git '2>/dev/null git status'

echo "── false positives: dry runs and help are not the real thing"
check 0 hw 'npm publish --dry-run'
check 0 hw 'pnpm publish --dry-run --no-git-checks'
check 2 hw 'npm publish --dry-run=false'
check 2 hw 'npm publish'
check 2 hw 'npm publish --dry-run; npm publish'
check 0 hw 'terraform destroy -help'
check 0 hw 'terraform destroy --help'
check 2 hw 'terraform destroy -auto-approve'
check 0 hw 'kubectl delete ns x --dry-run=client'
check 0 hw 'kubectl delete ns x --dry-run=server'
check 2 hw 'kubectl delete ns x --dry-run=none'
check 2 hw 'kubectl delete ns x'
check 0 git 'git clean -nfd'
check 0 git 'git clean -fd --dry-run'
check 0 git 'git clean -n'
# (14/10, OCR) the n of a glued -e value is no dry-run flag: git deletes all the same
check 2 git 'git clean -fdx -enode_modules'
check 2 git 'git clean -fd -eignore'
check 2 git 'cd "$(git rev-parse --show-toplevel)" && git clean -fdx -enode_modules'
check 0 git 'git clean -fdn -e node_modules'
check 2 git 'git clean -fd'
check 2 git 'git clean -f -d -x'
check 0 git 'git rm -f --cached src/a.kt'
check 0 git 'git rm -r -f --cached build'
check 2 git 'git rm -f src/a.kt'
# the same inside a command with $(…), which the raw regex judges first
check 0 git 'cd "$(git rev-parse --show-toplevel)" && git clean -nfd'
check 2 git 'cd "$(git rev-parse --show-toplevel)" && git clean -fd'
check 0 git 'cd "$(git rev-parse --show-toplevel)" && git rm -f --cached src/a.kt'
check 2 git 'cd "$(git rev-parse --show-toplevel)" && git rm -f src/a.kt'

echo "── false positive: \$PWD is the cwd"
check 0 hw 'rm -rf "$PWD/build"'
check 0 hw 'rm -rf ${PWD}/build'
check 2 hw 'rm -rf "$PWD/src"'
check 2 hw 'rm -rf "$PWD"'
check 2 hw 'cd $X && rm -rf "$PWD/build"'

echo "── heredoc: a body nothing runs is data (main refused these)"
check 0 git $'python3 - <<\'EOF\'\ndoc = """Run `git checkout -b feature` to start."""\nprint(doc)\nEOF'
check 0 git $'python3 - <<\'EOF\'\ncases = ["git reset --hard", "x"]\nprint("a `b` c", len(cases))\nEOF'
check 0 git $'cat > notes.md <<EOF\ngit reset --hard is never used here\nEOF'
# (15/10, OCR) a program that is not a known pure data reader and gets a heredoc on stdin keeps its body in the scan: `python3 tool.py`
# may run it (main's RUNS_INPUT did); this line used to expect 0 (the quoted body was cut as text)
check 2 git $'python3 tool.py <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'python3 -m runner <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'node tool.js <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'ruby -e \'system(STDIN.read)\' <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'perl -ne \'system $_\' <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'ruby -ne \'system $_\' <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'perl -e \'system(<STDIN>)\' <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'node -e "require(\'child_process\').execSync(require(\'fs\').readFileSync(0,\'utf8\'))" <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'cat <<\'EOF\' | python3 -c \'import os,sys; os.system(sys.stdin.read())\'\ngit reset --hard\nEOF'
check 0 git $'mystery-tool <<\'EOF\'\ngit status\nEOF'
check 0 hw $'cat > notes.md <<\'EOF\'\nrm -rf ~\nEOF'
check 0 hw $'cat > notes.md <<EOF\nrm -rf ~\nEOF'
check 0 hw $'cat > notes.md <<\'EOF\'\nnever run adb remount\nEOF'
check 0 hw $'git commit -q -F - <<\'EOF\'\nrm -rf ~ is refused now\nEOF'
echo "── hw heredoc: a body an interpreter reads is source, but one that can start a process stays in the rm walk (15/10, OCR: perl/ruby/php"
echo "   backticks, qx, %x went 2 -> 0)"
check 2 hw $'perl <<\'EOF\'\nmy $x = `rm -rf ~`;\nEOF'
check 2 hw $'ruby <<\'EOF\'\n%x(rm -rf ~)\nEOF'
check 2 hw $'ruby <<\'EOF\'\n`rm -rf $HOME`\nEOF'
check 2 hw $'perl <<\'EOF\'\nqx(rm -rf ~);\nEOF'
check 2 hw $'php <<\'EOF\'\n<?php `rm -rf ~`; ?>\nEOF'
check 2 hw $'cat > x.rb <<\'EOF\'\n`rm -rf ~`\nEOF\nruby x.rb'
check 0 hw $'python3 - <<\'EOF\'\nprint("rm -rf ~ is dangerous")\nEOF'
check 0 hw $'ruby <<\'EOF\'\nputs "rm -rf ~ is dangerous"\nEOF'
echo "── heredoc: a body a shell runs, or a \$(…) in an unquoted body, is still judged"
check 2 git $'bash <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'cat <<\'EOF\' | sh\ngit clean -fdx\nEOF'
check 2 git $'ssh u@h <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'cat > notes.md <<EOF\nnow $(git reset --hard) x\nEOF'
check 2 git $'cat > notes.md <<EOF\nnow `git clean -fdx` x\nEOF'
check 2 git $'X=$(python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'git\', \'reset\', \'--hard\'])\nEOF\n)'
check 2 git $'ruby <<\'EOF\'\n`git reset --hard`\nEOF'
check 2 hw $'bash <<\'EOF\'\nrm -rf ~\nEOF'
check 2 hw $'cat <<\'EOF\' | sh\nrm -rf ~\nEOF'
check 2 hw $'cat > notes.md <<EOF\nnow $(rm -rf ~) x\nEOF'
check 2 hw $'cat > x.sh <<\'EOF\'\nrm -rf ~\nEOF\nbash x.sh'
check 2 hw $'cat > x.sh <<\'EOF\'\nrm -rf ~\nEOF\nchmod +x x.sh && ./x.sh'
check 2 hw $'cat > x.txt <<\'EOF\'\nrm -rf ~\nEOF\nmystery x.txt'
check 2 git $'cat > /tmp/x.sh <<\'EOF\'\ngit reset --hard\nEOF\nbash /tmp/x.sh'
# accepted false positive (policy 15/10): anything after the statement keeps the body in the scan, a script that is then run included
check 2 hw $'cat > probe.py <<\'EOF\'\nrm -rf ~\nEOF\npython3 probe.py'
check 2 hw $'cat > notes.txt <<\'EOF\'\nrm -rf ~\nEOF\nwc -l notes.txt'
check 2 hw $'echo "$(cat <<\'EOF\'\nrm -rf ~\nEOF\n)" | sh'
check 2 hw $'read -r -d \'\' X <<\'EOF\'\nrm -rf ~\nEOF\neval "$X"'
check 2 hw $'mysql <<EOF\nDROP TABLE users;\nEOF'
check 2 hw $'adb shell <<\'EOF\'\nmount -o rw,remount /system\nEOF'
echo "── heredoc: a << inside quotes or a comment is no heredoc (main cut the next lines unjudged)"
check 2 git $'echo "<<\'EOF\'"\ngit reset --hard\nEOF'
check 2 git $'echo x # <<\'EOF\'\ngit reset --hard\nEOF'
check 2 hw $'echo "<<\'EOF\'"\nrm -rf ~\nEOF'
check 0 git $'echo "<<\'EOF\'"\ngit status\nEOF'
# a here-string (<<<) is no heredoc: its last two < read as << \x27x\x27 cut the lines up to a line x (main did it for git too)
check 2 git $'cat <<< \'x\'\ngit reset --hard\nx'
check 2 hw $'cat <<< \'x\'\nrm -rf ~\nx'
check 0 git $'grep -c a <<< "abc"\ngit status'

echo "── git: su -c, adb shell and an ssh option value"
check 2 git "su -c 'git reset --hard'"
check 2 git 'su root -c "git clean -fdx"'
check 2 git "sudo su -c 'git push --force origin main'"
check 2 git "adb shell 'git reset --hard'"
check 2 git "ssh -E ssh.log u@h 'git reset --hard'"
check 0 git "su -c 'git status'"
check 0 git "adb shell 'ls /sdcard'"
check 0 git "ssh -E ssh.log u@h 'git log -1'"
# (14/10, OCR) su --command / -s SHELL USER CMD, an ssh flag cluster whose last letter takes a value, adb shell<<EOF
check 2 git "su --command='git reset --hard'"
check 2 git "su --command 'git reset --hard'"
check 2 git 'su -s /bin/sh root git reset --hard'
check 2 git "ssh -tp 22 u@h 'git push --force origin main'"
check 0 git "ssh -tp 22 u@h 'git status'"
check 2 git $'adb shell<<\'EOF\'\ngit reset --hard\nEOF'
# a body read into a variable that a later eval runs; a python program written to a file and then run; a Makefile make runs
check 2 git $'read -r -d \'\' X <<\'EOF\'\ngit reset --hard\nEOF\neval "$X"'
check 2 git $'cat > x.py <<\'EOF\'\nimport os\nos.system("git reset --hard")\nEOF\npython3 x.py'
check 2 git $'cat > Makefile <<\'EOF\'\nall:\n\tgit reset --hard\nEOF\nmake'
check 2 hw $'cat > Makefile <<\'EOF\'\nall:\n\trm -rf ~\nEOF\nmake'
check 2 hw $'cat > notes.mk <<\'EOF\'\nall:\n\trm -rf ~\nEOF\nmake'
check 2 hw $'cat <<\'EOF\' > a.txt && cat a.txt | sh\nrm -rf ~\nEOF'
check 2 git $'mapfile -t L <<\'EOF\'\ngit reset --hard\nEOF\neval "${L[0]}"'

echo "── hw: su --command / --session-command (review 15/10: a TypeError, the verdict was a crash, the rm walk never ran)"
check 0 hw "su --command='rm -rf /tmp/build'"
check 0 hw "su --command 'rm -rf /tmp/build'"
check 0 hw "su root --session-command 'rm -rf /tmp/x'"
check 0 hw "su -c 'rm -rf /tmp/build'"
check 2 hw "su --command='rm -rf /'"
check 2 hw "su --command 'rm -rf ~'"
check 2 hw "su --session-command='rm -rf ~'"
check 2 hw "su root --session-command 'rm -rf ~'"
check 2 hw "su -c 'rm -rf ~'"
check 2 hw "su -s /bin/sh root rm -rf ~"
check 0 hw "su -s /bin/sh root rm -rf /tmp/x"
check 2 hw 'su root rm -rf /system'
check_deny 2 "su --command='adb -s DENIED1 reboot'"
check_deny 2 "su root --session-command 'adb -s DENIED1 reboot'"
check_deny 0 "su --command='adb -s OK1 reboot'"

echo "── hw: ~ on a device, xargs -i, the device policy behind bash -lc / su -c"
check 2 hw 'adb shell rm -rf ~'
check 2 hw 'adb shell "rm -rf ~/"'
check 0 hw 'adb shell rm -rf /sdcard/Download/old'
check 0 hw "ssh u@h 'rm -rf ~/tmp/build'"
check 2 hw 'ls | xargs -i rm -rf {}'
check 0 hw "find . -name '*.tmp' | xargs -i rm -rf {}"
check_deny 2 "bash -lc 'adb -s DENIED1 reboot'"
check_deny 2 "su -c 'adb -s DENIED1 reboot'"
check_deny 0 "bash -lc 'adb -s OK1 reboot'"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
