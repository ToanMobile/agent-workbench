#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh (+ hooks/shell_norm.py, phần đọc lệnh chung): chính shell_norm.py (loại
#  heredoc, strip, cut_ok, import fail-closed), heredoc ghi ra file, delimiter ANSI-C / locale, bảng wrapper dùng chung, chính sách
#  thiết bị sau giá trị option của wrapper, và một từ redirect ở cuối lệnh (review 15/10).
#  Tách từ tests/gates/test_guard_shell_norm.sh (03/11, shard REG-DK-ALL-GATES-01); helper: tests/lib/guard_shell_norm_lib.sh.
# Only the hooks run here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, check / check_mcp / check_deny / pair / r5_rows

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
    # heredoc body is never read here; no SQL schema keyword in it: a split moved this line, merge_policy saw it as added and human-gated #940
    ("mysql <<EOF\nSELECT 1;\nEOF", [("EOF", O, True)]),
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
# 15/10 r6: the text joined outside single quotes is a reading of its own when it differs: a backslash-newline inside '…' or $'…' is the inner shell's (a quoted heredoc terminator of
# a -c script must not move); inside "…" the outer shell joins it, and a $( ) inside "…" is a context of its own again
for text, want in [("bash -c 'a\\\nb'", ["bash -c 'ab'", "bash -c 'a\\\nb'"]), ("echo a\\\nb 'c\\\nd'", ["echo ab 'cd'", "echo ab 'c\\\nd'"]), ("echo \"a\\\nb\"", ["echo \"ab\""]),
                   ("echo $'a\\\nb'", ["echo $'ab'", "echo $'a\\\nb'"]), ("echo \"$(bash -c 'a\\\nb')\"", ["echo \"$(bash -c 'ab')\"", "echo \"$(bash -c 'a\\\nb')\""]),
                   ("echo \"it's\" a\\\nb", ["echo \"it's\" ab"]), ("echo 'x'; echo a\\\nb", ["echo 'x'; echo ab"]), ("echo $'\\''\nbash -c 'a\\\nb'", ["echo $'\\''\nbash -c 'ab'", "echo $'\\''\nbash -c 'a\\\nb'"]),
                   ("echo 'a\\\nb", ["echo 'ab", "echo 'a\\\nb"])]:
    got = sn.readings(text)
    print(("✔ " if got == want else "✖ ") + f"readings (single quotes) {text!r}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    bad += got != want
# 15/10 r6: scan_text drops the quote characters of the lines of a body that stay in the scan and do not close them, nothing else
SCAN_KEEP = lambda h: False
for text, drop, want in [("cat <<EOF\nit's\nEOF\nls", SCAN_KEEP, ("cat <<EOF\nits\nEOF\nls", True)), ("cat <<EOF\nsay \"ok; x\"\nEOF", SCAN_KEEP, ("cat <<EOF\nsay \"ok; x\"\nEOF", False)),
                         ("cat <<EOF\nthe 5\" screen\nsay 'a' \"b\"\nEOF", SCAN_KEEP, ("cat <<EOF\nthe 5 screen\nsay 'a' \"b\"\nEOF", True)),
                         ("cat > n.md <<'EOF'\nit's\nEOF", lambda h: h.kind == "data", ("cat > n.md <<'EOF'\n", False)),
                         ("cat > n.md <<'EOF'\nit's\nEOF", SCAN_KEEP, ("cat > n.md <<'EOF'\nits\nEOF", True)),
                         ("cat <<\"E'OF\"\nx\nE'OF", SCAN_KEEP, ("cat <<\"E'OF\"\nx\nE'OF", False)), ("cat <<EOF\nit's", SCAN_KEEP, ("cat <<EOF\nits", True)),
                         ("echo \"it's\"\ncat <<EOF\nx\nEOF\necho 'a", SCAN_KEEP, ("echo \"it's\"\ncat <<EOF\nx\nEOF\necho 'a", False)),
                         ("cat <<EOF\n" + "a'" * 3000 + "\nEOF", SCAN_KEEP, ("cat <<EOF\n" + "a" * 3000 + "\nEOF", True)),
                         ("cat <<A\nit's\nA\nls\ncat <<B\ndon't\nB", SCAN_KEEP, ("cat <<A\nits\nA\nls\ncat <<B\ndont\nB", True))]:
    got = sn.scan_text(text, drop)
    print(("✔ " if got == want else "✖ ") + f"scan_text {text[:50]!r}: {got[0][:60]!r}, {got[1]}" + ("" if got == want else f" (want {want[0][:60]!r}, {want[1]})"))
    bad += got != want
# 15/10 r6: dq_nested_quote: a "…" holding a $( ) that holds a double quote of its own (the lexer pairs the quotes across it)
for text, want in [("echo \"$(echo \"a b\"; rm -rf ~)\"", True), ("echo \"$(date +%F)\"", False), ("echo \"$(date +\"%F\")\"", True), ("echo $(echo \"a b\")", False), ("echo '\"$(\"'", False),
                   ("echo \"a\" \"$(date)\"", False), ("\"$(\" \";x)\"", True), ("echo \"\\$(echo \"a\")\"", False), ("echo \"$(echo 'a b'; ls)\"", False), ("echo \"$(echo $((1+2)) \"a\")\"", True),
                   ("echo \"$(echo \\\")\"", False), ("echo \"$(true\"", True), ("echo \"x\"$(echo \"y\")", False)]:
    got = sn.dq_nested_quote(text)
    print(("✔ " if got == want else "✖ ") + f"dq_nested_quote {text!r}: {got}" + ("" if got == want else f" (want {want})"))
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

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
