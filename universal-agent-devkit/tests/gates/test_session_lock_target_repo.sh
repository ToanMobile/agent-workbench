#!/usr/bin/env bash
# bin/session_lock.py blocks a Bash call or an Edit/Write while ANOTHER live session holds the checkout. Until 2026-10-08 it
# decided from the command TEXT alone, so a session holding nothing in repo A was blocked for work in a different repo B:
#   - `cd /clone && git commit`, `git -C /clone cherry-pick`, `CLAUDE_PROJECT_DIR=/clone post-fix-gate ...` (target is repo B)
#   - read-only plumbing named like a write verb: `git merge-base`, `git merge-tree`, `git commit-tree` (`merge\b` matches before `-`)
#   - the Edit/Write tools for ANY path, even a scratch file or a file in repo B
# That cost the Office 1.4.6 release about three hours (the user had to run `!` commands by hand). The rule now is by TARGET repo:
# a write collides only when it can land in the locked checkout (or the target cannot be resolved: fail closed).
# Second part: the USER's approval (`agent-kit allow-shared`, a flag file in the git dir) reaches the running hook; an agent's own
# Bash call that tries to switch it on or off is blocked, whichever session it comes from.
# Table: command / tool call -> expected exit code of the hook (0 allow, 2 block), against a lock held by another LIVE session.
#   SLT_KIT=<devkit dir>   run the same table against another copy of the kit (the unpatched one: RED).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SLT_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time

KIT = os.path.realpath(sys.argv[1])
SCRIPT = os.path.join(KIT, "bin", "session_lock.py")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="slt_"))


def sh(*a, cwd=None):
    r = subprocess.run(list(a), cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"setup failed: {a}: {r.stderr[:200]}")
    return r.stdout


def repo(name):
    d = os.path.join(tmp, name)
    os.makedirs(d)
    sh("git", "init", "-q", d)
    sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
    return d


A = repo("locked")      # the checkout another live session holds
B = repo("other")       # a different repo (a clone, a worktree) the tested session writes to
os.makedirs(os.path.join(tmp, "scratch"))
LOCK = os.path.join(A, ".git", "devkit-session.lock")
now = time.time()
with open(LOCK, "w", encoding="utf-8") as f:   # another session, alive (this process), fresh heartbeat
    json.dump({"session_id": "holder", "started": now, "heartbeat": now, "cwd": A, "pid": os.getpid()}, f)


def hook(payload, env_extra=None, sid="me", cwd=None):
    env = {k: v for k, v in os.environ.items() if k != "DEVKIT_ALLOW_SHARED_CHECKOUT"}
    env.update(env_extra or {})
    p = dict(payload, hook_event_name="PreToolUse", session_id=sid, cwd=cwd or A)
    try:
        return subprocess.run([sys.executable, "-I", SCRIPT], input=json.dumps(p), capture_output=True, text=True, env=env, timeout=10).returncode
    except subprocess.TimeoutExpired:
        return 124   # the hook hung


def bash(cmd, **kw):
    return hook({"tool_name": "Bash", "tool_input": {"command": cmd}}, **kw)


def tool(name, path, key="file_path"):
    return hook({"tool_name": name, "tool_input": {key: path}})


os.makedirs(os.path.join(A, "sub"))
os.symlink(A, os.path.join(tmp, "alias_of_locked"))


