#!/usr/bin/env bash
# Regression test (gate speed, 2026-10-15): a runs.jsonl record said how long a gate run took (total_wall_s) and how long its
# suites ran (suites_wall_s), and nothing about the rest: on OfficeReader 28.6 % of the gate time sat outside the suites and could
# not be attributed. The record now carries `steps`: seconds per phase of the run, additive (every old field and reader unchanged).
#   git        argument parsing, the list of changed files          analysis  matrix load, edited-test and author analysis
#   static     the static audits (layers 1-3 and 5-8)               select    the matrix rules and the impacted-test plan
#   cache      the reuse check (tree fingerprint, receipt)          lock      the wait for test_run.lock
#   suites     the whole suite loop, vacuity re-runs included       vacuity   the vacuity re-runs, a PART of suites (suites_wall_s stops before them)
#   verdict    the verdict block                                    receipt   receipt + budget record      checklist  the checklist write      report  the report write
# The checks run the REAL gate in throw-away git repos:
#   S1  a run's record has `steps`: only known keys, finite numbers >= 0, the phases add up to the run's wall time
#   S2  the suites step holds the suite's own seconds; a suite run is not hidden in "static"
#   S3  vacuity: the re-run of an impacted test with its production diff put back is its own step and is NOT in suites_wall_s
#       (control: VACUITY_REVERT=0 has no vacuity seconds)
#   S4  a wait for test_run.lock held by another process is the `lock` step
#   S5  a 40-suite record with long ids is still written (the size cap cuts suites, never the whole line) and keeps its steps
#   S6  readers: gate_runs_report.py reads a record with steps (a bad `steps` value never drops the record), stop_hook_times.py prints the split
#       from the steps and still prints the old split for a record without them
# bash 3.2 and Python 3.9 compatible; python stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${STEPS_KIT:-$DEVKIT_DIR}"   # STEPS_KIT=<kit dir>: test another copy (a mutant must go red)
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
python3 -I - "$KIT" "$TMP" <<'PY'
import json, math, os, subprocess, sys, time

KIT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
GATE = os.path.join(KIT, "bin", "post-fix-gate.py")
HOOK_TIMES = os.path.join(KIT, "scripts", "governance", "stop_hook_times.py")
RUNS_REPORT = os.path.join(KIT, "scripts", "governance", "gate_runs_report.py")
KEYS = {"git", "analysis", "static", "select", "cache", "lock", "suites", "verdict", "receipt", "checklist", "report", "vacuity"}
fails = 0


def ok(msg):
    print("✔ " + msg, flush=True)


def bad(msg):
    global fails
    fails += 1
    print("✖ " + msg, flush=True)


def chk(cond, good, why=""):
    ok(good) if cond else bad("%s: %s" % (good, why))
    return bool(cond)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=120).stdout.decode("utf-8", "replace").strip()


