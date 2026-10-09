#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py appends ONE data-only JSON line per `--run-tests` run to
# <git-common-dir>/postfix-gate/runs.jsonl (modes full | impacted; plain static runs, --help, --commit-msg, --staged,
# --dry-run and "nothing to audit" log nothing), so that 3 days of data can answer "how often is a --full run
# triggered by a documentation-only change and what does it cost" (scripts/governance/gate_runs_report.py).
# The log must be IMPOSSIBLE to feed back into a decision. Everything below runs the REAL gate in throw-away repos:
#   (a) docs-only --full: one line, docs_only, mode full, suites present, fields agree with the gate's own --json
#   (b) code change: docs_only false.   (c) doc + code: docs_only false, n_docs 1.   Renames (code -> doc, doc -> code, doc -> doc) and
#       deletes: the rename SOURCE and a deleted file count as changed files (git mv src/Core.kt docs/Core.md is not docs-only).
#   (d) a run without --full: mode impacted.   (e) BUSY (lock held by another run), deferred (sibling session): exit codes
#       unchanged, verdict recorded; REUSED (the full receipt re-used); FAIL; UNVERIFIED -> "UNTESTED" (exit kept);
#       no line for a static run, a dry run, a clean tree.
#   (f) failure injection at the log path: a directory, a FIFO (no reader / a reader), a symlink to a regular file, a
#       dangling symlink, a hard-linked file, an unwritable directory, a file the gate cannot read: the exit code AND the
#       stdout/stderr bytes are IDENTICAL to the same run with the logging function switched off (launcher below), nothing
#       outside is touched, no hang.
#   (f2) a FIFO at every file the log could read (the active profile files): the gate ends as fast as without the log; the log call
#       itself may open nothing but its own files, read no profile, run no git and no process (a guard around the call);
#       write faults (ENOSPC, short write finished, torn line ended with a newline); a BaseException is not swallowed.
#   (g) 12 gates in parallel: every line is valid JSON, none lost.   (h) rotation: > 512 KB keeps the tail, bounded.
#   (i) no file name, absolute path, commit message, session id or transcript path in any line.
# "Logging switched off" = the same gate imported by a test-only launcher that replaces _log_gate_run by a no-op: the
# only difference between the two runs is the log call (the kit at 1b291aa, which has no log, was also compared by hand).
# Output normalisation for the byte comparison: durations (\d+.\d+s), clock times (HH:MM), the evidence log name
# (<stamp>[-n].log) and the receipt temp name (.tmp_full_pass.<random>) are masked, nothing else.
#   RUNLOG_KIT=<devkit dir>   test another copy of the kit (the pre-log one: RED; a mutant: must go red)
#   RUNLOG_PY=<python>        interpreter for the driver AND the gates (default python3; try /usr/bin/python3 = 3.9)
#   RUNLOG_BASE_KIT=<dir>     optional: a kit WITHOUT the log (1b291aa): every paired run is compared with it too (a line printed or an
#                             exit code changed anywhere in main(), not only inside the log function, shows up)
#   RUNLOG_TIMEOUT=<seconds>  bound of one gate run (default 240; a mutant that blocks on a FIFO is reported after this long)
#   RUNLOG_FAILFAST=1         stop at the first failed check (mutation runs)
#   Rotation constants asserted here: a file above 1.25 MiB is cut to its newest lines, at most 4000 lines and 1 MiB.
# bash 3.2 and Python 3.9 compatible; python stdlib only. Every gate run is bounded (240 s).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${RUNLOG_KIT:-$DEVKIT_DIR}"
PYBIN="${RUNLOG_PY:-python3}"
[ -f "$KIT/bin/post-fix-gate.py" ] || { echo "✖ no gate at $KIT/bin/post-fix-gate.py"; exit 1; }
TMP="$(mktemp -d)"
# BEFORE the trap: an empty $TMP would make the cleanup below a `rm -rf` of nothing sensible
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$KIT" "$TMP" <<'PY'
import difflib, json, os, re, signal, stat, subprocess, sys, time

KIT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
GATE = os.path.join(KIT, "bin", "post-fix-gate.py")
SESSION_LOCK = os.path.join(KIT, "bin", "session_lock.py")
BASE_GATE = os.path.join(os.environ["RUNLOG_BASE_KIT"], "bin", "post-fix-gate.py") if os.environ.get("RUNLOG_BASE_KIT") else None
TIMEOUT = float(os.environ.get("RUNLOG_TIMEOUT") or 240)
MAXB, KEEPB = 1280 * 1024, 1024 * 1024   # rotate above 1.25 MiB, keep at most 1 MiB
SESSION_ID = "SESS-SECRET-7731"
COMMIT_MSG = "SECRET-COMMIT-MSG-4410"
fails = 0
procs = []
print("python %s, kit %s" % (sys.version.split()[0], KIT), flush=True)


def ok(msg):
    print("✔ " + msg, flush=True)


def bad(msg):
    global fails
    fails += 1
    print("✖ " + msg, flush=True)
    if os.environ.get("RUNLOG_FAILFAST"):
        print("\ngate run log: FAILED (fail-fast)")
        sys.exit(1)


def chk(cond, good, why):
    if cond:
        ok(good)
    else:
        bad("%s: %s" % (good, why))
    return bool(cond)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=120).stdout.decode("utf-8", "replace").strip()


