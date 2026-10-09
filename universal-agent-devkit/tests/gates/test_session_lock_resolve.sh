#!/usr/bin/env bash
# hooks/session_lock.sh runs on EVERY PreToolUse (Bash, Edit, Write) and is the slowest hook of the PreBash group, so a python start
# that only finds the hook's own directory (`python3 -I -c 'os.path.realpath($0)'`, ~18 ms) sits on the critical path of every command.
# The hook now resolves $0 in bash (readlink loop + `cd -P`) and keeps the old python line as the fallback for anything odd. This
# test proves it is a DROP-IN: the python decision logic (bin/session_lock.py) is untouched and the hook's exit code, stdout, stderr
# and state files do not change.
#   (a) old-vs-new EQUIVALENCE, on 8 layouts (symlink-mode, copy-mode, relative symlink chain, hooks dir that is itself a symlink holding
#       a relative link with `..`, linked worktree, subdirectory cwd, spaces/unicode in every path, plugin layout), run the way Claude Code
#       runs it (`sh -c 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/..."'`). OLD = the frozen pre-change hook text below.
#       Default: per layout (1) a python SHIM stands in for session_lock.py and records what the hook execs: the script path, the whole
#       environment, stdin, and the process chain (its parent is the test = nothing but `exec` ran in between): old == new; (2) a real
#       canary on the real python: no lock + SessionStart, other session fresh + Edit / git commit, exit code, stdout, stderr and state
#       files old == new, and the OLD hook must really have blocked / taken the lock (a layout that never reaches session_lock.py proves
#       nothing). The python decision code (bin/session_lock.py) is untouched, so what could differ is only WHICH file is exec'd and with
#       WHAT input: that is what (1) compares. SLR_FULL=1 additionally runs the full table 7 lock states (no lock, own fresh, own stale,
#       other fresh / stale / dead pid, shared-checkout env) x 18 payloads x 8 layouts, old vs new, byte for byte (1008 pairs, ~2 min).
#       Dropped from the DEFAULT run only: that 7 x 18 matrix (it re-tests the unchanged python decision code once per layout).
#   (b) the speed claim by COUNT, not seconds: python3 starts (a PATH shim logs each one) on the quiet path: new = old - 1, and the
#       fallback (a symlink loop) starts the python resolver again.
#   (c) the resolver itself: a table of $0 forms (absolute, relative, no slash, `..`, symlink chain, directory symlink + `..`, spaces,
#       a leading dash, loop, chain over the bound, a link target that ends in a NEWLINE next to a decoy of the same name without it,
#       CDPATH decoy, PATH without readlink, a failing readlink, `bash -e`, `sh`, python missing) -> the directory session_lock.py is
#       launched from must equal os.path.realpath's and equal what the OLD line gives. A runaway loop is caught by COUNTING readlink calls
#       (a shim kills the run after 80), not by a clock: the real bound is 32.
#   (d) MUTATIONS: each production line is broken in a copy of the hook; (b)+(c) must go red.
#   Known, accepted differences (none changes an allow / block decision; the exit code is the same in every case):
#     - stderr text, only where the hook already failed: with python3 absent the old line 7 printed "python3: command not found" (gone:
#       line 7 no longer starts python; exec still fails with 127, as before); bash messages quote the line number of the fallback
#       python line (33 / 34) instead of 7 / 8 (table (c) compares them with the number masked); a deleted cwd prints fewer
#       "error retrieving current directory" lines (the old `cd` / python start printed "chdir: ..."; same exit code, same HERE).
#     - the STRING of HERE, never the directory: a link target that starts with `//` or an inherited PWD spelled through a symlink /
#       firmlink is returned as the physical path (cd -P, pwd -P) where python's realpath keeps the leading `//`; (c) compares those by
#       directory identity.
#     - inputs that still fall back to the python line (same behaviour as before, no speed-up): a `$0` that starts with `-` (readlink
#       reads it as an option), a chain over 32 hops, no readlink or a readlink without -n on PATH, a newline in a link target or in the
#       directory name, an empty `$0`.
#   SLR_KIT=<devkit dir>   run the same checks against another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only, 3.9 compatible).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SLR_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import concurrent.futures, glob, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time

KIT = os.path.realpath(sys.argv[1])
HOOK_PATH = os.path.join(KIT, "hooks", "session_lock.sh")
PY_SRC = os.path.join(KIT, "bin", "session_lock.py")
NEW = open(HOOK_PATH, encoding="utf-8").read()
# the hook as it was before the change (frozen baseline; the python realpath start is line 7)
OLD = r'''#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_lock.sh — SessionStart / PreToolUse / SessionEnd hook: ONE agent session per checkout.
# Logic and rationale: bin/session_lock.py (owner request, GeelyEx2 2026-09-29: two sessions in one checkout voided
# full-gate receipts and blocked a push). Exit 2 on PreToolUse = blocked; SessionStart never blocks.
# ─────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
exec python3 "$HERE/../bin/session_lock.py"
'''
ROOT = os.path.realpath(tempfile.mkdtemp(prefix="slres."))
REAL_PY = shutil.which("python3")
import atexit
atexit.register(lambda: shutil.rmtree(ROOT, ignore_errors=True))      # an exception or sys.exit leaves nothing in TMPDIR
signal.signal(signal.SIGTERM, lambda *a: sys.exit(143))
fails = []
DEVNULL = subprocess.DEVNULL


def fail(msg):
    fails.append(msg)
    print("  FAIL " + msg)

if not re.search(r'(?m)^exec python3 -I "\$HERE/../bin/session_lock\.py"', NEW):
    fail("session_lock.sh must exec python3 -I so PYTHONPATH cannot shadow the stdlib")


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def git(cwd, *a):
    subprocess.run(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), check=True,
                   capture_output=True, stdin=DEVNULL)


