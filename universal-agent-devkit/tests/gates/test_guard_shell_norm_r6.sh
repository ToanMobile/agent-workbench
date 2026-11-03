#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh (+ hooks/shell_norm.py, phần đọc lệnh chung): các dòng r6 (kiểm độc lập 76899f4):
#  dấu nháy trong hai thân heredoc không bị cắt, backslash-newline trong nháy đơn của script -c, và tên chương trình ANSI-C (#526).
#  Tách từ tests/gates/test_guard_shell_norm.sh (03/11, shard REG-DK-ALL-GATES-01); helper: tests/lib/guard_shell_norm_lib.sh.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, check / check_mcp / check_deny / pair / r5_rows

echo "── r6 (independent verification of 76899f4; every dangerous row below ran its harmless marker twin under /bin/bash 3.2 and zsh 5.9): a quote character of a"
echo "   heredoc body that stays in the scan is no quote of the command (P0-1: it paired with one in another body and hid the command between them from every"
echo "   quote scanner), and a backslash-newline inside the single quotes of a -c script is the inner shell's own (P0-2: the outer join moved a quoted terminator)"
echo "   P0-1: two uncut bodies with a quote character, the command between them RUNS (every reader, the quote as ' or \", inside a script, a \$( ) or backticks)"
r5_rows "$R5_COMMON"'
APOS = "it\x27s"
for r in ("cat <<EOF", "cat <<\x27EOF\x27", "cat > n.md <<\x27EOF\x27", "git commit -F - <<\x27EOF\x27", "grep x <<\x27EOF\x27", ": <<\x27EOF\x27", "tee n.md <<EOF", "echo a <<EOF"):
    both(r + "\n" + APOS + "\nEOF\n@CMD@\n" + r + "\n" + APOS + "\nEOF")
for b in ("don\x27t", "say \"hi", "the 5\" screen"):
    both("cat <<EOF\n" + b + "\nEOF\n@CMD@\ncat <<EOF\n" + b + "\nEOF")
    both("git commit -F - <<\x27EOF\x27\n" + b + "\nEOF\n@CMD@\ngit commit -F - <<\x27EOF\x27\n" + b + "\nEOF")
both("cat > n.md <<\x27EOF\x27\n" + APOS + "\nEOF\n@CMD@\ncat > m.md <<\x27EOF\x27\n" + APOS + "\nEOF")
both("echo $\x27\\\x27\x27\n@CMD@\ncat <<EOF\n" + APOS + "\nEOF")
both("cat <<EOF\n" + APOS + "\nEOF\nls && @CMD@ && ls\ncat <<EOF\n" + APOS + "\nEOF")
both("cat <<EOF\n" + APOS + "\nEOF\nif true; then @CMD@; fi\ncat <<EOF\n" + APOS + "\nEOF")
both("x=$(cat <<\x27EOF\x27\n" + APOS + "\nEOF\n@CMD@\ncat <<\x27EOF\x27\n" + APOS + "\nEOF\n)")
both("echo `cat <<\x27EOF\x27\n" + APOS + "\nEOF\n@CMD@\ncat <<\x27EOF\x27\n" + APOS + "\nEOF\n`")
both("echo \"$(cat <<\x27EOF\x27\n" + APOS + "\nEOF\n@CMD@\ncat <<\x27EOF\x27\n" + APOS + "\nEOF\n)\"")
for w in ("bash -c %s", "sh -c %s", "zsh -c %s", "eval %s", "env bash -c %s", "nohup sh -c %s"):
    both(w % shlex.quote("cat <<EOF\n" + APOS + "\nEOF\n@CMD@\ncat <<EOF\n" + APOS + "\nEOF"))
    both(w % shlex.quote("git commit -F - <<\x27EOF\x27\n" + APOS + "\nEOF\n@CMD@\ngit commit -F - <<\x27EOF\x27\n" + APOS + "\nEOF"))
for extra in ("git checkout -b newb", "git worktree add ../w"):   # a rule that the raw regex of the git guard does not read
    for tpl in ("cat <<EOF\n" + APOS + "\nEOF\n" + extra + "\ncat <<EOF\n" + APOS + "\nEOF", "git commit -F - <<\x27EOF\x27\n" + APOS + "\nEOF\n" + extra + "\ngit commit -F - <<\x27EOF\x27\n" + APOS + "\nEOF"):
        emit("2", "git", tpl)
        emit("0", "git", tpl.replace(extra, "git status"))
'
echo "   P0-1b: the scanners that run before the lexer (a # comment, a \$( ) or backticks) see no quote of a body: a # inside a string after a body, a command"
echo "   substitution between two bodies, a body inside \"\$( )\" with a quote of its own"
r5_rows "$R5_COMMON"'
APOS = "it\x27s"
for q in ("\x27", "\""):
    both("cat <<EOF\n" + APOS + "\nEOF\necho " + q + "a # b" + q + "; @CMD@")
    both("cat <<\x27EOF\x27\n" + APOS + "\nEOF\necho " + q + "a # b" + q + "; @CMD@")