def put(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


# Test-only launcher: the gate unchanged, except that the log function is a no-op (when the kit has one).
LAUNCHER_OFF = os.path.join(TMP, "launcher_off.py")
put(LAUNCHER_OFF, '''import importlib.util, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_off", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_off"] = m
spec.loader.exec_module(m)
if hasattr(m, "_log_gate_run"):
    m._log_gate_run = lambda *a, **k: None
sys.exit(m.run_brief() if "--brief" in sys.argv[1:] else m.main())   # as the gate's own __main__ block
''')

MATRIX_FILE = "matrix.json"
POISON_N = [0]   # unique repo names for the case helpers


def make_repo(name, suite_a="exit 0", impacted=False, same_cmd=False, extra_suites=0):
    """A repo (basename pj-<name>) whose rule watches src/* and docs/*, with two fast suites; HEAD is clean."""
    root = os.path.join(TMP, name, "pj-" + name)
    os.makedirs(root)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    put(root + "/src/Core.kt", "fun a() = 1\n")
    put(root + "/docs/guide.md", "# guide\n")
    put(root + "/.claude/audit-gate/.gitignore", "*\n")   # what the gate writes there on its first run: both runs of a pair see one state
    put(root + "/a.sh", suite_a + "\n")
    put(root + "/b.sh", "exit 0\n")
    b = {"id": "REG-B", "name": "b suite", "command": "sh a.sh" if same_cmd else "sh b.sh"}
    a = {"id": "REG-A", "name": "a suite", "command": "sh a.sh"}
    if impacted:
        a["impacted_command"] = "sh a.sh {pytest_nodes}"
    tests = [a, b] + [{"id": "REG-EXTRA-%03d-%s" % (i, "x" * 20), "name": "extra %d" % i, "command": "sh b.sh # %d" % i} for i in range(extra_suites)]
    put(root + "/" + MATRIX_FILE, json.dumps({"project": "t", "rules": [
        {"component": "App", "watch_files": ["src/*", "docs/*"], "mandatory_regression_tests": tests}]}))
    git(root, "add", "-A")
    git(root, "commit", "-qm", COMMIT_MSG)
    return root


def edit(root, rel, text="changed\n"):
    with open(os.path.join(root, rel), "a") as f:
        f.write(text)


def log_path(root):
    common = git(root, "rev-parse", "--git-common-dir")
    return os.path.join(root, common, "postfix-gate", "runs.jsonl")


def read_log(root):
    """Parsed lines of runs.jsonl ([] when absent); raises ValueError on a line that is not JSON."""
    path = log_path(root)
    try:
        if not stat.S_ISREG(os.lstat(path).st_mode):   # a poisoned path (FIFO, link, directory) is never opened here: a FIFO would block
            return []
        with open(path, "rb") as f:
            raw = f.read()
    except OSError:
        return []
    return [json.loads(l) for l in raw.decode("utf-8").splitlines() if l.strip()]


def gate_env(root, extra=None):
    drop = ("CI", "POSTFIX_GATE_FULL", "POSTFIX_GATE_FORCE_FULL", "DEVKIT_GATE_CACHE", "DEVKIT_SESSION_ID",
            "CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID", "GATE_TOTAL_BUDGET_S", "TEST_RUN_LOCK_WAIT_S", "FLAKY_RETRY")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k not in drop}
    env.update({"CLAUDE_PROJECT_DIR": root, "VACUITY_REVERT": "0", "FLAKY_RETRY": "0"})
    env.update(extra or {})
    return env


