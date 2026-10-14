#!/usr/bin/env bash
# bin/session_lock.py bash_collides (issues-bugs.md A.1 #3, 13/10): it judged only git writes, gate runs and `>` redirects, so a
# session that does NOT hold the checkout wrote into it with cp / mv / rm / tee / sed -i / touch (11:03 that day). It now also asks
# hooks/shell_writes.py (the scanner hooks/worktree_guard.sh used inline, moved out so both share ONE) for file writes.
# Two false blocks of read-only commands, met by session d91dffdd on 14/10, are fixed with it:
#  - GATE matched the DIRECTORY .git/postfix-gate/ (`python3 -c "…open('.git/postfix-gate/full_pass.json')…"` was a "gate run");
#  - a line with no write in any segment was judged again as a whole, where its first word (`cd`) is no reader: "gate run".
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TOP="$TMP/held"; OTHER="$TMP/other"
for r in "$TOP" "$OTHER"; do mkdir -p "$r" && git -C "$r" init -q && echo x > "$r/AGENTS.md"; done
TOP="$(cd "$TOP" && pwd -P)"; OTHER="$(cd "$OTHER" && pwd -P)"

python3 - "$DEVKIT_DIR" "$TOP" "$OTHER" > "$TMP/out" 2>&1 <<'PY'
import sys
dk, top, other = sys.argv[1:4]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
cases = [   # (want hits_top, label, command); every command runs with cwd = the held checkout
    (True, "cp into the held checkout", f"cp /tmp/a {top}/x.txt"),
    (True, "mv in it", "mv a.txt b.txt"),
    (True, "rm in it", "rm -f foo.py"),
    (True, "tee in it", "echo hi | tee notes.md"),
    (True, "sed -i in it", "sed -i '' 's/a/b/' AGENTS.md"),
    (True, "touch in it", "touch newfile"),
    (True, "mkdir in it", "mkdir -p build/x"),
    (True, "a bash -c that copies in", "bash -c 'cp /tmp/a b.txt'"),
    (True, "a cp after cd into it", f"cd {other} && cd {top} && cp /tmp/a c.txt"),
    (True, "a git write (as before)", "git commit -qm x"),
    (True, "a redirect (as before)", "echo x > y.txt"),
    (True, "the gate (as before)", "python3 .agents/devkit/bin/post-fix-gate.py --run-tests"),
    (False, "cp between two outside paths", "cp /tmp/a /tmp/b"),
    (False, "cd into another checkout, then cp", f"cd {other} && cp /tmp/a x.txt"),
    (False, "rm in another checkout by absolute path", f"rm -f {other}/x.txt"),
    (False, "a read", "grep -rn foo . | head -3"),
    (False, "python -c reading .git/postfix-gate/", f"python3 -c \"import json; print(json.load(open('{top}/.git/postfix-gate/full_pass.json')))\""),
    (False, "ls / tail of .git/postfix-gate/", f"ls -la {top}/.git/postfix-gate/ | head; tail -n 3 {top}/.git/postfix-gate/runs.jsonl"),
    (False, "cd elsewhere, then grep naming the gate", f"cd {other} && grep -n 'x' AGENTS.md | head -2; grep -rn 'y' bin/post-fix-gate.py | head"),
    (False, "a heredoc body is data", "cat <<'EOF'\ncp /tmp/a b.txt\nrm -rf x\nEOF"),
    # an option's value or a mode is no target (principal-code-reviewer 14/10: each of these made a session working in its own
    # worktree look like a writer of the held checkout - blocked, or taking a free lock)
    (False, "chmod's mode", f"chmod +x {other}/run.sh"),
    (False, "the empty suffix of BSD sed -i ''", f"sed -i '' 's/a/b/' {other}/f.txt"),
    (False, "mkdir -m MODE", f"mkdir -m 755 {other}/d"),
    (False, "touch -t STAMP", "touch -t 202601010000 /tmp/x"),
    (False, "truncate -s SIZE", "truncate -s 0 /tmp/x"),
    (False, "touch -r REF reads REF", f"touch -r {top}/AGENTS.md /tmp/x"),
    (False, "perl -M is not -i", "perl -MList::Util=sum -e 'print sum(1, 2)'"),
    (False, "cp -t DIR: the sources are read", f"cp -t {other} src.txt"),
    (False, "ln -s TARGET with one operand links in the cwd", f"cd {other} && ln -s {top}/node_modules"),
    (True, "cp -t into it", f"cp -t {top} /tmp/a"),
    (True, "cp --target-directory= into it", f"cp --target-directory={top} /tmp/a"),
    (True, "ln -s TARGET in it (the link lands in the cwd)", "ln -s /tmp/a"),
    (True, "env -i rm in it", "env -i rm x.txt"),
    (True, "nice -n 5 rm in it", "nice -n 5 rm x.txt"),
    (True, "timeout 5 rm in it", "timeout 5 rm x.txt"),
    (True, "sudo -n rm in it", "sudo -n rm x.txt"),
    # OpenCodeReview 14/10: a chmod mode may start with `-`; env -C / sudo -D move the directory the command runs in
    (True, "chmod -w in it (the mode starts with -)", "chmod -w AGENTS.md"),
    (False, "chmod -- 755 outside", f"chmod -- 755 {other}/x"),
    (False, "chmod --reference REF: REF is read", f"chmod --reference {top}/AGENTS.md {other}/x"),
    (True, "env -C into it, then rm", f"cd {other} && env -C {top} rm x.txt"),
    (True, "env --chdir= into it, then rm", f"cd {other} && env --chdir={top} rm x.txt"),
    (True, "sudo -D into it, then rm", f"cd {other} && sudo -D {top} rm x.txt"),
    (False, "env -C out of it, then rm", f"env -C {other} rm x.txt"),
    # OpenCodeReview 14/10: env -S / --split-string runs its value as a command line (the words after it appended)
    (True, "env -S '<rm>' in it", "env -S 'rm x.txt'"),
    (True, "env -iS 'rm -f' x.txt in it (cluster, operand after)", "env -iS 'rm -f' x.txt"),
    (True, "env --split-string=<rm> in it", "env --split-string='rm -f x.txt'"),
    (False, "env -S '<rm>' of an outside path", f"env -S 'rm {other}/x.txt'"),
]
fails = 0
for want, label, cmd in cases:
    got = sl.bash_collides(cmd, top, top, "me")[0]
    print(("✔ " if got == want else "✖ ") + f"{label}: hits_top={got} (want {want})")
    fails += got != want
try:   # a NUL in a target: no crash of the hook (it would exit 1 and the call would go through)
    sl.bash_collides("rm /tmp/a\x00b", top, top, "me")
    print("✔ a NUL in a target: no exception")
except Exception as e:
    print(f"✖ a NUL in a target raised {e!r}")
    fails += 1
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$TMP/out"
[ "$rc" = 0 ] && ok "bash_collides: every case as expected" || fail "bash_collides: $(grep -c '^✖' "$TMP/out") case(s) wrong"
# (hooks/worktree_guard.sh, which now imports the same scanner: tests/gates/test_worktree_guard_scan.sh)

if [ "$FAILS" -ne 0 ]; then echo "session_lock file writes: $FAILS FAILED"; exit 1; fi
echo "session_lock file writes: all checks passed"
