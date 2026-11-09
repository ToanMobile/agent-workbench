#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh (+ hooks/shell_norm.py, phần đọc lệnh chung): các dòng 15/10 r5 (kiểm độc lập
#  cây r4): script trong nháy giữ terminator heredoc, chương trình interpreter bị lấy output không bao giờ bị cắt, zx / Bun / dax /
#  Deno khởi tiến trình; các dương tính giả đã chấp nhận được ghim là chặn.
#  Tách từ tests/gates/test_guard_shell_norm.sh (03/11, shard REG-DK-ALL-GATES-01); helper: tests/lib/guard_shell_norm_lib.sh.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, check / check_deny / pair / r5_rows

echo "── r5 (independent verification of the r4 tree; every dangerous row below ran its harmless marker twin under /bin/bash 3.2 and zsh): the"
echo "   newline of the OUTER text is not rewritten, so a quoted script reaches the second pass as typed, and a backslash-newline inside"
echo "   single quotes is literal there (P0-1, P1-c); an interpreter that cannot spawn still prints what a shell runs (P1-a); zx / Bun / Deno start"
echo "   a process without a word of the old sink list (P1-b)"
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