def put(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def init(root):
    os.makedirs(root)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")


def matrix(suites, impacted=False):
    rows = []
    for sid, cmd in suites:
        row = {"id": sid, "name": sid, "command": cmd}
        if impacted:
            row["impacted_command"] = "./gradlew :app:testDebugUnitTest {gradle_tests}"
        rows.append(row)
    return json.dumps({"project": "t", "rules": [{"component": "Core", "watch_files": ["src/*", "app/*"], "mandatory_regression_tests": rows}]})


def make_plain(name, suites):
    root = os.path.join(TMP, name)
    init(root)
    put(os.path.join(root, "src", "Core.kt"), "fun ok() = 1\n")
    put(os.path.join(root, "matrix.json"), matrix(suites))
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    put(os.path.join(root, "src", "Core.kt"), "fun ok() = 2\n")
    return root


def make_vacuity(name, nap):
    """The fixture of tests/verification/test_vacuity_since.sh: an impacted run whose test goes red only without the fix."""
    root = os.path.join(TMP, name)
    init(root)
    put(os.path.join(root, "settings.gradle.kts"), 'include(":app")\n')
    put(os.path.join(root, "app/build.gradle.kts"), 'plugins { id("com.example.app") }\n')
    put(os.path.join(root, "app/src/main/kotlin/pkg/Foo.kt"), "package pkg\n\nobject Foo {\n    fun value() = 1\n}\n")
    put(os.path.join(root, "app/src/test/kotlin/pkg/FooTest.kt"),
        "package pkg\n\nimport org.junit.Test\n\nclass FooTest {\n    @Test fun works() { Foo.value() }\n}\n")
    put(os.path.join(root, "gradlew"), '#!/bin/sh\nsleep %s\ngrep -q tweak app/src/main/kotlin/pkg/Foo.kt || '
        '{ echo "java.lang.AssertionError: expected 2 but was 1"; echo "FooTest > works FAILED"; exit 1; }\n' % nap, 0o755)
    put(os.path.join(root, "matrix.json"), matrix([("REG-APP", "./gradlew testDebugUnitTest")], impacted=True))
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    with open(os.path.join(root, "app/src/main/kotlin/pkg/Foo.kt"), "a") as f:
        f.write("// tweak\n")
    return root


def run_gate(root, extra=(), env=None):
    e = dict(os.environ)
    e.update({"CLAUDE_PROJECT_DIR": root, "FLAKY_RETRY": "0", "VACUITY_REVERT": "0", "TEST_RUN_LOCK_WAIT_S": "30"})
    e.update(env or {})
    p = subprocess.run([PY, GATE, "--matrix", os.path.join(root, "matrix.json"), "--lang", "en", "--run-tests"] + list(extra),
                       cwd=root, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    return p.returncode, p.stdout.decode("utf-8", "replace")


def records(root):
    gdir = git(root, "rev-parse", "--absolute-git-dir")
    path = os.path.join(gdir, "postfix-gate", "runs.jsonl")
    try:
        return [json.loads(l) for l in open(path) if l.strip()]
    except OSError:
        return []


def good_steps(steps):
    return (isinstance(steps, dict) and steps and set(steps) <= KEYS
            and all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0 for v in steps.values()))


# S1 + S2: a plain run, one suite that takes a moment
root = make_plain("plain", [("REG-NAP", "sleep 3"), ("REG-FAST", "true")])
rc, out = run_gate(root)
recs = records(root)
r = recs[-1] if recs else {}
steps = r.get("steps")
chk(len(recs) == 1 and rc == 0, "S1: one gate run, one record", "rc=%s records=%d out=%s" % (rc, len(recs), out[-300:]))
chk(good_steps(steps), "S1: the record has `steps`: known keys, finite numbers >= 0", repr(steps))
if good_steps(steps):
    phases = sum(v for k, v in steps.items() if k != "vacuity")
    tw = r.get("total_wall_s", 0)
    chk(abs(phases - tw) <= 1.0, "S1: the phases add up to the run's wall time (%.1f s of %.1f s)" % (phases, tw),
        "phases %.2f vs total_wall_s %.2f: %r" % (phases, tw, steps))
    chk(all(k in steps for k in ("static", "suites", "checklist", "report")), "S1: the phases every --run-tests run passes through are all there", repr(sorted(steps)))
    # bounds that hold on a slow machine: the nap is a floor for the suites step, and the run's other phases are not charged with it
    chk(steps.get("suites", 0) >= 2.9 and steps.get("suites", 0) <= tw, "S2: the suites step holds the suite's own seconds (%.1f s, the suite sleeps 3 s)" % steps.get("suites", 0), repr(steps))
    chk(steps.get("static", 99) < steps.get("suites", 0), "S2: the nap is not charged to `static` (static %.1f s, suites %.1f s)" % (steps.get("static", 0), steps.get("suites", 0)), repr(steps))
    chk("vacuity" not in steps or steps["vacuity"] < 0.2, "S1: no vacuity re-run, no vacuity seconds", repr(steps))

# S2b: the first phase starts at the start of main(): a slow `git status` (listing the changed files) is the git step, not nobody's
real_git = subprocess.run(["sh", "-c", "command -v git"], stdout=subprocess.PIPE).stdout.decode().strip()
slow = os.path.join(TMP, "bin-slow")
put(os.path.join(slow, "git"), '#!/bin/sh\nfor a in "$@"; do [ "$a" = status ] && sleep 0.6; done\nexec %s "$@"\n' % real_git, 0o755)
root = make_plain("slowgit", [("REG-FAST", "true")])
rc, out = run_gate(root, env={"PATH": slow + os.pathsep + os.environ.get("PATH", "")})
r = (records(root) or [{}])[-1]
steps = r.get("steps") or {}
chk(good_steps(steps) and steps.get("git", 0) >= 0.5, "S2b: a slow `git status` while the changed files are listed is charged to the git step (%.1f s)" % steps.get("git", 0), "rc=%s %r" % (rc, steps))
chk(good_steps(steps) and abs(sum(v for k, v in steps.items() if k != "vacuity") - r.get("total_wall_s", 0)) <= 1.0,
    "S2b: and the phases still add up to the run's wall time", repr(r))

# S3: vacuity
root = make_vacuity("vac", "1")
rc, out = run_gate(root, env={"VACUITY_REVERT": "1"})
r = (records(root) or [{}])[-1]
steps = r.get("steps") or {}
chk(rc == 0 and r.get("impacted_run") is True, "S3: fixture run is an impacted PASS whose test was proven red at the base", "rc=%s impacted_run=%s out=%s" % (rc, r.get("impacted_run"), out[-400:]))
if good_steps(steps):
    sw = r.get("suites_wall_s", 0)
    chk(steps.get("vacuity", 0) >= 0.9, "S3: the vacuity re-run is its own step (%.1f s)" % steps.get("vacuity", 0), repr(steps))
    chk(steps.get("suites", 0) - sw >= 0.9, "S3: it is NOT in suites_wall_s (%.1f s) and IS in the suites step (%.1f s)" % (sw, steps.get("suites", 0)), repr(r))
    chk(steps.get("vacuity", 0) <= steps.get("suites", 0) + 0.2, "S3: vacuity is a part of suites, never more", repr(steps))
else:
    bad("S3: no usable steps in the record: %r" % r)
root = make_vacuity("vac0", "1")
rc, out = run_gate(root, env={"VACUITY_REVERT": "0"})
steps = (records(root) or [{}])[-1].get("steps") or {}
r0 = (records(root) or [{}])[-1]
chk(good_steps(steps) and steps.get("vacuity", 0) < 0.2 and steps.get("suites", 0) - r0.get("suites_wall_s", 0) < 0.9,
    "S3: control, VACUITY_REVERT=0: no vacuity seconds, the suites step is the suite's own seconds", repr(r0))

# S4: the lock wait. The holder lets go 2 s after the gate SAYS it waits (a release file), not a fixed time after it took the lock: a slow start of
# the gate must not shorten the wait this test measures
root = make_plain("lockwait", [("REG-FAST", "true")])
lockdir = os.path.join(root, ".claude", "audit-gate")
os.makedirs(lockdir, exist_ok=True)
ready, release, gate_out = os.path.join(TMP, "lock-ready"), os.path.join(TMP, "lock-release"), os.path.join(TMP, "lock-gate.out")
holder = subprocess.Popen([PY, "-c", "import fcntl,os,sys,time\nf=open(sys.argv[1]+'/test_run.lock','a')\nfcntl.flock(f,fcntl.LOCK_EX)\n"
                           "open(sys.argv[2],'w').close()\nfor _ in range(900):\n    if os.path.exists(sys.argv[3]):\n        break\n    time.sleep(0.1)\n",
                           lockdir, ready, release])
for _ in range(300):
    if os.path.exists(ready):
        break
    time.sleep(0.1)
env = dict(os.environ)
env.update({"CLAUDE_PROJECT_DIR": root, "FLAKY_RETRY": "0", "VACUITY_REVERT": "0", "TEST_RUN_LOCK_WAIT_S": "120"})
with open(gate_out, "w") as fo:
    gate = subprocess.Popen([PY, GATE, "--matrix", os.path.join(root, "matrix.json"), "--lang", "en", "--run-tests"], cwd=root, env=env,
                            stdout=fo, stderr=subprocess.STDOUT)
    for _ in range(900):
        if "waiting for it" in open(gate_out).read() or gate.poll() is not None:
            break
        time.sleep(0.1)
    time.sleep(2.0)
    open(release, "w").close()
    rc = gate.wait(timeout=240)
holder.wait(timeout=30)
steps = (records(root) or [{}])[-1].get("steps") or {}
chk(good_steps(steps) and 1.8 <= steps.get("lock", 0) <= 30, "S4: a wait for test_run.lock held by another process is the lock step (%.1f s, held 2 s after the gate said it waits)" % steps.get("lock", 0),
    "rc=%s steps=%r out=%s" % (rc, steps, open(gate_out).read()[-300:]))
root = make_plain("nolock", [("REG-FAST", "true")])
rc, out = run_gate(root)
steps = (records(root) or [{}])[-1].get("steps") or {}
chk(good_steps(steps) and steps.get("lock", 0) < 1.0, "S4: control, nobody holds the lock: the lock step is ~0 (%.1f s)" % steps.get("lock", 0), repr(steps))

# S5: 40 suites with long ids
many = [("REG-" + ("LONG-SUITE-ID-" * 3) + str(i), "true") for i in range(40)]
root = make_plain("many", many)
rc, out = run_gate(root)
recs = records(root)
r = recs[-1] if recs else {}
raw = ""
try:
    gdir = git(root, "rev-parse", "--absolute-git-dir")
    raw = open(os.path.join(gdir, "postfix-gate", "runs.jsonl")).read()
except OSError:
    pass
chk(len(recs) == 1 and len(raw) <= 3000 and good_steps(r.get("steps")), "S5: a 40-suite run with long ids still logs one line under the cap, steps kept (%d bytes)" % len(raw),
    "records=%d bytes=%d steps=%r" % (len(recs), len(raw), r.get("steps")))
chk(r.get("suites_cut") is True or len(r.get("suites", [])) == 40, "S5: the cap cuts `suites` (suites_cut) rather than dropping the line or the steps", "cut=%r n=%d" % (r.get("suites_cut"), len(r.get("suites", []))))

# S6: readers
root = os.path.join(TMP, "readers")
init(root)
put(os.path.join(root, "a.txt"), "x\n")
git(root, "add", "-A")
git(root, "commit", "-qm", "init")
gdir = git(root, "rev-parse", "--absolute-git-dir")
now = int(time.time())


def rec(epoch, wall, suites_s, steps=None, **kw):
    r = {"v": 1, "ts": "2026-10-15T10:00:00+00:00", "epoch": epoch, "project": "t", "mode": "impacted", "source": "hook", "exit": 0,
         "verdict": "PASS", "deferred": False, "busy": False, "reused_full_pass": False, "n_changed": 3, "n_docs": 0, "docs_only": False,
         "no_test_only": False, "suites": [["REG-A", "PASS", suites_s]], "suites_wall_s": suites_s, "force_full": False, "impacted_run": False,
         "total_wall_s": wall}
    if steps is not None:
        r["steps"] = steps
    r.update(kw)
    return r


lines = [rec(now - 300, 100.0, 40.0, {"git": 1.0, "analysis": 2.0, "static": 10.0, "select": 1.0, "cache": 3.0, "lock": 0.0, "suites": 80.0,
                                       "vacuity": 40.0, "verdict": 1.0, "receipt": 0.5, "checklist": 1.0, "report": 0.5}),
         rec(now - 200, 50.0, 30.0),                                  # an old record: no steps
         rec(now - 100, 10.0, 5.0, {"static": "slow", "suites": -1}),  # a broken steps value: the record is still read
         rec(now - 50, 10.0, 5.0, "not a dict")]
put(os.path.join(gdir, "postfix-gate", "runs.jsonl"), "".join(json.dumps(x) + "\n" for x in lines))
p = subprocess.run([PY, "-I", RUNS_REPORT, "--repo", root], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
txt = p.stdout.decode()
chk(p.returncode == 0 and "4 valid" in txt and "0 ignored" in txt, "S6: gate_runs_report reads records with steps, old records and broken steps alike (none ignored)", txt[:400])
p = subprocess.run([PY, "-I", HOOK_TIMES, "--repo", root, "--projects-dir", os.path.join(TMP, "no-transcripts"), "--json"],
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
try:
    data = json.loads(p.stdout.decode())
    g = data["repos"][0]["gate_hook_runs"]
except Exception as e:  # noqa: BLE001
    g = None
    bad("S6: stop_hook_times --json is not JSON: %r %s" % (e, p.stdout.decode()[:300]))
if g:
    st = g.get("steps") or {}
    chk(g.get("runs") == 4 and g.get("steps_runs") == 1, "S6: exactly one of the four runs has a usable step record", repr({k: g.get(k) for k in ("runs", "steps_runs")}))
    chk(abs(st.get("suites", 0) - 40.0) < 0.01 and abs(st.get("vacuity", 0) - 40.0) < 0.01 and abs(st.get("static", 0) - 10.0) < 0.01,
        "S6: the split is the sum of the steps (suites 80 s hold vacuity 40 s: suites without vacuity 40 s)", repr(st))
    chk(g.get("other_s") is not None, "S6: the old split (suites / lock / other) is still there", repr(sorted(g)))
p = subprocess.run([PY, "-I", HOOK_TIMES, "--repo", root, "--projects-dir", os.path.join(TMP, "no-transcripts")],
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
txt = p.stdout.decode()
chk("steps" in txt and "vacuity" in txt and "running suites" in txt, "S6: the text report prints the step split next to the old one", txt[-900:])

print("\ngate run steps: all checks passed" if not fails else "\ngate run steps: %d FAILED" % fails)
sys.exit(1 if fails else 0)
PY