def run_gate(root, flags, env=None, off=False, wait=True, launcher=None, gate=None, timeout=None):
    """(rc, stdout, stderr) of one gate run, bounded; rc None on a timeout (the process group is killed)."""
    launcher = LAUNCHER_OFF if off else launcher
    cmd = [PY] + ([launcher] if launcher else []) + [gate or GATE, "--matrix", os.path.join(root, MATRIX_FILE), "--lang", "en",
                                                     "--no-checklist"] + list(flags)
    p = subprocess.Popen(cmd, cwd=root, env=gate_env(root, env), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         start_new_session=True)
    if not wait:
        procs.append(p)
        return p
    try:
        out, err = p.communicate(timeout=timeout or TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = p.communicate()
        return None, out, err
    return p.returncode, out, err


def norm(b):
    t = b.decode("utf-8", "replace")
    t = re.sub(r"\d+\.\d+s", "<s>", t)
    t = re.sub(r"\d{8}-\d{6}(-\d+)?\.log", "<evidence>.log", t)   # .agents/evidence/<suite>/<stamp>[-n].log
    t = re.sub(r"\.tmp_full_pass\.\w+", ".tmp_full_pass.<rnd>", t)   # the receipt's random temp name, in an error line
    return re.sub(r"\b\d\d:\d\d\b", "<hm>", t)


def same_as_off(label, root, flags, env=None, prep=None):
    """Run the gate with logging switched off, then normally, in the same state: rc and output must be identical.
    Returns (rc_off, rc_on, out_on) so that the caller can check the log of the normal run."""
    if prep:
        prep()
    r0 = run_gate(root, flags, env, off=True)
    try:
        before = len(read_log(root))
    except ValueError:   # a poisoned path that holds a non-JSON file
        before = -1
    if prep:
        prep()
    r1 = run_gate(root, flags, env)
    if BASE_GATE:   # the kit without any log code: same rc and bytes as the logging gate
        if prep:
            prep()
        rb = run_gate(root, flags, env, gate=BASE_GATE)
        chk(rb[0] == r1[0] and norm(rb[1]) == norm(r1[1]) and norm(rb[2]) == norm(r1[2]),
            "%s: same exit code and bytes as the kit without the log (RUNLOG_BASE_KIT)" % label,
            "base rc %s, on rc %s\n%s" % (rb[0], r1[0], "\n".join(list(difflib.unified_diff(norm(rb[1] + rb[2]).splitlines(), norm(r1[1] + r1[2]).splitlines(), "base", "on", lineterm="", n=0))[:14])))
    chk(r0[0] is not None and r1[0] is not None, "%s: both runs end (no hang)" % label, "timeout: off=%s on=%s" % (r0[0], r1[0]))
    chk(r0[0] == r1[0], "%s: same exit code with and without the log (%s)" % (label, r1[0]), "off=%s on=%s" % (r0[0], r1[0]))
    same_out = norm(r0[1]) == norm(r1[1])
    same_err = norm(r0[2]) == norm(r1[2])
    diff = "\n".join(list(difflib.unified_diff(norm(r0[1] + r0[2]).splitlines(), norm(r1[1] + r1[2]).splitlines(), "off", "on", lineterm="", n=0))[:14])
    chk(same_out and same_err, "%s: same stdout and stderr bytes" % label,
        "stdout %s, stderr %s\n%s" % ("same" if same_out else "DIFFERS", "same" if same_err else "DIFFERS", diff))
    return r0, r1, before


def hold_lock(root):
    held, release = os.path.join(TMP, "held"), os.path.join(TMP, "release")
    for f in (held, release):
        try:
            os.unlink(f)
        except OSError:
            pass
    code = ("import fcntl,os,sys,time\n"
            "d=sys.argv[1]+'/.claude/audit-gate'\nos.makedirs(d,exist_ok=True)\n"
            "f=open(d+'/test_run.lock','a')\nfcntl.flock(f,fcntl.LOCK_EX)\nopen(sys.argv[2],'w').close()\n"
            "for _ in range(1500):\n    if os.path.exists(sys.argv[3]): break\n    time.sleep(0.1)\n")
    p = subprocess.Popen([PY, "-I", "-c", code, root, held, release], start_new_session=True)
    procs.append(p)
    end = time.monotonic() + 20
    while not os.path.exists(held) and time.monotonic() < end:
        time.sleep(0.05)
    return p, release


def release_lock(holder):
    p, release = holder
    open(release, "w").close()
    try:
        p.wait(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()


# ── (a) docs-only --full ─────────────────────────────────────────────────────────────────────────────────────
def json_of(out):
    for l in reversed(out.decode("utf-8", "replace").splitlines()):
        if l.startswith("{"):
            return json.loads(l)
    return {}


def check_fields(label, r, j=None):
    """Shape of one line + agreement with the gate's own --json output."""
    keys = ("v", "ts", "epoch", "project", "mode", "source", "exit", "verdict", "deferred", "busy", "reused_full_pass",
            "n_changed", "n_docs", "docs_only", "no_test_only", "suites", "suites_wall_s", "total_wall_s",
            "force_full", "impacted_run")
    missing = [k for k in keys if k not in r]
    extra = [k for k in r if k not in keys and k != "suites_cut"]
    chk(not missing and not extra and r.get("v") == 1, "%s: line has every field and no other (n_code is gone: it read the profile), v=1" % label,
        "missing %s extra %s in %s" % (missing, extra, r))
    chk(re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d", str(r.get("ts"))) and abs(time.time() - r.get("epoch", 0)) < 600,
        "%s: ts is ISO-8601 local with offset, epoch is now" % label, "ts=%r epoch=%r" % (r.get("ts"), r.get("epoch")))
    chk(isinstance(r.get("total_wall_s"), (int, float)) and r["total_wall_s"] >= (r.get("suites_wall_s") or 0)
        and all(isinstance(s, list) and len(s) == 3 for s in r.get("suites", [])), "%s: wall times and [id,status,secs] suites are sane" % label, repr(r))
    chk(abs((r.get("suites_wall_s") or 0) - sum(s[2] for s in r.get("suites", []) if s[2] is not None)) < 0.011,
        "%s: suites_wall_s is the sum of the seconds of the suites that ran" % label, repr(r))
    if j:
        chk(j.get("exit_code") == r.get("exit") and j.get("busy") == r.get("busy") and j.get("full_run_required") == r.get("impacted_run")
            and len(j.get("files", [])) == r.get("n_changed"),
            "%s: exit / busy / impacted_run / n_changed agree with the gate's own --json" % label,
            "json exit=%s busy=%s full_run_required=%s files=%d, line %s" % (j.get("exit_code"), j.get("busy"), j.get("full_run_required"),
                                                                          len(j.get("files", [])), r))
        ran = {t["id"]: t for t in j.get("regression_tests", [])}
        good = all(abs((s[2] or 0) - float(str(ran[s[0]].get("duration", "0")).rstrip("s") or 0)) < 0.011 for s in r.get("suites", [])
                   if s[2] is not None and s[0] in ran and str(ran[s[0]].get("duration", "")).endswith("s"))
        chk(good, "%s: suite seconds equal the gate's recorded durations" % label, repr(r.get("suites")))


root = make_repo("docs")
edit(root, "docs/guide.md")
r0, r1, before = same_as_off("a docs-only --full", root, ["--run-tests", "--full", "--no-cache", "--json"])
chk(before == 0, "logging switched off writes no line", "%d lines" % before)
recs = read_log(root)
chk(len(recs) == 1, "a docs-only --full run: exactly one line", "%d lines" % len(recs))
if recs:
    r = recs[0]
    check_fields("docs-only", r, json_of(r1[1]))
    chk(r["mode"] == "full" and r["docs_only"] is True and r["no_test_only"] is True and r["n_changed"] == 1 and r["n_docs"] == 1
        and r["source"] == "cli" and r["exit"] == 0 and r["verdict"] == "PASS" and r["force_full"] is False
        and r["impacted_run"] is False and r["busy"] is False and r["deferred"] is False and r["reused_full_pass"] is False
        and r["project"] == "pj-docs", "docs-only: mode full, docs_only, no_test_only, 1 doc file, no code, PASS, cli", repr(r))
    chk([s[0] for s in r["suites"]] == ["REG-A", "REG-B"] and all(s[1] == "PASS" and isinstance(s[2], (int, float)) for s in r["suites"])
        # the sum, not "> 0": an `exit 0` suite takes ~2 ms on Linux and rounds to 0.00 s (it is > 0 only where a spawn is slower)
        and r["suites_wall_s"] == round(sum(s[2] for s in r["suites"]), 2),
        "docs-only: both suites present with PASS and their seconds", repr(r["suites"]))

# docs + LICENSE + agent state: no_test_only true but docs_only false (the gate's own `docs_only` local is the no_test_only one)
root = make_repo("state")
edit(root, "docs/guide.md")
put(root + "/LICENSE", "license\n")
put(root + "/.antigravity-pm.json", "{}\n")
rc, out, err = run_gate(root, ["--run-tests", "--full", "--no-cache"])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["docs_only"] is False and recs[0]["no_test_only"] is True and recs[0]["n_docs"] == 2 and recs[0]["n_changed"] == 3
    , "doc + LICENSE + agent state: docs_only false, no_test_only true, n_docs 2 of 3", repr(recs))

# two suites sharing one command run it once: the second has no seconds (its cost is not counted twice)
root = make_repo("dup", same_cmd=True)
edit(root, "docs/guide.md")
rc, out, err = run_gate(root, ["--run-tests", "--full", "--no-cache"])
recs = read_log(root)
chk(len(recs) == 1 and [s[0] for s in recs[0]["suites"]] == ["REG-A", "REG-B"] and recs[0]["suites"][0][2] is not None and recs[0]["suites"][1][2] is None,
    "two suites with one command: seconds only on the one that ran", repr(recs))

# a linked worktree: its runs go to the COMMON dir's log (they survive the worktree's removal), not to the worktree's own git dir
root = make_repo("wtmain")
wt = os.path.join(TMP, "wtmain", "wt-linked")
git(root, "worktree", "add", "-q", "-b", "wtb", wt)
edit(wt, "docs/guide.md")
rc, out, err = run_gate(wt, ["--run-tests", "--full", "--no-cache"])
wt_gitdir = git(wt, "rev-parse", "--absolute-git-dir")
recs = read_log(root)
chk(rc == 0 and len(recs) == 1 and recs[0]["project"] == "wt-linked" and recs[0]["docs_only"] is True
    and not os.path.exists(os.path.join(wt_gitdir, "postfix-gate", "runs.jsonl")) and wt_gitdir != git(root, "rev-parse", "--absolute-git-dir"),
    "a linked worktree logs into the common dir (<git-common-dir>/postfix-gate/runs.jsonl), not its own git dir", "rc %s recs %r wt gitdir %s" % (rc, recs, wt_gitdir))

# a matrix with 100 suites: the line stays under 3 KB (the suites list is cut, `suites_cut` says so) and is still one valid line
root = make_repo("many", extra_suites=100)
edit(root, "docs/guide.md")
rc, out, err = run_gate(root, ["--run-tests", "--full", "--no-cache"])
try:
    raw = open(log_path(root), "rb").read()
    recs = read_log(root)
except (OSError, ValueError):
    raw, recs = b"", []
chk(rc == 0 and len(recs) == 1 and len(raw) <= 3000 and recs[0].get("suites_cut") is True and 0 < len(recs[0]["suites"]) < 102
    and recs[0]["n_changed"] == 1 and recs[0]["verdict"] == "PASS", "102 suites: the line is cut to <= 3000 bytes (suites_cut), still one valid line",
    "rc %s lines %d bytes %d keys %s" % (rc, len(recs), len(raw), sorted(recs[0])[:6] if recs else None))

# the log call itself: no lock, no subprocess, nothing printed (a guard around it; a violation or an error leaves a marker or no line)
LAUNCHER_GUARD = os.path.join(TMP, "launcher_guard.py")
put(LAUNCHER_GUARD, '''import importlib.util, io, os, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_guard", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_guard"] = m
spec.loader.exec_module(m)
import fcntl, subprocess
orig = m._log_gate_run
def guarded(*a, **k):
    bad = []
    def boom(name):
        def f(*x, **y):
            bad.append(name)
            raise AssertionError("forbidden in the run log: " + name)
        return f
    saved = [(subprocess, n, getattr(subprocess, n)) for n in ("Popen", "run", "call", "check_call", "check_output")]
    saved += [(fcntl, n, getattr(fcntl, n)) for n in ("flock", "lockf")] + [(m, "acquire_test_run_lock", m.acquire_test_run_lock)]
    import builtins, io
    saved += [(m, n, getattr(m, n)) for n in ("get_project_dir", "get_repo_root", "profile_source_exts", "get_base_dir", "needs_no_test") if hasattr(m, n)]
    saved += [(builtins, "open", builtins.open), (io, "open", io.open)]
    allowed = os.environ["GUARD_ALLOWED"]
    def only_own(name, real):
        def f(path, *x, **y):
            ap = os.path.abspath(os.fsdecode(path)) if isinstance(path, (str, bytes)) else None
            if ap is None or not (ap == allowed or ap.startswith(allowed + os.sep)):
                bad.append("%s(%r)" % (name, path))
                raise AssertionError("the log call may only touch its own files: " + name)
            return real(path, *x, **y)
        return f
    for n in ("open", "listdir", "scandir", "stat", "lstat", "readlink", "unlink", "mkdir"):
        if hasattr(os, n):
            saved.append((os, n, getattr(os, n)))
    out, err, so, se = io.StringIO(), io.StringIO(), sys.stdout, sys.stderr
    for o, n, v in saved:
        setattr(o, n, only_own(n, v) if o is os else boom(n))
    sys.stdout, sys.stderr = out, err
    try:
        return orig(*a, **k)
    finally:
        sys.stdout, sys.stderr = so, se
        for o, n, v in saved:
            setattr(o, n, v)
        if bad or out.getvalue() or err.getvalue():
            with open(os.environ["GUARD_MARK"], "a") as f:
                f.write("forbidden=%r stdout=%r stderr=%r\\n" % (bad, out.getvalue()[:80], err.getvalue()[:80]))
m._log_gate_run = guarded
sys.exit(m.main())
''')
root = make_repo("guard")
edit(root, "docs/guide.md")
mark = os.path.join(TMP, "guard.mark")
os.makedirs(os.path.join(git(root, "rev-parse", "--absolute-git-dir"), "postfix-gate"), exist_ok=True)
rc, out, err = run_gate(root, ["--run-tests", "--full", "--no-cache"],
                        {"GUARD_MARK": mark, "GUARD_ALLOWED": os.path.join(git(root, "rev-parse", "--absolute-git-dir"), "postfix-gate")}, launcher=LAUNCHER_GUARD)
recs = read_log(root)
chk(rc == 0 and len(recs) == 1 and not os.path.exists(mark), "the log call takes no lock, starts no process, runs no git, reads no profile, opens only its own files, prints nothing, and still logs its line",
    "rc %s, lines %d, violations: %s" % (rc, len(recs), open(mark).read() if os.path.exists(mark) else "none"))

# --brief (what the Stop hook runs): main() runs inside run_brief, one line, same output
root = make_repo("brief")
edit(root, "docs/guide.md")
r0, r1, _ = same_as_off("--brief", root, ["--run-tests", "--full", "--no-cache", "--brief"])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["mode"] == "full" and recs[0]["docs_only"] is True and recs[0]["exit"] == r1[0], "--brief: one line, as without it", repr(recs))