def base_env(extra=None):
    e = {k: v for k, v in os.environ.items()
         if not k.startswith(("GIT_", "CLAUDE_", "DEVKIT_", "SLR_", "SHIM_")) and k not in ("CDPATH", "SHELLOPTS", "BASHOPTS")}
    e["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra:
        e.update(extra)
    return e


def run(argv, inp=b"", env=None, cwd=None, timeout=60):
    """subprocess in its own process group; a timeout kills the group (a hang is a failure, not a stuck test)."""
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=env if env is not None else base_env(), cwd=cwd, start_new_session=True)
    try:
        out, err = p.communicate(inp, timeout=timeout)
        return p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        return 124, "", "TIMEOUT"


# ───────────────────────── (a) layouts and the equivalence table ─────────────────────────
class Layout(object):
    pass


def make_repo(path):
    os.makedirs(os.path.join(path, "src", "sub"))
    write(os.path.join(path, "src", "A.kt"), "x\n")
    subprocess.run(["git", "init", "-q", path], check=True, capture_output=True, stdin=DEVNULL)
    git(path, "add", "-A")
    git(path, "commit", "-qm", "init")


def put_kit(kit):
    write(os.path.join(kit, "hooks", "session_lock.sh"), OLD, 0o755)
    os.makedirs(os.path.join(kit, "bin"), exist_ok=True)
    shutil.copy(PY_SRC, os.path.join(kit, "bin", "session_lock.py"))