both("cat <<EOF\nsay \"hi\nEOF\necho \"a # b\"; @CMD@")
both("echo \"$(cat <<EOF\nsay \"hi\nEOF\n)\" \"a # b\"; @CMD@")
both("echo \"$(cat <<EOF\n" + APOS + "\nEOF\n)\" \x27a # b\x27; @CMD@")
for sub in ("echo \"$(@CMD@)\"", "echo $(@CMD@)", "echo `@CMD@`", "x=\"$(@CMD@)\""):
    both("cat <<EOF\n" + APOS + "\nEOF\n" + sub + "\ncat <<EOF\n" + APOS + "\nEOF")
'
echo "   P0-1 controls: a prose body with an open quote and danger text only in the prose stays refused (accepted false positive of r4, pinned), prose alone passes"
check 2 git $'git status && cat <<\'EOF\'\ndon\'t run git reset --hard\nEOF'
check 0 git $'cat <<EOF\nit\'s\nEOF\nls\ncat <<EOF\nit\'s\nEOF'
check 0 hw $'cat <<EOF\nit\'s\nEOF\nls\ncat <<EOF\nit\'s\nEOF'
check 0 git $'cat <<\'EOF\'\nthe 5" screen\nEOF\necho "a # b"; git status'
echo "   a body line that closes its own quotes is read as typed: a ; inside them is no separator (only the lines that do not close them lose their quote characters)"
check 0 git $'cat <<\'EOF\'\nsay "ok; git reset --hard"\nEOF'
check 0 hw $'cat <<\'EOF\'\nsay "ok; rm -rf ~"\nEOF'
check 0 git $'git status\ncat <<\'EOF\'\nsay \'a; git reset --hard\' and "b; git reset --hard"\nEOF'
check 0 hw $'git status\ncat <<\'EOF\'\nsay \'a; rm -rf ~\' and "b; rm -rf ~"\nEOF'
echo "   P0-1c: the git guard scanners that read comments and quotes: an apostrophe in a comment paired with a later quote and hid a \"\$( )\" between them, a # after a"
echo "   backslash-newline or inside \${ } was read as a comment and dropped the substitution after it (OLD too, found by the marker fuzz)"
r5_rows "$R5_COMMON"'
for sub in ("\"$(@CMD@)\"", "$(@CMD@)", "`@CMD@`"):
    for tpl in ("${: #}" + sub, "echo ${x:-a # b} " + sub, "a" + BS + "\n#" + sub, "echo a" + BS + "\n# b; " + sub, "# it\x27s a comment\n" + sub + "\n# it\x27s a comment",
                "echo hi # it\x27s\n" + sub + "\necho hi # it\x27s", "#\x27\n" + sub + "\n\x27", "echo a # \"\n" + sub + "\n# \""):
        both(tpl)
both("bash -c " + shlex.quote("#\x27\n\"$(@CMD@)\"\n\x27"))
both("eval " + shlex.quote("${: #}\"$(@CMD@)\""))
'
check 0 git $'echo ${x:-a # b} "$(git status)"'
check 0 git $'echo a # it\'s $(git status)\necho "$(git status)" # it\'s'
check 0 git $'echo a \\\n# b $(git status)'
echo "   P1-3 (review of 76899f4, OLD too): the hardware lexer paired the quotes of a \"\$( )\" that holds quotes of its own, and the command inside ended up inside a word"
r5_rows "$R5_COMMON"'
for tpl in ("echo \"$(echo \"a b\"; @CMD@)\"", "echo \"$(echo \"a\" ; @CMD@)\"", "echo \"$(echo \"a\"\n@CMD@\n)\"", "echo \"x$(echo \"a b\"; @CMD@)y\"", "x=\"$(echo \"a b\"; @CMD@)\"",
            "echo \"`echo \\\"a b\\\"; @CMD@`\"", "echo \"$(echo \"$(echo \"a b\"; @CMD@)\")\"", "git commit -m \"$(echo \"a b\"; @CMD@)\"", "echo \"$(\" \";if true; then @CMD@; fi)\"",
            "echo \"$(\" \"\nif true; then @CMD@; fi)\"", "cat <<EOF\n$(echo \"a b\"; @CMD@)\nEOF", "bash -c \x27echo \"$(echo \"a b\"; @CMD@)\"\x27"):
    both(tpl)