GATE = KIT + "/bin/post-fix-gate.py"
cases = [
    # (label, got-callable, expected)
    ("git commit in the locked checkout (no target)", lambda: bash("git commit -m x"), 2),
    ("git -C <locked> commit", lambda: bash(f"git -C {A} commit -m x"), 2),
    ("cd <locked> && git add", lambda: bash(f"cd {A} && git add -A"), 2),
    ("git merge feature (verb, no target)", lambda: bash("git merge feature"), 2),
    ("git push origin main (no target)", lambda: bash("git push origin main"), 2),
    ("post-fix-gate in the locked checkout", lambda: bash(f"python3 {GATE} --run-tests --full"), 2),
    ("write to B, then a write to A in one command", lambda: bash(f"git -C {B} commit -m y && git commit -m z"), 2),
    ("cd B && commit && cd A && add", lambda: bash(f"cd {B} && git commit -m x && cd {A} && git add ."), 2),
    ("unresolvable target ($VAR) fails closed", lambda: bash("cd $SOMEWHERE && git commit -m x"), 2),
    ("git -C B cherry-pick", lambda: bash(f"git -C {B} cherry-pick abc"), 0),
    ("cd B && git commit", lambda: bash(f"cd {B} && git commit -m x"), 0),
    ("cd B; git switch main && git merge --ff-only", lambda: bash(f"cd {B}; git switch main && git merge --ff-only abc"), 0),
    ("git -C B push", lambda: bash(f"git -C {B} push origin main"), 0),
    ("post-fix-gate with CLAUDE_PROJECT_DIR=B", lambda: bash(f"CLAUDE_PROJECT_DIR={B} python3 {GATE} --run-tests --full"), 0),
    ("cd B && post-fix-gate", lambda: bash(f"cd {B} && python3 {GATE} --run-tests"), 0),
    ("git merge-base --is-ancestor (read-only)", lambda: bash("git merge-base --is-ancestor a b"), 0),
    ("git merge-tree --write-tree (read-only)", lambda: bash("git merge-tree --write-tree a b"), 0),
    ("git commit-tree (writes an object, no ref)", lambda: bash("git commit-tree T -p a -m m"), 0),
    ("git status / log (reads)", lambda: bash("git status && git log -3"), 0),
    ("Write a file in B", lambda: tool("Write", os.path.join(B, "x.txt")), 0),
    ("Write a scratch file", lambda: tool("Write", os.path.join(tmp, "scratch", "n.txt")), 0),
    ("Write a file in the locked checkout", lambda: tool("Write", os.path.join(A, "x.txt")), 2),
    ("Edit a relative path (= under the locked cwd)", lambda: tool("Edit", "x.txt"), 2),
    ("Edit with no path at all fails closed", lambda: hook({"tool_name": "Edit", "tool_input": {}}), 2),
    ("escape hatch still works", lambda: bash("git commit -m x", env_extra={"DEVKIT_ALLOW_SHARED_CHECKOUT": "1"}), 0),
    # a `cd` only moves the shell for what follows it when it runs in the same shell
    ("cd B | git commit: the cd runs in a pipe subshell", lambda: bash(f"cd {B} | git commit -m x"), 2),
    ("cd B & git commit: the cd runs in a background job", lambda: bash(f"cd {B} & git commit -m x"), 2),
    ("cd B || git commit: the cd may have failed", lambda: bash(f"cd {B} || git commit -m x"), 2),
    ("(cd B && git commit): a subshell fails closed", lambda: bash(f"(cd {B} && git commit -m x)"), 2),
    ("cd B <newline> git commit", lambda: bash(f"cd {B}\ngit commit -m x"), 0),
    ("cd ../other (relative to the locked cwd) && git commit", lambda: bash("cd ../other && git commit -m x"), 0),
    ("git -C ../other commit (relative -C)", lambda: bash("git -C ../other commit -m x"), 0),
    ("cd B && git commit && cd - && git add: `cd -` is unresolvable", lambda: bash(f"cd {B} && git commit -m x && cd - && git add ."), 2),
    ("cd <subdir of the locked checkout> && git add", lambda: bash(f"cd {A}/sub && git add ."), 2),
    ("cd <symlink to the locked checkout> && git add", lambda: bash(f"cd {tmp}/alias_of_locked && git add ."), 2),
    ("git -C \"<B>\" commit (quoted -C)", lambda: bash(f'git -C "{B}" commit -m x'), 0),
    ("git -C ~/nowhere commit: ~ is unresolvable", lambda: bash("git -C ~/nowhere commit -m x"), 2),
    ("redirect into the locked checkout stays blocked", lambda: bash("echo hi > x.txt"), 2),
    ("MultiEdit a file in B", lambda: tool("MultiEdit", os.path.join(B, "x.txt")), 0),
    ("MultiEdit a file in the locked checkout", lambda: tool("MultiEdit", os.path.join(A, "x.txt")), 2),
    ("NotebookEdit a scratch notebook (notebook_path)", lambda: tool("NotebookEdit", os.path.join(tmp, "scratch", "n.ipynb"), "notebook_path"), 0),
    ("NotebookEdit a notebook in the locked checkout", lambda: tool("NotebookEdit", os.path.join(A, "n.ipynb"), "notebook_path"), 2),
    ("Write through a symlink into the locked checkout", lambda: tool("Write", os.path.join(tmp, "alias_of_locked", "y.txt")), 2),
    # review 2026-10-08 #7: once a `cd` into another repo has been seen, a directory change the walk cannot follow must fail CLOSED
    ("cd B && (cd A && git commit): subshell", lambda: bash(f"cd {B} && (cd {A} && git commit -m x)"), 2),
    ("cd B && bash -c 'cd A && git commit'", lambda: bash(f"cd {B} && bash -c 'cd {A} && git commit -m x'"), 2),
    ("cd B && x=$(cd A && git commit)", lambda: bash(f"cd {B} && x=$(cd {A} && git commit -m x)"), 2),
    ("cd B && eval 'cd A'; git commit", lambda: bash(f"cd {B} && eval 'cd {A}'; git commit -m x"), 2),
    ("cd B && cd A 2>/dev/null && git commit", lambda: bash(f"cd {B} && cd {A} 2>/dev/null && git commit -m x"), 2),
    ("cd B && cd A || exit 1; git commit", lambda: bash(f"cd {B} && cd {A} || exit 1; git commit -m x"), 2),
    ("cd B && pushd A && git commit", lambda: bash(f"cd {B} && pushd {A} && git commit -m x"), 2),
    ("cd B && GIT_DIR=A/.git GIT_WORK_TREE=A git commit", lambda: bash(f"cd {B} && GIT_DIR={A}/.git GIT_WORK_TREE={A} git commit -m x"), 2),
    ("cd B && git --git-dir=A/.git commit-tree style: --work-tree", lambda: bash(f"cd {B} && git --work-tree={A} --git-dir={A}/.git commit -m x"), 2),
    ("cd B && git commit with a heredoc message (no cd in it): still B", lambda: bash(f"cd {B} && git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\""), 0),
    # review #9: reading about the switch is not switching it
    ("grep the flag name into a file under /tmp", lambda: bash("grep -rn 'devkit-allow-shared' bin/ > /tmp/hits.txt"), 0),
    ("grep the command name in docs", lambda: bash("grep -rn 'agent-kit allow-shared' docs/"), 0),
    ("ls the flag then run pytest", lambda: bash(f"ls {A}/.git/devkit-allow-shared && python3 -m pytest -q"), 0),
    ("cat session_lock.py | grep --allow-shared", lambda: bash("cat bin/session_lock.py | grep -- --allow-shared"), 0),
    ("git log -S flag | tee /tmp/l", lambda: bash("git log -S devkit-allow-shared | tee /tmp/l"), 0),
    ("redirect INTO the flag file", lambda: bash(f"echo x > {A}/.git/devkit-allow-shared"), 2),
    ("redirect into the flag file inside bash -c", lambda: bash(f"bash -c 'echo x >> {A}/.git/devkit-allow-shared'"), 2),
    ("touch the flag file", lambda: bash(f"touch {A}/.git/devkit-allow-shared"), 2),
    # review round 2 #7: a commit message that talks about the switch is a message (heredoc body / quoted text), not a command
    ("heredoc commit message with lines that start like the switch commands", lambda: bash(f"cd {B} && git commit -m \"$(cat <<'EOF'\nSubject\n\nagent-kit allow-shared --minutes 30\n  python3 bin/session_lock.py --allow-shared\nEOF\n)\""), 0),
    ("UNQUOTED heredoc commit message with a switch-looking line", lambda: bash(f"cd {B} && git commit -F - <<'EOF'\nSubject\n\nagent-kit allow-shared --minutes 30\nEOF"), 0),
    ("a heredoc fed to bash RUNS: the switch inside it is caught", lambda: bash("bash <<'EOF'\nagent-kit allow-shared\nEOF"), 2),
    ("UNQUOTED heredoc line 'cd B' is data: the push after it runs where it ran", lambda: bash(f"git -C {B} commit -F - <<'EOF'\nRepro:\ncd {B}\nEOF\ngit push origin main"), 2),
    ("quoted message with a newline and the switch name", lambda: bash(f"cd {B} && git commit -m \"line one\nagent-kit allow-shared\""), 0),
    ("sed -n over the flag name (a read)", lambda: bash("sed -n '/devkit-allow-shared/p' bin/session_lock.py"), 0),
    ("awk over the flag name (a read)", lambda: bash("awk '/devkit-allow-shared/' bin/session_lock.py"), 0),
    ("sed -i on the flag file (a write)", lambda: bash(f"sed -i s/a/b/ {A}/.git/devkit-allow-shared"), 2),
    # round 2 #6: wrappers in front of the switch
    ("nice python3 session_lock.py --allow-shared", lambda: bash(f"nice python3 {SCRIPT} --allow-shared"), 2),
    ("timeout 10 agent-kit allow-shared", lambda: bash("timeout 10 agent-kit allow-shared"), 2),
    ("uv run python session_lock.py --allow-shared", lambda: bash(f"uv run python {SCRIPT} --allow-shared"), 2),
    # round 2 #8: more ways to reach a repo the walk did not follow
    ("git -c user.name=\"A B\" commit (a quoted value with a space)", lambda: bash("git -c user.name=\"A B\" commit -m x"), 2),
    ("git -c user.email=\"a b\" -C A push", lambda: bash(f"git -c user.email=\"a b\" -C {A} push"), 2),
    ("git -c user.name=\"A B\" -C B commit (legitimate, another repo)", lambda: bash(f"git -c user.name=\"A B\" -C {B} commit -m x"), 0),
    ("cd B && env -C A git commit", lambda: bash(f"cd {B} && env -C {A} git commit -m x"), 2),
    ("a heredoc line 'cd B' is data, the push runs where it ran", lambda: bash(f"git -C {B} commit -m \"$(cat <<'EOF'\nRepro:\ncd {B}\nEOF\n)\" && git push origin main"), 2),
    ("/usr/bin/git commit", lambda: bash("/usr/bin/git commit -m x"), 2),
    ("echo \"&& cd B &&\" ; git commit (separators inside quotes)", lambda: bash(f"echo \"&& cd {B} &&\" ; git commit -m x"), 2),
]
bad = 0
for label, run, want in cases:
    got = run()
    ok = got == want
    bad += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: exit {got} (want {want})")
