#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh check 7 (an outcome claim needs a paired RED→GREEN run) judged two honest sessions wrongly
# (issue #4, agent-workbench):
#   (1) check 2 accepts the DevKit gate's PASS ("gate-green") as a green run, check 7 asked for a literal "green" and refused it;
#   (2) an Edit of a TEST file after the RED→GREEN pair moved the "last source edit" marker past the green run (the fix itself did not
#       change), so the pair no longer counted.
# Still blocked: no RED at all, a gate PASS from before the fix, a SOURCE edit after the green run.
#   EG_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EG_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

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
    for d in ("src", "tests", os.path.join(".claude", "audit-gate")):
        os.makedirs(os.path.join(p, d))
    open(os.path.join(p, "tests", "test_foo.py"), "w").write("def test_a():\n    assert 1\n")
    open(os.path.join(p, "src", "app.py"), "w").write("def f():\n    return 1\n")
    return p


def transcript(p, steps):
    lines = []
    for i, s in enumerate(steps):
        uid = "tu%d" % i
        if s[0] == "bash":
            use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": s[1]}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": s[2], "is_error": bool(s[3]) if len(s) > 3 else False}
        else:
            path, old, new = ("tests/test_foo.py", "assert 1", "assert 2") if s[0] == "edit_test" else ("src/app.py", "return 1", "return 2")
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p, path), "old_string": old, "new_string": new}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def case(name, steps, want, sub=None, msg="Đã fix lỗi X."):
    global fails
    p = project()
    payload = json.dumps({"session_id": "c7p-" + os.path.basename(p), "transcript_path": transcript(p, steps), "last_assistant_message": msg})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0")
    r = subprocess.run(["bash", GATE], input=payload, capture_output=True, text=True, env=env)
    ok = r.returncode == want and (sub is None or sub in r.stderr)
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  — want exit %d%s, got %d: %s" % (
        want, " + '%s'" % sub if sub else "", r.returncode, " ".join(l for l in r.stderr.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


GATE_CMD = 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief'
G_PASS = "  KẾT LUẬN CỔNG POST-FIX AUDIT: PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO\n  • Test hồi quy đạt: 6/6\nGATE EXIT=0"
RED = ["bash", "pytest tests/test_foo.py", "FAILED tests/test_foo.py::test_a - assert 2\n1 failed", True]
GREEN = ["bash", "pytest tests/test_foo.py", "1 passed"]
E, TE = ["edit"], ["edit_test"]

# control: the plain pair is accepted today
case("control: RED, fix, GREEN", [RED, E, GREEN], 0)
# (1) the DevKit gate's PASS is the green half of the pair
case("RED runner, fix, then the gate PASS: the pair holds", [RED, E, ["bash", GATE_CMD, G_PASS]], 0)
# (2) editing a test after the pair does not void it
case("RED, fix, GREEN, then a test file is edited: the pair holds", [RED, E, GREEN, TE], 0)
case("RED, fix, gate PASS, then a test file is edited: the pair holds", [RED, E, ["bash", GATE_CMD, G_PASS], TE], 0)

# still blocked
case("no RED at all: blocked", [E, GREEN], 2, "CHECK 7")
case("RED, fix, GREEN, then a SOURCE edit: blocked", [RED, E, GREEN, E], 2, "CHECK 7")
case("the gate PASS ran BEFORE the fix: blocked", [RED, ["bash", GATE_CMD, G_PASS], E], 2, "CHECK 7")

shutil.rmtree(TMP, ignore_errors=True)
print("")
print("test_evidence_check7_pair: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