# --force-full and a source=hook line (a session id and a transcript are passed: neither may leak, checked in (i))
transcript = os.path.join(TMP, "transcript-secret.jsonl")
put(transcript, "")
root = make_repo("hook")
edit(root, "docs/guide.md")
rc, out, err = run_gate(root, ["--run-tests", "--force-full", "--session", SESSION_ID, "--transcript", transcript])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["source"] == "hook" and recs[0]["mode"] == "full" and recs[0]["force_full"] is True and recs[0]["exit"] == rc,
    "--session/--transcript: source hook; --force-full: force_full true", repr(recs))

# ── (b) code change, (c) doc + code ──────────────────────────────────────────────────────────────────────────
root = make_repo("code")
edit(root, "src/Core.kt", "fun b() = 2\n")
r0, r1, _ = same_as_off("a code change", root, ["--run-tests", "--full", "--no-cache", "--json"])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["docs_only"] is False and recs[0]["no_test_only"] is False
    and recs[0]["n_docs"] == 0 and recs[0]["n_changed"] == 1, "code change: docs_only false, no_test_only false", repr(recs))
root = make_repo("both")
edit(root, "src/Core.kt", "fun b() = 2\n")
edit(root, "docs/guide.md")
r0, r1, _ = same_as_off("a doc + code change", root, ["--run-tests", "--full", "--no-cache", "--json"])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["docs_only"] is False and recs[0]["no_test_only"] is False and recs[0]["n_docs"] == 1
    and recs[0]["n_changed"] == 2, "doc + code: docs_only false, n_docs 1, n_changed 2", repr(recs))

