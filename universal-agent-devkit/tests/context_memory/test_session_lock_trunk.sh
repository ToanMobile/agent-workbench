#!/usr/bin/env bash
# W1 R1/R2 v6 (docs/workflow-improvements.md I.0; user 14/10: "mọi phiên sử dụng phải tạo worktree riêng ko giữ main để merge"): in trunk
# mode (`git config devkit.trunkMode true`) the main checkout is merge-only. bin/session_lock.py refuses every write into main ITSELF -
# whoever the session is, from main or from a worktree - and never takes main's lock, so no session ever holds main and a finished
# worktree is merged whenever its session stops. Still allowed in main: the integrator (agent-kit worktree …, worktree.py …), syncing with
# origin (fetch, push, pull --ff-only), builds, and local state git ignores (memory, .claude/audit-gate). A worktree nested under main
# (.claude/worktrees/<name>, where EnterWorktree puts it) is NOT main. `--status` on main says so with exit 5 (Antigravity reads it).
# WORKTREE_TRUNK_MODE=0 (R7) and trunk mode off: the old one-session-per-checkout lock, unchanged.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SL="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"; W2="$TMP/main-w2"
mkdir -p "$M/src" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '.agents/local/memory/\n.claude/audit-gate/\n/.claude/worktrees/\nnode_modules/\n' > "$M/.gitignore"
echo a > "$M/src/a.py" && echo r > "$M/README.md" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD && git -C "$M" worktree add -q --detach "$W2" HEAD
mkdir -p "$M/.agents/local/memory/claude-auto" "$M/.claude/audit-gate"
git -C "$M" config devkit.trunkMode true

# 1 unit: trunk_write - what is a write into main itself
python3 - "$DEVKIT_DIR" "$M" "$W" "$W2" > "$TMP/unit" 2>&1 <<'PY'
import sys
dk, m, w, w2 = sys.argv[1:5]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
E = lambda p: ("Edit", {"file_path": p}, "")
B = lambda c: ("Bash", {"command": c}, c)
import os
tmp = os.path.dirname(m)
alias = tmp + "/alias_of_main"   # a symlink to main: $PWD / $W through it must still land in main
if not os.path.islink(alias):
    os.symlink(m, alias)
os.makedirs(w + "/l[m]", exist_ok=True)   # a dir literally named l[m] in the worktree, and lm -> main: unquoted, the glob l[m] is lm
if not os.path.islink(w + "/lm"):
    os.symlink(m, w + "/lm")
