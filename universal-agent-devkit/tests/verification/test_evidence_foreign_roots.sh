#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh credits ANOTHER project's TEST-*.xml to the session only for a project the session RAN
# tests in, not for every path a test command happens to mention.
#   Real case (2026-10-07): one Bash command ran the kit's suites in a loop and, in the same command, read the state of four repos. The hook
#   took every absolute path of a test command as "a project this session ran tests in", found OfficeReader's fresh XML (written by ANOTHER
#   agent during one of this session's long Bash windows) and quoted its `skipped=14` against a claim that had nothing to do with it. The same
#   hole could just as well have BACKED a pass claim with someone else's green XML.
# A foreign project is rooted only where the command RUNS: the `cd`/`pushd` target, the value of -p / -C / --project-dir / --project /
# --prefix / --manifest-path / -projectPath / --cwd, the runner executable itself (…/gradlew, mvnw), or the script handed to an interpreter.
# A path that is only an argument of ls / cat / grep / a smoke script is no run there. A result XML named in the command (`cat …/TEST-x.xml`)
# is still credited when it was written in the session's window (unchanged). The DevKit gate counts as a runner only when it is INVOKED
# (python… post-fix-gate.py, or ./path/post-fix-gate.py), not when its name sits inside `pgrep -f "…"` / `grep`.
#   EF_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
# bash 3.2 compatible wrapper; the scenarios are python3 stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EF_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time

KIT = sys.argv[1]
GATE = os.path.join(KIT, "hooks", "test_evidence_gate.sh")
TMP = tempfile.mkdtemp()
CLEAN = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CLAUDE_"))}
MSG = "JUnit XML shows 13/13 tests passed, 0 failures."
fails = 0
n = 0


def fixture():
    """p = this session's project (Gradle, no XML of its own); f = ANOTHER project holding a fresh green XML that was written
    inside this session's open Bash window (no ledger of its own). Returns (p, f, xml)."""
    global n
    n += 1
    d = os.path.join(TMP, "c%d" % n)
    p, f = os.path.join(d, "p"), os.path.join(d, "f")
    os.makedirs(os.path.join(f, "app", "build", "test-results", "testDebugUnitTest"))
    os.makedirs(os.path.join(p, ".claude", "audit-gate"))
    for g in (p, f):
        open(os.path.join(g, "gradlew"), "w").close()
    xml = os.path.join(f, "app", "build", "test-results", "testDebugUnitTest", "TEST-GreenSuite.xml")
    open(xml, "w").write('<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="com.example.GreenSuite" tests="13" failures="0" '
                         'errors="0" skipped="0">\n  <testcase classname="com.example.GreenSuite" name="doesSomething"/>\n</testsuite>\n')
    now = time.time()
    os.utime(xml, (now - 5, now - 5))
    open(os.path.join(p, ".claude", "audit-gate", "bash_write_ledger.tsv"), "w").write("s-me\tstart\t%.3f\tm1\n" % (now - 600))
    return p, f, xml


def run(p, cmds):
    start = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 900))
    with open(os.path.join(p, "tr.jsonl"), "w") as fh:
        for i, c in enumerate(cmds):
            fh.write(json.dumps({"timestamp": start, "message": {"content": [{"type": "tool_use", "id": "b%d" % i, "name": "Bash", "input": {"command": c}}]}}) + "\n")
            fh.write(json.dumps({"timestamp": start, "message": {"content": [{"type": "tool_result", "tool_use_id": "b%d" % i, "content": "ok"}]}}) + "\n")
    payload = json.dumps({"session_id": "s-me", "transcript_path": os.path.join(p, "tr.jsonl"), "last_assistant_message": MSG})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0", BUG_LINK_REMINDER="0", RED_PROOF="0")
    r = subprocess.run(["bash", GATE], input=payload, capture_output=True, text=True, env=env)
    return r.returncode, r.stderr


def case(name, make_cmds, want, sub=None):
    global fails
    p, f, xml = fixture()
    rc, err = run(p, make_cmds(p, f, xml))
    ok = rc == want and (sub is None or sub in err)
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  — want exit %d, got %d: %s" % (want, rc, " ".join(l for l in err.splitlines() if l.strip())[:170])))
    if not ok:
        fails += 1


# ── a path that is only MENTIONED is no run there: the foreign XML must not back the claim ─────────────────────────────
case("cd <mine> && ./gradlew test; ls <other>: the other project is only listed",
     lambda p, f, x: ["cd %s && ./gradlew test; ls %s" % (p, f)], 2, "TEST-*.xml")
case("a test script run next to a command that only reads <other>",
     lambda p, f, x: ["bash tests/gates/test_x.sh; ls %s" % f], 2, "TEST-*.xml")
case("a loop of suites + a smoke that names <other> as a python argument",
     lambda p, f, x: ['for t in a b; do bash "$K/tests/gates/$t.sh"; done; python3 -I -c "print(1)" %s' % f], 2, "TEST-*.xml")
case("pgrep -f \"post-fix-gate.py --run-tests\" + cd <other>: a process lookup, not a gate run",
     lambda p, f, x: ['cd %s && pgrep -f "post-fix-gate.py --run-tests"' % f], 2, "TEST-*.xml")
case("a test run of mine + cat of a NOTES file inside <other>",
     lambda p, f, x: ["cd %s && ./gradlew test && cat %s/notes.txt" % (p, f)], 2, "TEST-*.xml")

# ── a project the command RUNS in is still credited (unchanged behaviour) ───────────────────────────────────────────────
case("cd <other> && ./gradlew test: the other project is where the run happens",
     lambda p, f, x: ["cd %s && ./gradlew test" % f], 0)
case("./gradlew -p <other> test",
     lambda p, f, x: ["./gradlew -p %s test" % f], 0)
case("<other>/gradlew test (the runner executable lives there)",
     lambda p, f, x: ["%s/gradlew test" % f], 0)
case("./gradlew --project-dir=<other> test",
     lambda p, f, x: ["./gradlew --project-dir=%s test" % f], 0)
case("a test script of <other> handed to an interpreter (bash <other>/tests/test_x.sh)",
     lambda p, f, x: ["bash %s/tests/test_x.sh" % f], 0)
case("the result XML itself named (cat …/TEST-GreenSuite.xml): credited when written in the window",
     lambda p, f, x: ["cat " + x], 0)
case("the module's build/test-results path named",
     lambda p, f, x: ["ls " + os.path.dirname(x)], 0)

# ── controls ────────────────────────────────────────────────────────────────────────────────────────────────────────────
case("cd <mine> && ./gradlew test; git -C <other> status: -C on a later non-test segment roots nothing",
     lambda p, f, x: ["cd %s && ./gradlew test; git -C %s status" % (p, f)], 2, "TEST-*.xml")
case("cd <other relative to this repo> && ./gradlew test: a relative cd is where the run happens",
     lambda p, f, x: ["cd %s && ./gradlew test" % os.path.relpath(f, p)], 0)
case("F=<other>; cd \"$F\" && ./gradlew test: the variable expands to where the run happens",
     lambda p, f, x: ['F=%s; cd "$F" && ./gradlew test' % f], 0)
case("a command that is not a test run (cd <other> && git status) roots nothing",
     lambda p, f, x: ["cd %s && git status" % f], 2, "TEST-*.xml")
case("a DevKit gate really invoked in <other> (cd … && python3 …/post-fix-gate.py --run-tests --full)",
     lambda p, f, x: ['cd %s && python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief' % f], 0)

shutil.rmtree(TMP, ignore_errors=True)
print("")
print("test_evidence_foreign_roots: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
