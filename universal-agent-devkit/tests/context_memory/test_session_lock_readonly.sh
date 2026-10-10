#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, GeelyEx2) for bin/session_lock.py: a second live session was blocked from READING
# while another session held the checkout. `git stash list` / `git stash show` matched GIT_WRITE (every `stash` did), and any segment that
# merely NAMED post-fix-gate (`grep -c post-fix-gate AGENTS.md`, `cat bin/post-fix-gate.py`, `git log -- bin/post-fix-gate.py`) matched GATE
# as if it ran the gate. Both fail closed, so nothing was lost, but a held checkout could not even be inspected. Running the gate and the
# real stash writes still collide, also behind a wrapper, an env prefix, `cd … &&` or a pipe.
# Only the judge runs (bash_collides on a temp repo): never the command.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SL="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
REPO="$TMP/repo"; mkdir -p "$REPO/src" && git -C "$REPO" init -q . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t \
  && git -C "$REPO" config commit.gpgsign false && echo x > "$REPO/src/A.kt" && git -C "$REPO" add -A && git -C "$REPO" commit -qm init

python3 -I - "$SL" "$REPO" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("session_lock", sys.argv[1])
sl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sl)
repo = sys.argv[2]
G = ".agents/devkit/bin/post-fix-gate.py"
COLLIDES = [   # these write (or run the gate) in the locked checkout
    "git stash", "git stash push -m x", "git stash pop", "git stash drop", "git commit -m x",
    f"python3 {G} --run-tests --full --brief", f"python3 -I {G}", "postfix-gate --run-tests", "./bin/post-fix-gate.py",
    f"CLAUDE_PROJECT_DIR=. python3 {G}", f'bash -c "python3 {G} --full"', f"cd src && postfix-gate --run-tests",
    f"time python3 {G} --run-tests 2>&1 | tail -5", f'echo start; python3 {G}', "ls && postfix-gate",
    # review 2026-10-10: the first fix let these through (a `list` / `show` on the NEXT line is not the stash verb; git is not a reader of
    # the gate through bisect / submodule foreach / an alias; a quote in an env prefix must not hide the real command word)
    "git stash\nlist=$(ls)", "git stash\nshow -p", "git stash\r\nlist",
    f"git bisect run python3 {G}", f"git submodule foreach 'python3 {G}'", f"git -c alias.x='!python3 {G}' x", f'FOO="a grep" python3 {G}',
    f"git -C . log; python3 {G}",
]
FREE = [       # these only read: the checkout may be inspected while another session holds it
    "git stash list", "git stash show -p", "git stash list | head -3",
    "grep -c post-fix-gate AGENTS.md", f"grep -n GATE {G}", f"cat {G}", f"head -20 {G}", f"wc -l {G}", f"ls -l {G}",
    f"git log --oneline -- {G}", f"git diff HEAD -- {G}", f"diff {G} /tmp/x", "rg post-fix-gate .agents", "cat AGENTS.md | grep postfix-gate",
    'grep -n "post-fix-gate" AGENTS.md', f"git blame {G}", f"git show HEAD:{G}", f"git grep -n gate -- {G}",
]
bad = 0
for cmd in COLLIDES:
    hits, _ = sl.bash_collides(cmd, repo, repo, "s1")
    print(("✔" if hits else "✖") + f" collides: {cmd}")
    bad += not hits
for cmd in FREE:
    hits, _ = sl.bash_collides(cmd, repo, repo, "s1")
    print(("✔" if not hits else "✖") + f" free: {cmd}")
    bad += bool(hits)
sys.exit(1 if bad else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_session_lock_readonly: all passed" || { echo "❌ test_session_lock_readonly: failed"; exit 1; }
