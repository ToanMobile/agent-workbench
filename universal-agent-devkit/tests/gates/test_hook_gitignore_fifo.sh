#!/usr/bin/env bash
# Every hook writes <project>/.claude/audit-gate/.gitignore when it is missing: `[ -f X ] || printf '*\n' > X`. A FIFO planted
# there is not a regular file, so the redirect opened it and blocked until the hook was killed at its timeout - and a Stop hook
# killed by its timeout lets the Stop through (issues-bugs.md A.4, FIFO class; the subagent fix of post-fix-gate/proof_gate/push_gate,
# 14/10, named these 15 hooks as left). Now `[ -e X ]`: anything already there is kept as it is.
# Dynamic: each hook runs with a FIFO at that path and must end within 10 s. Static: no hook keeps the `-f` form.
# Each hook runs in a process group of its own, killed whole on the timeout; a canary hook whose grandchild blocks on a FIFO checks
# that first (OpenCodeReview 14/10: subprocess.run(timeout=) killed only the bash child and left the grandchild blocked for ever),
# and one whose detached child holds its pipes (a group of zombies only: killpg gets EPERM on macOS, which must not crash the run).
# The fixture ignores .claude/audit-gate/ in the project's .gitignore, as all 5 repos do (checked 14/10): git itself opens every
# .gitignore of a folder it walks, so a FIFO .gitignore in a folder git DOES walk hangs `git status` / `ls-files` - git's limit, not a
# hook's write (the hooks bound their git calls; ponytail: guard it if a planted FIFO is ever seen in a tracked folder).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$DEVKIT_DIR" "$TMP" <<'PY'
import contextlib, fcntl, glob, json, os, re, signal, subprocess, sys, time

dk, tmp = sys.argv[1:3]
fails = 0


def ends(argv, stdin, env, cwd, limit=10):
    """True when the hook ended within `limit` s; False = HUNG. The hook runs in a process group of its own: on the timeout the
    whole group is killed and its pipes are never read again (subprocess.run(timeout=) killed only the bash child, so a grandchild
    blocked on a FIFO stayed blocked for ever, holding the pipes - and an interpreter that reads them after the kill hangs on it)."""
    with subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, cwd=cwd,
                          start_new_session=True) as proc:
        try:
            proc.communicate(stdin, timeout=limit)
            return True
        except subprocess.TimeoutExpired:
            # the group ended by itself right at the limit, or holds only zombies (macOS: EPERM); a live member is always killed
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            return False


# The harness itself first (OpenCodeReview 14/10, issues-bugs.md A.4 (d)): a hook whose GRANDCHILD blocks on a FIFO must be reported
# HUNG, and nothing of it may outlive the case. The grandchild holds a lock while it lives (no pid to reuse): free = it is gone.
c = os.path.join(tmp, "canary")
os.makedirs(c)
lock, ready, fifo = (os.path.join(c, n) for n in ("held.lock", "ready", "fifo"))
os.mkfifo(fifo)
with open(os.path.join(c, "grandchild.py"), "w") as fh:
    fh.write("import fcntl, os, sys\nlock, ready, fifo = sys.argv[1:4]\nheld = open(lock, 'a')\nfcntl.flock(held, fcntl.LOCK_EX)\n"
             "with open(ready + '.tmp', 'w') as r:\n    r.write(str(os.getpid()))\nos.rename(ready + '.tmp', ready)\n"
             "open(fifo, 'w')   # no reader: blocks for ever, as a hook's write-open of a planted FIFO\n")
with open(os.path.join(c, "hook.sh"), "w") as fh:
    fh.write('python3 "$@"\necho unreachable\n')
