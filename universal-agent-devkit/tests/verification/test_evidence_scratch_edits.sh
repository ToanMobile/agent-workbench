#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh does not count a source file the session wrote in a TEMP directory (the scratchpad the
# harness tells every agent to use, /tmp, $TMPDIR) as "the last code edit": a green test run no longer goes stale because of a helper script.
#   Measured 2026-10-10 over 1227 real transcripts: 171 Stop blocks of this gate; 62 (36%) came right after the last source file the session
#   wrote lay in a temp dir (restore_corpus.py, patch_review3_green.py ... under .../scratchpad/), 71 after an edit inside the project.
# Not changed (checked here): an edit INSIDE the project still ages a green run, also when the project itself sits under a temp dir (every test
# project here does); an edit in another project / path outside any temp dir still counts; a missing run is still a block.
#   EG_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
# bash 3.2 compatible wrapper; the scenarios are python3 stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EG_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PY'
import json, os, subprocess, sys, tempfile

KIT = sys.argv[1]
GATE = os.path.join(KIT, "hooks", "test_evidence_gate.sh")
TMP = tempfile.mkdtemp()
CLEAN = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CLAUDE_"))}
fails = 0
n = 0


def project():
    global n
    n += 1
    p = os.path.join(TMP, "p%d" % n)
    os.makedirs(os.path.join(p, "src"))
    os.makedirs(os.path.join(p, ".claude", "audit-gate"))
    os.makedirs(os.path.join(p, "tests"))
    open(os.path.join(p, "tests", "test_foo.py"), "w").write("def test_a():\n    assert 1\n")
    open(os.path.join(p, "src", "app.py"), "w").write("def f():\n    return 1\n")
    return p