# renames and deletes: the SOURCE of a rename and a deleted file are changed files too
def rename_case(label, setup, want_docs_only, want_n_changed, want_n_docs, want_no_test_only=None):
    POISON_N[0] += 1
    root = make_repo("rn%d" % POISON_N[0])
    setup(root)
    r0, r1, _ = same_as_off(label, root, ["--run-tests", "--full", "--no-cache"])
    recs = read_log(root)
    chk(len(recs) == 1 and recs[0]["docs_only"] is want_docs_only and recs[0]["n_changed"] == want_n_changed and recs[0]["n_docs"] == want_n_docs
        and (want_no_test_only is None or recs[0]["no_test_only"] is want_no_test_only),
        "%s: docs_only %s, n_changed %d, n_docs %d" % (label, want_docs_only, want_n_changed, want_n_docs), repr(recs))


rename_case("rename code to doc", lambda r: git(r, "mv", "src/Core.kt", "docs/Core.md"), False, 2, 1, False)
rename_case("rename doc to code", lambda r: git(r, "mv", "docs/guide.md", "src/Guide.kt"), False, 2, 1, False)
rename_case("rename doc to doc", lambda r: git(r, "mv", "docs/guide.md", "docs/guide2.md"), True, 2, 2, True)
rename_case("delete code and edit doc", lambda r: (git(r, "rm", "-q", "src/Core.kt"), edit(r, "docs/guide.md")), False, 2, 1, False)
rename_case("delete a doc", lambda r: git(r, "rm", "-q", "docs/guide.md"), True, 1, 1, True)

# ── (d) a run without --full ─────────────────────────────────────────────────────────────────────────────────
root = make_repo("impacted", impacted=True)
edit(root, "src/Core.kt", "fun b() = 2\n")
r0, r1, _ = same_as_off("a run without --full", root, ["--run-tests", "--no-cache", "--json"])
recs = read_log(root)
chk(len(recs) == 1 and recs[0]["mode"] == "impacted" and recs[0]["force_full"] is False and recs[0]["exit"] == r1[0],
    "no --full: mode impacted", repr(recs))
if recs:
    check_fields("impacted", recs[0], json_of(r1[1]))

# ── (e) BUSY, deferred, REUSED, FAIL, UNVERIFIED, and the runs that log nothing ───────────────────────────
root = make_repo("busy")
edit(root, "docs/guide.md")
holder = hold_lock(root)
r0, r1, _ = same_as_off("BUSY", root, ["--run-tests", "--full", "--no-cache", "--json"], {"TEST_RUN_LOCK_WAIT_S": "1"})
release_lock(holder)
recs = read_log(root)
chk(r1[0] == 4 and len(recs) == 1 and recs[0]["verdict"] == "BUSY" and recs[0]["busy"] is True and recs[0]["exit"] == 4
    and all(s[1] == "UNTESTED" and s[2] is None for s in recs[0]["suites"]) and recs[0]["suites"],
    "BUSY: exit 4 kept, verdict BUSY, busy true, suites UNTESTED with no seconds", repr(recs))
if recs:
    check_fields("busy", recs[0], json_of(r1[1]))