def build(name):
    L = Layout()
    L.name = name
    r = os.path.join(ROOT, "L_" + name)
    L.root = r
    proj = os.path.join(r, "proj")
    kit = os.path.join(r, "kit")
    L.cwd_sub = None
    L.cmd = 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/session_lock.sh"'
    L.extra_env = {}
    link = lambda target, path: (os.makedirs(os.path.dirname(path), exist_ok=True), os.symlink(target, path))
    if name == "spaces":
        proj = os.path.join(r, "my proj (é) 'q'")
        kit = os.path.join(r, "kit dir ü")
    make_repo(proj)
    L.proj = proj
    hook = os.path.join(proj, ".claude", "hooks", "session_lock.sh")
    if name in ("symlink", "worktree", "subdir", "spaces"):
        put_kit(kit)
        link(os.path.join(kit, "hooks", "session_lock.sh"), hook)
    elif name == "copy":
        write(hook, OLD, 0o755)
        os.makedirs(os.path.join(proj, ".claude", "bin"))
        shutil.copy(PY_SRC, os.path.join(proj, ".claude", "bin", "session_lock.py"))
    elif name == "plugin":
        plug = os.path.join(r, "plugin")
        write(os.path.join(plug, "hooks", "session_lock.sh"), OLD, 0o755)
        os.makedirs(os.path.join(plug, "bin"))
        shutil.copy(PY_SRC, os.path.join(plug, "bin", "session_lock.py"))
        hook = os.path.join(plug, "hooks", "session_lock.sh")
        L.cmd = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/session_lock.sh"'
        L.extra_env = {"CLAUDE_PLUGIN_ROOT": plug}
    elif name == "relchain":
        put_kit(kit)
        link("../links/a.sh", hook)                                  # relative, up one directory
        link("b.sh", os.path.join(proj, ".claude", "links", "a.sh"))  # relative, same directory
        link("../../../kit/hooks/session_lock.sh", os.path.join(proj, ".claude", "links", "b.sh"))
    elif name == "dirlink":
        # .claude/hooks is a symlink to a directory whose file is a RELATIVE link with `..`: physical `..` != textual `..`
        deep = os.path.join(r, "elsewhere", "deep", "hooks")
        put_kit(os.path.join(r, "elsewhere", "kit"))
        link("../../kit/hooks/session_lock.sh", os.path.join(deep, "session_lock.sh"))
        os.makedirs(os.path.join(proj, ".claude"), exist_ok=True)
        os.symlink(deep, os.path.join(proj, ".claude", "hooks"))
    else:
        raise AssertionError(name)
    if name == "worktree":
        wt = os.path.join(r, "wt")
        git(proj, "worktree", "add", "-q", wt, "-b", "wt")
        os.makedirs(os.path.join(wt, ".claude", "hooks"))
        os.symlink(os.path.join(kit, "hooks", "session_lock.sh"), os.path.join(wt, ".claude", "hooks", "session_lock.sh"))
        L.proj = wt
        hook = os.path.join(wt, ".claude", "hooks", "session_lock.sh")
    L.entry = hook
    L.real = os.path.realpath(hook)
    L.cwd = L.proj
    if name == "subdir":
        L.cwd = os.path.join(L.proj, "src", "sub")
    L.gdir = subprocess.run(["git", "-C", L.proj, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True,
                            stdin=DEVNULL).stdout.strip()
    L.common = os.path.realpath(os.path.join(L.gdir, subprocess.run(["git", "-C", L.proj, "rev-parse", "--git-common-dir"],
                                capture_output=True, text=True, stdin=DEVNULL).stdout.strip()))
    if not os.path.isabs(os.path.join(L.gdir)):
        raise AssertionError("gdir")
    return L


ME, OTHER = "eq-me-0001", "eq-other-0002"
LIVE, DEAD = os.getpid(), 999999


def clear(L):
    for d in (L.gdir, L.common):
        for f in glob.glob(os.path.join(d, "devkit-sessions", "*")):
            os.unlink(f)
        for f in ("devkit-session.lock", "devkit-session.log"):
            if os.path.exists(os.path.join(d, f)):
                os.unlink(os.path.join(d, f))
    os.makedirs(os.path.join(L.common, "devkit-sessions"), exist_ok=True)


def put_lock(L, sid, hb_age, pid):
    now = time.time()
    json.dump({"session_id": sid, "started": now - 1000, "heartbeat": now - hb_age, "cwd": L.proj, "pid": pid},
              open(os.path.join(L.gdir, "devkit-session.lock"), "w"))
    json.dump({"session_id": sid, "agent": "claude", "pid": pid, "started": now - 1000, "heartbeat": now - hb_age, "cwd": L.proj,
               "gitdir": L.gdir, "status": "working"}, open(os.path.join(L.common, "devkit-sessions", sid + ".json"), "w"))


STATES = [
    ("no-lock", lambda L: None, {}),
    ("own-fresh", lambda L: put_lock(L, ME, 2, LIVE), {}),
    ("own-stale", lambda L: put_lock(L, ME, 900, LIVE), {}),
    ("other-fresh", lambda L: put_lock(L, OTHER, 5, LIVE), {}),
    ("other-stale", lambda L: put_lock(L, OTHER, 900, LIVE), {}),
    ("other-dead-pid", lambda L: put_lock(L, OTHER, 5, DEAD), {}),
    ("shared-checkout-env", lambda L: put_lock(L, OTHER, 5, LIVE), {"DEVKIT_ALLOW_SHARED_CHECKOUT": "1"}),
]


def pre(tool, ti, **kw):
    d = {"session_id": ME, "hook_event_name": "PreToolUse", "cwd": "{CWD}", "tool_name": tool, "tool_input": ti}
    d.update(kw)
    return d


def bash(cmd, **kw):
    return pre("Bash", {"command": cmd}, **kw)


# 18 payload shapes ("{PROJ}" / "{CWD}" are filled in per layout; a str is sent raw)
PAYLOADS = [
    ("SessionStart", {"session_id": ME, "hook_event_name": "SessionStart", "cwd": "{CWD}", "source": "startup"}),
    ("SessionEnd", {"session_id": ME, "hook_event_name": "SessionEnd", "cwd": "{CWD}"}),
    ("Bash read", bash("ls -la")),
    ("Bash git read", bash("git status --short")),
    ("Bash redirect in checkout", bash("echo hi > notes.txt")),
    ("Bash git write", bash("git commit -m x")),
    ("Bash gate run", bash("python3 .agents/devkit/bin/post-fix-gate.py --run-tests")),
    ("Edit inside", pre("Edit", {"file_path": "{PROJ}/src/A.kt"})),
    ("Write inside", pre("Write", {"file_path": "{PROJ}/src/B.kt"})),
    ("Write outside checkout", pre("Write", {"file_path": "/private/tmp/outside-slres.txt"})),
    ("Edit subagent (agent_id)", pre("Edit", {"file_path": "{PROJ}/src/A.kt"}, agent_id="a1b2c3", agent_type="general-purpose")),
    ("Bash git push subagent", bash("git push origin main", agent_id="a1b2c3", agent_type="Explore")),
    ("empty stdin", ""),
    ("garbled JSON", '{"session_id": "x", '),
    ("non-dict JSON (traceback text)", "[1, 2]"),
    ("other tool (Read)", pre("Read", {"file_path": "{PROJ}/src/A.kt"})),
    ("Stop event", {"session_id": ME, "hook_event_name": "Stop", "cwd": "{CWD}"}),
    ("no session id", pre("Edit", {"file_path": "{PROJ}/src/A.kt"}, session_id="")),
]


def render(pl, L):
    if isinstance(pl, str):
        return pl.encode()
    esc = lambda s: json.dumps(s)[1:-1]
    return json.dumps(pl).replace("{PROJ}", esc(L.proj)).replace("{CWD}", esc(L.cwd)).encode()


def norm_text(s):
    s = re.sub(r"cách đây \d+s", "cách đây Ns", s)
    return re.sub(r"giữ từ \d\d:\d\d", "giữ từ HH:MM", s)


def snap(L, now):
    out = {}
    files = sorted(glob.glob(os.path.join(L.common, "devkit-sessions", "*.json"))) + [os.path.join(L.gdir, "devkit-session.lock")]
    for f in files:
        if os.path.exists(f):
            try:
                d = json.load(open(f))
            except ValueError:
                d = "UNREADABLE"
            if isinstance(d, dict):
                for k in ("started", "heartbeat"):
                    if isinstance(d.get(k), (int, float)):
                        d[k] = "NOW" if abs(d[k] - now) < 60 else "AGED"
            out[os.path.basename(f)] = d
    lg = os.path.join(L.gdir, "devkit-session.log")
    out["log"] = [norm_text(l.split(" ", 2)[2].strip()) for l in open(lg)] if os.path.exists(lg) else None
    return out


def one(L, text, pl, extra):
    write(L.real, text, 0o755)
    env = base_env(dict(L.extra_env, CLAUDE_PROJECT_DIR=L.proj, **extra))
    now = time.time()
    rc, out, err = run(["sh", "-c", L.cmd], render(pl, L), env, L.cwd)
    return (rc, norm_text(out), norm_text(err), snap(L, now))


FULL = os.environ.get("SLR_FULL") == "1"
CANARY_STATES = ("no-lock", "other-fresh")
CANARY_PAYLOADS = ("SessionStart", "Edit inside", "Bash git write")


def table(L):
    """-> (cases, diffs, canary failures). Default: the canary slice; SLR_FULL=1: every state x every payload."""
    n, diffs, old_res = 0, [], {}
    for sname, setup, extra in STATES:
        for pname, pl in PAYLOADS:
            if not (FULL or (sname in CANARY_STATES and pname in CANARY_PAYLOADS)):
                continue
            res = []
            for text in (OLD, NEW):
                clear(L)
                setup(L)
                res.append(one(L, text, pl, extra))
            n += 1
            old_res[(sname, pname)] = res[0]
            if res[0] != res[1]:
                diffs.append("%s | %s | %s\n    old %r\n    new %r" % (L.name, sname, pname, res[0], res[1]))
    canary = []
    r = old_res[("other-fresh", "Edit inside")]
    if r[0] != 2 or "⛔" not in r[2]:
        canary.append("%s: the OLD hook never blocked a second session (rc=%s err=%r): layout does not reach session_lock.py" % (L.name, r[0], r[2][:80]))
    r = old_res[("no-lock", "SessionStart")]
    if r[0] != 0 or not r[3].get("devkit-session.lock"):
        canary.append("%s: the OLD hook did not take the lock on SessionStart: layout does not reach session_lock.py" % L.name)
    write(L.real, NEW, 0o755)
    return n, diffs, canary


LAYOUTS = ["symlink", "copy", "relchain", "dirlink", "worktree", "subdir", "spaces", "plugin"]
print("(a) old vs new hook on %d layouts: exec probe + canary%s" % (len(LAYOUTS), " + the FULL table (SLR_FULL=1)" if FULL else " (SLR_FULL=1 adds the 7 x 18 table)"))
t0 = time.time()
built = [build(n) for n in LAYOUTS]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
    results = list(ex.map(table, built))
total = sum(r[0] for r in results)
for r in results:
    for c in r[2]:
        fail(c)
    for d in r[1][:6]:
        fail("DIFF " + d)
print("  canary%s: %d old/new case pairs, %d differing, %.0f s" % (" + full table" if FULL else "", total, sum(len(r[1]) for r in results), time.time() - t0))
EXPECT_CASES = (len(STATES) * len(PAYLOADS) if FULL else len(CANARY_STATES) * len(CANARY_PAYLOADS)) * len(LAYOUTS)
if total != EXPECT_CASES:
    fail("table size %d != %d" % (total, EXPECT_CASES))


# ───────────────────── python start shim, used by (a), (b) and (c) ─────────────────────
SHIM_DIR = os.path.join(ROOT, "shim")
write(os.path.join(SHIM_DIR, "python3"), """#!/bin/sh
# logs every start. SHIM_MODE=run execs the real python. SHIM_MODE=log (default) execs it only for
# `python3 -I -c ...` (the resolver). `python3 -I script.py` is a script launch, same as `python3 script.py`:
# log the script path and do not exec it (session_lock.py is not wanted in the resolver table).
if [ "${1:-}" = "-I" ] && [ "${2:-}" = "-c" ]; then printf 'resolver-start\\n' >> "$SHIM_LOG"; exec "%s" "$@"; fi
if [ "${1:-}" = "-I" ]; then
  printf 'script %%s\\n' "${2:-}" >> "$SHIM_LOG"
  if [ "${SHIM_MODE:-log}" = "run" ]; then exec "%s" "$@"; fi
  if [ "${SHIM_MODE:-log}" = "probe" ]; then
    env | sort > "$SHIM_LOG.env"; cat > "$SHIM_LOG.in"; printf '%%s\\n' "$PPID" > "$SHIM_LOG.ppid"
  fi
  exit 0
fi
printf 'script %%s\\n' "${1:-}" >> "$SHIM_LOG"
if [ "${SHIM_MODE:-log}" = "run" ]; then exec "%s" "$@"; fi
if [ "${SHIM_MODE:-log}" = "probe" ]; then
  env | sort > "$SHIM_LOG.env"; cat > "$SHIM_LOG.in"; printf '%%s\\n' "$PPID" > "$SHIM_LOG.ppid"
fi
exit 0
""" % (REAL_PY, REAL_PY, REAL_PY), 0o755)
REAL_READLINK = shutil.which("readlink")
write(os.path.join(SHIM_DIR, "readlink"), """#!/bin/sh
# counts its calls in $SHIM_RL_COUNT and kills the whole run (its process group) after 80: a loop with no bound cannot hang the test;
# SHIM_READLINK=fail makes it fail the way an unusable readlink does
if [ -n "${SHIM_RL_COUNT:-}" ]; then
  printf x >> "$SHIM_RL_COUNT"
  if [ "$(wc -c < "$SHIM_RL_COUNT")" -gt 80 ]; then kill -9 0; fi
fi
if [ "${SHIM_READLINK:-}" = "fail" ]; then exit 1; fi
exec "%s" "$@"
""" % REAL_READLINK, 0o755)
SUFFIX = "/../bin/session_lock.py"
RUNAWAY = -9
_SEQ = [0]
_SEQ_LOCK = threading.Lock()


def shim_run(argv, env_extra=None, cwd=None, inp=b"", timeout=30):
    """-> (rc, stdout, stderr, python-start log lines, {"rl": readlink calls, "log": log path}); every call has its own files"""
    with _SEQ_LOCK:
        _SEQ[0] += 1
        n = _SEQ[0]
    log = os.path.join(ROOT, "shim.%d.log" % n)
    cnt = os.path.join(ROOT, "shim.%d.rl" % n)
    env = base_env({"PATH": SHIM_DIR + os.pathsep + os.environ["PATH"], "SHIM_LOG": log, "SHIM_RL_COUNT": cnt})
    if env_extra:
        env.update(env_extra)
    rc, out, err = run(argv, inp, env, cwd, timeout)
    lines = open(log).read().splitlines() if os.path.exists(log) else []
    rl = os.path.getsize(cnt) if os.path.exists(cnt) else 0
    for f in (log, cnt):
        if os.path.exists(f):
            os.unlink(f)
    return rc, out, err, lines, {"rl": rl, "log": log}


# ───────────────────── (a1) what the hook EXECs: script path, environment, stdin, process chain ─────────────────────
# Claude Code launches a hook with `sh -c '<cmd>'`. macOS /bin/sh (bash) execs that last command; Linux dash forks it and stays as a
# parent until the hook ends, so "nothing stayed alive between" cannot hold there for ANY hook text, old or new (2026-10-09). (a1) is about
# the hook's OWN exec, so where sh does not exec, the probe launches with bash in posix mode (what macOS sh is). The dash parent itself:
# tests/context_memory/test_session_lock_sh_parent.sh.
_sh = subprocess.run(["sh", "-c", '"$0" -c "import os; print(os.getppid())"', sys.executable], capture_output=True, text=True)
PROBE_SH = ["sh", "-c"] if _sh.stdout.strip() == str(os.getpid()) else ["bash", "--posix", "-c"]


def probe(L, text):
    write(L.real, text, 0o755)
    clear(L)
    payload = render(pre("Edit", {"file_path": "{PROJ}/src/A.kt"}, session_id=ME), L)
    env = dict(L.extra_env, CLAUDE_PROJECT_DIR=L.proj, SHIM_MODE="probe")
    rc, out, err, lines, x = shim_run(PROBE_SH + [L.cmd], env, L.cwd, payload)
    log = x["log"]
    rd = lambda f: open(f, "rb").read().decode("utf-8", "replace") if os.path.exists(f) else None
    write(L.real, NEW, 0o755)
    env_seen = rd(log + ".env")
    if env_seen is not None:       # the shim's own plumbing differs per call by design
        env_seen = "\n".join(l for l in env_seen.splitlines() if not l.startswith(("SHIM_LOG=", "SHIM_RL_COUNT=")))
    return {"rc": rc, "out": out, "err": err, "exec": [l for l in lines if l != "resolver-start"], "env": env_seen,
            "stdin": rd(log + ".in"), "payload": payload.decode("utf-8"), "ppid": rd(log + ".ppid")}


def a1_failures(L, new_text):
    """what the hook execs, old vs this text: [] when identical"""
    po, pn = probe(L, OLD), probe(L, new_text)
    if len(po["exec"]) != 1 or not po["exec"][0].endswith(SUFFIX) or po["ppid"] is None or po["stdin"] != po["payload"]:
        return ["(a1) %s: the OLD hook did not exec the shim with its stdin (non-vacuous check): %r" % (L.name, {k: po[k] for k in ("rc", "exec", "ppid")})]
    out = []
    if po["ppid"].strip() != str(os.getpid()):
        out.append("(a1) %s: the exec'd process is not a child of the test (old chain %r): something stayed alive between" % (L.name, po["ppid"]))
    for k in ("rc", "out", "err", "exec", "env", "stdin", "ppid"):
        if po[k] != pn[k]:
            out.append("(a1) %s: %s differs: old %r new %r" % (L.name, k, str(po[k])[:200], str(pn[k])[:200]))
    if "_sl_" in (pn["env"] or ""):
        out.append("(a1) %s: a hook variable leaked into the exec'd environment" % L.name)
    return out


print("(a1) exec probe: the hook must exec the same session_lock.py with the same environment, stdin and parent")
a1_bad = []
for L in built:
    a1_bad += a1_failures(L, NEW)
for f in a1_bad:
    fail(f)
print("  %d layouts: %s" % (len(built), "exec path, environment, stdin and parent identical old vs new" if not a1_bad else "DIFFERENCES"))


# ───────────────────── (b) python starts on the quiet path (COUNT) ─────────────────────
def count_python(L, text):
    write(L.real, text, 0o755)
    clear(L)
    pl = pre("Read", {"file_path": L.proj + "/src/A.kt"}, cwd=L.proj)
    env = {"CLAUDE_PROJECT_DIR": L.proj, "SHIM_MODE": "run"}
    env.update(L.extra_env)
    rc, out, err, lines, _ = shim_run(["sh", "-c", L.cmd], env, L.cwd, json.dumps(pl).encode())
    write(L.real, NEW, 0o755)
    return rc, lines


print("(b) python starts on the quiet path (PreToolUse Read), per layout")
for L in built:
    if L.name not in ("symlink", "copy", "relchain", "dirlink", "plugin"):
        continue
    rc_o, lo = count_python(L, OLD)
    rc_n, ln = count_python(L, NEW)
    print("  %-9s old %d python starts %s | new %d %s" % (L.name, len(lo), lo, len(ln), ln))
    if rc_o != 0 or rc_n != 0:
        fail("(b) %s: quiet-path Read exited %s/%s" % (L.name, rc_o, rc_n))
    if len(lo) != 2:
        fail("(b) %s: the OLD hook starts %d python processes, expected 2 (resolver + session_lock.py)" % (L.name, len(lo)))
    if len(ln) != len(lo) - 1:
        fail("(b) %s: the new hook starts %d python processes, expected old-1 = %d (the realpath start must be gone)" % (L.name, len(ln), len(lo) - 1))
    if ln and ln[-1].startswith("resolver-start"):
        fail("(b) %s: the last python start is a resolver, not session_lock.py" % L.name)


# ───────────────────── (c) the resolver table ─────────────────────
def c_tree():
    t = os.path.join(ROOT, "C")
    kit = os.path.join(t, "kit")
    put_kit(kit)
    real = os.path.join(kit, "hooks", "session_lock.sh")
    os.makedirs(os.path.join(kit, "hooks", "sub"))
    ln = lambda target, path: (os.makedirs(os.path.dirname(path), exist_ok=True), os.symlink(target, path))
    ln(real, os.path.join(t, "abs_link.sh"))
    ln("kit/hooks/session_lock.sh", os.path.join(t, "rel_link.sh"))
    ln("rel_link.sh", os.path.join(t, "chain2.sh"))
    ln("chain2.sh", os.path.join(t, "chain3.sh"))
    ln("../abs_link.sh", os.path.join(t, "dd", "up_link.sh"))
    ln(os.path.join(kit, "hooks", "sub"), os.path.join(t, "lk"))                  # directory symlink: lk/../ is kit/hooks physically
    ln(os.path.join(kit, "hooks"), os.path.join(t, "hooks_dir_link"))
    ln("../../../abs_link.sh", os.path.join(t, "ex", "a", "b", "up2.sh"))       # physical `..` x3 from ex/a/b is t; textual from shortcut/ is not
    ln(os.path.join(t, "ex", "a", "b"), os.path.join(t, "shortcut"))
    ln("loopB", os.path.join(t, "loopA"))
    ln("loopA", os.path.join(t, "loopB"))
    prev = "chain_00"
    ln("kit/hooks/session_lock.sh", os.path.join(t, "chain_00"))                   # a chain of 20 (under the bound) and 40 (over it)
    for i in range(1, 40):
        ln(prev, os.path.join(t, "chain_%02d" % i))
        prev = "chain_%02d" % i
    write(os.path.join(t, "sp ace", "k d ü", "hooks", "session_lock.sh"), OLD, 0o755)
    ln("sp ace/k d ü/hooks/session_lock.sh", os.path.join(t, "sp link.sh"))
    ln(os.path.join(t, "sp ace", "k d ü", "hooks"), os.path.join(t, "my hooks"))
    write(os.path.join(t, "-dash", "hooks", "session_lock.sh"), OLD, 0o755)
    ln("hooks/session_lock.sh", os.path.join(t, "-dash", "dash_link.sh"))
    os.makedirs(os.path.join(t, "decoy", "hooks"))
    ln(os.path.join(t, "hooks_dir_link", "session_lock.sh"), os.path.join(t, "decoy", "hooks", "session_lock.sh"))
    os.makedirs(os.path.join(t, "decoy2", "kit"))
    # a link target that ends in a NEWLINE (rv-d P1): `$(readlink)` strips it and would follow the decoy named without it (another kit)
    evil = os.path.join(t, "evil")
    put_kit(evil)
    nl = os.path.join(t, "nl")
    os.makedirs(nl)
    os.symlink(real, os.path.join(nl, "s.sh\n"))                                         # genuine
    os.symlink(os.path.join(evil, "hooks", "session_lock.sh"), os.path.join(nl, "s.sh"))   # the decoy
    os.symlink("s.sh\n", os.path.join(nl, "entry_rel.sh"))
    os.symlink(os.path.join(nl, "s.sh\n"), os.path.join(nl, "entry_abs.sh"))
    os.symlink("/" + real, os.path.join(t, "dbl.sh"))                                     # a target that starts with //
    write(os.path.join(t, "dirnl\n", "x.sh"), OLD, 0o755)                                  # the script's own directory name ends in a newline
    return t


T = c_tree()
H = os.path.join(T, "kit", "hooks")
# a PATH that has bash, sh, dirname, git and the python shim but NO readlink
NORD = os.path.join(ROOT, "nord")
os.makedirs(NORD)
for tool in ("dirname", "git", "bash", "sh"):
    if shutil.which(tool):
        os.symlink(shutil.which(tool), os.path.join(NORD, tool))
os.symlink(os.path.join(SHIM_DIR, "python3"), os.path.join(NORD, "python3"))
# (label, $0, cwd, extra env, flags)  flags: e / u = bash -e / -u, sh = run with /bin/sh, loop = a symlink loop, fb = the python fallback is
# expected (the other forms must NOT start the python resolver), samedir = HERE may differ in spelling but not in directory, oldonly = a
# case whose right answer is undefined (no such file): only old == new is checked, delcwd = start in a deleted directory, nostderr = the
# stderr text is known to differ (see the header)
CASES = [
    ("absolute real file", H + "/session_lock.sh", T, {}, ""),
    ("absolute, // and . components", H + "//./session_lock.sh", T, {}, ""),
    ("relative with slash", "kit/hooks/session_lock.sh", T, {}, ""),
    ("relative ./", "./session_lock.sh", H, {}, ""),
    ("no slash (bash session_lock.sh)", "session_lock.sh", H, {}, ""),
    ("empty $0 (old: parent of the cwd)", "", H, {}, "fb"),
    ("relative with ..", "../hooks/session_lock.sh", H, {}, ""),
    ("relative ../.. then down", "../../kit/hooks/session_lock.sh", H, {}, ""),
    ("absolute link", T + "/abs_link.sh", T, {}, ""),
    ("relative link", T + "/rel_link.sh", T, {}, ""),
    ("relative path to relative link", "rel_link.sh", T, {}, ""),
    ("chain of 3 links", T + "/chain3.sh", T, {}, ""),
    ("relative chain from another cwd", "../chain3.sh", os.path.join(T, "dd"), {}, ""),
    ("link with .. target", T + "/dd/up_link.sh", T, {}, ""),
    ("link with .. target, relative $0", "dd/up_link.sh", T, {}, ""),
    ("relative link with ../../.. inside a symlinked dir", T + "/shortcut/up2.sh", T, {}, ""),
    ("root-level $0", "/session_lock.sh", T, {}, ""),
    ("sh -c (posix mode), chain", T + "/chain3.sh", T, {}, "sh"),
    ("sh -c (posix mode), loop", T + "/loopA", T, {}, "sh loop"),
    ("dir symlink then ..", T + "/lk/../session_lock.sh", T, {}, ""),
    ("file in a symlinked dir", T + "/hooks_dir_link/session_lock.sh", T, {}, ""),
    ("link in a symlinked dir (relative $0)", "hooks_dir_link/session_lock.sh", T, {}, ""),
    ("chain of 20 links", T + "/chain_19", T, {}, ""),
    ("chain of 40 links (over the bound: python line)", T + "/chain_39", T, {}, "fb"),
    ("spaces and unicode", T + "/sp ace/k d ü/hooks/session_lock.sh", T, {}, ""),
    ("link with spaces", T + "/sp link.sh", T, {}, ""),
    ("dir link with spaces", T + "/my hooks/session_lock.sh", T, {}, ""),
    ("leading dash dir, relative", "-dash/hooks/session_lock.sh", T, {}, ""),
    ("leading dash link, relative (readlink reads it as an option)", "-dash/dash_link.sh", T, {}, "fb"),
    ("symlink loop (python line)", T + "/loopA", T, {}, "loop"),
    ("symlink loop, relative", "loopA", T, {}, "loop"),
    ("link target ending in a newline + decoy, relative target", T + "/nl/entry_rel.sh", T, {}, "fb"),
    ("link target ending in a newline + decoy, absolute target", T + "/nl/entry_abs.sh", T, {}, "fb"),
    ("link target starting with //", T + "/dbl.sh", T, {}, "samedir"),
    ("inherited PWD spelled through a symlink", "session_lock.sh", H, {"PWD": T + "/hooks_dir_link"}, ""),
    ("script directory name ends in a newline (as old)", T + "/dirnl\n/x.sh", T, {}, "fb oldonly"),
    ("CDPATH decoy, relative dir", "hooks/session_lock.sh", T + "/kit", {"CDPATH": T + "/decoy:" + T + "/decoy2"}, ""),
    ("CDPATH decoy, no slash", "session_lock.sh", H, {"CDPATH": T + "/decoy:" + H + ":."}, ""),
    ("CDPATH decoy, link", "decoy/hooks/session_lock.sh", T, {"CDPATH": T}, ""),
    ("nonexistent file (as old)", T + "/nowhere/session_lock.sh", T, {}, "fb oldonly"),
    ("bash -e, absolute link", T + "/abs_link.sh", T, {}, "e"),
    ("bash -eu, chain", T + "/chain3.sh", T, {}, "e u"),
    ("bash -e, nonexistent dir", T + "/nowhere/session_lock.sh", T, {}, "e fb oldonly"),
    ("bash -e, loop", T + "/loopA", T, {}, "e loop"),
    ("SHELLOPTS=errexit:nounset", T + "/chain3.sh", T, {"SHELLOPTS": "errexit:nounset"}, ""),
    ("PATH without readlink (python line)", T + "/chain3.sh", T, {"PATH": NORD}, "fb"),
    ("PATH without readlink, bash -e", T + "/chain3.sh", T, {"PATH": NORD}, "e fb"),
    ("PATH without readlink, real file (no readlink needed)", H + "/session_lock.sh", T, {"PATH": NORD}, ""),
    ("readlink fails (python line)", T + "/chain3.sh", T, {"SHIM_READLINK": "fail"}, "fb"),
    ("readlink fails, bash -e", T + "/chain3.sh", T, {"SHIM_READLINK": "fail"}, "e fb"),
    ("HOME unset, minimal PATH", T + "/chain3.sh", T, {"HOME": "/nonexistent"}, ""),
    ("deleted cwd (stderr: fewer 'error retrieving current directory' lines)", T + "/abs_link.sh", T, {}, "delcwd nostderr"),
]


def bash_argv(text, zero, flags):
    tk = flags.split()
    opts = [f for f in ("e", "u") if f in tk]
    return ["/bin/sh" if "sh" in tk else "/bin/bash"] + (["-" + "".join(opts)] if opts else []) + ["-c", text, zero]


def case_argv(text, zero, flags):
    argv = bash_argv(text, zero, flags)
    if "delcwd" in flags.split():      # the hook starts in a working directory that has been deleted
        argv = ["/bin/bash", "-c", 'mkdir -p "$1" && cd "$1" && rmdir "$1" && shift && exec "$@"', "_", os.path.join(T, "gone.%d" % threading.get_ident())] + argv
    return argv


OLD_CACHE = {}      # the old hook's answer for a case does not depend on the mutant under test


def here_of(lines):
    scripts = [l[7:] for l in lines if l.startswith("script ")]
    if len(scripts) != 1:
        return "NOSCRIPT:%r" % (lines,)
    s = scripts[0]
    return s[: -len(SUFFIX)] if s.endswith(SUFFIX) else "BADSUFFIX:" + s


def check_resolver(new_text, label="", stop=False):
    """-> list of failures of the resolver table for this hook text (stop: return at the first one, used for mutants)"""
    bad = []
    for lab, zero, cwd, extra, flags in CASES:
        if stop and bad:
            break
        tk = flags.split()
        key = (lab, zero, cwd, tuple(sorted(extra.items())), flags)
        if key not in OLD_CACHE:
            OLD_CACHE[key] = shim_run(case_argv(OLD, zero, flags), extra, cwd)
        rc_o, _, err_o, lo, _ = OLD_CACHE[key]
        rc_n, _, err_n, ln, xn = shim_run(case_argv(new_text, zero, flags), extra, cwd)
        rl = xn["rl"]
        if rc_n == RUNAWAY:
            bad.append("%s%s: RUNAWAY, readlink called more than 80 times (no loop bound)" % (label, lab))
            continue
        if rc_n == 124:
            bad.append("%s%s: HANG (killed by the 30 s backstop)" % (label, lab))
            continue
        # the only stderr text that may differ is the line number inside a bash message of a case that cannot happen for a real hook
        # (a $0 whose directory does not exist: bash could not have opened the script): the old line was line 7, the fallback is not
        err_o, err_n = re.sub(r"line \d+:", "line N:", err_o), re.sub(r"line \d+:", "line N:", err_n)
        ho, hn = here_of(lo), here_of(ln)
        same = (rc_o == rc_n and os.path.realpath(ho) == os.path.realpath(hn)) if "samedir" in tk else (rc_o, ho) == (rc_n, hn)
        if not same:
            bad.append("%s%s: old rc=%s HERE=%r | new rc=%s HERE=%r" % (label, lab, rc_o, ho, rc_n, hn))
            continue
        if err_o != err_n and "nostderr" not in tk:
            bad.append("%s%s: stderr differs old=%r new=%r" % (label, lab, err_o[:80], err_n[:80]))
            continue
        starts = ln.count("resolver-start")
        want_starts = 1 if ("fb" in tk or "loop" in tk) else 0
        if starts != want_starts:
            bad.append("%s%s: the python resolver started %d time(s), expected %d (%s)" % (
                label, lab, starts, want_starts, "fallback" if want_starts else "resolved in bash"))
            continue
        if "loop" in tk and rl > 33:
            bad.append("%s%s: readlink called %d times in a loop, the bound is 32" % (label, lab, rl))
            continue
        if "oldonly" in tk:
            continue
        # independent oracle: python's own realpath (a loop has no answer)
        want = os.path.dirname(os.path.realpath(os.path.join(cwd, zero)))
        if "loop" not in tk and not (here_of(ln) == want or ("samedir" in tk and os.path.realpath(hn) == os.path.realpath(want))):
            bad.append("%s%s: HERE=%r but os.path.realpath says %r" % (label, lab, here_of(ln), want))
    return bad


print("(c) resolver table: %d $0 forms, new vs old vs os.path.realpath" % len(CASES))
bad = check_resolver(NEW)
for b in bad:
    fail("(c) " + b)
print("  %d forms, %d failing" % (len(CASES), len(bad)))

# python3 missing: the same exit code as the old line (exec python3 fails: 127 = a non-blocking error, exactly as before; the old
# line-7 "command not found" message is gone because line 7 no longer starts python)
for variant, tools in (("with readlink", ("dirname", "git", "readlink")), ("without readlink", ("dirname", "git"))):
    nopy = os.path.join(ROOT, "nopy_" + variant.split()[0] + variant.split()[1])
    os.makedirs(nopy)
    for tool in tools:
        os.symlink(shutil.which(tool), os.path.join(nopy, tool))
    res = {}
    for lab, text in (("old", OLD), ("new", NEW)):
        res[lab] = run(["/bin/bash", "-c", text, T + "/chain3.sh"], b"", base_env({"PATH": nopy}), T)
    print("  python3 missing, PATH %s: old rc=%s new rc=%s" % (variant, res["old"][0], res["new"][0]))
    if res["old"][0] != res["new"][0] or res["new"][0] in (0, 2):
        fail("(c) python3 missing (%s): exit code changed old=%s new=%s" % (variant, res["old"][0], res["new"][0]))


# ───────────────────── fallback is the OLD line, not "pass" ─────────────────────
# a loop: the python resolver must run, and the hook must still launch session_lock.py exactly as before
rc_n, _, _, ln, _ = shim_run(bash_argv(NEW, T + "/loopA", ""), {}, T)
if ln.count("resolver-start") != 1:
    fail("(c) loop: the python fallback did not run: %r" % (ln,))


# ───────────────────── (d) mutations ─────────────────────
MUTANTS = [
    ("symlinks are not followed", [('[ -L "$_sl_self" ]', '[ -L "$_sl_self.x" ]')]),
    ("loop bound dropped (runaway)", [(' && [ "$_sl_n" -lt 32 ]', "")]),
    ("cd without -P", [("cd -P --", "cd --")]),
    # (`pwd -P` -> `pwd` is an EQUIVALENT mutant: after `cd -P` bash's PWD is already physical; the hook keeps -P only to say so.
    #  Likewise dropping the newline test of a link target: the sentinel keeps the exact bytes, so following it is still right.)
    ("relative link taken relative to the cwd", [('"${_sl_self%/*}/$_sl_link"', '"$_sl_link"')]),
    ("CDPATH not reset", [("unset CDPATH; ", "")]),
    ("no python fallback (the old line cannot run python)", [("python3 -I -c", "true -I -c")]),
    ("readlink failure kills the hook under set -e", [(' && printf x)" || _sl_link=""', ' && printf x)"')]),
    ("unreadable link does not fall back", [("_sl_n=99", "_sl_n=0")]),
    ("rv-d P1: readlink output loses a trailing newline ($(readlink) as before)",
     [('"$(readlink -n "$_sl_self" 2>/dev/null && printf x)"', '"$(readlink "$_sl_self" 2>/dev/null)"')]),
    ("rv-d P1: sentinel dropped (readlink -n alone: $() still strips the newline)", [(" && printf x)", ")")]),
    ("readlink without -n (its own newline makes every link a newline link: no speed-up)", [("readlink -n ", "readlink ")]),
]
print("(d) mutations: each must make (b) or (c) go red")
def run_mutant(m):
    lab, edits = m
    missing = [o for o, n in edits if NEW.count(o) < 1]
    if missing:
        return lab, None, "mutation target missing in the hook: %r" % missing[0], 0
    mut = NEW
    for o, n in edits:
        mut = mut.replace(o, n)
    t1 = time.time()
    bad = check_resolver(mut, "mutant: ", stop=True)
    return lab, mut, bad[0] if bad else None, time.time() - t1


with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
    mutant_results = list(ex.map(run_mutant, MUTANTS))
for lab, mut, why, secs in mutant_results:
    if mut is None:
        fail("(d) %s (%s)" % (why, lab))
        continue
    if not why:
        # (b) for the mutant: the symlink layout must still save a python start
        L = built[0]
        write(L.real, mut, 0o755)
        rc, lines = count_python(L, mut)
        write(L.real, NEW, 0o755)
        if len(lines) != 1:
            why = "python starts %d, expected 1" % len(lines)
    if why:
        print("  killed: %-72s (%.1f s) e.g. %s" % (lab, secs, why[:90]))
    else:
        fail("(d) SURVIVED mutation: %s" % lab)

for lab, edits in (("(a1) exec dropped: a bash stays alive between", [('exec python3 -I "$HERE', 'python3 -I "$HERE')]),
                   ("(a1) a hook variable is exported into the python environment", [('_sl_self="$0"', 'export _sl_self="$0"')])):
    if any(NEW.count(o) < 1 for o, n in edits):
        fail("(d) mutation target missing in the hook (%s)" % lab)
        continue
    mut = NEW
    for o, n in edits:
        mut = mut.replace(o, n)
    why = a1_failures(built[0], mut)
    if why:
        print("  killed: %-72s e.g. %s" % (lab, why[0][:90]))
    else:
        fail("(d) SURVIVED mutation: %s" % lab)
print("")
if fails:
    print("test_session_lock_resolve: %d failure(s)" % len(fails))
    sys.exit(1)
print("test_session_lock_resolve: all passed")
PY
