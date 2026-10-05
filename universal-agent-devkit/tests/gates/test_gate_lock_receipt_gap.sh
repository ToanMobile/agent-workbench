#!/usr/bin/env bash
# Regression test: a --full run that WAITED for the test-run lock re-uses the PASS the other run records, always.
# bin/post-fix-gate.py used to close .claude/audit-gate/test_run.lock when its suite loop ended and write the full-pass
# receipt (.git/postfix-gate/full_pass.json) only ~250 lines later, after the static audits and the receipt's own
# fingerprint work. A second run polling for the lock (every 0.5 s) that won it in that gap found no receipt yet, passed
# its post-lock reuse check empty-handed and ran every suite AGAIN (measured by review on a copy: 4 of 20 runs with 3
# changed files, 12 of 12 with 300). The lock is now closed right after the receipt block: a waiter can only take it
# once the receipt is on disk.
#
# The gap is made long and certain with NO production change: each gate is started through a test-only launcher (written
# into the temp dir below) that imports the gate unchanged and delays write_full_pass_receipt by GAP_SLEEP seconds (default
# 1.5 = three polls of the waiter), whatever the machine speed or the size of the diff. A is held in its suite by a fake
# gradlew until B is provably waiting (B printed its "waiting for it" line); then the suite is let go. Every wait is
# bounded; the suite counter (.runs, one line per execution) is the oracle: exactly 1 means B re-used A's PASS.
#   RED on the unfixed gate (the lock is free during the 1.5 s: B takes it, finds no receipt, runs the suite again), GREEN
#   once the lock is held until after the receipt. A lock released just before the receipt, or after the static audits, is
#   RED too. DEVKIT_GATE_CACHE is pinned to 1: with 0 no run ever re-uses a receipt and the test could not tell.
#   Control (first rep): content edited after the receipt must run its suite again (kills a reuse that ignores the fingerprint).
#   GAP_KIT=<devkit dir>   test another copy of the kit (e.g. the unfixed one: RED; a mutant: must go red)
#   GAP_FILES=<n>          modified files per run (default 3); GAP_REPS=<n> repetitions (default 3); GAP_SLEEP=<seconds>
# ponytail: the launcher patches the module global write_full_pass_receipt; if that function is renamed the launcher dies
# with an AttributeError, both gates exit and the test fails loudly (never silently green): follow the rename here.
# Cleanup: the driver kills both gates' process groups and lets the fake suites go; the EXIT trap below removes the temp
# dir and kills any gate whose command line holds it, also after Ctrl-C/SIGTERM of this script (a SIGKILL of this script
# leaves the temp dir; the fake suite ends itself after 180 s).
# bash 3.2 and Python 3.9 compatible; python3 stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${GAP_KIT:-$DEVKIT_DIR}"
GATE="$KIT/bin/post-fix-gate.py"
[ -f "$GATE" ] || { echo "✖ no gate at $GATE"; exit 1; }
TMP="$(mktemp -d)"
# BEFORE the trap: an empty $TMP (mktemp failed) would make its `pkill -f -- "$TMP/"` a `pkill -f -- /`, SIGTERM for nearly every process
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'touch "$TMP"/rep*/ctl/go 2>/dev/null; pkill -f -- "$TMP/" 2>/dev/null; rm -rf "$TMP"' EXIT

# The driver runs in the background so a SIGINT/SIGTERM of this script reaches it NOW (bash defers a trap while a foreground
# command runs; a background job of a non-interactive shell ignores SIGINT): the trap hands it SIGTERM, whose handler cleans up.
python3 -I - "$GATE" "${GAP_FILES:-3}" "${GAP_REPS:-3}" "$TMP" <<'PY' &
import os, re, signal, subprocess, sys, time

GATE, NFILES, REPS, TMP = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
WAIT_SUITE_S, WAIT_B_S, FINISH_S = 180, 180, 300   # bounds, far above a loaded run
fails = 0
procs, gofiles = [], []