root = make_repo("deferred")
edit(root, "docs/guide.md")
subprocess.run([PY, SESSION_LOCK, "--register", "--session", "S2", root], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
r0, r1, _ = same_as_off("deferred --full", root, ["--run-tests", "--full", "--session", "S1", "--json"])
recs = read_log(root)
chk(r1[0] == 5 and len(recs) == 1 and recs[0]["verdict"] == "DEFERRED" and recs[0]["deferred"] is True and recs[0]["exit"] == 5
    and recs[0]["mode"] == "full" and recs[0]["source"] == "hook", "deferred --full: exit 5 kept, verdict DEFERRED, mode full", repr(recs))
r0, r1, _ = same_as_off("deferred by POSTFIX_GATE_FULL=1 (the Stop hook)", root, ["--run-tests", "--session", "S1"], {"POSTFIX_GATE_FULL": "1"})
recs = read_log(root)
chk(r1[0] == 0 and len(recs) == 2 and recs[-1]["verdict"] == "DEFERRED" and recs[-1]["exit"] == 0 and recs[-1]["deferred"] is True,
    "deferred without --full: exit 0 kept, verdict DEFERRED", repr(recs[-1:]))

root = make_repo("reused")
edit(root, "docs/guide.md")
rc1, o1, e1 = run_gate(root, ["--run-tests", "--full"])
rc2, o2, e2 = run_gate(root, ["--run-tests", "--full"])
recs = read_log(root)
chk(rc1 == 0 and rc2 == 0 and len(recs) == 2 and recs[0]["verdict"] == "PASS" and recs[1]["verdict"] == "REUSED"
    and recs[1]["reused_full_pass"] is True and all(s[2] is None for s in recs[1]["suites"]) and recs[1]["suites"]
    and recs[1]["suites_wall_s"] == 0, "second --full of the same content: verdict REUSED, reused_full_pass, no suite seconds", repr(recs))

root = make_repo("fail", suite_a="exit 1")
edit(root, "src/Core.kt", "fun b() = 2\n")
r0, r1, _ = same_as_off("a failing suite", root, ["--run-tests", "--full", "--no-cache"])
recs = read_log(root)
chk(r1[0] == 1 and len(recs) == 1 and recs[0]["verdict"] == "FAIL" and recs[0]["exit"] == 1 and ["REG-A", "FAIL"] == recs[0]["suites"][0][:2],
    "a failing suite: exit 1 kept, verdict FAIL", repr(recs))

root = make_repo("unver")
put(root + "/other/Elsewhere.kt", "fun x() = 1\n")   # code no rule watches: UNVERIFIED (exit 2)
r0, r1, _ = same_as_off("UNVERIFIED (uncovered code)", root, ["--run-tests", "--full", "--no-cache"])
recs = read_log(root)
chk(r1[0] == 2 and len(recs) == 1 and recs[0]["exit"] == 2 and recs[0]["verdict"] == "UNTESTED",
    "UNVERIFIED exit 2 is recorded as verdict UNTESTED with exit 2", repr(recs))

root = make_repo("none")
edit(root, "docs/guide.md")
for label, flags in (("a static run (no --run-tests)", []), ("--dry-run", ["--run-tests", "--dry-run"]), ("--help", ["--help"]),
                     ("--staged", ["--staged"])):
    rc, out, err = run_gate(root, flags)
    chk(rc is not None and read_log(root) == [], "%s logs nothing (exit %s)" % (label, rc), "lines: %r" % (read_log(root),))
root = make_repo("clean")
rc, out, err = run_gate(root, ["--run-tests", "--full"])
chk(rc == 3 and read_log(root) == [], "a clean tree (exit 3, nothing to audit) logs nothing", "rc %s, %r" % (rc, read_log(root)))

# ── (f) failure injection at the log path ─────────────────────────────────────────────────────────────────────
outside = os.path.join(TMP, "outside.txt")


def poison_case(label, setup, after, flags=("--run-tests", "--full", "--no-cache"), cleanup=None):
    POISON_N[0] += 1
    root = make_repo("p%d_%s" % (POISON_N[0], re.sub(r"[^a-z0-9]", "", label.lower())[:12]))
    edit(root, "docs/guide.md")
    os.makedirs(os.path.dirname(log_path(root)), exist_ok=True)
    put(outside, "SENTINEL-OUTSIDE\n")
    state = setup(log_path(root), root)
    r0, r1, _ = same_as_off(label, root, list(flags), prep=None)
    after(log_path(root), state, label)
    if cleanup:
        cleanup(log_path(root), state)
    return r1


def a_dir(path, root):
    os.makedirs(path)


def dir_after(path, state, label):
    chk(os.path.isdir(path) and os.listdir(path) == [], "%s: still an empty directory" % label, "changed")


poison_case("runs.jsonl is a directory", a_dir, dir_after)


def a_symlink(path, root):
    os.symlink(outside, path)


def symlink_after(path, state, label):
    with open(outside, "rb") as f:
        data = f.read()
    chk(data == b"SENTINEL-OUTSIDE\n" and os.path.islink(path), "%s: the target file was not written, link untouched" % label,
        "target now %r" % data[-120:])


poison_case("runs.jsonl is a symlink to a regular file", a_symlink, symlink_after)


def dangling(path, root):
    os.symlink(os.path.join(TMP, "never-created.txt"), path)


poison_case("runs.jsonl is a dangling symlink", dangling,
            lambda path, st, label: chk(not os.path.exists(os.path.join(TMP, "never-created.txt")), "%s: the target was not created" % label, "created"))


def to_devnull(path, root):
    os.symlink("/dev/null", path)


poison_case("runs.jsonl is a symlink to /dev/null", to_devnull,
            lambda path, st, label: chk(os.path.islink(path) and os.readlink(path) == "/dev/null", "%s: the link is untouched" % label, "changed"))


def hardlink(path, root):
    os.link(outside, path)


def hardlink_after(path, state, label):
    with open(outside, "rb") as f:
        data = f.read()
    chk(data == b"SENTINEL-OUTSIDE\n", "%s: the other name of the file was not appended to" % label, "target now %r" % data[-120:])


poison_case("runs.jsonl is a hard link to another file", hardlink, hardlink_after)


def fifo_noreader(path, root):
    os.mkfifo(path)


def fifo_after(path, state, label):
    chk(stat_is_fifo(path), "%s: still a FIFO" % label, "changed")


def stat_is_fifo(path):
    try:
        return stat.S_ISFIFO(os.lstat(path).st_mode)
    except OSError:
        return False


poison_case("runs.jsonl is a FIFO, no reader", fifo_noreader, fifo_after)


def fifo_reader(path, root):
    os.mkfifo(path)
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)   # a reader: a write-open now succeeds, the line must still not be sent
    return fd


def fifo_reader_after(path, fd, label):
    try:
        got = os.read(fd, 65536)
    except OSError:
        got = b""
    os.close(fd)
    chk(got == b"" and stat_is_fifo(path), "%s: nothing was written to the pipe" % label, "pipe got %r" % got[:120])


poison_case("runs.jsonl is a FIFO with a reader", fifo_reader, fifo_reader_after)


def unwritable(path, root):
    os.chmod(os.path.dirname(path), 0o500)


def unwritable_after(path, state, label):
    chk(not os.path.exists(path), "%s: no file appeared" % label, "exists")


if os.geteuid() == 0:
    ok("unwritable directory: skipped (running as root, chmod does not restrict)")
else:
    poison_case("the postfix-gate directory is read-only", unwritable, unwritable_after,
                cleanup=lambda path, st: os.chmod(os.path.dirname(path), 0o700))


def unreadable_file(path, root):
    put(path, '{"v":1,"old":true}\n')
    os.chmod(path, 0o000)


def unreadable_after(path, state, label):
    os.chmod(path, 0o600)
    with open(path) as f:
        data = f.read()
    chk(data == '{"v":1,"old":true}\n', "%s: left as it was" % label, "now %r" % data[-120:])


if os.geteuid() != 0:
    poison_case("runs.jsonl exists but is mode 000", unreadable_file, unreadable_after)

# ── (f2) a FIFO where the log might read: the gate must end as it does without the log ─────────────────────────────
def fifo_read_case(label, rel):
    POISON_N[0] += 1
    root = make_repo("ff%d" % POISON_N[0])
    edit(root, "docs/guide.md")
    os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
    os.mkfifo(os.path.join(root, rel))
    flags = ["--run-tests", "--full", "--allow-no-tests", "--no-cache"]
    t0 = time.time()
    r0 = run_gate(root, flags, off=True, timeout=30)
    t_off = time.time() - t0
    if r0[0] is None:
        ok("%s: the gate itself hangs on it without the log (not the log's doing)" % label)
        return
    t0 = time.time()
    r1 = run_gate(root, flags, timeout=30)
    t_on = time.time() - t0
    chk(r1[0] is not None and r1[0] == r0[0] and norm(r0[1]) == norm(r1[1]) and norm(r0[2]) == norm(r1[2]) and t_on < t_off + 10,
        "%s: with the log the gate ends as without it (%.1f s vs %.1f s), same exit code and bytes" % (label, t_on, t_off),
        "rc off=%s on=%s, %.1fs vs %.1fs" % (r0[0], r1[0], t_off, t_on))