print(f"session_lock target-repo table: {len(cases) - bad}/{len(cases)} ok")


def check(label, got, want):
    global bad
    ok = got == want
    bad += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: {got!r} (want {want!r})")


# A session that holds nothing must not take the lock by writing OUTSIDE a checkout (the old rule took it for any Edit/Write).
C = repo("free")
tool_c = lambda name, path, sid: hook({"tool_name": name, "tool_input": {"file_path": path}}, sid=sid, cwd=C)
check("free session: Write outside the checkout allowed", tool_c("Write", os.path.join(tmp, "scratch", "o.txt"), "x1"), 0)
check("  … and it did not take the lock", os.path.exists(os.path.join(C, ".git", "devkit-session.lock")), False)
check("free session: Write inside the checkout allowed", tool_c("Write", os.path.join(C, "f.txt"), "x1"), 0)
check("  … and now it holds the lock", os.path.exists(os.path.join(C, ".git", "devkit-session.lock")), True)

# The user's approval (agent-kit allow-shared) reaches the running hook.
FLAG = os.path.join(A, ".git", "devkit-allow-shared")
LOG = os.path.join(A, ".git", "devkit-session.log")
cli = lambda *a: subprocess.run([sys.executable, "-I", SCRIPT, *a], capture_output=True, text=True)
check("no approval yet: a second session's git commit is blocked", bash("git commit -m x"), 2)
check("  … `session_lock.py --status` says do not edit (exit 3)", cli("--status", "--session", "me", A).returncode, 3)
r = cli("--allow-shared", "--minutes", "5", A)
check("the user's `--allow-shared --minutes 5` succeeds", r.returncode, 0)
check("  … and writes the flag file", os.path.isfile(FLAG), True)
check("  … the second session's git commit now passes", bash("git commit -m x"), 0)
check("  … Write in the locked checkout passes", tool("Write", os.path.join(A, "z.txt")), 0)
check("  … `--status` now says editable (exit 0)", cli("--status", "--session", "me", A).returncode, 0)
check("  … the use is logged with the session id", "me ghi song song" in open(LOG, encoding="utf-8").read(), True)
with open(FLAG, "w", encoding="utf-8") as f:
    json.dump({"until": time.time() - 5, "granted": time.time() - 400, "by": "user"}, f)
