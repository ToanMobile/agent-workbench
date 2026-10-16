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
#  shell_norm.py itself: the heredoc reader kinds, and the fail-closed import (a hook copied without the module blocks).
# 15/10 r5 (independent verification of the r4 tree, every dangerous row ran its harmless marker twin under /bin/bash 3.2 and zsh): the guards no longer
#  rewrite the newlines of the text (a quoted script keeps its heredoc terminators), a comment that ends in a backslash is read joined AND as typed, an
#  interpreter program whose output a $( ), a redirect or a pipe takes is never cut, and zx / Bun / dax / Deno count as programs that start a process.
#  The last section of the file ("r5") holds those rows; its accepted false positives are pinned blocked.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
# a hook that crashes fails closed (rc 2 and "lỗi nội bộ" on stderr): never the verdict a case waits for (review 15/10: su --command)
crashed() { grep -q -E 'lỗi nội bộ|python không chạy được|không nạp được shell_norm.py' "$TMP/err"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH

P="$TMP/work/proj"
mkdir -p "$P/src/sub" "$P/build"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && printf 'y\n' > "$P/src/sub/b.kt" && printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init && git -C "$P" branch feat

# check <want rc> <hw|git> <command>
check() {
  local want="$1" hook="$2" c="$3" h
  [ "$hook" = hw ] && h="$HW" || h="$GG"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$h" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  if [ "$rc" = "$want" ] && ! crashed; then ok "$hook rc $rc: ${s:0:110}"; else fail "$hook rc $rc (want $want): ${s:0:110} — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}

# check_mcp <want rc> <device command>: the same through replicant-mcp adb-shell (its command runs on the device)
check_mcp() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"mcp__replicant-mcp__adb-shell","tool_input":{"command":sys.argv[1]}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "mcp rc $rc: $c"; else fail "mcp rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}
# check_deny <want rc> <command>: with the serial DENIED1 on the device denylist (only literal -s serials here: no adb call)
check_deny() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS=DENIED1 ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "deny rc $rc: $c"; else fail "deny rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}

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

echo "── shell_norm.py: heredoc reader kinds, and the hooks fail closed without it"
SN_DIR="$(cd "$(dirname "$HW")" && pwd)"
python3 -I - "$SN_DIR" > "$TMP/sn.txt" 2>&1 <<'PY'
import sys
import time
sys.dont_write_bytecode = True
sys.path.append(sys.argv[1])
import shell_norm as sn
D, S, I, O, SRC = "data", "shell", "interp", "other", "source"
CASES = [
    # data: a message of a known option, the ONE file statement of the command, git commit -F -
    ("cat > notes.md <<'EOF'\nrm -rf ~\nEOF", [("EOF", D, True)]),
    ("cat > notes.md <<EOF\nx\nEOF\n# written", [("EOF", D, True)]),
    ("cat <<'EOF' > notes.md\nx\nEOF", [("EOF", D, True)]),
    ("cat >> notes.md <<-EOF\n\tx\n\tEOF", [("EOF", D, True)]),
    ("tee notes.md <<'EOF'\nx\nEOF", [("EOF", D, True)]),
    ("cd docs && cat > notes.md <<'EOF'\nx\nEOF", [("EOF", D, True)]),
    ("mkdir -p docs && cat >> docs/notes.md <<'EOF'\nx\nEOF", [("EOF", D, True)]),
    ("git commit -q -F - <<'EOF'\nmsg\nEOF", [("EOF", D, True)]),
    ("git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\"", [("EOF", D, True)]),
    ("git add -A && git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\" && git status", [("EOF", D, True)]),
    ("git commit --message=\"$(cat <<'EOF'\nmsg\nEOF\n)\"", [("EOF", D, True)]),
    ("git tag -a v1 -m \"$(cat <<'EOF'\nmsg\nEOF\n)\"", [("EOF", D, True)]),
    ("gh pr create --title t --body \"$(cat <<'EOF'\nmsg\nEOF\n)\"", [("EOF", D, True)]),
    ("gh release create v1 --notes \"$(cat <<'EOF'\nmsg\nEOF\n)\"", [("EOF", D, True)]),
    # not data: a follower, a second heredoc, a hook / config / script target, a message of no known option, a consumer that runs it
    ("cat > x.sh <<'EOF'\nls\nEOF\nbash x.sh", [("EOF", O, True)]),
    ("cat > notes.md <<'EOF'\nls\nEOF\nwc -l notes.md", [("EOF", O, True)]),
    ("cat > notes.md <<'EOF'\nls\nEOF\nbash run.sh", [("EOF", O, True)]),
    ("cat > a.md <<'EOF'\nx\nEOF\ncat > b.md <<'EOF'\ny\nEOF", [("EOF", O, True), ("EOF", O, True)]),
    ("cat <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .git/hooks/pre-commit <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > ~/.zshenv <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > ~/.config/git/config <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .pre-commit-config.yaml <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > Makefile <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .claude/settings.json <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > pyproject.toml <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > n.yaml <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > hooks/README.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cd .git/hooks && cat > n.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .notes.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > docs/notes.rst <<'EOF'\nls\nEOF", [("EOF", D, True)]),
    ("cat > notes.txt <<'EOF'\nls\nEOF", [("EOF", D, True)]),
    ("cat > notes <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("echo \"$(cat <<'EOF'\nls\nEOF\n)\"", [("EOF", O, True)]),
    ("git -c alias.x=\"$(cat <<'EOF'\n!ls\nEOF\n)\" x", [("EOF", O, True)]),
    ("git config alias.x \"$(cat <<'EOF'\n!ls\nEOF\n)\"", [("EOF", O, True)]),
    ("git bisect run python3 -c \"$(cat <<'EOF'\nimport os\nEOF\n)\"", [("EOF", O, True)]),
    ("git commit -m $(cat <<'EOF'\nmsg\nEOF\n)", [("EOF", O, True)]),
    ("git commit -m \"$(cat <<EOF\nmsg\nEOF\n)\"", [("EOF", O, True)]),
    ("git commit -m \"$(sort <<'EOF'\nmsg\nEOF\n)\"", [("EOF", O, True)]),
    ("sudo -u root cat <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("python3 tool.py <<'EOF'\nx\nEOF", [("EOF", O, True)]),
    ("mysql <<EOF\nDROP TABLE x;\nEOF", [("EOF", O, True)]),
    ("read -r X <<'EOF'\nx\nEOF", [("EOF", O, True)]),
    ("cat <<EOF\nno end", [("EOF", O, False)]),
    # a script written to a file is judged as source by the git guard and never cut
    ("cat > p.py <<'EOF'\nprint(1)\nEOF\npython3 p.py", [("EOF", SRC, True)]),
    ("tee -a x.js <<'EOF'\nx\nEOF", [("EOF", SRC, True)]),
    # an interpreter reads it as its program
    ("python3 - <<'EOF'\nprint(1)\nEOF", [("EOF", I, True)]),
    ("cat <<'EOF' | python3 -\nprint(1)\nEOF", [("EOF", I, True)]),
    ("X=$(python3 - <<'EOF'\nprint(1)\nEOF\n)", [("EOF", I, True)]),
    # a shell reads it
    ("bash <<'EOF'\nls\nEOF", [("EOF", S, True)]),
    ("cat <<'EOF' | sh\nls\nEOF", [("EOF", S, True)]),
    ("adb shell <<'EOF'\nls\nEOF", [("EOF", S, True)]),
    ("ssh h <<'EOF'\nls\nEOF", [("EOF", S, True)]),
    ("echo \"$(cat <<'EOF'\nls\nEOF\n)\" | sh", [("EOF", S, True)]),
    # no heredoc at all: a << inside quotes, a comment, arithmetic, a here-string, a $'..' / $".." word (not decoded: bash and zsh differ)
    ("echo \"<<'EOF'\"\nls\nEOF", []),
    ("echo x # <<'EOF'\nls\nEOF", []),
    ("echo $((1 << 2))\nls", []),
    ("cat <<< 'x'\nls\nx", []),
    ("cat <<<x\nls\nx", []),
    ("cat <<$'EOF'\nhi\nEOF\nls", []),
    ("cat <<$\"EOF\"\nhi\nEOF\nls", []),
    ("cat <<-$'EOF'\n\thi\n\tEOF\nls", []),
    ("cat <<$'E\\x4fF'\nhi\nEOF\nls", []),
    ("cat <<\"$EOF\"\nhi\n$EOF\nls", [("$EOF", O, True)]),
    # 15/10 r4 P0-A: an unquoted body joins its continuation lines like the shell, so E\<nl>OF IS the delimiter (the next lines are commands, no
    # statement); a quoted body at top level joins nothing; x\<nl>EOF is xEOF, the body goes on; an escaped backslash joins nothing
    ("cat > n.md <<EOF\nhi\nE\\\nOF\nls\nEOF\n", [("EOF", O, True)]),
    ("cat > n.md <<EOF\nhi\nE\\\nOF\n", [("EOF", D, True)]),
    ("cat > n.md <<EOF\nhi\nEO\\\nF\n", [("EOF", D, True)]),
    ("cat > n.md <<'EOF'\nhi\nE\\\nOF\nls\nEOF\n", [("EOF", D, True)]),
    ("cat > n.md <<EOF\nhi\nx\\\nEOF\nls\nEOF\n", [("EOF", D, True)]),
    ("cat > n.md <<EOF\nhi\nE\\\\\nOF\nEOF\n", [("EOF", D, True)]),
    ("cat > n.md <<-EOF\n\thi\n\tE\\\nOF\nls\n", [("EOF", O, True)]),
    ("python3 - <<EOF\nx\nE\\\nOF\nls\nEOF\n", [("EOF", I, True)]),
    ("cat <<EOF\nx\nE\\", [("EOF", O, False)]),
    # a continuation that ends a line at the very end of the text joins nothing
    ("cat <<EOF\nx\\\n", [("EOF", O, False)]),
    # 15/10 r4 P0-D: the sinks after the operator (inside $( ) too) and sudo -s / -i / --shell with no command: a shell reads the heredoc
    ("python3 -c \"pass\" \"$(cat <<'EOF' | sh\nx\nEOF\n)\"", [("EOF", S, True)]),
    ("x=$(cat <<'EOF' | bash\nx\nEOF\n)", [("EOF", S, True)]),
    ("x=$(cat <<'EOF' | python3 -\nx\nEOF\n)", [("EOF", I, True)]),
    ("x=$(cat <<'EOF' \\\n| sh\nx\nEOF\n)", [("EOF", S, True)]),
    ("x=$(cat <<'EOF' | wc -l\nx\nEOF\n)", [("EOF", O, True)]),
    ("node -e \"x\" \"$(cat <<'EOF'\nx\nEOF\n)\"", [("EOF", O, True)]),
    ("python3 -c \"pass\" \"$(cat <<'EOF'\nx\nEOF\n)\"", [("EOF", O, True)]),
    ("python3 -c \"$(cat <<'EOF'\nx\nEOF\n)\"", [("EOF", I, True)]),
    ("python3 -c \"$(cat <<'EOF' | sh\nx\nEOF\n)\"", [("EOF", S, True)]),
    ("python3 -c \"$(cat <<'EOF'\nx\nEOF\n); ls\"", [("EOF", I, True)]),
    ("sudo -s <<'EOF' | python3 -\nx\nEOF", [("EOF", S, True)]),
    ("sudo -i <<'EOF' | python3 -\nx\nEOF", [("EOF", S, True)]),
    ("doas -s <<'EOF' | python3 -\nx\nEOF", [("EOF", S, True)]),
    ("sudo -u root -s <<'EOF' | python3 -\nx\nEOF", [("EOF", S, True)]),
    ("sudo --shell <<'EOF'\nx\nEOF", [("EOF", S, True)]),
    ("sudo -s <<'EOF' | cat\nx\nEOF", [("EOF", S, True)]),
    ("sudo -u root <<'EOF'\nx\nEOF", [("EOF", O, True)]),
    # 15/10 r4 P3: not prose for a note file
    ("cat > CLAUDE.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > AGENTS.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > docs/agents.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > CMakeLists.txt <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > requirements.txt <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > dev-requirements.txt <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .claude/commands/x.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > .agents/notes.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cd .claude && cat > x.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > /etc/n.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > ~root/n.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > ../n.md <<'EOF'\nls\nEOF", [("EOF", O, True)]),
    ("cat > docs/guide.md <<'EOF'\nls\nEOF", [("EOF", D, True)]),
    ("cat > docs/claude-notes.md <<'EOF'\nls\nEOF", [("EOF", D, True)]),
]
bad = 0
for cmd, want in CASES:
    got = [(h.delim, h.kind, h.terminated) for h in sn.heredocs(cmd)]
    shown = cmd.replace("\n", " ⏎ ")[:70]
    print(("✔ " if got == want else "✖ ") + f"kinds {shown}: {got}" + ("" if got == want else f" (want {want})"))
    bad += got != want
data = lambda h: h.kind == D
# an unquoted body that holds a $ or a backtick is never cut (review 15/10: the extraction of its $( ) paired parentheses without regard to
# quotes, comments or case, and dropped the rest of the body from the scan); the others are cut as before
for cmd, want in [("cat > f.txt <<EOF\na $(rm -rf ~) b `ls`\nEOF", "cat > f.txt <<EOF\na $(rm -rf ~) b `ls`\nEOF"),
                  ("cat > f.txt <<EOF\n$(echo \")\" ; rm -rf ~)\nEOF", "cat > f.txt <<EOF\n$(echo \")\" ; rm -rf ~)\nEOF"),
                  ("cat > f.txt <<EOF\na $x b\nEOF", "cat > f.txt <<EOF\na $x b\nEOF"),
                  ("cat > f.txt <<EOF\nplain text\nEOF", "cat > f.txt <<EOF\n"),
                  ("cat > f.txt <<'EOF'\na $(echo \")\" ; rm -rf ~) `x`\nEOF", "cat > f.txt <<'EOF'\n"),
                  ("cat <<EOF\nno end", "cat <<EOF\nno end")]:
    got = sn.strip_heredocs(cmd, data)
    print(("✔ " if got == want else "✖ ") + f"strip {cmd!r}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
# R1: a body is cut only when every construct outside the bodies is modeled (cut_ok); each of these makes the scanner untrustworthy
STMT = "cat > f.txt <<'EOF'\nbody\nEOF"
UNMODELED = ["echo ${x}", "echo $[1+2]", "echo ${x//<<EOF}", "echo $[1<<2]", "echo $((1<<2))", "(true)", "(true)#", "{ true; }", "if true; then true; fi",
             "for i in 1; do true; done", "while false; do true; done", "case x in x) true;; esac", "f() { true; }", "function f { true; }",
             "trap true EXIT", "eval true", "source x", ". x", "exec true", "true &", "diff <(true) <(true)", "tee >(cat)", "cat <<< x",
             "echo `true`", "echo \"`true`\"", "echo $'a'", "echo $\"a\"", "echo a\\\nb", "echo \\a", "echo \"${x}\"", "echo \"$((1))\"",
             "echo a\rb", "echo a\x00b", "FOO=$'x' true"]
MODELED = ["echo hi", "echo 'a b' \"c d\" $x $(date)", "echo \"$(date +%F)\"", "true && true || true; true | cat", "echo a # comment",
           "cd /tmp && ls", "cat < f.txt > g.txt 2>&1", "echo x 2>/dev/null", "FOO=1 true", "ls *.md {a,b}"]
for x in UNMODELED:
    ok = not sn.heredocs(x + "\n" + STMT)[-1].cut_ok if sn.heredocs(x + "\n" + STMT) else False
    print(("✔ " if ok else "✖ ") + f"cut_ok is False when a construct is not modeled: {x!r}")
    bad += not ok
for x in MODELED:
    docs = sn.heredocs(x + "\n" + STMT)
    ok = bool(docs) and docs[-1].cut_ok
    print(("✔ " if ok else "✖ ") + f"cut_ok is True for modeled constructs: {x!r}")
    bad += not ok
# the gate itself: a message argument is data, yet it is cut only in a command that is modeled (cut_ok)
MSG = "git commit -m \"$(cat <<'EOF'\nbody\nEOF\n)\""
for pre, want in (("echo x\n", "echo x\ngit commit -m \"$(cat <<'EOF'\n)\""), ("echo ${x}\n", "echo ${x}\n" + MSG), ("true &\n", "true &\n" + MSG),
                  ("(true)\n", "(true)\n" + MSG), ("trap true EXIT\n", "trap true EXIT\n" + MSG)):
    got = sn.strip_heredocs(pre + MSG, data)
    print(("✔ " if got == want else "✖ ") + f"strip of a message argument after {pre.strip()!r}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
# a delimiter word that is not plain (escaped, decoded, expanded, punctuation, non-ASCII) is never cut either
for w in ("\\EOF", "E\"\"OF", "'E'\"O\"F", "$EOF", "EOF.", "E-F", "\u00c9OF", "'EOF'x"):
    docs = sn.heredocs("cat > f.txt <<" + w + "\nbody\n" + (w.strip("'\"\\").replace("\"", "")) + "\n")
    ok = not any(h.cut_ok for h in docs)
    print(("✔ " if ok else "✖ ") + f"cut_ok is False for the heredoc word {w!r}")
    bad += not ok
# the sinks an interpreter program can start a process with (the hardware gate keeps such a body in its rm walk)
SINKS = [("python3", "os.posix_spawn('/bin/sh', ['sh'], os.environ)"), ("python3", "os.posix_spawnp('sh', ['sh'], os.environ)"),
         ("python3", "import commands\ncommands.getoutput('x')"), ("python3", "import subprocess\nsubprocess.getoutput('x')"),
         ("perl", "readpipe('x');"), ("perl", "syscall(59, '/bin/sh', 0, 0);"), ("php", "<?php pcntl_exec('/bin/sh');"), ("ruby", "`x`"),
         ("node", "process.binding('spawn_sync').spawn({})"), ("python3", "os.system('x')"), ("perl", "qx(x);")]
NO_SINKS = [("python3", "print('hello')"), ("node", "console.log(1)"), ("ruby", "puts 1"), ("python3", "x = ['git', 'status']")]
bad_s = [(p_, b_) for p_, b_ in SINKS if not sn.spawns(b_, p_)] + [(p_, b_) for p_, b_ in NO_SINKS if sn.spawns(b_, p_)]
print(("✔ " if not bad_s else "✖ ") + f"spawns: {len(SINKS)} process-starting programs seen, {len(NO_SINKS)} plain ones not" + (f" — wrong: {bad_s}" if bad_s else ""))
bad += bool(bad_s)
# the redirect the lexer splits (2> & 1): prefix_end skips the operator, the & and the descriptor (the hooks join the & first)
pe = [sn.prefix_end(w) for w in (["2>", "&", "1", "git", "reset"], [">", "&", "2", "git"], ["3<", "&", "0", "git"], ["2>/dev/null", "git"],
                                 ["sudo", "--user", "root", "git"], ["time", "-p", "git"], ["env", "-P", "/usr/bin", "git"])]
ok = pe == [3, 3, 3, 1, 3, 2, 3]
print(("✔ " if ok else "✖ ") + f"prefix_end of a lexer-split redirect and the new wrapper options: {pe}")
bad += not ok
# env -iS STR / -vS STR: -S as the last letter of a cluster takes the string (it ran unseen); -u / -C / -P too, glued or the next word
inl = [sn.inline_script(w) for w in (["env", "-iS", "git status"], ["env", "-i", "-S", "ls -l"], ["env", "-iSls -l"], ["env", "--split-string=ls -l", "x"],
                                     ["env", "-iu", "X", "ls"], ["env", "-uX", "ls"])]
ok = inl == [["env", "git", "status"], ["env", "-i", "ls", "-l"], ["env", "ls", "-l"], ["env", "ls", "-l", "x"], ["env", "-iu", "X", "ls"], ["env", "-uX", "ls"]]
print(("✔ " if ok else "✖ ") + f"inline_script of env clusters: {inl}")
bad += not ok
# bounds (review 15/10): a brace bomb is judged as the worst target (/), past 24 heredocs nothing is cut, and both stay fast
six, seven, bomb = sn.braces("/{,x}" * 6 + "system"), sn.braces("/{,x}" * 7 + "system"), sn.braces("/{,x}" * 14 + "system")
ok = len(six) == 64 and "/" not in six and "/" in seven and "/" in bomb and len(bomb) <= 65   # the bound is the cap, not the clock
print(("✔ " if ok else "✖ ") + f"braces: 6 groups {len(six)} words, 7 groups bomb={'/' in seven}, 14 groups {len(bomb)} words")
bad += not ok
many = "".join("cat <<'E%d'\nx\nE%d\n" % (i, i) for i in range(120))
docs = sn.heredocs(many)
ok = len(docs) == 120 and all(h.kind == "shell" and not h.cut_ok for h in docs)   # past MAX_HEREDOCS none is classified or cut
print(("✔ " if ok else "✖ ") + f"120 heredocs: none classified, none cut (the classification was quadratic: 100 heredocs took 2.5 s)")
bad += not ok
# 15/10 r4 P1: a backslash-newline is a continuation only when the backslash is not itself escaped (an odd run before the newline)
for got, want in [(sn.join_continuations("a\\\nb"), "ab"), (sn.join_continuations("a\\\\\nb"), "a\\\\\nb"), (sn.join_continuations("a\\\\\\\nb"), "a\\\\b"),
                  (sn.join_continuations("a\\\\\\\\\nb"), "a\\\\\\\\\nb"), (sn.join_continuations("a\\\n\\\nb"), "ab"), (sn.join_continuations("a\nb\\\n"), "a\nb"),
                  (sn.join_continuations("\\\\\\\\\\\n"), "\\\\\\\\"), (sn.join_continuations("plain"), "plain"), (sn.join_continuations("x\\\\ \\\ny"), "x\\\\ y")]:
    print(("✔ " if got == want else "✖ ") + f"join_continuations: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
# 15/10 r5: the one lexer of both guards: a newline outside quotes is a word of its own (merged with the separators around it), a newline inside quotes
# stays in its word as typed (the old " ;<nl>" rewrite changed the newlines of a quoted script too)
for text, want in [("a b\nc", ["a", "b", "\n", "c"]), ("'a\nb' c", ["a\nb", "c"]), ('"x\ny"', ["x\ny"]), ("a &&\nb", ["a", "&&\n", "b"]), ("a |\nb", ["a", "|\n", "b"]), ("a;\n\nb", ["a", ";\n\n", "b"]),
                   ("python3 - <<EOF\nEOF\nx", ["python3", "-", "<<EOF", "\n", "EOF", "\n", "x"]), ("sh -c 'a\nEOF\nb'", ["sh", "-c", "a\nEOF\nb"])]:
    got = sn.lex_words(text)
    print(("✔ " if got == want else "✖ ") + f"lex_words {text!r}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
try:
    sn.lex_words("echo 'x")
    print("✖ lex_words of an open quote must raise ValueError")
    bad += 1
except ValueError:
    print("✔ lex_words of an open quote raises ValueError")
# readings: the joined text, and a second one (every continuation kept as a newline) only when a COMMENT ends in a backslash
for text, want in [("echo a\\\nb", ["echo ab"]), ("# c\\\nb", ["# cb", "# c\nb"]), ("true # c\\\n\\\nb", ["true # cb", "true # c\n\nb"]), ("rm -rf bu\\\nild", ["rm -rf build"]),
                   ("plain", ["plain"]), ("echo a\\\\\nb # c", ["echo a\\\\\nb # c"]), ("echo a\\\\\\\ngit status", ["echo a\\\\git status"]),
                   ("echo \"a # b\" \\\nc", ["echo \"a # b\" c", "echo \"a # b\" \nc"])]:
    got = sn.readings(text)
    print(("✔ " if got == want else "✖ ") + f"readings {text!r}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
# captured: the output of an interpreter program is taken by a $( ), a redirect, a pipe or a group; program_cut cuts only a program nothing takes that cannot spawn
for cmd, want in [("python3 - <<'EOF'\nprint(1)\nEOF", False), ("python3 - <<'EOF' 2>/dev/null\nprint(1)\nEOF", True), ("python3 - <<'EOF' > s.sh\nprint(1)\nEOF\nsh s.sh", True),
                  ("python3 - <<'EOF' | tee s.sh\nprint(1)\nEOF", True), ("x=$(python3 - <<'EOF'\nprint(1)\nEOF\n)", True), ("`python3 - <<'EOF'\nprint(1)\nEOF\n`", True),
                  ("{ python3 - <<'EOF'\nprint(1)\nEOF\n} > s.sh", True), ("(python3 - <<'EOF'\nprint(1)\nEOF\n)", True),
                  ("python3 -c \"$(cat <<'EOF'\nprint(1)\nEOF\n)\"", False),
                  ("python3 -c \"$(cat <<'EOF'\nprint(1)\nEOF\n)\" > s.sh", True), ("python3 -c \"$(cat <<'EOF'\nprint(1)\nEOF\n)\" | tee s.sh", True),
                  ("x=$(python3 -c \"$(cat <<'EOF'\nprint(1)\nEOF\n)\")", True), ("cat <<'EOF' | python3 -\nprint(1)\nEOF", False),
                  ("cat <<'EOF' | python3 - > s.sh\nprint(1)\nEOF", True), ("cat <<'EOF' | python3 - | tee s.sh\nprint(1)\nEOF", True),
                  ("deno run -A - <<'EOF'\nprint(1)\nEOF", False)]:
    docs = sn.heredocs(cmd)
    ok = len(docs) == 1 and docs[0].kind == "interp" and docs[0].captured == want and sn.program_cut(docs[0], cmd) == (not want)
    print(("✔ " if ok else "✖ ") + f"captured {want} (program_cut {not want}) for {cmd[:60]!r}: {[(d.kind, d.captured) for d in docs]}")
    bad += not ok
for body, prog, want in [("await $`ls`", "node", True), ("import {$} from 'zx'", "node", True), ("await Bun.$`ls`", "bun", True), ("await $ `ls`", "node", True), ("import {$} from 'zx'", "node", True), ("import {$} from 'zx'\n$.sync`ls`", "node", True),
                         ("import $ from 'https://deno.land/x/dax/mod.ts'", "deno", True), ("import {$} from 'bun'", "bun", False), ("new Deno.Command('ls')", "deno", True), ("Deno.run({cmd: ['ls']})", "deno", True),
                         ("console.log(`plain ${1}`)", "node", False), ("const s = `a`", "node", False), ("Deno.readTextFileSync('x')", "deno", False)]:
    got = sn.spawns(body, prog)
    print(("✔ " if got == want else "✖ ") + f"spawns({body!r}, {prog}) is {got}")
    bad += got != want
t_big = ("echo a \\\n" * 20000) + "b"
t0 = time.perf_counter()
ok = sn.join_continuations(t_big).count("\n") == 0 and time.perf_counter() - t0 < 1
print(("✔ " if ok else "✖ ") + "join_continuations: 20000 continuation lines in under 1 s")
bad += not ok
# 15/10 r4 P0-A: where bash 3.2 and zsh disagree about the delimiter line (a quoted heredoc inside $( ) or backticks: bash 3.2 removes the
# continuations first) no heredoc of the command is cut; where they agree, the body is cut as before
AMB = "git commit -m \"$(cat <<'EOF'\nx\nE\\\nOF\nrm -rf /\nEOF\n)\""
# (command, cut_ok of its heredoc, ambiguous)
for cmd, want, amb in [(AMB, False, True), (AMB.replace("E\\\nOF", "EOF"), True, False), (AMB.replace("\"$(", "\"$(echo a; "), False, True),
                       ("x=`cat <<'EOF'\nx\nE\\\nOF\nrm -rf /\nEOF\n`", False, True), ("x=$(cat <<'EOF'\nx\nE\\\nOF\nrm -rf /\nEOF\n)", False, True),
                       ("( cat <<'EOF'\nx\nE\\\nOF\nrm -rf /\nEOF\n)", False, False), ("cat > n.md <<'EOF'\nx\nE\\\nOF\nrm -rf /\nEOF\n", True, False),
                       ("cat > n.md <<EOF\nx\nE\\\nOF\nEOF\n", True, False)]:
    docs = sn.heredocs(cmd)
    got = [(h.cut_ok, h.ambiguous) for h in docs]
    ok = bool(docs) and got[0] == (want, amb)
    print(("✔ " if ok else "✖ ") + f"cut_ok / ambiguous {(want, amb)} for {cmd[:50]!r}: {got}")
    bad += not ok
    if amb and "E\\\nOF" in cmd:   # an ambiguous heredoc ends at the EARLIER of the two readings: the joined delimiter, so the rest of the text is commands
        ok = docs[0].body(cmd) == "x\n" and docs[0].terminated
        print(("✔ " if ok else "✖ ") + f"ambiguous heredoc ends at the joined delimiter: {docs[0].body(cmd)!r}")
        bad += not ok
# the unterminated interpreter heredoc is never cut, whatever drop says (the mutant that cut it let the program through)
for cmd in ("python3 - <<'EOF'\ngit reset --hard", "python3 - <<'EOF'\nimport os\nos.system('x')", "cat > n.md <<'EOF'\nls"):
    got = sn.strip_heredocs(cmd, lambda h: True)
    ok = got == cmd
    print(("✔ " if ok else "✖ ") + f"strip of an unterminated heredoc keeps the text: {cmd[:40]!r}")
    bad += not ok
sys.exit(1 if bad else 0)
PY
sn_rc=$?
cat "$TMP/sn.txt"
if [ "$sn_rc" != 0 ]; then   # each failed check once; a crash before any check printed counts one
  n=$(grep -c '^✖' "$TMP/sn.txt"); echo "✖ shell_norm.py checks (rc $sn_rc)"; FAILS=$((FAILS + (n > 0 ? n : 1)))
fi
mkdir -p "$TMP/partial"
cp "$HW" "$TMP/partial/hardware_safety_gate.sh" && cp "$GG" "$TMP/partial/block-dangerous-git.sh"
for pair in "hardware_safety_gate.sh|rm -rf ~" "block-dangerous-git.sh|git reset --hard"; do
  h="${pair%%|*}" c="${pair#*|}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$TMP/partial/$h" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  rc=$?
  if [ "$rc" = 2 ] && grep -q "shell_norm.py" "$TMP/err"; then ok "$h without shell_norm.py beside it: rc 2, names the module"
  else fail "$h without shell_norm.py beside it: rc $rc — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
done

# pair <want rc> <template with @BODY@>: the template through the git guard with a git danger in the body and through the hardware gate with
# an rm danger in it — each hook must reach the verdict by itself (review 15/10: a git row alone proves nothing about the hw gate)
pair() {
  local g="${2//@BODY@/git reset --hard}" w="${2//@BODY@/rm -rf ~}"   # @BODY@: a heredoc body, @CMD@: the command itself
  check "$1" git "${g//@CMD@/git reset --hard}"; check "$1" hw "${w//@CMD@/rm -rf ~}"
}

echo "── heredoc: a body written to a file is data only when nothing that can run the file follows (review 15/10, policy: fail closed)"
echo "   (a) the file is renamed, copied or linked first"
pair 2 $'cat > x <<EOF\n@BODY@\nEOF\nmv x y.sh && bash y.sh'
pair 2 $'cat > x <<\'EOF\'\n@BODY@\nEOF\nmv x y.sh && bash y.sh'
pair 2 $'cat > x <<\'EOF\'\n@BODY@\nEOF\ncp x y.sh; sh y.sh'
pair 2 $'cat > a.sh <<\'EOF\'\n@BODY@\nEOF\ncp a.sh b.sh; bash b.sh'
pair 2 $'cat > a.sh <<\'EOF\'\n@BODY@\nEOF\nmv a.sh b.sh && sh b.sh'
pair 2 $'cat > x <<\'EOF\'\n@BODY@\nEOF\nln -s x y.sh; sh y.sh'
pair 2 $'cat > x <<\'EOF\'\n@BODY@\nEOF\ninstall -m755 x /tmp/y; /tmp/y'
echo "   (b) the file is named by a variable, a glob, a loop or a redirect the name match does not read"
pair 2 $'cat > "$F" <<EOF\n@BODY@\nEOF\nsh "${F}"'
pair 2 $'cat > ${F} <<\'EOF\'\n@BODY@\nEOF\nbash ${F}'
pair 2 $'F=a.sh; cat > $F <<\'EOF\'\n@BODY@\nEOF\nbash a.sh'
pair 2 $'cat > x.sh <<\'EOF\'\n@BODY@\nEOF\nF=x.sh; bash $F'
pair 2 $'cat > x.sh <<\'EOF\'\n@BODY@\nEOF\nbash x.s?'
pair 2 $'cat > x.sh <<\'EOF\'\n@BODY@\nEOF\nbash ./*.sh'
pair 2 $'cat > x.sh <<\'EOF\'\n@BODY@\nEOF\nfor f in *.sh; do bash $f; done'
pair 2 $'cat > x.sh <<\'EOF\'\n@BODY@\nEOF\nbash $(ls *.sh)'
pair 2 $'cat 1>a.sh <<\'EOF\'\n@BODY@\nEOF\nbash a.sh'
pair 2 $'cat &> a.sh <<\'EOF\'\n@BODY@\nEOF\nbash a.sh'
echo "   (c) a git hook, then a git command that runs it"
pair 2 $'cat > .git/hooks/pre-commit <<EOF\n@BODY@\nEOF\ngit commit -m x'
pair 2 $'cat > .git/hooks/pre-commit <<\'EOF\'\n@BODY@\nEOF\ngit commit -m x'
pair 2 $'cat > .githooks/pre-push <<\'EOF\'\n@BODY@\nEOF\ngit push origin main'
pair 2 $'cat > hooks/post-checkout <<\'EOF\'\n@BODY@\nEOF\ngit checkout main'
pair 2 $'cd .git/hooks && cat > pre-commit <<\'EOF\'\n@BODY@\nEOF\ngit commit -m x'
pair 2 $'H=.git/hooks; cat > $H/pre-commit <<\'EOF\'\n@BODY@\nEOF\ngit commit -m x'
pair 2 $'cat > pre-commit <<\'EOF\'\n@BODY@\nEOF\ngit commit -m x'
echo "   a loop that ran the file on its previous round"
pair 2 $'while true; do bash x.sh; cat > x.sh <<\'EOF\'\n@BODY@\nEOF\ndone'
pair 2 $'for i in 1 2; do sh x.sh; cat > x.sh <<\'EOF\'\n@BODY@\nEOF\ndone'
echo "   (d) a compound command piped into a shell: the | sh is on the line of the heredoc operator"
pair 2 $'{ cat <<\'EOF\'; } | sh\n@BODY@\nEOF'
pair 2 $'if true; then cat <<\'EOF\'; fi | sh\n@BODY@\nEOF'
pair 2 $'while true; do cat <<\'EOF\'; break; done | sh\n@BODY@\nEOF'
pair 2 $'for i in 1; do cat <<\'EOF\'; done | bash\n@BODY@\nEOF'
pair 2 $'{ cat <<\'EOF\'\n@BODY@\nEOF\n} | sh'
pair 2 $'( cat <<\'EOF\'\n@BODY@\nEOF\n) | sh'
pair 2 $'{ cat <<\'EOF\'; } | xargs -0 sh -c\n@BODY@\nEOF'
pair 2 $'$(cat <<\'EOF\'\n@BODY@\nEOF\n)'
echo "   (e) the reader is a shell in disguise: sudo -s / -i read stdin, a git alias can be !sh"
pair 2 $'sudo -s <<\'EOF\'\n@BODY@\nEOF'
pair 2 $'sudo -i <<\'EOF\'\n@BODY@\nEOF'
pair 2 $'sudo -u root -s <<\'EOF\'\n@BODY@\nEOF'
pair 2 $'sudo --shell <<\'EOF\'\n@BODY@\nEOF'
check 2 git $'git -c alias.x=\'!sh\' x <<\'EOF\'\ngit reset --hard\nEOF'
check 2 git $'sudo -u root cat <<\'EOF\'\ngit reset --hard\nEOF'   # accepted false positive: no file written, no message
echo "   the intentional false-positive fixes: text nothing runs stays data"
pair 0 $'cat > notes.md <<\'EOF\'\n@BODY@\nEOF'
pair 0 $'cat <<\'EOF\' > notes.md\n@BODY@\nEOF'
# accepted false positive (policy 15/10)
pair 2 $'cat > notes.md <<\'EOF\'\n@BODY@\nEOF\nwc -l notes.md'
# accepted false positive (policy 15/10)
pair 2 $'cat > notes.md <<\'EOF\'\n@BODY@\nEOF\ncat notes.md; ls -la notes.md'
pair 0 $'cat > notes.md <<\'EOF\'\n@BODY@\nEOF\n# written'
pair 0 $'cat > notes.md <<\'EOF\' 2>/dev/null\n@BODY@\nEOF\n'
# accepted false positive (policy 15/10)
pair 2 $'cat > notes.md <<\'EOF\'\n@BODY@\nEOF\ngit add notes.md && git commit -m x'
pair 0 $'git commit -F - <<\'EOF\'\nmessage @BODY@\nEOF'
pair 0 $'git commit -q -F - -- a.kt <<\'MSG\'\nfix: `grep x` was blocked; @BODY@\nMSG'   # tests/gates/test_gate_friction.sh asks for this one
pair 0 $'git commit --allow-empty --file=- <<EOF\nmessage @BODY@\nEOF'
pair 2 $'git commit -m x -F - $(echo a) <<\'EOF\'\n@BODY@\nEOF'   # an expansion in the arguments: not a plain statement
pair 0 $'git commit -m "$(cat <<\'EOF\'\nmessage @BODY@\nEOF\n)"'
pair 0 $'git add -A && git commit -m "$(cat <<\'EOF\'\nmessage @BODY@\nEOF\n)" && git status'
pair 0 $'gh pr create --title t --body "$(cat <<\'EOF\'\nsummary @BODY@\nEOF\n)"'
# accepted false positive (policy 15/10)
pair 2 $'echo "$(cat <<\'EOF\'\n@BODY@\nEOF\n)"'
# a message argument is no written file: words like for / while / hooks/ in the title are prose (review 15/10, own pass)
pair 0 $'gh pr create --title "support for the hooks/ dir while testing" --body "$(cat <<\'EOF\'\nsummary @BODY@\nEOF\n)"'
pair 0 $'git commit -m "$(cat <<\'EOF\'\nfix for .git/hooks docs @BODY@\nEOF\n)"'
# accepted false positive (policy 15/10)
pair 2 $'echo "for a while" && cat > notes.md <<\'EOF\'\n@BODY@\nEOF'
# two statements: no body is cut, but a line of prose is no command, so nothing is refused
pair 0 $'cat > a.md <<\'EOF\'\nprose\nEOF\ncat > b.md <<\'EOF\'\nmore prose @BODY@\nEOF\nls'
pair 2 $'cat > a.md <<\'EOF\'\nprose\nEOF\ncat > b.md <<\'EOF\'\n@BODY@\nEOF\nls'   # accepted false positive (policy 15/10)

echo "── heredoc: an ANSI-C / locale quoted delimiter (<<\$'EOF', <<\$\"EOF\") is the word EOF: bash drops the \$, so the lines after the"
echo "   real EOF line are commands (review 15/10: the \$ was kept, the body ran on to a line \$EOF and hid them)"
check 2 git $'cat <<$\'EOF\'\nhi\nEOF\ngit reset --hard\n$EOF'
check 2 git $'cat <<$"EOF"\nhi\nEOF\ngit reset --hard\n$EOF'
check 2 git $'cat <<-$\'EOF\'\n\thi\n\tEOF\ngit reset --hard\n$EOF'
check 2 git $'cat <<$\'E\\x4fF\'\nhi\nEOF\ngit reset --hard\n$EOF'
check 2 hw $'cat <<$\'EOF\'\nhi\nEOF\nrm -rf ~\n$EOF'
check 2 hw $'cat <<$"EOF"\nhi\nEOF\nrm -rf ~\n$EOF'
check 2 hw $'cat <<-$\'EOF\'\n\thi\n\tEOF\nrm -rf ~\n$EOF'
check 0 git $'cat <<$\'EOF\'\nhi\nEOF\ngit status\n$EOF'
check 2 hw $'cat > notes.md <<$\'EOF\'\nrm -rf ~\nEOF'   # accepted false positive: no heredoc is found for a $'..' word, the lines are judged
# a delimiter that really is $EOF (the \$ is part of a quoted word): the body ends at that line
check 2 git $'cat <<"$EOF"\nhi\n$EOF\ngit reset --hard\nEOF'

echo "── shared tables (review 15/10): time -p, sudo long options, sudo -s / -i STR, env -P / -S, a leading N>&M redirect"
pair 2 $'time -p @CMD@'
pair 2 $'sudo --user=root @CMD@'
pair 2 $'sudo --user root @CMD@'
pair 2 $'sudo --chdir /tmp @CMD@'
pair 2 $'sudo --group wheel @CMD@'
pair 2 $'sudo --host h @CMD@'
pair 2 $'sudo -u root -g wheel @CMD@'
pair 2 $'sudo -s \'@CMD@\''
pair 2 $'sudo -i \'@CMD@\''
pair 2 $'sudo -u root -s \'@CMD@\''
pair 2 $'doas -s \'@CMD@\''
pair 2 $'env -P /usr/bin @CMD@'
pair 2 $'env -S \'@CMD@\''
pair 2 $'env -S"@CMD@"'
pair 2 $'env -i -S \'FOO=1 @CMD@\''
pair 2 $'2>&1 @CMD@'
pair 2 $'>&2 @CMD@'
pair 2 $'3<&0 @CMD@'
pair 2 $'2>&1 sudo -u root @CMD@'
check 0 git 'time -p git status'
check 0 git 'sudo --user=root git status'
check 0 git "sudo -s 'git status'"
check 0 git 'env -P /usr/bin git status'
check 0 git '2>&1 git status'
check 0 git '>&2 git log -1'
check 0 hw 'time -p rm -rf build'
check 0 hw 'sudo --user root rm -rf build'
check 0 hw "sudo -s 'rm -rf build'"
check 0 hw 'env -P /usr/bin rm -rf build'
check 0 hw '2>&1 rm -rf build'
check 0 hw "env -S 'rm -rf build'"

echo "── hw: the device policy sees a shell / su behind a wrapper option value (OCR 3), adb behind wait-for-device, adb shell -e"
check_deny 2 'sudo -u me bash -lc "adb -s DENIED1 reboot"'
check_deny 2 'timeout -s KILL 5 sh -c "adb -s DENIED1 reboot"'
check_deny 2 'env -u X bash -c "adb -s DENIED1 reboot"'
check_deny 2 "nice -n 5 bash -lc 'adb -s DENIED1 reboot'"
check_deny 2 "sudo -u me su -c 'adb -s DENIED1 reboot'"
check_deny 0 'sudo -u me bash -lc "adb -s OK1 reboot"'
check 2 hw 'adb wait-for-device remount'
check 2 hw 'adb wait-for-device shell rm -rf ~'
check 2 hw 'adb shell -e ^ rm -rf ~'
check 0 hw 'adb wait-for-device shell ls /sdcard'
check 0 hw 'adb shell -e ^ ls /sdcard'
check 2 git 'adb wait-for-device shell git reset --hard'

echo "── never a crash: a redirect word at the very end of a command (the shadow replay of 7 days of real commands found an"
echo "   IndexError in the first draft: 225 harmless commands refused fail-closed)"
check 0 hw 'git grep -n -o -i -E ".{60}(<|dưới) ?1 ?% ?CPU.{20}" | head'
check 0 hw 'grep -E "(>|<)?x" notes.txt'

# ── 15/10 r4, independent verification of 4f1e4b0: every dangerous row below ran its marker twin (a harmless `echo RAN > m1.txt`) under
# /bin/bash 3.2.57 and zsh 5.9 and the marker RAN, unless the line says the shells differ; each has a control of the same shape that must pass.
echo "── P0-A: a backslash-newline in a heredoc body hides the terminator from the scanner, not from the shell (E\\<nl>OF is EOF in bash and"
echo "   zsh: the next line RUNS). An unquoted body joins its continuation lines like the shell; where bash 3.2 and zsh differ nothing is cut"
pair 2 $'cat > n.md <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'git commit -F - <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'tee n.md <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'python3 - <<EOF\nx = 1\nE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'cat > n.md <<-EOF\n\thello\n\tE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'cat > n.md <<EOF \nhello\nE\\\nOF\n@BODY@\nEOF\n'
pair 2 $'cat > n.md <<EOF\nhello\nEO\\\nF\n@BODY@\nEOF\n'
pair 2 $'cat > n.md <<EOF\nhello\nE\\\nO\\\nF\n@BODY@\nEOF\n'
pair 2 $'git commit -m "$(cat <<EOF\nx\nE\\\nOF\n@BODY@\nEOF\n)"'
echo "   a quoted heredoc inside \$( ) or backticks: bash 3.2 (backticks: zsh too) removes the continuations before it reads the body"
pair 2 $'git commit -m "$(cat <<\'EOF\'\nx\nE\\\nOF\n@BODY@\nEOF\n)"'
pair 2 $'x=$(cat <<\'EOF\'\nx\nE\\\nOF\n@BODY@\nEOF\n)'
pair 2 $'x=`cat <<\'EOF\'\nx\nE\\\nOF\n@BODY@\nEOF\n`'
pair 2 $'echo "$(python3 - <<\'EOF\'\nx\nE\\\nOF\n@BODY@\nEOF\n)"'
echo "   controls: a harmless line after the joined terminator, a quoted heredoc at top level (the shell joins nothing), a continuation that"
echo "   swallows the real terminator (the body goes on to the next EOF), a backslash pair (an escaped backslash joins nothing)"
check 0 hw $'cat > n.md <<EOF\nhello\nE\\\nOF\nls\nEOF\n'
check 0 git $'cat > n.md <<EOF\nhello\nE\\\nOF\ngit status\nEOF\n'
check 0 git $'git commit -m "$(cat <<\'EOF\'\nx\nE\\\nOF\ngit status\nEOF\n)"'
check 0 hw $'git commit -m "$(cat <<\'EOF\'\nx\nE\\\nOF\nls\nEOF\n)"'
check 0 hw $'x=$(cat <<\'EOF\'\nx\nE\\\nOF\nls\nEOF\n)'
check 0 hw $'x=`cat <<\'EOF\'\nx\nE\\\nOF\nls\nEOF\n`'
check 0 git $'x=$(cat <<\'EOF\'\nx\nE\\\nOF\ngit status\nEOF\n)'
pair 0 $'cat > n.md <<\'EOF\'\nhello\nE\\\nOF\n@BODY@\nEOF\n'
pair 0 $'cat > n.md <<EOF\nhello\nx\\\nEOF\n@BODY@\nEOF\n'
pair 0 $'cat > n.md <<EOF\nhello\nE\\\\\nOF\n@BODY@\nEOF\n'
echo "   an escaped backslash joins nothing at the terminator either: x\\\\<nl>EOF ends the body, the next line RUNS"
pair 2 $'cat > n.md <<EOF\nhi\nx\\\\\nEOF\n@BODY@\nEOF\n'
pair 2 $'git commit -F - <<EOF\nhi\nx\\\\\\\\\nEOF\n@BODY@\nEOF\n'
pair 0 $'cat > n.md <<EOF\nhi\nx\\\\\\\nEOF\n@BODY@\nEOF\n'

echo "── P0-B (hardware gate): a comment ends at the newline even after a backslash; joining the two lines glued its last character to the next"
echo "   word (#cadb), so no \\badb matched. Every pattern and the device policy also read the text as typed"
for p in 'adb remount' 'adb disable-verity' 'adb shell pm uninstall com.android.systemui' 'adb shell mount -o remount,rw /system' 'fastboot erase userdata' \
         'fastboot flash boot x.img' 'fastboot oem unlock' 'dd if=a.img of=/dev/sda' 'rm -rf ~' 'npm publish' 'terraform destroy -auto-approve' \
         'kubectl delete ns x' 'helm uninstall x' 'firebase deploy' 'docker volume rm x' 'aws s3 rm s3://b --recursive' 'redis-cli flushall' \
         'prisma migrate reset' 'security delete-keychain x' 'xcrun simctl erase all' 'fastlane match nuke'; do
  check 2 hw "#c"$'\\\n'"$p"
  check 2 hw "echo hi #c"$'\\\n'"$p"
done
check 2 hw $'ls\n#c\\\nadb remount'
check 2 hw $'true; #c\\\nadb remount'
check 2 hw $'#c\\\n\\\nadb remount'
check 2 hw $'#c\\\nadb remount && ls'
check 2 hw $'echo $(true)\n#c\\\nadb remount'
check 2 git $'#c\\\ngit reset --hard'
check 2 git $'echo $(true)\n#c\\\ngit reset --hard'
check_deny 2 $'#c\\\nadb -s DENIED1 reboot'
check_deny 0 $'#c\\\nadb -s OK1 reboot'
# the automotive logcat rule (an adb logcat that streams to this computer) reads the text as typed too
PA="$TMP/work/auto"; mkdir -p "$PA/.agents"; printf '{"profile":"automotive"}\n' > "$PA/.agents/active-profile.json"
check_auto() {   # check_auto <want rc> <command>: the hardware gate in a project whose profile is automotive
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$PA" > "$TMP/in.json"
  ( cd "$PA" && CLAUDE_PROJECT_DIR="$PA" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "auto rc $rc: ${c//$'\n'/ ⏎ }"; else fail "auto rc $rc (want $want): ${c//$'\n'/ ⏎ } — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}
check_auto 2 'adb logcat'
check_auto 0 'adb logcat -d'
check_auto 2 $'#c\\\nadb logcat'
check_auto 0 $'#c\\\nadb logcat -d'
check 0 hw $'#c\\\nls'
check 0 hw $'echo hi #c\\\nls'
check 0 git $'#c\\\ngit status'

echo "── P0-C (git guard): a quote, a backtick or a \$( left open by a prose body that stays in the scan must not turn off the rules the raw"
echo "   regex lacks (it misses a single space between the subcommand and its option, and has no branch, worktree or hooks-off rule)"
for d in 'git push -f origin main' 'git checkout . ' 'git switch -c newb' 'git checkout -f main' 'git branch -f main HEAD~1' 'git branch -M main' \
         'git checkout -b newb' 'git branch newb' 'git worktree add ../x' 'git push origin HEAD:refs/heads/other' 'DEVKIT_PRECOMMIT=0 git commit -m x' \
         'git reset --hard' 'git clean -fd' 'git rebase main'; do
  for b in "don't" "star's" 'say "hi' 'the 5" screen' 'use `foo' 'use $(foo' 'foo\'; do
    check 2 git "$d && cat <<'EOF'"$'\n'"$b"$'\nEOF'
  done
done
for b in "don't" "star's" 'say "hi' 'the 5" screen' 'use `foo' 'use $(foo'; do
  check 0 git "git status && cat <<'EOF'"$'\n'"$b"$'\nEOF'
  check 0 hw "ls && cat <<'EOF'"$'\n'"$b"$'\nEOF'
done
echo "   a danger on a line whose OWN quote stays open (the whole text no longer parses): read word by word with the quotes dropped, never skipped"
check 2 git "git push -f origin main 'x"
check 2 git "git commit --no-verify -m don't"
check 2 git 'git push -f origin main \'
check 2 git $'echo ok\ngit worktree add ../x "y'
check 0 git "git status 'x"
check 0 git "git commit -m don't"
check 0 git 'git status \'
check 0 git $'echo ok\ngit status "y'
check 2 git $'cd /tmp && git switch -c chore/x && git add -A && git commit -q -F - <<\'EOF\'\nfix: the user\'s file\nEOF'
check 0 git $'cd /tmp && git status && git add -A && git commit -q -F - <<\'EOF\'\nfix: the user\'s file\nEOF'

echo "── P0-D (1): a sink after the heredoc operator inside \$( ) is invisible to a scanner that only records depth-0 pipes; and the body of"
echo "   python3 -c \"pass\" \"\$(cat <<EOF …)\" is an ARGUMENT of the program, not its code"
pair 2 $'python3 -c "pass" "$(cat <<\'EOF\' | sh\n@BODY@\nEOF\n)"'
pair 2 $'node -e "require(\'child_process\').execSync(process.argv[1])" "$(cat <<\'EOF\'\n@BODY@\nEOF\n)"'
pair 2 $'python3 -c "$(cat <<\'EOF\' | sh\n@BODY@\nEOF\n)"'
pair 2 $'x=$(cat <<\'EOF\' | bash\n@BODY@\nEOF\n)'
pair 2 $'python3 -c "$(cat <<\'EOF\' \\\n| sh\n@BODY@\nEOF\n)"'
echo "   the program operand of -c is code only when cat prints it and the operator ends its line (a grep, or a pipe after it, may change it)"
pair 2 $'python3 -c "$(grep x <<\'EOF\'\n@BODY@\nEOF\n)"'
pair 2 $'python3 -c "$(cat <<\'EOF\' | tee /tmp/x\n@BODY@\nEOF\n)"'
check 0 git $'python3 -c "$(grep x <<\'EOF\'\nhello\nEOF\n)"'
check 0 hw $'python3 -c "$(cat <<\'EOF\' | tee /tmp/x\nhello\nEOF\n)"'
echo "   (2) sudo -s / -i / --shell with no command words is a shell that reads its stdin: the reader of the heredoc"
pair 2 $'sudo -s <<\'EOF\' | python3 -\n@BODY@\nEOF'
pair 2 $'sudo -i <<\'EOF\' | python3 -\n@BODY@\nEOF'
pair 2 $'doas -s <<\'EOF\' | python3 -\n@BODY@\nEOF'
pair 2 $'sudo -u root -s <<\'EOF\' | python3 -\n@BODY@\nEOF'
pair 2 $'sudo -s <<\'EOF\' | cat\n@BODY@\nEOF'
echo "   (3) an interpreter program that can start a process is never cut: ruby / perl backticks run branch, worktree and hooks-off commands too"
check 2 git $'ruby <<\'EOF\'\n`git checkout -b newbranch`\nEOF'
check 2 git $'ruby <<\'EOF\'\n`git worktree add ../x`\nEOF'
check 2 git $'ruby <<\'EOF\'\n`DEVKIT_PRECOMMIT=0 git commit -m x`\nEOF'
check 2 git $'perl <<\'EOF\'\n`git checkout -b newbranch`\nEOF'
check 2 git $'perl <<\'EOF\'\n`git worktree add ../x`\nEOF'
check 2 git $'perl <<\'EOF\'\n`DEVKIT_PRECOMMIT=0 git commit -m x`\nEOF'
check 2 git $'ruby <<\'EOF\'\n`git reset --hard`\nEOF'
check 0 git $'ruby <<\'EOF\'\nputs `git status`\nEOF'
check 0 git $'perl <<\'EOF\'\nprint `git status`;\nEOF'
echo "   (P2) an interpreter heredoc with no delimiter line is judged as the program it is (the check skipped it)"
check 2 git $'python3 - <<\'EOF\'\nimport os\nos.system(\'git reset --hard\')'
check 2 git $'python3 - <<\'EOF\'\ngit reset --hard'
check 0 git $'python3 - <<\'EOF\'\nprint(1)'
echo "   controls: the program operand of -c, a body that only mentions the danger, sudo -s with a command, a reader that is no shell"
check 0 git $'python3 -c "$(cat <<\'EOF\'\nprint(1)\nEOF\n)"'
check 0 git $'python3 -c "$(cat <<\'EOF\'\ncases = [\'git reset --hard\']\nprint(len(cases))\nEOF\n)"'
check 0 hw $'python3 -c "$(cat <<\'EOF\'\nprint(\'rm -rf ~ is dangerous\')\nEOF\n)"'
check 0 git $'python3 -c "pass" "$(cat <<\'EOF\' | wc -l\nhello\nEOF\n)"'
check 0 hw $'python3 -c "pass" "$(cat <<\'EOF\'\nhello\nEOF\n)"'
check 0 git $'sudo -s git status <<\'EOF\'\nhello\nEOF'

echo "── P1: an escaped backslash before the newline joins nothing (echo a\\\\<nl>git reset --hard: the next line RUNS); an odd run still joins"
pair 2 $'echo a\\\\\n@BODY@'
pair 2 $'echo a\\\\\\\\\n@BODY@'
check 0 git $'echo a\\\\\ngit status'
check 0 hw $'echo a\\\\\nls'
check 0 hw $'echo mount \\\\\nrw /system \'x'   # echo mount \ and a command rw /system (an open quote keeps shlex from flattening the lines): glued it would read as mount … rw … /system
# ACCEPTED false positive, pinned BLOCKED (15/10 r5, old 5fd5fd9 and every later version alike): without the open quote the hardware gate also reads the text as
# shlex words (readings: norm), which turns the real newline into a blank, so `mount … rw … /system` is matched across two commands. Not a hole, not this
# lane to change (a pattern reading of its own): the row above is the join-parity control, this one says what the gate does with the plain shape.
check 2 hw $'echo mount \\\\\nrw /system'
check 0 git $'echo $(true)\ngit reset \\\\\n--hard'   # git reset \ (a pathspec) and a command --hard: no hard reset; the raw regex must not join them either
check 2 git $'gi\\\nt reset --hard'
check 2 hw $'ad\\\nb remount'
check 0 git $'echo a\\\\\\\ngit reset --hard'   # three backslashes: an escaped backslash and a continuation, the next line is part of the echo
check 0 hw $'echo a\\\\\\\nrm -rf ~'   # the second reading (shell_norm.readings) is for a COMMENT that ends in a backslash only: this one has none
check 0 git $'echo a\\\\\\\ngit status'
check 2 hw $'echo ok\\\\\n\\\nrm -rf ~'

echo "── P1b (both guards, OLD too, found by the marker fuzz): a # comment inside a multi-line quoted script ends at ITS newline; the guards flattened"
echo "   every newline to ' ; ' before they lexed, so the comment swallowed the later lines of a bash -c / eval / \$( ) script that RUNS"
pair 2 $'echo "$(\n# c\n@CMD@\n)"'
pair 2 $'echo "$(true # c\n@CMD@\n)"'
pair 2 $'sh -c "\n# c\n@CMD@\n"'
pair 2 $'bash -c \'true # c\n@CMD@\''
pair 2 $'bash -lc \'true # c\n@CMD@\''
pair 2 $'eval "true # c\n@CMD@"'
pair 2 $'bash -c "bash -c \'true # c\n@CMD@\'"'
pair 2 $'echo "$(cat <<\'EOF\' | sh\nx\nEOF #\n@BODY@\nEOF\n)"'
check 0 git $'sh -c "\n# c\ngit status\n"'
check 0 hw $'sh -c "\n# c\nls\n"'
check 0 git $'bash -c \'true # c\ngit status\''
check 0 hw $'bash -c \'true # c\nrm -rf build\''
check 0 hw $'echo "a # b\nrm -rf ~"'
check 0 git $'echo "a # b\ngit reset --hard"'

echo "── P2: git -c alias.x=!CMD x runs CMD through a shell: the hardware gate reads the alias as the git guard does"
check 2 hw "git -c alias.x='!rm -rf ~' x"
check 2 hw "git -c alias.x='!rm -rf /system' x"
check 2 hw "git -c alias.x='!adb remount' x"
check 2 hw "git -calias.x='!rm -rf ~' x"
check 0 hw "git -c alias.x='!ls' x"
check 0 hw "git -c alias.x='!rm -rf build' x"
check 0 hw "git -c alias.x=status x"
check 0 hw "git -c user.name=x commit -m y"

echo "── P3: a prose-only data target is a note file inside the project: not CLAUDE.md / AGENTS.md (an agent reads them as instructions), nothing"
echo "   under .claude/ .agents/ .gemini/ .cursor/, no build or dependency list, no absolute, ~ or .. path"
for t in CLAUDE.md AGENTS.md GEMINI.md CMakeLists.txt requirements.txt requirements-dev.txt .claude/commands/x.md .agents/notes.md .gemini/x.md /etc/n.md ~root/n.md '~/n.md' ../n.md a/../../n.md; do
  pair 2 "cat > $t <<'EOF'"$'\n@BODY@\nEOF'
done
pair 0 $'cat > docs/guide.md <<\'EOF\'\n@BODY@\nEOF'
pair 0 $'cat > notes.txt <<\'EOF\'\n@BODY@\nEOF'
pair 0 $'cat > docs/CHANGELOG.md <<\'EOF\'\n@BODY@\nEOF'

echo "── r5 (independent verification of the r4 tree; every dangerous row below ran its harmless marker twin under /bin/bash 3.2 and zsh): the"
echo "   newline of the OUTER text is not rewritten, so a quoted script reaches the second pass as typed, and a backslash-newline inside"
echo "   single quotes is literal there (P0-1, P1-c); an interpreter that cannot spawn still prints what a shell runs (P1-a); zx / Bun / Deno start"
echo "   a process without a word of the old sink list (P1-b)"
# rows_from_py <<'PY' … PY: the generator prints NUL separated triples (want rc, guard, command), each one is a check
r5_rows() {
  local want hook cmd
  while IFS= read -r -d '' -u 3 want && IFS= read -r -d '' -u 3 hook && IFS= read -r -d '' -u 3 cmd; do check "$want" "$hook" "$cmd"; done 3< <(python3 -I -c "$1")
}
R5_COMMON='
import shlex, sys
BS = "\\"
PAY = {"git": "git reset --hard", "hw": "rm -rf ~"}
CTL = {"git": "git status", "hw": "ls"}
def emit(want, hook, cmd):
    sys.stdout.write("%s\0%s\0%s\0" % (want, hook, cmd))
def both(tpl, hooks=("git", "hw"), want="2"):
    for h in hooks:
        emit(want, h, tpl.replace("@CMD@", PAY[h]))
        emit("0", h, tpl.replace("@CMD@", CTL[h]))
WRAPS = ["bash -c %s", "sh -c %s", "bash -lc %s", "eval %s", "ssh host %s", "zsh -c %s", "env bash -c %s", "sudo bash -c %s", "nohup sh -c %s"]
# ssh runs the script on another machine: the hardware gate does not refuse rm -rf ~ there (the remote home), for every version: git guard only
HOOKS_OF = lambda w: ("git",) if w.startswith("ssh") else ("git", "hw")
'
echo "   P0-1: a heredoc terminator in a quoted script, whatever wraps the script (the 2nd EOF is the real command's neighbour, not a terminator)"
r5_rows "$R5_COMMON"'
SCRIPTS = ["python3 - <<EOF\nx = 1\nEOF\n@CMD@\nEOF", "python3 - <<EOF\nx = 1\nEOF\n@CMD@\ncat > n.md <<EOF\nhi\nEOF",
           "python3 - <<EOF\nprint(1)\nEOF\n@CMD@\npython3 - <<EOF\nprint(2)\nEOF", "node - <<EOF\nconsole.log(1)\nEOF\n@CMD@\nEOF",
           "python3 - <<\x27EOF\x27\nx = 1\nEOF\n@CMD@\nEOF", "python3 - <<-EOF\nx\nEOF\n@CMD@\nEOF\n\tEOF",
           "python3 - <<EOF\nx = 1\nEOF\n@CMD@\npython3 - <<EOT\nprint(2)\nEOT", "cat > n.md <<EOF\nhi\nEOF\n@CMD@\nEOF"]
for sc in SCRIPTS:
    for w in WRAPS:
        both(w % shlex.quote(sc), hooks=HOOKS_OF(w))
    both("bash -c \"" + sc.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$") + "\"")
    both("x=$(" + sc + "\n)")
    both("echo \"$(" + sc + "\n)\"")
'
echo "   P0-1 (hardware gate, newline is a separator of its own lexer): the fallback for text that does not parse, and the cwd walk across &&<nl>"
check 2 hw $'ls\nrm -rf ~'
check 2 hw $'echo don\'t\nrm -rf ~'
check 2 hw $'echo "a\nrm -rf ~'
check 2 hw $'echo don\'t\nadb remount'
check 0 hw $'echo don\'t\nls'
check 0 hw $'echo "a\nls'
check 2 git $'echo don\'t\ngit reset --hard'
check 0 git $'echo don\'t\ngit status'
check 0 hw $'cd src/sub &&\nrm -rf data'   # the && before the newline still means the cd ran: data is level 3, not the project\'s own top-level data
check 2 hw $'cd src/sub &&\nrm -rf ~'
check 2 git $'echo \'git reset --hard\' |\nsh'   # a pipe before the newline continues the pipeline: sh reads what echo prints
check 0 git $'echo \'git status\' |\nsh'
echo "   P1-c: a backslash-newline inside SINGLE quotes is literal for the outer shell: the script it hands over holds a comment that ENDS at the newline"
r5_rows "$R5_COMMON"'
for w in WRAPS:
    for sc in ("true # c" + BS + "\n@CMD@", "# c" + BS + "\n@CMD@", "ls\n# c" + BS + "\n@CMD@", "echo hi # c" + BS + "\n@CMD@", "true # c" + BS + "\n" + BS + "\n@CMD@"):
        both(w % shlex.quote(sc), hooks=HOOKS_OF(w))
both("bash -c " + shlex.quote("bash -c " + shlex.quote("true # c" + BS + "\n@CMD@")))
both("echo \"$(true # c" + BS + "\n@CMD@\n)\"")
'
check 0 git $'cd src && git push origin feat:feat # c\\\nls'   # the second reading starts where the command started (the cd of the first one is not counted twice: src/src does not exist)
check 0 git $'cd src && git status # c\\\nls'
echo "   ACCEPTED false positive of the as-typed reading, pinned BLOCKED: inside DOUBLE quotes the outer shell removes the backslash-newline, so the comment"
echo "   below swallows the next word and nothing runs; the as-typed reading cannot tell (it is the price of reading both ways instead of modelling quotes)"
r5_rows "$R5_COMMON"'
for w in ("bash -c", "sh -c", "eval"):
    for h in ("git", "hw"):
        emit("2", h, w + " \"true # c" + BS + "\n" + PAY[h] + "\"")
        emit("0", h, w + " \"true # c" + BS + "\n" + CTL[h] + "\"")
'
echo "   P1-a: an interpreter that cannot start a process still PRINTS, and the shell runs what is printed ($( ), a file that is run, a pipe into tee)"
r5_rows "$R5_COMMON"'
PR = "print(\x27@CMD@\x27)"
for tpl in ("$(python3 - <<\x27EOF\x27\n%s\nEOF\n)", "x=$(python3 - <<\x27EOF\x27\n%s\nEOF\n); $x", "$(python3 - <<\x27EOF\x27\n%s\nEOF\n) arg",
            "for c in $(python3 - <<\x27EOF\x27\n%s\nEOF\n); do $c; done", "`python3 - <<\x27EOF\x27\n%s\nEOF\n`", "x=`python3 - <<\x27EOF\x27\n%s\nEOF\n`; $x",
            "python3 -c \"$(cat <<\x27EOF\x27\n%s\nEOF\n)\" > s.sh; sh s.sh", "python3 -c \"$(cat <<\x27EOF\x27\n%s\nEOF\n)\" >> s.sh; sh s.sh",
            "python3 -c \"$(cat <<\x27EOF\x27\n%s\nEOF\n)\" | tee s.sh; sh s.sh", "python3 - <<\x27EOF\x27 > s.sh\n%s\nEOF\nsh s.sh",
            "python3 - <<\x27EOF\x27 >> s.sh\n%s\nEOF\nsh s.sh", "python3 - <<\x27EOF\x27 | tee s.sh\n%s\nEOF\nsh s.sh", "python3 > s.sh <<\x27EOF\x27\n%s\nEOF\nsh s.sh",
            "cat <<\x27EOF\x27 | python3 - > s.sh\n%s\nEOF\nsh s.sh", "{ python3 - <<\x27EOF\x27\n%s\nEOF\n} > s.sh; sh s.sh", "$(python3 <<\x27EOF\x27\n%s\nEOF\n)"):
    both(tpl % PR, hooks=("git",))
for tpl in ("python3 - <<\x27EOF\x27 > s.sh\n@CMD@\nEOF\nsh s.sh", "x=$(python3 - <<\x27EOF\x27\n@CMD@\nEOF\n)", "python3 - <<\x27EOF\x27 | tee s.sh\n@CMD@\nEOF",
            "{ python3 - <<\x27EOF\x27\n@CMD@\nEOF\n} > s.sh; sh s.sh"):   # the same with the danger as a bare line of the body: an uncut body is judged by BOTH guards
    both(tpl)
both("$(node -e \"$(cat <<\x27EOF\x27\nconsole.log(\x27@CMD@\x27)\nEOF\n)\")", hooks=("git",))
both("$(python3 -c \"$(cat <<\x27EOF\x27\n%s\nEOF\n)\")" % PR, hooks=("git",))
both("$(ruby <<\x27EOF\x27\nputs \x27@CMD@\x27\nEOF\n)", hooks=("git",))
both("$(perl <<\x27EOF\x27\nprint \x27@CMD@\x27;\nEOF\n)", hooks=("git",))
both("$(node - <<\x27EOF\x27\nconsole.log(\x27@CMD@\x27)\nEOF\n)", hooks=("git",))
'
echo "   P1-a controls: nothing captures the output of the program (a bare run, the program operand of -c, stderr only) and the body only mentions the danger"
check 0 git $'python3 - <<\'EOF\'\ncases = [\'git reset --hard\']\nprint(len(cases))\nEOF'
check 0 git $'python3 -c "$(cat <<\'EOF\'\ncases = [\'git reset --hard\']\nprint(len(cases))\nEOF\n)"'
check 0 hw $'python3 - <<\'EOF\'\ncases = [\'rm -rf ~\']\nprint(len(cases))\nEOF'
check 0 git $'python3 - <<\'EOF\'\nprint(\'git reset --hard is dangerous\')\nEOF'
check 0 hw $'python3 - <<\'EOF\'\nprint(\'rm -rf ~ is dangerous\')\nEOF'
echo "   P1-b: zx / Bun / dax start a process with a tagged template, Deno with Deno.Command / Deno.run (the sink list had none of them)"
r5_rows "$R5_COMMON"'
for tpl in ("node - <<\x27EOF\x27\nimport {$} from \x27zx\x27\nawait $`@CMD@`\nEOF", "node - <<\x27EOF\x27\nconst {$} = require(\x27zx\x27);\n$`@CMD@`\nEOF",
            "node - <<\x27EOF\x27\nimport \x27zx/globals\x27\nawait $`@CMD@`\nEOF", "node - <<\x27EOF\x27\nimport {$} from \x27zx\x27\nawait $.sync`@CMD@`\nEOF",
            "node - <<\x27EOF\x27\nimport {$} from \x27zx\x27\nawait $({quiet: true})`@CMD@`\nEOF", "node - <<\x27EOF\x27\nawait $`@CMD@`\nEOF",
            "bun - <<\x27EOF\x27\nimport {$} from \x27bun\x27\nawait $`@CMD@`\nEOF", "bun - <<\x27EOF\x27\nawait Bun.$`@CMD@`\nEOF",
            "deno run -A - <<\x27EOF\x27\nimport $ from \x27https://deno.land/x/dax/mod.ts\x27\nawait $`@CMD@`\nEOF"):
    both(tpl)
for tpl in ("deno run -A - <<\x27EOF\x27\nawait new Deno.Command(\x27sh\x27, {args: [\x27-c\x27, \x27@CMD@\x27]}).output()\nEOF",
            "deno run -A - <<\x27EOF\x27\nconst p = Deno.run({cmd: [\x27sh\x27, \x27-c\x27, \x27@CMD@\x27]})\nEOF"):
    both(tpl, hooks=("git",))   # the hardware gate does not read the string literals of a program (documented limit, same for every version)
'
echo "   P1-b controls: a node body with a template literal and a body that only mentions a danger are still data"
check 0 git $'node - <<\'EOF\'\nconsole.log(`git reset --hard is dangerous`)\nEOF'
check 0 hw $'node - <<\'EOF\'\nconsole.log(`rm -rf ~ is dangerous`)\nEOF'
check 0 git $'node - <<\'EOF\'\nconst s = `plain ${1 + 1}`;\nconsole.log(s)\nEOF'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