fifo_read_case("FIFO at .agents/active-profile/profile.json", ".agents/active-profile/profile.json")
fifo_read_case("FIFO at .agents/active-profile.json", ".agents/active-profile.json")
fifo_read_case("FIFO at .active-profile.json", ".active-profile.json")
fifo_read_case("FIFO at .agents/active-profile (the folder)", ".agents/active-profile")

# ── write faults and a BaseException inside the log call ───────────────────────────────────────────────────────────
LAUNCHER_FAULT = os.path.join(TMP, "launcher_fault.py")
put(LAUNCHER_FAULT, '''import errno, importlib.util, os, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_fault", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_fault"] = m
spec.loader.exec_module(m)
mode = os.environ["LOG_FAULT"]
real_write = os.write
calls = []
def fake_write(fd, data):
    calls.append(len(data))
    if mode == "enospc":
        raise OSError(errno.ENOSPC, "No space left on device")
    if mode == "short" and len(calls) == 1:
        return real_write(fd, data[:40])
    if mode == "torn":
        if len(calls) == 1:
            return real_write(fd, data[:40])
        if len(calls) == 2:
            raise OSError(errno.ENOSPC, "No space left on device")
    return real_write(fd, data)
orig = m._log_gate_run
def wrapped(*a, **k):
    if mode in ("enospc", "short", "torn"):
        os.write = fake_write
    elif mode == "runtime":
        m._run_log_suites = lambda *x, **y: (_ for _ in ()).throw(RuntimeError("injected"))
    elif mode == "kbint":
        m._run_log_suites = lambda *x, **y: (_ for _ in ()).throw(KeyboardInterrupt())
    elif mode == "sysexit":
        m._run_log_suites = lambda *x, **y: (_ for _ in ()).throw(SystemExit(7))
    try:
        return orig(*a, **k)
    finally:
        os.write = real_write
m._log_gate_run = wrapped
sys.exit(m.main())
''')


def fault_case(mode):
    root = make_repo("ft" + mode)
    edit(root, "docs/guide.md")
    flags = ["--run-tests", "--full", "--no-cache"]
    r0 = run_gate(root, flags, off=True)
    r1 = run_gate(root, flags, {"LOG_FAULT": mode}, launcher=LAUNCHER_FAULT)
    path = log_path(root)
    raw = open(path, "rb").read() if os.path.isfile(path) else b""
    if mode in ("enospc", "runtime"):
        chk(r1[0] == r0[0] and norm(r1[1]) == norm(r0[1]) and norm(r1[2]) == norm(r0[2]) and raw.count(b"{") <= 0,
            "log fault %s: the gate's exit code and bytes are untouched, nothing logged" % mode, "rc %s vs %s, log %r" % (r1[0], r0[0], raw[:80]))
    elif mode == "short":
        try:
            recs = read_log(root)
        except ValueError:
            recs = []
        chk(r1[0] == r0[0] and len(recs) == 1 and raw.endswith(b"\n"), "log fault short write: the line is finished, whole and valid", "rc %s, %r" % (r1[0], raw[-80:]))
    elif mode == "torn":
        chk(r1[0] == r0[0] and raw.endswith(b"\n") and b"\n" not in raw[:-1], "log fault torn line: ended with a newline, so it cannot swallow the next line", "rc %s, %r" % (r1[0], raw[-80:]))
        r2 = run_gate(root, flags, off=False)
        lines = open(path, "rb").read().split(b"\n")
        try:
            last_ok = json.loads(lines[-2].decode("utf-8"))["v"] == 1
        except (ValueError, IndexError):
            last_ok = False
        chk(last_ok and len(lines) == 3, "log fault torn line: the next run's line is its own whole line", "lines %r" % lines[-3:])
    elif mode == "kbint":
        chk(r1[0] != r0[0] and b"KeyboardInterrupt" in r1[2], "a KeyboardInterrupt inside the log call is NOT swallowed", "rc %s vs %s, stderr %r" % (r1[0], r0[0], r1[2][-120:]))
    elif mode == "sysexit":
        chk(r1[0] == 7, "a SystemExit inside the log call is NOT swallowed (exit 7)", "rc %s" % r1[0])


for fm in ("enospc", "runtime", "short", "torn", "kbint", "sysexit"):
    fault_case(fm)

# the log file is created private (0600), and a stale temp file of a dead rotation is removed by the next rotation
root = make_repo("mode")
edit(root, "docs/guide.md")
run_gate(root, ["--run-tests", "--full", "--no-cache"])
chk(os.path.isfile(log_path(root)) and stat.S_IMODE(os.stat(log_path(root)).st_mode) == 0o600, "runs.jsonl is created with mode 0600", oct(os.stat(log_path(root)).st_mode))

# ── (g) 12 gates in parallel ──────────────────────────────────────────────────────────────────────────────────
root = make_repo("par")
edit(root, "docs/guide.md")
ps = [run_gate(root, ["--run-tests", "--full"], {"TEST_RUN_LOCK_WAIT_S": "0"}, wait=False) for _ in range(12)]
rcs = []
for p in ps:
    try:
        p.communicate(timeout=280)
        rcs.append(p.returncode)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        rcs.append(None)
try:
    recs = read_log(root)
    valid = True
except ValueError as e:
    recs, valid = [], False
chk(valid and len(recs) == 12, "12 parallel gate runs: 12 lines, every one valid JSON", "valid=%s lines=%d rcs=%s" % (valid, len(recs), rcs))
chk(all(r["verdict"] in ("PASS", "BUSY", "REUSED") for r in recs) and all(r["exit"] == (4 if r["verdict"] == "BUSY" else 0) for r in recs)
    and sorted(rc for rc in rcs if rc is not None) == sorted(r["exit"] for r in recs),
    "12 parallel runs: verdicts PASS/BUSY/REUSED, each line's exit is that run's exit", "rcs=%s verdicts=%s" % (rcs, [r["verdict"] for r in recs]))