def transcript(p, steps):
    """steps: ("edit",) a source edit in the project; ("write", path) a Write of any path; ("bash", cmd, output)."""
    lines = []
    for i, s in enumerate(steps):
        uid = "tu%d" % i
        if s[0] == "bash":
            use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": s[1]}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": s[2], "is_error": bool(s[3]) if len(s) > 3 else False}
        elif s[0] == "write":
            use = {"type": "tool_use", "id": uid, "name": "Write", "input": {"file_path": s[1], "content": "print(1)\n"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        else:
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p, "src", "app.py"), "old_string": "return 1", "new_string": "return 2"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def case(name, steps_fn, want, sub=None, msg="14/14 test pass.", extra_env=None, cwd=None):
    global fails
    p = project()
    tr = transcript(p, steps_fn(p))
    payload = json.dumps({"session_id": "scr-" + os.path.basename(p), "transcript_path": tr, "last_assistant_message": msg})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0", **(extra_env or {}))
    r = subprocess.run(["bash", GATE], input=payload, capture_output=True, text=True, env=env, cwd=cwd)
    ok = r.returncode == want and (sub is None or sub in r.stderr)
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  — want exit %d%s, got %d: %s" % (
        want, " + '%s'" % sub if sub else "", r.returncode, " ".join(l for l in r.stderr.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


LOOP = 'for t in test_a test_b; do bash "$K/tests/gates/$t.sh"; done'
GREEN = "a: all checks passed\nb: all checks passed"
EDIT = ("edit",)
RUN = ("bash", LOOP, GREEN)
SCRATCH = lambda name: os.path.join(TMP, "scratch", name)           # a temp dir, NOT inside the project (siblings under TMP)
NO = "THÀNH CÔNG"

# ── a temp-dir helper written after the green run does not age it ───────────────────────────────────────────────────────────
case("scratch .py written after the green run: the run still backs the claim", lambda p: [EDIT, RUN, ("write", SCRATCH("helper.py"))], 0)
case("scratch .py written between the edit and the run", lambda p: [EDIT, ("write", SCRATCH("helper.py")), RUN], 0)
case("a literal /tmp path (the harness scratchpad lives under /private/tmp)", lambda p: [EDIT, RUN, ("write", "/tmp/claude-scratch-x/probe.py")], 0)
case("scratch .kt and a scratch test file under the temp dir are scratch too", lambda p: [EDIT, RUN, ("write", SCRATCH("Probe.kt")), ("write", SCRATCH("test_probe.py"))], 0)

# ── everything that is not scratch still ages the run ────────────────────────────────────────────────────────────────────────
case("an edit INSIDE the project after the green run is stale (control)", lambda p: [EDIT, RUN, EDIT], 2, NO)
case("a Write inside the project, though the project itself sits under a temp dir, is stale",
     lambda p: [EDIT, RUN, ("write", os.path.join(p, "src", "extra.py"))], 2, NO)
case("a file in ANOTHER project (outside any temp dir) still counts", lambda p: [EDIT, RUN, ("write", "/opt/other-project/src/x.py")], 2, NO)
case("no test run at all is still a block", lambda p: [EDIT, ("write", SCRATCH("helper.py"))], 2, NO)
case("a project edit AFTER scratch, before no run: still blocked", lambda p: [RUN, ("write", SCRATCH("helper.py")), EDIT], 2, NO)

# ── a wrong TMPDIR must not turn other projects into scratch ───────────────────────────────────────────────────────────────────
for bad in ("/", ".", ""):
    case("TMPDIR=%r does not make another project scratch" % bad, lambda p: [EDIT, RUN, ("write", "/opt/other-project/src/x.py")], 2, NO,
         extra_env={"TMPDIR": bad})

# a RELATIVE TMPDIR is the directory the hook runs in: with the home directory as cwd it would turn every project under it into scratch
HOME = os.path.expanduser("~")
case("TMPDIR=. with the home dir as cwd does not make a project under it scratch",
     lambda p: [EDIT, RUN, ("write", os.path.join(HOME, "other-project-xyz", "src", "x.py"))], 2, NO, extra_env={"TMPDIR": "."}, cwd=HOME)

# ── look-alike directory names are not temp dirs / not the project (the roots end in a path separator) ────────────────────────
case("/tmpx is not /tmp: a file there still counts", lambda p: [EDIT, RUN, ("write", "/tmpx/helper.py")], 2, NO)
case("a sibling dir whose name starts with the project name (p1 / p10) is not inside the project: it is scratch (a temp dir)",
     lambda p: [EDIT, RUN, ("write", p + "0/src/x.py")], 0)

# ── CHECK 7 ("đã fix" needs a RED before and a GREEN after the last source edit): the edit may be a scratch one ──────────────────
# Reviewed 2026-10-10: when every source edit of the session lay in a temp dir (a fix made in a stage copy and installed after), the edit
# marker stayed unset and the pair could never be seen: a claim that the old hook accepted was blocked.
FIX = "Đã fix lỗi X. 1 passed."
PY_RED = ("bash", "pytest tests/test_foo.py", "FAILED tests/test_foo.py::test_a - assert 2\n1 failed", True)
PY_GREEN = ("bash", "pytest tests/test_foo.py", "1 passed")
case("CHECK 7: RED, a scratch-only fix, GREEN: the pair is seen", lambda p: [PY_RED, ("write", SCRATCH("stage_app.py")), PY_GREEN], 0, msg=FIX)
case("CHECK 7 control: RED, a fix inside the project, GREEN", lambda p: [PY_RED, EDIT, PY_GREEN], 0, msg=FIX)
case("CHECK 7 control: a scratch fix and a GREEN with no RED before it is still blocked", lambda p: [("write", SCRATCH("stage_app.py")), PY_GREEN], 2, "CHECK 7", msg=FIX)
case("CHECK 7 control: the RED comes after the scratch fix, so there is no RED before the fix",
     lambda p: [("write", SCRATCH("stage_app.py")), PY_RED, PY_GREEN], 2, "CHECK 7", msg=FIX)

print("evidence scratch edits: %s" % ("all passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