'
check 0 hw $'echo "$(date +"%F")"'
check 0 hw $'git commit -m "$(git log -1 --format="%s")"'
check 0 hw $'echo "$(echo "a b"; ls)"'
echo "   P0-2: a backslash-newline inside SINGLE quotes is literal for the outer shell: the script it hands over keeps it, and a quoted heredoc body joins nothing"
r5_rows "$R5_COMMON"'
APOS = "it\x27s"
INNERS = ["cat > n.md <<\"EOF\"\nx" + BS + "\nEOF\n@CMD@\nEOF", "cat > n.md <<\"EOF\"\nhello\nx" + BS * 3 + "\nEOF\n@CMD@\nEOF", "git commit -F - <<\"EOF\"\nx" + BS + "\nEOF\n@CMD@\nEOF",
          "tee n.md <<\"EOF\"\nx" + BS + "\nEOF\n@CMD@\nEOF", "python3 - <<\"EOF\"\nx = 1" + BS + "\nEOF\n@CMD@\nEOF", "node - <<\"EOF\"\nx" + BS + "\nEOF\n@CMD@\nEOF",
          "cat > n.md <<\"EOF\"\nhi" + BS + "\n" + BS + "\nEOF\n@CMD@\nEOF", "cat > n.md <<\"EOF\" # c\nx" + BS + "\nEOF\n@CMD@\nEOF", "cat > n.md <<E" + BS + "OF\nx" + BS + "\nEOF\n@CMD@\nEOF",
          "true; cat > n.md <<\"EOF\"\nx" + BS + "\nEOF\n@CMD@\nEOF"]
for sc in INNERS:
    both(sc)   # typed at top level, no outer quotes: a quoted body is not joined by the shell either
    both("bash -c " + shlex.quote(sc))
    both("cat <<EOF\n" + APOS + "\nEOF\nbash -c " + shlex.quote(sc))   # a body with a quote before the script: the quote of the script must not pair with it
for w in ("sh -c %s", "zsh -c %s", "eval %s", "env bash -c %s", "bash -lc %s", "nohup sh -c %s", "time bash -c %s", "x=$(bash -c %s)", "echo $(bash -c %s)"):
    both(w % shlex.quote(INNERS[0]))
    both(w % shlex.quote(INNERS[2]))
# what the model of the outer quotes must get right before the script: a quote inside "…", an ANSI-C string, a "$( )" around the script or before it
both("echo \"it\x27s\"\nbash -c " + shlex.quote(INNERS[0]))
both("echo $\x27\\\x27\x27\nbash -c " + shlex.quote(INNERS[0]))
both("echo \"$(bash -c " + shlex.quote(INNERS[0]) + ")\"")
both("echo \"a $(echo \"b\" ; bash -c " + shlex.quote(INNERS[0]) + ")\"")
both("echo \"$(echo x)\" ; bash -c " + shlex.quote(INNERS[0]))
both("echo \"x\" \x27y\x27 ; eval " + shlex.quote(INNERS[0]))
'
echo "   P0-2 controls: the same scripts without the danger pass, and the join the INNER shell does is still read (git re<nl>set --hard in a -c script)"
check 0 git $'bash -c \'cat > n.md <<"EOF"\nx\\\nEOF\ngit status\nEOF\''
check 0 hw $'bash -c \'cat > n.md <<"EOF"\nx\\\nEOF\nls\nEOF\''
check 2 git $'bash -c \'git re\\\nset --hard\''
check 2 hw $'bash -c \'rm -rf /sys\\\ntem\''
check 2 hw $'bash -c \'adb remo\\\nunt\''
check 2 hw $'bash -c "rm -rf /sys\\\ntem"'
echo "   P0-2b: the operator of python3 -c \"\$(cat <<EOF …)\" is not the end of its line: a pipe to a shell or a file that is run makes the body a command source (never cut)"
r5_rows "$R5_COMMON"'
for tail in (" | sh", " > s.sh", " | tee s.sh"):
    both("python3 -c \"$(cat <<\x27EOF\x27" + tail + "\n@CMD@\nEOF\n)\"; sh s.sh")
'
echo "   ACCEPTED false positive, pinned BLOCKED: after the operator a ; or && is no pipe or redirect, yet the guards judge the body (a command source) instead of cutting it as a"
echo "   program; the old guard did not cut it either. Without the operand rule of _code_operand (tail) the body of a program is cut and these rows pass"
r5_rows "$R5_COMMON"'
for tail in (" ; echo x", " && echo x", " || echo x"):
    for h in ("git", "hw"):
        emit("2", h, "python3 -c \"$(cat <<\x27EOF\x27" + tail + "\n" + PAY[h] + "\nEOF\n)\"")
        emit("0", h, "python3 -c \"$(cat <<\x27EOF\x27" + tail + "\n" + CTL[h] + "\nEOF\n)\"")
'

echo "   #526: a program name written in an ANSI-C \$'…' (hex, octal, unicode) is decoded before the rules read it: the same verdict as the bare command (stdin JSON only, nothing runs)"
check 2 git $'$\'\\x67it\' checkout src/a.kt'
check 2 git $'$\'\\147\\151t\' checkout src/a.kt'
check 2 git $'$\'\\u0067it\' checkout src/a.kt'
check 2 git $'g$\'\\x69\'t checkout src/a.kt'
check 0 git $'$\'\\x67it\' status'
check 2 hw $'$\'\\x72m\' -rf "$PWD"'
check 2 hw $'$\'\\162\\155\' -rf "$PWD"'
check 2 hw $'$\'\\u0072m\' -rf "$PWD"'
check 0 hw $'$\'\\x72m\' -f nothing.tmp'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