G = "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"
cases = [   # (want, label, cwd, (tool, input, command))
    (True, "Edit a tracked file of main", m, E(f"{m}/src/a.py")),
    (True, "Write a new (not ignored) file in main", m, E(f"{m}/new.md")),
    (True, "a redirect in main", m, B("echo x > a.txt")),
    (True, "a git commit in main", m, B("git commit -qm x")),
    (True, "the gate run in main (it writes the tracked checklist)", m, B("python3 .agents/devkit/bin/post-fix-gate.py --run-tests")),
    (True, "a pull that merges in main", m, B("git pull --no-rebase origin main")),
    (True, "a redirect to $VAR run in main", m, B('echo x > "$OUT"')),
    # issue #13: from a worktree a redirect to "$VAR/..." was judged by where the command runs (the worktree) and let through
    (True, "worktree: MAIN=<main>; redirect to \"$MAIN/f\"", w, B(f'MAIN={m}; echo evil > "$MAIN/src/a.py"')),
    (True, "worktree: export MAIN=<main> && redirect to ${MAIN}/f", w, B(f'export MAIN={m} && echo evil > ${{MAIN}}/README.md')),
    (True, "worktree: single-quoted assignment of main, then tee into it", w, B(f"MAIN='{m}'; echo evil | tee $MAIN/README.md")),
    (True, "worktree: redirect to a variable of unknown origin (fail closed)", w, B('echo evil > "$UNKNOWN/README.md"')),
    (True, "worktree: redirect inside backticks-built path (fail closed)", w, B('echo evil > `pwd`/../x')),
    (False, "worktree: VAR assigned outside main, redirect to \"$VAR/f\"", w, B('OUT=/tmp/o; echo x > "$OUT/f"')),
    (False, "worktree: VAR assigned to a relative file, redirect to $VAR", w, B('OUT=a.txt; echo x > $OUT')),
    # issue #13 QA gap (High): a variable assigned from another variable reads as the empty string, so "$B/f" looked like "/f"
    (True, "worktree: B=$M chained from MAIN, redirect to \"$B/f\"", w, B(f'M={m}; B=$M; echo evil > "$B/README.md"')),
    (True, "worktree: B=\"$M\" chained and quoted, redirect to \"$B/f\"", w, B(f'M={m}; B="$M"; echo evil > "$B/README.md"')),
    (True, "worktree: B=$M/x chained with a suffix, redirect to \"$B/../f\"", w, B(f'M={m}; B=$M/x; echo evil > "$B/../README.md"')),
    # issue #13 reviewer R1: `M+=/main` appends to the value, so the variable is no longer the one assigned before
    (True, "worktree: M=<parent>; M+=/main appended, redirect to \"$M/f\"", w, B(f'M={m.rsplit("/", 1)[0]}; M+=/{m.rsplit("/", 1)[1]}; echo evil > "$M/README.md"')),
    (True, "worktree: M=<main>; M+=/x appended (value changes), redirect to \"$M/../README.md\"", w, B(f'M={m}; M+=/x; echo evil > "$M/../README.md"')),
    # issue #13 QA v3 gap (High): sed -i / perl -pi have no target in shell_writes, so a "$VAR/f" target skipped the $VAR rule (the literal path is blocked)
    (True, "worktree: M=<main>; sed -i on \"$M/f\"", w, B(f'M={m}; sed -i s/r/x/ "$M/README.md"')),
    (True, "worktree: M=<main>; perl -pi on \"$M/f\"", w, B(f'M={m}; perl -pi -e s/r/x/ "$M/README.md"')),
    (False, "worktree: O=/tmp/o; sed -i on \"$O/f\"", w, B('O=/tmp/o; sed -i s/r/x/ "$O/f"')),
    # issue #13 QA v4 gap (High): a bare $VAR operand of sed -i / perl -pi, and a cd through a variable, fell outside the $VAR/ rule
    (True, "worktree: M=<main>/README.md; sed -i on \"$M\"", w, B(f'M={m}/README.md; sed -i s/r/x/ "$M"')),
    (True, "worktree: M=<main>/README.md; perl -pi on \"${M}\"", w, B(f'M={m}/README.md; perl -pi -e s/r/x/ "${{M}}"')),
    (True, "worktree: M=<main>; cd \"$M\" then a relative redirect", w, B(f'M={m}; cd "$M" && echo x > README.md')),
    (True, "worktree: M=<main>; cd \"$M\" then a relative sed -i", w, B(f'M={m}; cd "$M" && sed -i s/r/x/ README.md')),
    (True, "worktree: cd to a variable of unknown origin, then a relative redirect (fail closed)", w, B('cd "$UNKNOWN" && echo x > README.md')),
    (False, "worktree: O=/tmp/o; sed -i on a bare \"$O\"", w, B('O=/tmp/o/f; sed -i s/r/x/ "$O"')),
    (False, "worktree: sed -i with the script '$d' on a worktree file", w, B("sed -i '$d' README.md")),
    (False, "worktree: O=/tmp/o; cd \"$O\" then a relative redirect", w, B('O=/tmp/o; cd "$O" && echo x > f.txt')),
    (True, "an allowed segment does not excuse the next", m, B(f"agent-kit worktree finish {w} && echo x > a.txt")),
    (True, "cp into main from a worktree", w, B(f"cp /tmp/a {m}/b.txt")),
    (True, "cd to main from a worktree, then rm", w, B(f"cd {m} && rm -f README.md")),
    (True, "git -C main commit from a worktree", w, B(f"git -C {m} commit -qm x")),
    (True, "an allowed fetch with its own redirect into main", m, B("git fetch origin > src/a.py")),
    (True, "an allowed agent-kit worktree list redirected into main", m, B("agent-kit worktree list > README.md")),
    (True, "an allowed push appending its stderr into main", m, B("git push 2>> notes.md")),
    (False, "Edit in the nested session worktree", m, E(f"{w}/src/a.py")),
    (False, "Edit in a sibling worktree", m, E(f"{w2}/README.md")),
    (False, "Edit agent memory (ignored)", m, E(f"{m}/.agents/local/memory/claude-auto/n.md")),
    (False, "append to .claude/audit-gate (ignored)", m, B(f"echo x >> {m}/.claude/audit-gate/log")),
    (False, "a redirect in the worktree", w, B("echo x > a.txt")),
    (False, "a git commit in the worktree", w, B("git commit -qm x")),
    (False, "cd from main into the nested worktree, then write", m, B(f"cd {w} && echo y > f.txt")),
    (False, "agent-kit worktree finish (the integrator)", m, B(f"agent-kit worktree finish {w}")),
    (False, "worktree.py automerge (the integrator)", m, B(f"python3 -I {dk}/scripts/git/worktree.py automerge {w}")),
    (False, "fetch + push", m, B("git fetch origin && git push origin main")),
    (False, "pull --ff-only", m, B("git pull --ff-only")),
    (False, "a build run in main", m, B("npm test")),
    (False, "a redirect outside", m, B("grep -rn x . > /tmp/out.txt 2>/dev/null")),
    (False, "a read", m, B("git status --short && git log --oneline -3")),
    # R3 review P2-4: the body of a heredoc fed to a shell is commands, fed to an interpreter a script (its literal file paths)
    (True, "a bash heredoc whose body redirects into main", m, B("bash <<'EOF'\necho x > README.md\nEOF")),
    (True, "a `sh -s` heredoc whose body copies into main", m, B("sh -s <<EOF\ncp /tmp/a b.txt\nEOF")),
    (True, "a bash heredoc whose body cds to main from a worktree, then writes", w, B(f"bash <<'EOF'\ncd {m} && echo x > README.md\nEOF")),
    (True, "a python heredoc opening a file of main for writing", m, B("python3 - <<EOF\nopen('README.md','w').write('x')\nEOF")),
    (True, "a node heredoc writing a file of main", m, B("node - <<EOF\nrequire('fs').writeFileSync('README.md', 'x')\nEOF")),
    (False, "a bash heredoc whose body redirects in the worktree", w, B("bash <<'EOF'\necho x > a.txt\nEOF")),
    (False, "a bash heredoc whose body redirects to /tmp", m, B("bash <<'EOF'\necho x > /tmp/o.txt\nEOF")),
    (False, "a bash heredoc whose body only reads", m, B("bash <<'EOF'\ngrep -rn x . | head -3\nEOF")),
    (False, "a data heredoc (cat) whose body holds a `>`", m, B("cat <<EOF\na > b.txt\nEOF")),
    (False, "a python heredoc writing to /tmp", m, B("python3 - <<EOF\nopen('/tmp/x.txt','w').write('x')\nEOF")),
    (False, "a python heredoc that only reads", m, B("python3 - <<EOF\nprint(open('README.md').read())\nEOF")),
    (False, "a python heredoc writing in the worktree", w, B("python3 - <<EOF\nopen('README.md','w').write('x')\nEOF")),
    # principal review R2 (14/10) + OCR 12: a script fed to a shell / interpreter on stdin, a substitution, and a body that does not parse
    (True, "echo '...' | sh redirecting into main", m, B("echo 'echo x > README.md' | sh")),
    (True, "printf ... | bash redirecting into main", m, B("printf '%s\\n' 'echo x > README.md' | bash")),
    (True, "cat <<EOF | bash whose body redirects into main", m, B("cat <<'EOF' | bash\necho x > README.md\nEOF")),
    (True, "bash <<< '...' redirecting into main", m, B("bash <<< 'echo x > README.md'")),
    (True, "cat <<EOF | python3 opening a file of main for writing", m, B("cat <<'EOF' | python3\nopen('README.md','w').write('x')\nEOF")),
    (True, "cat <<EOF | bash with a body cd-ing to main from a worktree", w, B(f"cat <<'EOF' | bash\ncd {m} && echo x > README.md\nEOF")),
    (True, "a bash heredoc with an apostrophe in a comment, then a redirect", m, B("bash <<'EOF'\n# don't worry\necho x > README.md\nEOF")),
    (True, "a bash heredoc whose body cannot be tokenised (fail closed)", m, B("bash <<'EOF'\necho 'oops\nEOF")),
    # OCR2 14: heredoc bodies are matched to `<<` tokens by position; a stray `<<` (arithmetic) or a `<<EOF` in a quote / comment shifted every body
    # onto the wrong command and the real one got none. When the counts differ every body is read as a script of the line (fail closed).
    (True, "arithmetic << before a bash heredoc whose body writes into main", m, B("echo $((1<<2)); bash <<EOF\necho x > README.md\nEOF")),
    (True, "arithmetic << before a python heredoc opening a file of main for writing", m, B("echo $((1<<2)); python3 - <<EOF\nopen('README.md','w').write('x')\nEOF")),
    (True, "a quoted <<EOF on an earlier line, then a real bash heredoc writing into main", m, B('echo "a<<EOF"\nbash <<EOF\necho x > README.md\nEOF')),
    (True, "a <<EOF in a comment, then a real bash heredoc writing into main", m, B("# <<EOF\nbash <<EOF\necho x > README.md\nEOF")),
    # OCR2 2: `-s` means "script from stdin" for a shell only; python's -s is "no user site-packages", the heredoc is data for tool.py
    (False, "python3 -s tool.py fed a heredoc of data (no stdin script)", m, B("python3 -s tool.py <<EOF\nopen('README.md','w').write('x')\nEOF")),
    (True, "python3 -s - fed a python heredoc (stdin script)", m, B("python3 -s - <<EOF\nopen('README.md','w').write('x')\nEOF")),
    # OCR2 3: literal-path writes the first pattern missed - a `+` mode, mode= after other keyword arguments, Path(...).open(mode)
    (True, "python heredoc open('README.md', 'r+')", m, B("python3 - <<EOF\nopen('README.md', 'r+').write('x')\nEOF")),
    (True, "python heredoc open('README.md','rb+')", m, B("python3 - <<EOF\nopen('README.md','rb+').write(b'x')\nEOF")),
    (True, "python heredoc open('README.md', encoding='utf8', mode='w')", m, B("python3 - <<EOF\nopen('README.md', encoding='utf8', mode='w').write('x')\nEOF")),
    (True, "python heredoc Path('README.md').open('w')", m, B("python3 - <<EOF\nfrom pathlib import Path\nPath('README.md').open('w').write('x')\nEOF")),
    (True, "python heredoc Path('README.md').open(mode='a')", m, B("python3 - <<EOF\nfrom pathlib import Path\nPath('README.md').open(mode='a').write('x')\nEOF")),
    (False, "python heredoc open('README.md', 'r') and 'rb'", m, B("python3 - <<EOF\nprint(open('README.md', 'r').read(), open('README.md','rb').read())\nEOF")),
    (False, "python heredoc open('README.md', encoding='utf8') (a read)", m, B("python3 - <<EOF\nprint(open('README.md', encoding='utf8').read())\nEOF")),
    (False, "python heredoc Path('README.md').open() and .open('r')", m, B("python3 - <<EOF\nfrom pathlib import Path\nPath('README.md').open().read(); Path('README.md').open('r').read()\nEOF")),
    (False, "python heredoc open('README.md', 'r+') in the worktree", w, B("python3 - <<EOF\nopen('README.md', 'r+').write('x')\nEOF")),
    (False, "arithmetic << before a bash heredoc that only reads", m, B("echo $((1<<2)); bash <<EOF\ngrep -rn x . | head -3\nEOF")),
    (False, "arithmetic << before a bash heredoc writing in the worktree", w, B("echo $((1<<2)); bash <<EOF\necho x > a.txt\nEOF")),
    (True, "a git commit inside a substitution", m, B("echo $(git commit -qm x)")),
    (True, "a redirect inside $( )", m, B("echo $(echo x > README.md)")),
    (True, "a redirect inside backticks", m, B("echo `echo x > README.md`")),
    (True, "a redirect inside <( )", m, B("cat <(echo x > README.md)")),
    (True, "a redirect two substitutions deep", m, B("echo $(echo $(echo x > README.md))")),
    (True, "a substitution inside bash -c", m, B("bash -c 'echo $(touch README.md)'")),
    (False, "echo of the text of a redirect (no pipe)", m, B("echo 'echo x > README.md'")),
    (False, "echo ... | sh redirecting in the worktree", w, B("echo 'echo x > a.txt' | sh")),
    (False, "bash <<< '...' writing to /tmp", m, B("bash <<< 'echo x > /tmp/o.txt'")),
    (False, "printf ... | bash that only reads", m, B("printf '%s\\n' 'git status' | bash")),
    (False, "a commit message heredoc inside $( ) with a > in it (a commit in the worktree)", w, B("git commit -qm \"$(cat <<'EOF'\nfix: a > b, don't\nEOF\n)\"")),
    (False, "a read substitution", m, B('echo "$(git status --short)" && echo "$(date)" > /tmp/o.txt')),
    (False, "cat <<EOF | python3 writing to /tmp", m, B("cat <<'EOF' | python3\nopen('/tmp/x.txt','w').write('x')\nEOF")),
    (False, "an apostrophe in a trailing comment after a read", m, B("git status # it's clean")),
    (False, "a redirect that only appears in a comment", m, B("git status # then echo x > README.md, don't")),
    # OCR 9 (14/10): "syncing main with origin" is a remote sync only - no local path as the remote, no refspec that names a local ref, no -u
    (True, "pull --ff-only of a local branch (remote `.`) in main", m, B("git pull --ff-only . feature")),
    (True, "pull --ff-only with options after the remote, a local branch", m, B("git pull origin --ff-only feature:main")),
    (True, "git -C main pull --ff-only . branch, run from a worktree", w, B(f"git -C {m} pull --ff-only . feature")),
    (True, "pull --ff-only from a path remote in main", m, B("git pull --ff-only ../other main")),
    (True, "fetch into main's own branch with --update-head-ok, remote `.`", m, B("git fetch . HEAD:main --update-head-ok")),
    (True, "the same run from a worktree (it moves main's ref, whoever runs it)", w, B("git fetch . HEAD:main --update-head-ok")),
    (True, "fetch origin x:main --update-head-ok", w, B("git fetch origin x:main --update-head-ok")),
    (True, "fetch -u ., the short flag", w, B("git fetch -u . HEAD:main")),
    (True, "fetch with a clustered short flag containing u", w, B("git fetch -pu origin x:main")),
    (False, "pull --ff-only of a local branch in a worktree (it fast-forwards the worktree, not main)", w, B("git pull --ff-only . feature")),
    (False, "fetch origin", m, B("git fetch origin")),
    (False, "fetch origin main", m, B("git fetch origin main")),
    (False, "fetch --all --prune", m, B("git fetch --all --prune")),
    (False, "fetch into remote-tracking refs", m, B("git fetch origin main:refs/remotes/origin/main")),
    (False, "fetch from a worktree without the flag (git itself refuses to touch a checked-out branch)", w, B("git fetch origin")),
    (False, "pull --ff-only origin main", m, B("git pull --ff-only origin main")),
    (False, "git -C main pull --ff-only (no remote)", w, B(f"git -C {m} pull --ff-only")),
    (False, "push -u origin <branch>", m, B("git push -u origin feature")),
    (False, "push origin HEAD:refs/heads/x", m, B("git push origin HEAD:refs/heads/x")),
    # audit 25/10 A.4: lệnh gate mà kit tự dặn (AGENTS.md §7.1 `cd <wt> && CLAUDE_PROJECT_DIR="$PWD" …post-fix-gate.py`) bị chặn khi cwd LÀ
    # worktree: $PWD không được hiểu là thư mục đang theo dõi (404 lần/14 ngày). $PWD / ${PWD} = cwd của segment; cwd không biết, '$PWD' (nháy
    # đơn), $OLDPWD, PWD bị gán lại, phần sau dấu nháy (`"$PWD"/../..`) thì vẫn fail closed.
    (False, "worktree: CLAUDE_PROJECT_DIR=\"$PWD\" gate (AGENTS.md §7.1)", w, B(f'CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (False, "worktree: CLAUDE_PROJECT_DIR=$PWD gate", w, B(f"CLAUDE_PROJECT_DIR=$PWD {G}")),
    (False, "worktree: CLAUDE_PROJECT_DIR=${PWD} gate", w, B(f"CLAUDE_PROJECT_DIR=${{PWD}} {G}")),
    (False, "main: cd <wt> && CLAUDE_PROJECT_DIR=\"$PWD\" gate", m, B(f'cd {w} && CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (False, "worktree: cd <wt> && CLAUDE_PROJECT_DIR=\"$PWD\" gate > log 2>&1", w, B(f'cd {w} && CLAUDE_PROJECT_DIR="$PWD" {G} > {tmp}/g.log 2>&1')),
    (False, "worktree: git -C \"$PWD\" commit", w, B('git -C "$PWD" commit -qm x')),
    (True, "main: CLAUDE_PROJECT_DIR=\"$PWD\" gate", m, B(f'CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (True, "main: cd <main> && CLAUDE_PROJECT_DIR=\"$PWD\" gate", m, B(f'cd {m} && CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (True, "worktree: cd <main> && CLAUDE_PROJECT_DIR=\"$PWD\" gate", w, B(f'cd {m} && CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (True, "worktree: cd <symlink to main> && CLAUDE_PROJECT_DIR=\"$PWD\" gate", w, B(f'cd {alias} && CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (True, "worktree: CLAUDE_PROJECT_DIR=\"$PWD/../../..\" gate (.. back into main)", w, B(f'CLAUDE_PROJECT_DIR="$PWD/../../.." {G}')),
    (True, "worktree: CLAUDE_PROJECT_DIR=\"$PWD\"/../../.. gate (the word goes on after the quote)", w, B(f'CLAUDE_PROJECT_DIR="$PWD"/../../.. {G}')),
    (True, "worktree: git -C \"$PWD\"/../../.. commit (the word goes on after the quote)", w, B('git -C "$PWD"/../../.. commit -qm x')),
    (True, "worktree: git -C \"<wt>\"/../../.. commit (literal, the word goes on after the quote)", w, B(f'git -C "{w}"/../../.. commit -qm x')),
    (True, "worktree: CLAUDE_PROJECT_DIR='$PWD' gate (single quotes: no expansion)", w, B(f"CLAUDE_PROJECT_DIR='$PWD' {G}")),
    (True, "worktree: CLAUDE_PROJECT_DIR=\\$PWD gate (escaped $)", w, B(f"CLAUDE_PROJECT_DIR=\\$PWD {G}")),
    (True, "worktree: CLAUDE_PROJECT_DIR=$OLDPWD gate", w, B(f"CLAUDE_PROJECT_DIR=$OLDPWD {G}")),
    (True, "worktree: CLAUDE_PROJECT_DIR=$PWDX gate (another variable)", w, B(f"CLAUDE_PROJECT_DIR=$PWDX {G}")),
    (True, "worktree: CLAUDE_PROJECT_DIR=${PWD%/*} gate", w, B(f"CLAUDE_PROJECT_DIR=${{PWD%/*}} {G}")),
    (True, "worktree: cd $X && CLAUDE_PROJECT_DIR=\"$PWD\" gate (cwd unknown)", w, B(f'cd $X && CLAUDE_PROJECT_DIR="$PWD" {G}')),
    (True, "worktree: PWD=<main>; CLAUDE_PROJECT_DIR=$PWD gate (PWD rebound)", w, B(f"PWD={m}; CLAUDE_PROJECT_DIR=$PWD {G}")),
    (True, "worktree: (cd <main>; CLAUDE_PROJECT_DIR=$PWD gate) (a subshell)", w, B(f"(cd {m}; CLAUDE_PROJECT_DIR=$PWD {G})")),
    # audit 25/10 A.4: `git pull --ff-only 2>&1 | tail` ở main bị chặn vì `2>&1` bị đọc như remote (đối số vị trí) trong _trunk_sync
    (False, "main: git pull --ff-only 2>&1 | tail -5", m, B("git pull --ff-only 2>&1 | tail -5")),
    (False, "main: git pull --ff-only 2>/dev/null", m, B("git pull --ff-only 2>/dev/null")),
    (False, "main: git pull --ff-only > <outside>/pull.log 2>&1", m, B(f"git pull --ff-only > {tmp}/pull.log 2>&1")),
    (False, "main: git pull --ff-only origin 2>&1", m, B("git pull --ff-only origin 2>&1")),
    (True, "main: git pull --ff-only . feature 2>&1", m, B("git pull --ff-only . feature 2>&1")),
    (True, "main: git pull --ff-only 2>&1 > README.md", m, B("git pull --ff-only 2>&1 > README.md")),
    (True, "main: git pull --no-rebase origin main 2>&1 | tail", m, B("git pull --no-rebase origin main 2>&1 | tail")),
    (True, "main: git push 2>&1 . HEAD:main (a local remote after the redirect)", m, B("git push 2>&1 . HEAD:main")),
    (True, "main: git pull --ff-only origin \\> feature:main (an escaped >, no redirect)", m, B("git pull --ff-only origin \\> feature:main")),
    (True, "main: git pull --ff-only origin '>' feature:main (a quoted >, no redirect)", m, B("git pull --ff-only origin '>' feature:main")),
    (True, "main: git pull --ff-only origin '2>/tmp/x:main' (a quoted refspec into main, no redirect)", m, B("git pull --ff-only origin '2>/tmp/x:main'")),
    # audit 25/10 A.4: `W=<dir>; git -C $W …` - W gán giá trị chữ ở segment trước, cùng shell, chỉ một lần trước chỗ dùng
    (False, "worktree: W=<wt>; git -C $W add && git -C $W commit", w, B(f"W={w}; git -C $W add -A && git -C $W commit -qm x")),
    (False, "main: W=<wt>; git -C \"$W\" commit", m, B(f'W={w}; git -C "$W" commit -qm x')),
    (False, "main: W=.claude/worktrees/s1 (relative) && git -C $W commit", m, B("W=.claude/worktrees/s1 && git -C $W commit -qm x")),
    (False, "main: export W=<wt>; git -C ${W} commit", m, B(f"export W={w}; git -C ${{W}} commit -qm x")),
    (False, "main: W=<wt>; git -C $W add && commit -m \"$(cat <<'EOF' … EOF)\" (a heredoc message after the assignment)", m,
     B(f"W={w}; git -C $W add -A && git -C $W commit -qm \"$(cat <<'EOF'\nfix: x\nEOF\n)\"")),
    (True, "main: x=$(true; W=<wt> <newline>); git -C \"$W\" commit (W assigned in a substitution's subshell)", m, B(f"x=$(true; W={w}\n); git -C \"$W\" commit -qm x")),
    (True, "main: (W=<wt>); git -C \"$W\" commit (W assigned in a subshell)", m, B(f"(W={w}); git -C \"$W\" commit -qm x")),
    (True, "worktree: W=<main>; git -C $W commit", w, B(f"W={m}; git -C $W commit -qm x")),
    (True, "worktree: W=<wt>/../../..; git -C $W commit (.. back into main)", w, B(f"W={w}/../../..; git -C $W commit -qm x")),
    (True, "worktree: W=<symlink to main>; git -C $W commit", w, B(f"W={alias}; git -C $W commit -qm x")),
    (True, "worktree: W=<main>; git -C $W commit; W=<wt> (assigned again after the use)", w, B(f"W={m}; git -C $W commit -qm x; W={w}")),
    (True, "worktree: W=<wt>; for W in <main>; do git -C $W commit; done", w, B(f"W={w}; for W in {m}; do git -C $W commit -qm x; done")),
    (True, "worktree: W=<wt> git -C $W commit (an inline prefix: $W is the old value)", w, B(f"W={w} git -C $W commit -qm x")),
    (True, "worktree: false || W=<wt>; git -C $W commit (the assignment may not run)", w, B(f"false || W={w}; git -C $W commit -qm x")),
    (True, "worktree: W=<wt> | true; git -C $W commit (assigned in a pipe subshell)", w, B(f"W={w} | true; git -C $W commit -qm x")),
    (True, "worktree: if/else assigning W on its own lines (main on the path taken), then git -C $W commit", w, B(f"if true; then\nW={m}\nelse\nW={w}\nfi\ngit -C $W commit -qm x")),
    (True, "worktree: W=<wt>; read W; git -C $W commit", w, B(f"W={w}; read W; git -C $W commit -qm x")),
    (True, "worktree: W=<wt>; source x.sh; git -C $W commit", w, B(f"W={w}; source x.sh; git -C $W commit -qm x")),
    (True, "worktree: W=<wt>; W=$M (chained from an unknown variable)", w, B(f"W={w}; W=$M; git -C $W commit -qm x")),
    (True, "worktree: W=<main> <nl> # note; W=<wt> <nl> git -C $W commit (a comment assigns nothing)", w, B(f"W={m}\n# note; W={w}\ngit -C $W commit -qm x")),
    (True, "worktree: W=; : ${W:=<main>}; git -C $W commit (a default assignment)", w, B(f"W=; : ${{W:={m}}}; git -C $W commit -qm x")),
    (True, "worktree: W=<wt>/l[m] unquoted: the glob picks the link to main, not the dir named l[m]", w, B(f"W={w}/l[m]; git -C $W commit -qm x")),
    (False, "worktree: W=<wt>/l[m] in double quotes: the dir named l[m] (no glob)", w, B(f'W={w}/l[m]; git -C "$W" commit -qm x')),
]
bad = 0
for want, label, cwd, (tool, ti, cmd) in cases:
    got = sl.trunk_write(tool, ti, cmd, cwd, main, sw, "s")
    if got != want:
        bad += 1
        print(f"✖ {label}: want {want}, got {got}")
print(f"unit-bad={bad} of {len(cases)}")
PY
grep -q "unit-bad=0 " "$TMP/unit" && ok "trunk_write: $(grep -o 'of [0-9]*' "$TMP/unit") cases (main itself vs nested/sibling worktrees, ignored state, integrator, sync)" \
  || { fail "trunk_write cases"; grep "✖\|Error\|assert" "$TMP/unit" | head -12; }

# 1b review 25/10 (d6b6d57c): theo dõi biến / $PWD không được bậc hai theo độ dài lệnh - ~200 KB (20 000 phép gán) xong dưới 2 s, vẫn chặn
python3 - "$DEVKIT_DIR" "$M" "$W" > "$TMP/perf" 2>&1 <<'PY'
import signal, sys, time
dk, m, w = sys.argv[1:4]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
bad = 0


def too_slow(*_):
    raise TimeoutError("over 30 s")


# A quadratic walk runs for minutes: the wall-clock alarm only stops a hang (30 s), the bound itself is CPU time of this
# process (time.process_time), which a loaded machine does not inflate — the 2 s wall bound failed inside run_impacted.sh's
# parallel pool at load ~70 (gate 25/10) while the walk took 0.4 s alone.
signal.signal(signal.SIGALRM, too_slow)
for label, body in (("20000 x `W=/tmp/x; `", "W=/tmp/x; " * 20000), ("20000 distinct `W<i>=/x; `", "".join(f"W{i}=/x; " for i in range(20000))),
                    # every segment that is no assignment used to scan every known name (and compile two regexes for it): 2000 pairs took 57 s
                    ("15000 x `W<i>=/x; : ; `", "".join(f"W{i}=/x; : ; " for i in range(15000))),
                    ("12000 x `W<i>=/x; cd /tmp; `", "".join(f"W{i}=/x; cd /tmp; " for i in range(12000)))):
    cmd = body + f"W={m}; git -C $W commit -qm x"
    for fn, call in (("write_hits_locked", lambda: sl.write_hits_locked(cmd, m, w, "s")[0]),
                     ("_bash_trunk_write", lambda: sl._bash_trunk_write(cmd, w, main, sw, "s", 0))):
        t0 = time.process_time()
        signal.alarm(30)
        try:
            got = call()
        except TimeoutError:
            got = None
        finally:
            signal.alarm(0)
        dt = time.process_time() - t0
        print(f"{'✔' if got and dt < 2 else '✖'} {fn} on {label} ({len(cmd) // 1024} KB): {dt:.2f} s, blocked={got}")
        bad += not (got and dt < 2)
print(f"perf-bad={bad}")
PY
grep -q "perf-bad=0" "$TMP/perf" && ok "~200 KB command: write_hits_locked and _bash_trunk_write under 2 s, still blocked ($(grep -o '[0-9.]* s' "$TMP/perf" | tr '\n' ' '))" \
  || { fail "bounded time on a ~200 KB command"; grep "✖\|Error" "$TMP/perf" | head -6; }

# 2 the hook: a write into main is refused with what to do, and no lock is taken; a read and the integrator pass, also no lock
hook() {   # hook <event> <cwd> <tool> <json tool_input> [env...]: exit code; stderr in $TMP/err
  local ev="$1" cwd="$2" tool="$3" ti="$4"; shift 4
  python3 -c 'import json,sys; ev,cwd,tool,ti=sys.argv[1:5]; print(json.dumps({"hook_event_name":ev,"session_id":"sess-a","cwd":cwd,"tool_name":tool,"tool_input":json.loads(ti)}))' "$ev" "$cwd" "$tool" "$ti" \
    | env "$@" python3 -I "$SL" 2> "$TMP/err"
}
lockof() { [ -f "$(git -C "$1" rev-parse --absolute-git-dir)/devkit-session.lock" ]; }
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}"; rc=$?
[ "$rc" = 2 ] && grep -q "Trunk mode" "$TMP/err" && grep -q "EnterWorktree" "$TMP/err" && ! lockof "$M" && ok "Edit in main: refused (exit 2) with EnterWorktree as the way, main's lock not taken" \
  || fail "Edit in main (rc $rc, lock $(lockof "$M" && echo taken || echo none)): $(head -c 200 "$TMP/err")"
hook PreToolUse "$M" Bash '{"command": "git status --short"}'; r1=$?
hook PreToolUse "$M" Bash "{\"command\": \"agent-kit worktree finish $W\"}"; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && ! lockof "$M" && ok "  … a read and the integrator in main: allowed, still no lock on main" || fail "read/integrator in main: $r1 $r2 lock $(lockof "$M" && echo taken)"
hook PreToolUse "$W" Bash '{"command": "echo x > w.txt"}'; rc=$?
[ "$rc" = 0 ] && lockof "$W" && ! lockof "$M" && ok "a write in the session's worktree: allowed, the WORKTREE's lock taken (one session per worktree, as before)" \
  || fail "write in worktree (rc $rc): $(head -c 200 "$TMP/err")"
hook SessionStart "$M" "" '{}'; ! lockof "$M" && ok "SessionStart in main: no lock taken" || fail "SessionStart took main's lock in trunk mode"
# audit 25/10 A.4 qua hook thật: lệnh gate của AGENTS.md §7.1 từ worktree, `git pull --ff-only 2>&1 | tail` ở main (exit 0); cd về main rồi "$PWD" (exit 2)
ti() { python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }   # $PWD trong nháy đơn: hook thấy nguyên chữ $PWD
hook PreToolUse "$W" Bash "$(ti 'CLAUDE_PROJECT_DIR="$PWD" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief')"; r1=$?
hook PreToolUse "$M" Bash "$(ti "cd $W && CLAUDE_PROJECT_DIR=\"\$PWD\" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief")"; r2=$?
hook PreToolUse "$M" Bash "$(ti 'git pull --ff-only 2>&1 | tail -5')"; r3=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r3" = 0 ] && ! lockof "$M" && ok "hook: CLAUDE_PROJECT_DIR=\"\$PWD\" gate from / into a worktree, pull --ff-only 2>&1 | tail in main -> exit 0" \
  || fail "hook \$PWD gate / pull 2>&1 (rc $r1 $r2 $r3): $(head -c 300 "$TMP/err")"
hook PreToolUse "$W" Bash "$(ti "cd $M && CLAUDE_PROJECT_DIR=\"\$PWD\" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief")"; r1=$?
hook PreToolUse "$M" Bash "$(ti 'CLAUDE_PROJECT_DIR="$PWD" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief')"; r2=$?
[ "$r1" = 2 ] && [ "$r2" = 2 ] && grep -q "Trunk mode" "$TMP/err" && ok "hook: cd <main> && CLAUDE_PROJECT_DIR=\"\$PWD\" gate, and \"\$PWD\" gate run in main -> exit 2 (Trunk mode)" \
  || fail "hook \$PWD gate into main (rc $r1 $r2): $(head -c 300 "$TMP/err")"

# 2b the USER's switches (R3 review P2-5, like allow-shared): an agent's command may not turn trunk mode off - `agent-kit worktree trunk off`,
#    `git config devkit.trunkMode <not true>` / --unset ..., WORKTREE_TRUNK_MODE=0 set in the command. `trunk on`, true values and reads only tighten.
python3 - "$DEVKIT_DIR" > "$TMP/unit2" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/bin")
import session_lock as sl
cases = [   # (want, command)
    (True, "agent-kit worktree trunk off"),
    (True, "python3 -I scripts/git/worktree.py trunk off"),
    (True, "nice -n 5 agent-kit worktree trunk off"),
    (True, "cd /x && agent-kit worktree trunk off"),
    (True, "git config devkit.trunkMode false"),
    (True, "git config --local devkit.trunkMode 0"),
    (True, "git -C /x config devkit.trunkMode no"),
    (True, "git config devkit.trunkmode off"),
    (True, "git config devkit.trunkMode ''"),
    (True, 'git config devkit.trunkMode "$V"'),
    (True, "git config --bool devkit.trunkMode off"),
    (True, "git config --unset devkit.trunkMode"),
    (True, "git config --unset-all devkit.trunkMode"),
    (True, "git config --replace-all devkit.trunkMode false"),
    (True, "git config --add devkit.trunkMode false"),
    (True, "git config --global devkit.trunkMode false"),
    (True, "git config --file .git/config devkit.trunkMode false"),
    (True, "git config unset devkit.trunkMode"),
    (True, "git config set devkit.trunkMode false"),
    (True, "git config --remove-section devkit"),
    (True, "WORKTREE_TRUNK_MODE=0 agent-kit worktree finish x"),
    (True, "FOO=1 WORKTREE_TRUNK_MODE='0' git commit -qm x"),
    (True, 'WORKTREE_TRUNK_MODE="$X" git commit -qm x'),
    (True, "export WORKTREE_TRUNK_MODE=0 && git commit -qm x"),
    (True, "env -i WORKTREE_TRUNK_MODE=0 PATH=/bin git commit -qm x"),
    (True, "(WORKTREE_TRUNK_MODE=0 git commit -qm x)"),
    (True, "bash -c 'WORKTREE_TRUNK_MODE=0 git commit -qm x'"),
    (True, "bash <<'EOF'\nWORKTREE_TRUNK_MODE=0 git commit -qm x\nEOF"),
    (False, "agent-kit worktree trunk on"),
    (False, "agent-kit worktree trunk status"),
    (False, "git config devkit.trunkMode"),
    (False, "git config --get devkit.trunkMode"),
    (False, "git config --get-all devkit.trunkMode"),
    (False, "git config --list"),
    (False, "git config user.name x"),
    (False, "git config --unset core.editor"),
    (False, "WORKTREE_TRUNK_MODE=1 git commit -qm x"),
    (False, "unset WORKTREE_TRUNK_MODE"),
    (False, 'git commit -qm "docs: agent-kit worktree trunk off"'),
    (False, "git commit -qm \"WORKTREE_TRUNK_MODE=0 is the user's switch\""),
    (False, "echo agent-kit worktree trunk off"),
    (False, "grep -n WORKTREE_TRUNK_MODE=0 docs/a.md"),
    (False, 'grep -rn "git config devkit.trunkMode false" docs'),
    (False, "cat <<EOF\nagent-kit worktree trunk off\nEOF"),
    (False, "git status --short"),
    # OCR 12 + principal review R2 (14/10): the switch inside a substitution, or in a script fed to a shell on stdin
    (True, "echo $(agent-kit worktree trunk off)"),
    (True, "cat <(git config devkit.trunkMode false)"),
    (True, "x=$(git config devkit.trunkMode false)"),
    (True, "x=$(agent-kit worktree trunk off)"),
    (True, "echo `agent-kit worktree trunk off`"),
    (True, 'echo "$(git config devkit.trunkMode false)"'),
    (True, "echo $(echo $(git config devkit.trunkMode false))"),
    (True, "bash -c 'x=$(git config devkit.trunkMode false)'"),
    (True, "echo 'git config devkit.trunkMode false' | sh"),
    (True, "printf '%s\\n' 'agent-kit worktree trunk off' | bash"),
    (True, "cat <<'EOF' | bash\nagent-kit worktree trunk off\nEOF"),
    (True, "bash <<< 'git config devkit.trunkMode false'"),
    (True, "bash <<'EOF'\n# don't worry\ngit config devkit.trunkMode false\nEOF"),
    (True, "echo 'WORKTREE_TRUNK_MODE=0 git commit -qm x' | sh"),
    (False, 'echo "$(git config --get devkit.trunkMode)"'),
    (False, "x=$(git config devkit.trunkMode)"),
    (False, "git commit -qm \"$(cat <<'EOF'\ndocs: agent-kit worktree trunk off\nEOF\n)\""),
    (False, "echo 'agent-kit worktree trunk off' | grep -c off"),
    (False, "echo 'agent-kit worktree trunk off' | tee /tmp/n.txt"),
    (False, "echo 'agent-kit worktree trunk status' | sh"),
    (False, "bash <<< 'git config --get devkit.trunkMode'"),
    (False, "git status # don't run agent-kit worktree trunk off"),
    # OCR2 21: a launcher's option that takes a VALUE (env -u FOO, env -C DIR, sudo -u USER, nice -n N, timeout -s SIG) - the loop dropped the option and
    # read its value as the program, so the git config behind it was never looked at
    (True, "env -u FOO git config devkit.trunkMode false"),
    (True, "env -C /x git config devkit.trunkMode false"),
    (True, "sudo -u root git config devkit.trunkMode false"),
    (True, "sudo -n -g wheel git config --unset devkit.trunkMode"),
    (True, "nice -n 5 git config devkit.trunkMode false"),
    (True, "timeout -s KILL 5 git config devkit.trunkMode false"),
    (True, "timeout 5 git config devkit.trunkMode false"),
    (True, "sudo -u root env -u FOO git config devkit.trunkMode false"),
    (True, "env --unset FOO git config devkit.trunkMode false"),
    (True, "env -uFOO git config devkit.trunkMode false"),
    (True, "env -u FOO WORKTREE_TRUNK_MODE=0 git commit -qm x"),
    (True, "env -S 'git config devkit.trunkMode false'"),
    (True, "echo 'git config devkit.trunkMode false' | env -u FOO sh"),
    (False, "env -u FOO git config --get devkit.trunkMode"),
    (False, "env -C /x git config devkit.trunkMode true"),
    (False, "env -u FOO git status"),
    (False, "echo 'git config --get devkit.trunkMode' | env -u FOO sh"),
]
sw = sl._hook_module("session_worktree")
cases += [(False, f"git config devkit.trunkMode {v}") for v in sorted(sw._TRUE)]   # git's own spellings of true: the kit's list, not a copy
bad = 0
if sl._LAUNCHER_VALUE_OPTS != sl._hook_module("shell_writes").PREFIX_VALUE_OPTS:   # one launcher table in two files: they must not drift
    bad += 1
    print("✖ session_lock._LAUNCHER_VALUE_OPTS differs from hooks/shell_writes.py PREFIX_VALUE_OPTS")
for want, cmd in cases:
    got = sl.is_trunk_off(cmd)
    if got != want:
        bad += 1
        print(f"✖ {cmd!r}: want {want}, got {got}")
print(f"unit-bad={bad} of {len(cases)}")
PY
grep -q "unit-bad=0 " "$TMP/unit2" && ok "is_trunk_off: $(grep -o 'of [0-9]*' "$TMP/unit2") cases (trunk off / devkit.trunkMode not true / WORKTREE_TRUNK_MODE=0 refused; on, reads, quoted text, true values pass)" \
  || { fail "is_trunk_off cases"; grep "✖\|Error\|assert" "$TMP/unit2" | head -12; }
hook PreToolUse "$M" Bash '{"command": "agent-kit worktree trunk off"}'; r1=$?
grep -q "NGƯỜI DÙNG" "$TMP/err" && grep -q "trunk off" "$TMP/err" && r1m=said || r1m=silent
hook PreToolUse "$W" Bash '{"command": "git config devkit.trunkMode false"}'; r2=$?
hook PreToolUse "$W" Bash '{"command": "WORKTREE_TRUNK_MODE=0 agent-kit worktree finish x"}'; r3=$?
hook PreToolUse "$M" Bash '{"command": "agent-kit worktree trunk on"}'; r4=$?
hook PreToolUse "$W" Bash '{"command": "git config --get devkit.trunkMode"}'; r5=$?
[ "$r1" = 2 ] && [ "$r1m" = said ] && [ "$r2" = 2 ] && [ "$r3" = 2 ] && [ "$r4" = 0 ] && [ "$r5" = 0 ] \
  && ok "the hook: trunk off / devkit.trunkMode false / WORKTREE_TRUNK_MODE=0 refused with whose switch it is (exit 2); trunk on and a read pass" \
  || fail "user switches at the hook: off=$r1 ($r1m) config=$r2 env=$r3 on=$r4 read=$r5"
hook PreToolUse "$W" Bash '{"command": "echo $(agent-kit worktree trunk off)"}'; r6=$?
hook PreToolUse "$W" Bash '{"command": "echo '"'"'git config devkit.trunkMode false'"'"' | sh"}'; r7=$?
hook PreToolUse "$W" Bash '{"command": "echo '"'"'echo x > README.md'"'"' | sh"}' ; r8=$?
hook PreToolUse "$M" Bash '{"command": "echo '"'"'echo x > README.md'"'"' | sh"}' ; r9=$?
[ "$r6" = 2 ] && [ "$r7" = 2 ] && [ "$r8" = 0 ] && [ "$r9" = 2 ] \
  && ok "  … at the hook too: the switch inside a substitution or piped into a shell is refused; a piped write is judged where it runs (worktree 0, main 2)" \
  || fail "nested scripts at the hook: subst=$r6 pipe=$r7 worktree-write=$r8 main-write=$r9"

# 2c R4a (principal review 14/10): the `env` block of a Claude settings file is the environment of the hooks of the next session (measured with
#    `claude -p` 2.1.299: a project .claude/settings.local.json env reached a hook), and settings.local.json is git-ignored: WORKTREE_TRUNK_MODE=0 written
#    there is the user's switch by another door. Edit / Write / MultiEdit into a settings file, and Bash that writes one, are refused; value 1, reads
#    and other keys are not.
python3 - "$DEVKIT_DIR" "$M" > "$TMP/unit4" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/bin")
import session_lock as sl
m = sys.argv[2]
S = m + "/.claude/settings.local.json"
OFF, ON = '{"env": {"WORKTREE_TRUNK_MODE": "0"}}', '{"env": {"WORKTREE_TRUNK_MODE": "1"}}'
W = lambda path, content: ("Write", {"file_path": path, "content": content}, "")
B = lambda c: ("Bash", {"command": c}, c)
import os
cfg = os.path.join(os.path.dirname(m), "cfg"); os.makedirs(cfg + "/.claude", exist_ok=True)   # settings files that exist, for the value-only edits
T1, T0 = cfg + "/.claude/settings.local.json", cfg + "/.claude/settings.json"
open(T1, "w").write('{"env": {"WORKTREE_TRUNK_MODE": "1", "FOO": "bar"}, "theme": "dark"}')
open(T0, "w").write('{"env": {"WORKTREE_TRUNK_MODE": "0"}, "theme": "dark"}')
E = lambda path, old, new, **kw: ("Edit", dict({"file_path": path, "old_string": old, "new_string": new}, **kw), "")
cases = [
    (True, "Write settings.local.json with the key 0", W(S, OFF)),
    (True, "Write ~/.claude/settings.json with the key 0", W("/Users/x/.claude/settings.json", OFF)),
    (True, "Write with the key empty", W(S, '{"env": {"WORKTREE_TRUNK_MODE": ""}}')),
    (True, "Edit new_string adding the key 0", ("Edit", {"file_path": S, "old_string": '"env": {', "new_string": '"env": {"WORKTREE_TRUNK_MODE": "0", '}, "")),
    (True, "MultiEdit with one edit adding the key 0", ("MultiEdit", {"file_path": S, "edits": [{"old_string": "a", "new_string": "b"}, {"old_string": "{", "new_string": '{"env": {"WORKTREE_TRUNK_MODE": "0"},'}]}, "")),
    (True, "Bash echo > settings.local.json", B("echo '" + OFF + "' > .claude/settings.local.json")),
    (True, "Bash cat > settings.local.json <<EOF", B("cat > .claude/settings.local.json <<'EOF'\n" + OFF + "\nEOF")),
    (True, "Bash tee", B("echo '" + OFF + "' | tee ~/.claude/settings.json")),
    (True, "Bash sed -i", B("sed -i 's/\"WORKTREE_TRUNK_MODE\": \"1\"/\"WORKTREE_TRUNK_MODE\": \"0\"/' .claude/settings.json")),
    (True, "Bash jq > then mv", B("jq '.env.WORKTREE_TRUNK_MODE=\"0\"' .claude/settings.local.json > /tmp/x && mv /tmp/x .claude/settings.local.json")),
    (True, "Bash python heredoc editing the file", B("python3 - <<'EOF'\nimport json\np = '.claude/settings.local.json'\nd = json.load(open(p)); d.setdefault('env', {})['WORKTREE_TRUNK_MODE'] = '0'; json.dump(d, open(p, 'w'))\nEOF")),
    (False, "Write settings.local.json with the key 1", W(S, ON)),
    (False, "Write settings.local.json with other keys", W(S, '{"env": {"FOO": "0"}, "enableAllProjectMcpServers": true}')),
    (False, "Write a doc that names the key", W(m + "/docs/notes.md", "WORKTREE_TRUNK_MODE=0 turns trunk mode off")),
    (False, "Edit removing the key", ("Edit", {"file_path": S, "old_string": '"WORKTREE_TRUNK_MODE": "0"', "new_string": '"X": "1"'}, "")),
    (False, "Bash grep reading the key from settings", B("grep -n WORKTREE_TRUNK_MODE .claude/settings.local.json")),
    (False, "Bash cat | grep", B("cat .claude/settings.local.json | grep WORKTREE_TRUNK_MODE")),
    (False, "Bash sed -n | grep", B("sed -n 1,20p .claude/settings.json | grep WORKTREE_TRUNK_MODE")),
    (False, "a commit message that talks about it", B("git commit -qm \"docs: WORKTREE_TRUNK_MODE=0 in settings.local.json is the user's switch\"")),
    (False, "Bash writing the key with value 1", B("echo '" + ON + "' > .claude/settings.local.json")),
    (False, "Bash echo of the key to a file that is no settings file", B("echo WORKTREE_TRUNK_MODE=0 > /tmp/notes.txt")),
    # OCR2 8: a VALUE-only edit names no key, so the written text alone shows nothing; the file as it becomes is judged (Edit / MultiEdit), and
    # a `sed -i` on a settings file that turns a lone 1 into 0 (Bash: a bounded parse - two-step copies and built names stay out of reach)
    (True, "Edit turning MODE\": \"1\" into MODE\": \"0\" (the key is only in the file)", E(T1, 'MODE": "1"', 'MODE": "0"')),
    (True, "Edit turning the unique \"1\" into \"0\"", E(T1, '"1"', '"0"')),
    (True, "MultiEdit whose second edit flips the value", ("MultiEdit", {"file_path": T1, "edits": [{"old_string": "dark", "new_string": "light"}, {"old_string": '"1"', "new_string": '"0"'}]}, "")),
    (True, "Edit replace_all of \"1\" with \"0\"", E(T1, '"1"', '"0"', replace_all=True)),
    (True, "Bash sed -i 's/\"1\"/\"0\"/' on settings.local.json", B("sed -i 's/\"1\"/\"0\"/' .claude/settings.local.json")),
    (True, "Bash BSD sed -i '' with a partial key", B("sed -i '' 's/MODE\": \"1\"/MODE\": \"0\"/' .claude/settings.local.json")),
    (True, "Bash sed -i -e s/1/0/ on ~/.claude/settings.json", B("sed -i -e 's/1/0/' ~/.claude/settings.json")),
    (False, "Edit of an unrelated value in a file that has the key at 1", E(T1, '"dark"', '"light"')),
    (False, "Edit turning \"0\" into \"1\" (tightens)", E(T0, '"0"', '"1"')),
    (False, "Edit of an unrelated value in a file already at 0 (nothing left to switch)", E(T0, '"dark"', '"light"')),
    (False, "Edit whose old_string is not in the file (the tool refuses it anyway)", E(T1, 'nowhere', '"0"')),
    (False, "Edit of a settings file that does not exist", E(cfg + "/.claude/settings.other.json", '"1"', '"0"')),
    (False, "Bash sed -i turning \"0\" into \"1\"", B("sed -i 's/\"0\"/\"1\"/' .claude/settings.local.json")),
    (False, "Bash sed -i of \"v1\" into \"v2\" in a settings file", B("sed -i 's/\"v1\"/\"v2\"/' .claude/settings.local.json")),
    (False, "Bash sed -n printing a substitution of a settings file", B("sed -n 's/\"1\"/\"0\"/p' .claude/settings.local.json")),
    (False, "Bash sed -i turning 1 into 0 in a file that is no settings file", B("sed -i 's/\"1\"/\"0\"/' README.md")),
]
bad = 0
for want, label, (tool, ti, cmd) in cases:
    got = sl.trunk_env_in_settings(tool, ti, cmd)
    if got != want:
        bad += 1
        print(f"✖ {label}: want {want}, got {got}")
print(f"unit-bad={bad} of {len(cases)}")
PY
grep -q "unit-bad=0 " "$TMP/unit4" && ok "trunk_env_in_settings: $(grep -o 'of [0-9]*' "$TMP/unit4") cases (WORKTREE_TRUNK_MODE other than 1 into a settings file refused: Write / Edit / MultiEdit / Bash; value 1, reads, other keys, other files pass)" \
  || { fail "trunk_env_in_settings cases"; grep "✖\|Error\|assert" "$TMP/unit4" | head -12; }
# the value-only rule READS the settings file named in the Edit: a FIFO planted at that path (the agent writes there) must not hang the PreToolUse hook
mkdir -p "$TMP/fifo/.claude" && mkfifo "$TMP/fifo/.claude/settings.local.json"
r="$(python3 -I -c 'import json, subprocess, sys
dk, p = sys.argv[1:3]
code = "import sys; sys.path.insert(0, sys.argv[1] + \"/bin\"); import session_lock as sl; print(sl.trunk_env_in_settings(\"Edit\", {\"file_path\": sys.argv[2], \"old_string\": \"1\", \"new_string\": \"0\"}, \"\"))"
try:
    r = subprocess.run([sys.executable, "-I", "-c", code, dk, p], timeout=5, capture_output=True, text=True)
except subprocess.TimeoutExpired:
    print("HANG"); sys.exit(0)
print(r.returncode, r.stdout.strip())' "$DEVKIT_DIR" "$TMP/fifo/.claude/settings.local.json")"
[ "$r" = "0 False" ] && ok "  … a FIFO as the settings file of an Edit: no hang, nothing to judge (not refused)" || fail "FIFO settings file in an Edit: '$r'"
mkdir -p "$TMP/home/.claude"
hook PreToolUse "$W" Write "{\"file_path\": \"$TMP/home/.claude/settings.json\", \"content\": \"{\\\"env\\\": {\\\"WORKTREE_TRUNK_MODE\\\": \\\"0\\\"}}\"}"; r1=$?
grep -q "NGƯỜI DÙNG" "$TMP/err" && r1m=said || r1m=silent
hook PreToolUse "$W" Write "{\"file_path\": \"$TMP/home/.claude/settings.json\", \"content\": \"{\\\"env\\\": {\\\"FOO\\\": \\\"0\\\"}}\"}"; r2=$?
[ "$r1" = 2 ] && [ "$r1m" = said ] && [ "$r2" = 0 ] && ok "  … at the hook: a Write of the key 0 into a settings file is refused with whose switch it is; another key passes" || fail "settings env at the hook: key=$r1 ($r1m) other=$r2"

# 3 a lock on main left from before trunk mode (a live other session) changes nothing: writes refused by the trunk rule, the integrator passes
python3 -c 'import json,os,sys,time; json.dump({"session_id":"old-holder","started":time.time(),"heartbeat":time.time(),"cwd":sys.argv[1],"pid":os.getppid()}, open(sys.argv[2],"w"))' \
  "$M" "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"
hook PreToolUse "$M" Bash "{\"command\": \"agent-kit worktree finish $W\"}"; r1=$?
hook PreToolUse "$M" Bash '{"command": "touch src/new.py"}'; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 2 ] && grep -q "Trunk mode" "$TMP/err" && ok "an old holder's lock on main: the integrator still passes, a write is refused by the trunk rule" || fail "old holder: $r1 $r2"
rm -f "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"

# 4 --status (R2): main says merge-only with exit 5; a worktree is judged as before
(cd / && python3 -I "$SL" --status "$M" >"$TMP/st" 2>&1); s1=$?
(cd / && python3 -I "$SL" --status "$W2" >/dev/null 2>&1); s2=$?
[ "$s1" = 5 ] && grep -q "trunk mode" "$TMP/st" && [ "$s2" = 0 ] && ok "--status: main exit 5 (merge-only, says how), a worktree exit 0" || fail "--status: main $s1, worktree $s2"

# 4b /clear or /resume: SessionStart under a new id, still in the worktree - the dead id's record follows the session (no gate checks main)
RD="$M/.claude/audit-gate/session_worktree"; mkdir -p "$RD" && printf '%s\npid %s\n' "$W" "$$" > "$RD/sess-old"   # written under this very process (the hook's parent, $$): /clear keeps it
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-new","cwd":sys.argv[1]}))' "$W" | python3 -I "$SL" >/dev/null 2>&1
[ "$(head -1 "$RD/sess-new" 2>/dev/null)" = "$W" ] && [ "$(sed -n 2p "$RD/sess-new" 2>/dev/null)" = "pid $$" ] && [ ! -e "$RD/sess-old" ] && ok "SessionStart after /clear in the worktree: the record moves to the new session id" \
  || fail "reown at SessionStart: $(ls "$RD")"
python3 -I "$SL" --register --session sess-live --pid $$ "$M" >/dev/null 2>&1; printf '%s\n' "$W2" > "$RD/sess-live"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-x","cwd":sys.argv[1]}))' "$W2" | python3 -I "$SL" >/dev/null 2>&1
[ -e "$RD/sess-live" ] && [ ! -e "$RD/sess-x" ] && ok "  … a LIVE session's record is never taken over" || fail "a live session's record moved: $(ls "$RD")"
sleep 60 & PEER=$!   # a live process that is not this session's: a peer whose registry entry is missing (failed registration) but whose record's pid answers
printf '%s\npid %s\n' "$W2" "$PEER" > "$RD/sess-peer"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-y","cwd":sys.argv[1]}))' "$W2" | python3 -I "$SL" >/dev/null 2>&1
[ -e "$RD/sess-peer" ] && [ ! -e "$RD/sess-y" ] && ok "  … nor the record of a peer with no registry entry whose record's pid answers" || fail "an unregistered live peer's record moved: $(ls "$RD")"
kill "$PEER" 2>/dev/null; wait "$PEER" 2>/dev/null
printf '%s\npid %s\n' "$W2" 2147483646 > "$RD/sess-peer"
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","session_id":"sess-y","cwd":sys.argv[1]}))' "$W2" | python3 -I "$SL" >/dev/null 2>&1
[ -e "$RD/sess-y" ] && [ ! -e "$RD/sess-peer" ] && [ "$(sed -n 2p "$RD/sess-y")" = "pid 2147483646" ] && ok "  … a record whose process is gone is taken (/resume in a new process), its pid carried over" || fail "a dead record not re-owned: $(ls "$RD")"

# 4c owner_gone: the one test for adopting a worktree / taking a record - proof of death or nothing (OCR 13, R1 review 14/10)
python3 - "$DEVKIT_DIR" "$M" "$W" > "$TMP/unit3" 2>&1 <<'PY'
import json, os, sys, time
dk, m, w = sys.argv[1:4]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
sw = sl._hook_module("session_worktree")
DEAD = 2147483646
def case(label, want, rec_pid=None, reg_pid="none", hb_age=0, rec_age=0, sid="oc"):
    for p in (os.path.join(m, sw.RECORD_DIR, sid), os.path.join(sl.sessions_dir(m)[0], sid + ".json")):
        if os.path.lexists(p): os.unlink(p)
    assert sw.write_record(m, sid, w, pid=rec_pid)
    if rec_age:
        t = time.time() - rec_age; os.utime(os.path.join(m, sw.RECORD_DIR, sid), (t, t))
    if reg_pid != "none":
        sl.register_session(m, sid, pid=reg_pid)
        f = os.path.join(sl.sessions_dir(m)[0], sid + ".json"); d = json.load(open(f)); d["heartbeat"] = time.time() - hb_age
        if reg_pid is None: d.pop("pid", None)
        json.dump(d, open(f, "w"))
    got = sl.owner_gone(m, sid, sw, m)
    print(("✔ " if got[0] == want else "✖ ") + f"{label}: want dead={want}, got {got}")
case("a pid on the record that answers", False, rec_pid=os.getpid())
case("a pid on the record that is gone, no registry entry (an ended session)", True, rec_pid=DEAD)
case("registry pid alive, heartbeat 40 min old (idle at the prompt)", False, reg_pid=os.getpid(), hb_age=2400)
case("registry pid gone", True, reg_pid=DEAD)
case("record pid gone but the registry pid answers", False, rec_pid=DEAD, reg_pid=os.getpid())
case("no pid anywhere, a fresh record", False)
case("no pid anywhere, a 25 h old record", True, rec_age=25 * 3600)
case("registry entry with no pid and a fresh heartbeat (the old 180 s rule would call it alive)", False, reg_pid=None)
case("registry entry with no pid, a stale heartbeat, a fresh record: the heartbeat decides nothing", False, reg_pid=None, hb_age=3600)
case("a garbage registry pid (a bool) counts as none", False, reg_pid=True)
case("a garbage registry pid (1) counts as none", False, reg_pid=1)
case("a garbage registry pid (0) counts as none", False, reg_pid=0)
for label, bad in (("a path-like session id", "../x"), ("an empty session id", "")):   # (OCR2 23) a real case: unknown reads alive, never dead
    got = sl.owner_gone(m, bad, sw, m)
    print(("✔ " if got == (False, "unknown") else "✖ ") + f"owner_gone for {label}: want (False, 'unknown'), got {got}")
PY
! grep -q "^✖" "$TMP/unit3" && [ "$(grep -c '^✔' "$TMP/unit3")" = 14 ] && ok "owner_gone: dead only on a dead pid or a 25 h old pid-less record; every unknown reads alive" \
  || { fail "owner_gone cases"; grep "✖\|Error\|assert" "$TMP/unit3" | head -8; }

# 5 R7 and trunk mode off: the old rules, unchanged (main's lock taken by the first write)
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}" WORKTREE_TRUNK_MODE=0; rc=$?
[ "$rc" = 0 ] && lockof "$M" && ok "WORKTREE_TRUNK_MODE=0: a write in main is allowed and takes main's lock (as before)" || fail "R7 switch (rc $rc)"
rm -f "$(git -C "$M" rev-parse --absolute-git-dir)/devkit-session.lock"; git -C "$M" config devkit.trunkMode false
hook PreToolUse "$M" Edit "{\"file_path\": \"$M/src/a.py\"}"; rc=$?
(cd / && python3 -I "$SL" --status --session sess-a "$M" >/dev/null 2>&1); s1=$?; (cd / && python3 -I "$SL" --status "$M" >/dev/null 2>&1); s2=$?
[ "$rc" = 0 ] && lockof "$M" && [ "$s1" = 0 ] && [ "$s2" = 3 ] && ok "trunk mode off: the old lock - --status 0 for its holder, 3 for anyone else" || fail "trunk mode off (rc $rc, status holder $s1 / other $s2)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_session_lock_trunk: PASS"; exit 0; } || { echo "test_session_lock_trunk: FAIL ($FAILS)"; exit 1; }
