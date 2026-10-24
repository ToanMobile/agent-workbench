#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh check 2 in a repo with no Gradle build and no TEST-*.xml accepts the runners such a
# repo really uses, and still blocks everything that is not a passing run of one.
#   Real case (2026-10-07, this repo and GeelyEx2): a claim "14/14 test pass" was refused 8 times although the session had run
#   (a) bash/python test scripts in a loop through shell variables (`for t in …; do bash "$K/tests/gates/$t.sh"`,
#       `$py tests/scripts/test-x.py`), (b) the project's own gate `post-fix-gate.py --run-tests --full` (exit 0, 6/6 suites) —
#       none of them matched a runner pattern, and the kit's own suites count as green only with a summary line.
# Accepted now: a command that names a script under tests/ through a $VAR, an interpreter held in a $VAR, and post-fix-gate.py with
# --run-tests/--full/--force-full whose OWN verdict line is PASS with N/N suites (N ≥ 1).
# Issue #74: `bash`/`sh` chạy thẳng file tests/**/test_*.sh hoặc hooks/tests/*.sh của kit, tool exit 0,
# là một lần chạy xanh dù output chỉ có ✔/✖ và không có dòng "all passed". Vòng for vẫn cần dòng tóm tắt.
# Vẫn chặn: exit 1, lần chạy trước lần sửa cuối, `bash -c 'echo ✔'`, `cat test_y.sh`.
# Still blocked: a gate run that says CHƯA XÁC MINH / REJECT / 0 suites, any non-PASS verdict among several, is_error, a run before the
# last source edit, a script outside tests/, a loop with no summary or with a FAILED line, a Gradle repo (its evidence is the XML),
# and CHECK 7 (an outcome claim needs a RED→GREEN pair: a gate PASS is not one).
#   EG_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
# bash 3.2 compatible wrapper; the scenarios are python3 stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EG_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PYEND'
import json, os, shutil, subprocess, sys, tempfile

KIT = sys.argv[1]
GATE = os.path.join(KIT, "hooks", "test_evidence_gate.sh")
TMP = tempfile.mkdtemp()
CLEAN = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CLAUDE_"))}
fails = 0
n = 0


def project(gradle=False):
    global n
    n += 1
    p = os.path.join(TMP, "p%d" % n)
    os.makedirs(os.path.join(p, "src"))
    os.makedirs(os.path.join(p, ".claude", "audit-gate"))
    os.makedirs(os.path.join(p, "tests"))
    open(os.path.join(p, "tests", "test_foo.py"), "w").write("def test_a():\n    assert 1\n")
    open(os.path.join(p, "src", "app.py"), "w").write("def f():\n    return 1\n")
    if gradle:
        open(os.path.join(p, "build.gradle"), "w").write("// gradle\n")
    return p


def transcript(p, steps):
    lines = []
    for i, s in enumerate(steps):
        uid = "tu%d" % i
        if s[0] == "bash":
            use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": s[1]}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": s[2], "is_error": bool(s[3]) if len(s) > 3 else False}
        elif s[0] == "edit_test":  # a test file written this session (the RED-check applies to it)
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p, "tests", "test_foo.py"), "old_string": "assert 1", "new_string": "assert 2"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        else:  # ["edit"]: a source edit of src/app.py
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p, "src", "app.py"), "old_string": "return 1", "new_string": "return 2"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def run_gate(p, tr, msg):
    payload = json.dumps({"session_id": "evr-" + os.path.basename(p), "transcript_path": tr, "last_assistant_message": msg})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0")
    r = subprocess.run(["bash", GATE], input=payload, capture_output=True, text=True, env=env)
    return r.returncode, r.stderr