# Test-only launcher: the gate unchanged, but write_full_pass_receipt starts GAP_SLEEP seconds late.
LAUNCHER = '''import importlib.util, os, sys, time
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg"] = m
spec.loader.exec_module(m)
orig = m.write_full_pass_receipt
def slow(*a, **k):
    time.sleep(float(os.environ.get("GAP_SLEEP", "1.5")))
    return orig(*a, **k)
m.write_full_pass_receipt = slow
sys.exit(m.main())
'''


class Bad(Exception):
    pass


def ok(msg):
    print("✔ " + msg, flush=True)


def bad(msg):
    global fails
    fails += 1
    print("✖ " + msg, flush=True)


def git(root, *args):
    subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)


def make_repo(root, ctl):
    """A repo whose --full run executes one fake suite (it appends to .runs, then waits for ctl/go) on NFILES modified assets."""
    os.makedirs(root + "/app/src/main/assets")
    os.makedirs(root + "/app/src/test/kotlin/pkg")
    os.makedirs(ctl)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    with open(root + "/settings.gradle.kts", "w") as f:
        f.write('include(":app")\n')
    with open(root + "/app/build.gradle.kts", "w") as f:
        f.write('plugins { id("com.example.app") }\n')
    with open(root + "/app/src/test/kotlin/pkg/OtherTest.kt", "w") as f:
        f.write("package pkg\n\nimport org.junit.Test\n\nclass OtherTest {\n    @Test fun works() { }\n}\n")
    for i in range(NFILES):
        with open(root + "/app/src/main/assets/d%d.txt" % i, "w") as f:
            f.write("data %d\n" % i)
    with open(root + "/gradlew", "w") as f:
        f.write('#!/bin/sh\necho run >> .runs\ni=0\nwhile [ ! -e "%s/go" ] && [ $i -lt 1800 ]; do sleep 0.1; i=$((i + 1)); done\nexit 0\n' % ctl)
    os.chmod(root + "/gradlew", 0o755)
    with open(root + "/matrix.json", "w") as f:
        f.write('{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":'
                '[{"id":"REG-APP","name":"app unit tests","command":"./gradlew :app:testDebugUnitTest"}]}]}\n')
    with open(root + "/.git/info/exclude", "a") as f:
        f.write(".runs\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    for i in range(NFILES):   # the change under audit: every asset modified
        with open(root + "/app/src/main/assets/d%d.txt" % i, "a") as f:
            f.write("tweak\n")


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def clean(text, n):
    return "\n".join(re.sub(r"\x1b\[[0-9;]*m", "", l) for l in text.splitlines()[-n:])


def wait_until(pred, secs, what, *watch, **kw):
    abort = kw.get("abort")   # () -> message when waiting is pointless
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if pred():
            return
        if abort and abort():
            raise Bad(abort())
        for p, out in watch:
            if p.poll() is not None and not pred():
                raise Bad("a gate exited (rc %s) before %s\n--- its output tail ---\n%s" % (p.returncode, what, clean(read(out), 8)))
        time.sleep(0.05)
    raise Bad("timed out after %d s waiting for %s" % (secs, what))


def start(cmd, env, cwd, out):
    with open(out, "w") as fh:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=fh, stderr=subprocess.STDOUT, start_new_session=True)
    procs.append(p)
    return p


def cleanup():
    for g in gofiles:   # let any fake suite end now
        try:
            open(g, "a").close()
        except OSError:
            pass
    for p in procs:
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                p.wait(timeout=30)
            except subprocess.TimeoutExpired:
                pass