# ── (h) rotation ──────────────────────────────────────────────────────────────────────────────────────────────
def prefill(root, n, width, with_seq=True):
    path = log_path(root)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for i in range(n):
            f.write(json.dumps({"v": 1, "seq": i, "pad": "x" * width}) + "\n")
    return path


root = make_repo("rot1")
edit(root, "docs/guide.md")
path = prefill(root, 12000, 100)
size0 = os.path.getsize(path)
rc, out, err = run_gate(root, ["--run-tests", "--full"])
lines = open(path).read().splitlines()
seqs = [json.loads(l).get("seq") for l in lines[:-1]]
chk(size0 > MAXB and os.path.getsize(path) <= KEEPB and len(lines) == 4000 and seqs == list(range(11999 - len(seqs) + 1, 12000))
    and json.loads(lines[-1]).get("mode") == "full" and not [f for f in os.listdir(os.path.dirname(path)) if f.endswith(".tmp")],
    "rotation: a %d KB file keeps its newest lines (<= 4000, <= 1 MiB), the new line is last, no temp file left" % (size0 // 1024),
    "size %d lines %d first seqs %s" % (os.path.getsize(path), len(lines), seqs[:3]))
root = make_repo("rot2")
edit(root, "docs/guide.md")
path = prefill(root, 9000, 2500)   # ~23 MB of long lines: only the tail may be read and kept
rc, out, err = run_gate(root, ["--run-tests", "--full"])
lines = open(path).read().splitlines()
seqs = [json.loads(l).get("seq") for l in lines[:-1]]
chk(os.path.getsize(path) <= KEEPB and len(lines) > 50 and seqs == list(range(8999 - len(seqs) + 1, 9000)) and json.loads(lines[-1]).get("mode") == "full",
    "rotation: a 23 MB file of long lines is cut to its newest lines, still <= 1 MiB", "size %d lines %d" % (os.path.getsize(path), len(lines)))
root = make_repo("rot3")
edit(root, "docs/guide.md")
path = prefill(root, 50, 100)
old = open(path, "rb").read()
rc, out, err = run_gate(root, ["--run-tests", "--full"])
new = open(path, "rb").read()
chk(new.startswith(old) and new.count(b"\n") == 51, "a small file is only appended to (no rotation under 1.25 MiB)", "lines %d" % new.count(b"\n"))

# between the old 512 KB cap and the new 1.25 MiB cap nothing is rotated (retention: the whole file stays)
root = make_repo("rot4")
edit(root, "docs/guide.md")
path = prefill(root, 9000, 100)
old = open(path, "rb").read()
rc, out, err = run_gate(root, ["--run-tests", "--full"])
new = open(path, "rb").read()
chk(512 * 1024 < len(old) < MAXB and new.startswith(old) and new.count(b"\n") == 9001, "a %d KB file (above 512 KB, below 1.25 MiB) is only appended to" % (len(old) // 1024), "lines %d" % new.count(b"\n"))

# a stale temp file of a rotation that died (older than 1 h) is removed by the next rotation, a fresh one is left alone
root = make_repo("stale")
edit(root, "docs/guide.md")
path = prefill(root, 12000, 100)
stale, fresh = path + ".99999.tmp", path + ".88888.tmp"
for f in (stale, fresh):
    put(f, "x\n")
old_t = time.time() - 2 * 3600
os.utime(stale, (old_t, old_t))
run_gate(root, ["--run-tests", "--full"])
chk(not os.path.exists(stale) and os.path.exists(fresh) and os.path.getsize(path) <= KEEPB, "rotation removes a stale (> 1 h) runs.jsonl.<pid>.tmp and leaves a fresh one",
    "stale exists %s fresh exists %s" % (os.path.exists(stale), os.path.exists(fresh)))
os.unlink(fresh)

# rotation under concurrency: 12 gates append and rotate at once: whatever is kept is whole lines of valid JSON, no temp file stays
root = make_repo("rotpar")
edit(root, "docs/guide.md")
path = prefill(root, 12000, 100)
ps = [run_gate(root, ["--run-tests", "--full"], {"TEST_RUN_LOCK_WAIT_S": "0"}, wait=False) for _ in range(12)]
for p in ps:
    try:
        p.communicate(timeout=280)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
try:
    lines = [json.loads(l) for l in open(path, "rb").read().decode("utf-8").splitlines() if l.strip()]
    valid = True
except ValueError:
    lines, valid = [], False
chk(valid and 3000 < len(lines) <= 4012 and os.path.getsize(path) <= KEEPB + 100 * 1024
    and not [f for f in os.listdir(os.path.dirname(path)) if f.endswith(".tmp")],
    "12 gates appending and rotating at once: only whole valid lines remain (%d), no temp file left" % len(lines), "valid=%s lines=%d size=%d" % (valid, len(lines), os.path.getsize(path)))

# ── (i) nothing that identifies a file, a path, a commit or a session ────────────────────────────────────────
leaks = []
for dirpath, dirs, files in os.walk(TMP):
    if os.path.basename(dirpath) == "postfix-gate" and "runs.jsonl" in files and os.path.isfile(os.path.join(dirpath, "runs.jsonl")) \
            and not os.path.islink(os.path.join(dirpath, "runs.jsonl")):
        try:
            with open(os.path.join(dirpath, "runs.jsonl"), "rb") as f:
                for n, raw in enumerate(f):
                    line = raw.decode("utf-8", "replace")
                    if '"seq"' in line:
                        continue   # the synthetic pre-fill of the rotation test
                    for needle in (TMP, SESSION_ID, COMMIT_MSG, "guide", "Core", "Elsewhere", "transcript", "/", "\\"):
                        if needle in line:
                            leaks.append("%s line %d has %r: %s" % (dirpath[-40:], n + 1, needle, line[:200]))
                    if len(raw) > 3072:
                        leaks.append("%s line %d is %d bytes" % (dirpath[-40:], n + 1, len(raw)))
        except OSError:
            pass
chk(not leaks, "no file name, absolute path, commit message, session id or transcript path in any line; every line < 3 KB",
    "; ".join(leaks[:3]))

for p in procs:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        pass
print()
if fails:
    print("gate run log: %d FAILED" % fails)
    sys.exit(1)
print("gate run log: all checks passed")
PY