check("an expired approval does not count", bash("git commit -m x"), 2)
with open(FLAG, "w", encoding="utf-8") as f:
    f.write("not json")
check("a corrupt approval file does not count", bash("git commit -m x"), 2)
cli("--allow-shared", A)
check("`--allow-shared` with no minutes defaults to 60 (1..480)", 3500 < json.load(open(FLAG))["until"] - time.time() < 3700, True)
check("  … `--minutes 9999` is clamped to 480", (cli("--allow-shared", "--minutes", "9999", A), 28700 < json.load(open(FLAG))["until"] - time.time() < 28900)[1], True)
check("  … `--minutes abc` is refused (exit 2)", cli("--allow-shared", "--minutes", "abc", A).returncode, 2)
check("`--allow-shared-off` succeeds", cli("--allow-shared-off", A).returncode, 0)
check("  … removes the flag", os.path.exists(FLAG), False)
check("  … the second session's git commit is blocked again", bash("git commit -m x"), 2)
check("  … `--allow-shared-off` twice is not an error", cli("--allow-shared-off", A).returncode, 0)
check("non-git directory: --allow-shared refuses (exit 1)", cli("--allow-shared", os.path.join(tmp, "scratch")).returncode, 1)

# An agent cannot switch it on or off itself - neither the blocked session nor the holder.
grants = [
    f"python3 {SCRIPT} --allow-shared",
    f"python3 {KIT}/bin/session_lock.py --allow-shared-off",
    "agent-kit allow-shared",
    "agent-kit allow-shared --minutes 480",
    f"echo '{{}}' > {A}/.git/devkit-allow-shared",
    f"touch {A}/.git/devkit-allow-shared",
    f"cp /tmp/x {A}/.git/devkit-allow-shared",
    f"python3 -c \"open('{A}/.git/devkit-allow-shared','w')\"",
]
for g in grants:
    check(f"agent Bash `{g[:58]}` blocked (blocked session)", bash(g), 2)
    check(f"  … and for the HOLDER too", bash(g, sid="holder"), 2)