def one_rep(rep):
    base = "%s/rep%d" % (TMP, rep)
    root, ctl = base + "/repo", base + "/ctl"
    os.makedirs(root)
    make_repo(root, ctl)
    gofiles.append(ctl + "/go")
    env = dict(os.environ, CLAUDE_PROJECT_DIR=root, VACUITY_REVERT="0", TEST_RUN_LOCK_WAIT_S="240", DEVKIT_GATE_CACHE="1",
               GAP_SLEEP=os.environ.get("GAP_SLEEP", "1.5"))
    args = ["--matrix", root + "/matrix.json", "--lang", "en", "--run-tests", "--full"]
    slow_cmd = [sys.executable, TMP + "/slow_receipt.py", GATE] + args
    runs_file = root + "/.runs"
    a = start(slow_cmd, env, root, base + "/a.out")
    wait_until(lambda: os.path.isfile(runs_file) and os.path.getsize(runs_file) > 0, WAIT_SUITE_S, "A's suite to start", (a, base + "/a.out"))
    b = start(slow_cmd, env, root, base + "/b.out")
    wait_until(lambda: "waiting for it" in read(base + "/b.out"), WAIT_B_S, "B to wait for the lock", (b, base + "/b.out"),
               abort=lambda: "B started its own suite without waiting for A's lock" if len(read(runs_file).split()) > 1 else "")
    open(ctl + "/go", "w").close()   # A's suite ends; B is polling for the lock
    try:
        ra, rb = a.wait(timeout=FINISH_S), b.wait(timeout=FINISH_S)
    except subprocess.TimeoutExpired:
        raise Bad("A or B did not finish within %d s after the suite was let go" % FINISH_S)
    runs = len(read(runs_file).split())
    gd = subprocess.run(["git", "-C", root, "rev-parse", "--absolute-git-dir"], stdout=subprocess.PIPE, timeout=60).stdout.decode().strip()
    receipt = os.path.isfile(gd + "/postfix-gate/full_pass.json")
    reused = "reusing the full PASS" in read(base + "/b.out")
    label = "rep %d (%d files, receipt delayed %ss)" % (rep + 1, NFILES, env["GAP_SLEEP"])
    if (ra, rb, runs, reused, receipt) == (0, 0, 1, True, True):
        ok("%s: the waiting --full re-used the PASS of the run it waited for (suite ran once)" % label)
        if rep == 0:   # control: holding the lock must not make a run re-use a receipt of OTHER content
            with open(root + "/app/src/main/assets/d0.txt", "a") as f:
                f.write("edited after the receipt\n")
            c = start([sys.executable, GATE] + args, env, root, base + "/c.out")
            try:
                rc_c = c.wait(timeout=FINISH_S)
            except subprocess.TimeoutExpired:
                raise Bad("the control run did not finish within %d s" % FINISH_S)
            runs_c = len(read(runs_file).split())
            if (rc_c, runs_c) == (0, 2) and "reusing the full PASS" not in read(base + "/c.out"):
                ok("control: content edited after the receipt runs its suite again (suite executions %d)" % runs_c)
            else:
                bad("control: content edited after the receipt (exit %s, suite executions %d, want 2): a receipt of other content was re-used" % (rc_c, runs_c))
    else:
        bad("%s: exits A=%s B=%s, suite executions %d (want 1), B reused=%s, receipt=%s%s\n--- B output tail ---\n%s"
            % (label, ra, rb, runs, reused, receipt,
               " -- B ran the suite again: it took the lock before A's receipt existed, or its reuse check refused the receipt"
               if runs == 2 else "", clean(read(base + "/b.out"), 8)))


signal.signal(signal.SIGTERM, lambda *a: sys.exit(143))
try:
    with open(TMP + "/slow_receipt.py", "w") as f:
        f.write(LAUNCHER)
    for rep in range(REPS):
        try:
            one_rep(rep)
        except (Bad, subprocess.SubprocessError, OSError) as e:
            bad("rep %d: %s" % (rep + 1, e))
finally:
    cleanup()
sys.exit(1 if fails else 0)
PY
driver=$!
trap 'kill -TERM "$driver" 2>/dev/null' INT TERM
wait "$driver"; rc=$?
# a trapped signal ends the first wait at once while the driver is still cleaning up: wait for it (127 = already reaped)
wait "$driver" 2>/dev/null; r2=$?; [ "$r2" -ne 127 ] && rc=$r2
if [ "$rc" -eq 0 ]; then
  echo "gate lock/receipt gap: all checks passed"
else
  echo "gate lock/receipt gap: FAILED (driver exit $rc)"
  exit 1
fi
