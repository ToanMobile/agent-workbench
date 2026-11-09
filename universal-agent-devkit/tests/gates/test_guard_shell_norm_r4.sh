#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh (+ hooks/shell_norm.py, phần đọc lệnh chung): các phát hiện 15/10 r4: P0-A
#  (backslash-newline trong thân heredoc), P0-B (comment kết bằng backslash), P0-C (dấu nháy mở do thân văn xuôi để lại), P0-D
#  (sink sau toán tử heredoc trong $( )), P1, P1b, P2 (git -c alias) và P3 (đích chỉ chứa văn xuôi).
#  Tách từ tests/gates/test_guard_shell_norm.sh (03/11, shard REG-DK-ALL-GATES-01); helper: tests/lib/guard_shell_norm_lib.sh.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, check / check_deny / pair / r5_rows

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

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