check("reading about it is fine: grep allow-shared docs", bash("grep -rn allow-shared docs"), 0)
check("reading the flag is fine: cat", bash(f"cat {A}/.git/devkit-allow-shared"), 0)
check("the flag did not appear from any of those attempts", os.path.exists(FLAG), False)

# review #8: the Edit/Write tools cannot be used to write the switch or the lock either - also from a LINKED worktree, whose git dir lies outside it
W = os.path.join(tmp, "linked")
sh("git", "-C", A, "-c", "user.name=t", "-c", "user.email=t@t", "worktree", "add", "-q", "--detach", W)
WGD = sh("git", "-C", W, "rev-parse", "--absolute-git-dir").strip()
with open(os.path.join(WGD, "devkit-session.lock"), "w", encoding="utf-8") as f:   # another live session holds the worktree
    json.dump({"session_id": "holder2", "started": now, "heartbeat": now, "cwd": W, "pid": os.getpid()}, f)
in_w = lambda name, path: hook({"tool_name": name, "tool_input": {"file_path": path}}, sid="me", cwd=W)
check("linked worktree: Write of the approval flag in its own git dir is blocked", in_w("Write", os.path.join(WGD, "devkit-allow-shared")), 2)
check("  … and so is a Write of its lock file", in_w("Write", os.path.join(WGD, "devkit-session.lock")), 2)
check("  … and any other file inside that git dir", in_w("Write", os.path.join(WGD, "config")), 2)
check("  … and the approval flag anywhere else (a copy that is moved later)", in_w("Write", os.path.join(tmp, "scratch", "devkit-allow-shared")), 2)
check("  … but an ordinary scratch file is fine", in_w("Write", os.path.join(tmp, "scratch", "ok.txt")), 0)
check("  … the HOLDER may not Write the switch either (only the user does)", hook({"tool_name": "Write", "tool_input": {"file_path": os.path.join(WGD, "devkit-allow-shared")}}, sid="holder2", cwd=W), 2)