hung = not ends(["bash", os.path.join(c, "hook.sh"), os.path.join(c, "grandchild.py"), lock, ready, fifo], b"",
                {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, c, limit=2)
deadline = time.monotonic() + 10
while not os.path.exists(ready) and time.monotonic() < deadline:   # a leaked grandchild that was still starting shows up late
    time.sleep(0.02)
armed = os.path.exists(ready)   # the grandchild held its lock (alive or killed since): there is something to judge
gone = False
if armed:
    deadline = time.monotonic() + 10   # a wait of its own: the lock is freed once the killed grandchild is gone
    with open(lock, "a") as fh:
        while not gone:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                gone = True
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    break
                time.sleep(0.02)
# never ✔ for a check that tested nothing (OpenCodeReview 14/10), never ✖ because the machine is slow (W2b)
if not hung:
    print("✖ harness: the canary hook (its grandchild blocks on a FIFO) was not reported HUNG"); fails += 1
elif not armed:
    print("⚠ harness: the canary's grandchild did not start within the limit (machine busy): group kill not judged this run")
elif gone:
    print("✔ harness: a hook whose grandchild blocks on a FIFO is reported HUNG, and its whole process group is gone")
else:
    print("✖ harness: the canary's grandchild outlived the limit (left blocked for ever, holding the hook's pipes)"); fails += 1
    os.kill(int(open(ready).read()), signal.SIGKILL)   # the leaked canary is this test's own: do not leave it behind
# ... and a hook that has ended while a DETACHED child (a session of its own) still holds its pipes: at the limit the group holds
# only the hook's zombie, and macOS refuses killpg on such a group with EPERM (OpenCodeReview 14/10) - HUNG, never a crash.
ready2 = os.path.join(c, "detached.ready")
with open(os.path.join(c, "detached.py"), "w") as fh:
    fh.write("import os, sys, time\nos.setsid()\nwith open(sys.argv[1] + '.tmp', 'w') as r:\n    r.write(str(os.getpid()))\n"
             "os.rename(sys.argv[1] + '.tmp', sys.argv[1])\ntime.sleep(30)\n")
with open(os.path.join(c, "detach.sh"), "w") as fh:
    fh.write('python3 "$1" "$2" &\n')
crash = None
try:
    hung2 = not ends(["bash", os.path.join(c, "detach.sh"), os.path.join(c, "detached.py"), ready2], b"",
                     {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, c, limit=2)
except OSError as e:
    hung2, crash = False, e
deadline = time.monotonic() + 5
while not os.path.exists(ready2) and time.monotonic() < deadline:   # it detached before the limit, so it lives on
    time.sleep(0.02)
armed2 = os.path.exists(ready2)
if armed2:
    with contextlib.suppress(ProcessLookupError):
        os.kill(int(open(ready2).read()), signal.SIGKILL)   # the detached canary is this test's own
if crash is not None:
    print(f"✖ harness: killing the group of a hook whose detached child holds its pipes raised {crash!r}"); fails += 1
elif not armed2:
    print("⚠ harness: the canary's detached child did not start within the limit (machine busy): EPERM path not judged this run")
elif hung2:
    print("✔ harness: a hook whose detached child holds its pipes past the limit: HUNG, no crash")
else:
    print("✖ harness: a hook whose detached child holds its pipes past the limit was not reported HUNG"); fails += 1

hooks = sorted(h for h in glob.glob(os.path.join(dk, "hooks", "*.sh"))
               if '/.gitignore" ] || printf' in open(h, encoding="utf-8", errors="replace").read())
if len(hooks) < 15:
    print(f"✖ only {len(hooks)} hooks write .gitignore (expected 15+): the scan has gone blind"); fails += 1
for h in hooks:
    name = os.path.basename(h)
    for n, line in enumerate(open(h, encoding="utf-8", errors="replace"), 1):
        if re.search(r'\[ -f "\$\{LOG_DIR\}/\.gitignore" \] \|\| printf', line):
            print(f"✖ {name}:{n}: still `[ -f …/.gitignore ] || printf >` (a FIFO there blocks the redirect)"); fails += 1
    p = os.path.join(tmp, name.replace(".sh", ""))
    os.makedirs(os.path.join(p, ".claude", "audit-gate"))
    subprocess.run(["git", "init", "-q", p], check=True)
    with open(os.path.join(p, ".gitignore"), "w") as fh:
        fh.write(".claude/audit-gate/\n")
    os.mkfifo(os.path.join(p, ".claude", "audit-gate", ".gitignore"))
    # ... and at the hook's own log and the test-run lock (principal-code-reviewer 14/10: review_gate.log, claim_check.log,
    # test_evidence_gate.log, security_gate.log as FIFOs still hung the Stop hooks; testsourceset's `exec 9>>test_run.lock` too)
    for extra in (name.replace(".sh", ".log"), "test_run.lock"):
        os.mkfifo(os.path.join(p, ".claude", "audit-gate", extra))
    payload = {"session_id": "s", "cwd": p, "hook_event_name": "Stop", "transcript_path": "/dev/null",
               "tool_name": "Bash", "tool_input": {"command": "ls"}, "prompt": "hi"}
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["CLAUDE_PROJECT_DIR"] = p
    if ends(["bash", h], json.dumps(payload).encode(), env, p):
        print(f"✔ {name}: ends with FIFOs at .claude/audit-gate/ (.gitignore, its log, test_run.lock)")
    else:
        print(f"✖ {name}: HUNG on a FIFO at .claude/audit-gate/ (killed after 10 s)"); fails += 1
        continue
    # a hook that wrote anything there must leave a REGULAR .gitignore in the same run: the sweep runs BEFORE the .gitignore line
    # (OpenCodeReview 14/10: after it, the FIFO was dropped and nothing ignored the files written next). A hook that left before
    # that line (a disabled branch, a fast path) wrote nothing and opened nothing.
    ag = os.path.join(p, ".claude", "audit-gate")
    wrote = [f for f in os.listdir(ag) if f != ".gitignore" and os.path.isfile(os.path.join(ag, f))]
    if wrote and not os.path.isfile(os.path.join(ag, ".gitignore")):
        print(f"✖ {name}: wrote {wrote[:3]} but left no regular .gitignore in the same run"); fails += 1

# worktree_guard's WORKTREE_GUARD=0 branch appends to its log before any sweep (OpenCodeReview 14/10)
p = os.path.join(tmp, "wg_off")
os.makedirs(os.path.join(p, ".claude", "audit-gate"))
subprocess.run(["git", "init", "-q", p], check=True)
os.mkfifo(os.path.join(p, ".claude", "audit-gate", "worktree_guard.log"))
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
env.update(CLAUDE_PROJECT_DIR=p, WORKTREE_GUARD="0")
if ends(["bash", os.path.join(dk, "hooks", "worktree_guard.sh")], b'{"tool_name":"Bash"}', env, p):
    print("✔ worktree_guard.sh WORKTREE_GUARD=0: ends with a FIFO at its log")
else:
    print("✖ worktree_guard.sh WORKTREE_GUARD=0: HUNG on a FIFO at its log"); fails += 1
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && echo "hook .gitignore FIFO: all checks passed" || { echo "hook .gitignore FIFO: FAILED"; exit 1; }