def case(name, steps, want, sub=None, msg="14/14 test pass.", gradle=False):
    global fails
    p = project(gradle)
    rc, err = run_gate(p, transcript(p, steps), msg)
    ok = rc == want and (sub is None or sub in err)
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  — want exit %d%s, got %d: %s" % (
        want, " + '%s'" % sub if sub else "", rc, " ".join(l for l in err.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


GATE_CMD = ('cd /repo && CLAUDE_PROJECT_DIR="$PWD" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --force-full '
            '--since abc123 --brief > /tmp/g.log 2>&1; echo "GATE EXIT=$?"; grep -E "KẾT LUẬN|Test hồi quy" /tmp/g.log')
G_PASS = "  KẾT LUẬN CỔNG POST-FIX AUDIT: PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO\n  • Test hồi quy đạt: 6/6\nGATE EXIT=0"
G_PASS_EN = ("\x1b[1mPOST-FIX AUDIT GATE VERDICT:\x1b[0m \x1b[92m\x1b[1mPASS — READY FOR ACCEPTANCE & HANDOVER\x1b[0m\n"
             "  • Regression tests passed: 2/2\nGATE EXIT=0")
LOOP_VAR = 'for t in test_a test_b; do bash "$K/tests/gates/$t.sh"; done'
PYLOOP = 'for py in python3 /usr/bin/python3; do $py tests/scripts/test-foo.py; done'
E = ["edit"]

# ── accepted: these were refused before ─────────────────────────────────────
case("kit suites run in a loop through $t, each ending 'all checks passed'", [E, ["bash", LOOP_VAR, "a: all checks passed\nb: all checks passed"]], 0)
case("an interpreter held in $py running tests/scripts/test-foo.py", [E, ["bash", PYLOOP, "✅ one\n✅ two\n✅ all good"]], 0)
case("the project's own gate: verdict PASS and 6/6 suites (Vietnamese)", [E, ["bash", GATE_CMD, G_PASS]], 0)
case("the project's own gate: verdict PASS and 2/2 suites (English, with ANSI colours)", [E, ["bash", GATE_CMD, G_PASS_EN]], 0)

# ── still blocked ───────────────────────────────────────────────────────────
NO = "THÀNH CÔNG"
case("gate verdict CHƯA XÁC MINH is not a pass", [E, ["bash", GATE_CMD, "  KẾT LUẬN CỔNG POST-FIX AUDIT: CHƯA XÁC MINH — không có test hồi quy nào khớp thay đổi\n  • Test hồi quy đạt: 0/0"]], 2, NO)
case("gate verdict REJECT is not a pass", [E, ["bash", GATE_CMD, "  KẾT LUẬN CỔNG POST-FIX AUDIT: REJECT — CẦN KHẮC PHỤC\n  • Test hồi quy đạt: 4/6"]], 2, NO)
case("gate PASS with 0/0 suites ran nothing", [E, ["bash", GATE_CMD, "  KẾT LUẬN CỔNG POST-FIX AUDIT: PASS — ĐỦ ĐIỀU KIỆN\n  • Test hồi quy đạt: 0/0"]], 2, NO)
case("gate PASS but the tool result is an error", [E, ["bash", GATE_CMD, G_PASS, True]], 2, NO)
case("gate PASS text from a command that is not a test run (--help)", [E, ["bash", "python3 .agents/devkit/bin/post-fix-gate.py --help", G_PASS]], 2, NO)
case("gate PASS from BEFORE the last source edit", [["bash", GATE_CMD, G_PASS], E], 2, NO)
case("two verdict lines, one of them not PASS", [E, ["bash", GATE_CMD, G_PASS + "\n  KẾT LUẬN CỔNG POST-FIX AUDIT: CHƯA XÁC MINH — dry-run"]], 2, NO)
case("a script outside tests/ run through a variable is no test run", [E, ["bash", 'bash "$K/scripts/deploy.sh"', "deploy: all checks passed"]], 2, NO)
case("kit suites in a loop with no summary line prove nothing", [E, ["bash", LOOP_VAR, "ok\nok"]], 2, NO)
case("kit suites in a loop with one FAILED", [E, ["bash", LOOP_VAR, "a: all checks passed\nb: 1 FAILED"]], 2, NO)
case("a Gradle repo still needs the XML (a gate PASS is not enough there)", [E, ["bash", GATE_CMD, G_PASS]], 2, "TEST-*.xml", gradle=True)

# ── the RED-check of a test file written this session applies to a gate PASS like to any green runner ──
TE = ["edit_test"]
case("a test file written this session + only a green gate (no RED before it) is blocked", [TE, ["bash", GATE_CMD, G_PASS]], 2, "ĐỎ")
case("same, with a RED runner after the test edit and before the green gate: accepted",
     [TE, ["bash", "pytest tests/test_foo.py", "FAILED tests/test_foo.py::test_a - assert 2\n1 failed", True], E, ["bash", GATE_CMD, G_PASS]], 0)

# ── the gate counts only when it is INVOKED (2026-10-07: its name inside a pgrep/grep made a process lookup a "test run") ──
case("the gate's name inside pgrep -f \"…\" is a process lookup, not a run", [E, ["bash", 'pgrep -f "post-fix-gate.py --run-tests"; echo done', G_PASS]], 2, NO)
case("the gate's name inside grep -E is not a run", [E, ["bash", "ps aux | grep -E 'post-fix-gate.py --run-tests'", G_PASS]], 2, NO)
case("the gate run directly by path (./bin/post-fix-gate.py --run-tests) counts", [E, ["bash", "./bin/post-fix-gate.py --run-tests --full --brief", G_PASS]], 0)

# ── a reader that merely names a runner is not a run; a real invocation the old regex missed still is ──
case("grep of a suite path whose output says all checks passed is not a run",
     [E, ["bash", 'grep -n "all checks passed" tests/gates/test_x.sh', "12:all checks passed"]], 2, NO)
case("echo of the gate command with a PASS verdict is not a run",
     [E, ["bash", "echo python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full", G_PASS]], 2, NO)
case("python3 -c that prints the gate invocation is not a run",
     [E, ["bash", "python3 -c \"print('python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full')\"", G_PASS]], 2, NO)
case("the gate invoked by its bare path (no python, no ./) with PASS and 6/6",
     [E, ["bash", ".agents/devkit/bin/post-fix-gate.py --run-tests --full --brief", G_PASS]], 0)
case("the interpreter held in $py and the gate path literal",
     [E, ["bash", 'py=python3; $py .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief', G_PASS]], 0)
case('python3 "$GATE" after GATE= the gate path',
     [E, ["bash", 'GATE=.agents/devkit/bin/post-fix-gate.py; python3 "$GATE" --run-tests --full --brief', G_PASS]], 0)
case('for f in tests/gates/test_*.sh; do bash "$f"; done with a pass summary',
     [E, ["bash", 'for f in tests/gates/test_*.sh; do bash "$f"; done', "all checks passed"]], 0)

# ── unchanged behaviour ─────────────────────────────────────────────────────
case("control: a literal kit suite path still counts", [E, ["bash", "bash tests/gates/test_x.sh", "x: all checks passed"]], 0)

# ── issue #74: bash thẳng file kit, exit 0 của tool, không cần dòng "all passed" ──
MARKS = "✔ parallel hint\n✔ lane plan\n"
KIT_BASH = "bash universal-agent-devkit/tests/context_memory/test_parallel_hint.sh"
case("direct bash of tests/**/test_*.sh exit 0 with check marks is a pass",
     [E, ["bash", KIT_BASH, MARKS]], 0, msg="test PASS")
case("direct bash of a deeper tests/a/b/test_*.sh exit 0 is a pass",
     [E, ["bash", "bash tests/a/b/test_deep.sh", MARKS]], 0, msg="test PASS")
case("direct bash of hooks/tests/*.sh exit 0 is a pass",
     [E, ["bash", "bash hooks/tests/hook_contract_test.sh", "✔ contract\n"]], 0, msg="test PASS")
case("direct bash of hooks/tests/*.sh whose name is not test_* or contract_test",
     [E, ["bash", "sh hooks/tests/plain_helper.sh", "✔ helper\n"]], 0, msg="test PASS")
case("same bash kit test with tool exit 1 is blocked",
     [E, ["bash", KIT_BASH, MARKS, True]], 2, NO, msg="test PASS")
case("bash kit test before the last edit is blocked",
     [["bash", KIT_BASH, MARKS], E], 2, NO, msg="test PASS")
case("bash -c echo checkmark is not a test run",
     [E, ["bash", "bash -c 'echo ✔'", "✔"]], 2, NO, msg="test PASS")
case("bash -c <kit path> is a command string, not a direct file run",
     [E, ["bash", "bash -c tests/a/test_x.sh", "✔"]], 2, NO, msg="test PASS")
case("cat test_y.sh is not a test run",
     [E, ["bash", "cat test_y.sh", "✔"]], 2, NO, msg="test PASS")
case("cat of a suite path is not a test run",
     [E, ["bash", "cat tests/context_memory/test_y.sh", "✔\nall checks passed"]], 2, NO, msg="test PASS")
case("bash kit test exit 0 that prints a failure summary is still red",
     [E, ["bash", KIT_BASH, "✔ one\n1 failed\n"]], 2, NO, msg="test PASS")
case("deeper bash test that prints FAIL stays red",
     [E, ["bash", "bash tests/a/b/test_deep.sh", "FAIL tests/a/b/test_deep.sh"]], 2, NO, msg="test PASS")
case("hooks/tests exit 0 whose check name contains FAIL is still a pass",
     [E, ["bash", "sh hooks/tests/plain_helper.sh", "✔ FAIL on secrets\n"]], 0, msg="test PASS")
case("bash kit test chained with ; true is not a pass",
     [E, ["bash", KIT_BASH + "; true", MARKS]], 2, NO, msg="test PASS")
case("bash kit test or-true is not a pass",
     [E, ["bash", KIT_BASH + " || true", MARKS]], 2, NO, msg="test PASS")
case("bash kit test piped to cat is not a pass",
     [E, ["bash", KIT_BASH + " | cat", MARKS]], 2, NO, msg="test PASS")
case("bash kit test backgrounded is not a pass",
     [E, ["bash", KIT_BASH + " &", MARKS]], 2, NO, msg="test PASS")
# R1 (reviewer, PR #204): cờ chỉ kiểm cú pháp, bash thoát 0 mà không chạy test nào.
case("bash -n of a kit test only checks syntax, not a test run",
     [E, ["bash", "bash -n tests/a/test_x.sh", ""]], 2, NO, msg="test PASS")
case("bash -xn (clustered flags with n) is a syntax check, not a test run",
     [E, ["bash", "bash -xn tests/a/test_x.sh", ""]], 2, NO, msg="test PASS")
case("bash --noexec of a kit test is a syntax check, not a test run",
     [E, ["bash", "bash --noexec tests/a/test_x.sh", ""]], 2, NO, msg="test PASS")
case("sh -n of a hooks/tests file is a syntax check, not a test run",
     [E, ["bash", "sh -n hooks/tests/plain_helper.sh", ""]], 2, NO, msg="test PASS")
case("control: bash -x (trace, still runs) of a kit test is a pass",
     [E, ["bash", "bash -x tests/a/test_x.sh", MARKS]], 0, msg="test PASS")
case("CHECK 7 is untouched: a gate PASS is no RED→GREEN pair for an outcome claim",
     [E, ["bash", GATE_CMD, G_PASS]], 2, "CHECK 7", msg="Đã fix lỗi X. 14/14 test pass.")

shutil.rmtree(TMP, ignore_errors=True)
print("")
print("test_evidence_runners: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PYEND