# review #10: a write aimed at ANOTHER repo is judged by THAT repo's lock as well
C2 = repo("held_elsewhere")
with open(os.path.join(C2, ".git", "devkit-session.lock"), "w", encoding="utf-8") as f:
    json.dump({"session_id": "holder3", "started": now, "heartbeat": now, "cwd": C2, "pid": os.getpid()}, f)
check("cd <repo held by ANOTHER live session> && git commit is blocked for me", bash(f"cd {C2} && git commit -m x"), 2)
check("  … git -C too", bash(f"git -C {C2} push origin main"), 2)
check("  … and `agent-kit worktree finish` aimed at it", bash(f"cd {C2} && agent-kit worktree finish ../x"), 2)
check("  … but the HOLDER of that repo may", hook({"tool_name": "Bash", "tool_input": {"command": f"cd {C2} && git commit -m x"}}, sid="holder3"), 0)
with open(os.path.join(C2, ".git", "devkit-session.lock"), "w", encoding="utf-8") as f:
    json.dump({"session_id": "holder3", "started": now - 5000, "heartbeat": now - 5000, "cwd": C2, "pid": 2 ** 22 + 77}, f)   # a dead holder
check("  … a dead holder's lock does not block", bash(f"cd {C2} && git commit -m x"), 0)

# review round 2 #4: the lock of the TARGET repo counts also when the session's own checkout is free
CF = repo("own_free")
free = lambda cmd: hook({"tool_name": "Bash", "tool_input": {"command": cmd}}, sid="me", cwd=CF)
check("own checkout free: git -C <held repo> commit is blocked", free(f"git -C {A} commit -m x"), 2)
check("  … cd <held repo> && git commit", free(f"cd {A} && git commit -m x"), 2)
check("  … cd <held repo> && post-fix-gate", free(f"cd {A} && python3 {GATE} --run-tests"), 2)
check("  … cd <held repo> && agent-kit wt finish", free(f"cd {A} && agent-kit wt finish ../x"), 2)
check("  … but git commit in the own free checkout is fine", free("git commit -m x"), 0)
with open(FLAG, "w", encoding="utf-8") as f:
    json.dump({"until": time.time() + 300, "granted": time.time(), "by": "user"}, f)
check("  … and the user's approval for that repo lets it through", free(f"git -C {A} commit -m x"), 0)
os.unlink(FLAG)

# a FIFO planted where the approval flag belongs must not hang the hook
fifo = os.path.join(A, ".git", "devkit-allow-shared")
os.mkfifo(fifo)
t0 = time.time()
rc = bash("git commit -m x")
check("a FIFO at the flag path: the hook still answers (blocked) within 5 s", (rc, time.time() - t0 < 5), (2, True))
os.unlink(fifo)

shutil.rmtree(tmp, ignore_errors=True)
total = len(cases)
print(f"session_lock target-repo + allow-shared: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
