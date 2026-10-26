#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh, the holes left after the DevKit audit of 25-26/10 (issue #427). Each must-block row
# was green (or a forged RED half of check 7) on the hook before the fix; each sits next to a harmless row that must keep its verdict.
#   R1   a runner whose exit the tool's exit does not carry (`pytest -q || true`, `pytest; true`) next to a kit suite, with no pass
#        summary of its own, read as green from the kit's "all passed". (Alone it was already blocked: kept as regression rows.)
#   R3   a non-kit runner that printed its failure (`--- FAIL`, `FAILED tests/…`, `panicked`) carried by a kit's "all passed".
#   R4   200 KB of tool output: RED_GRADLE, TEST_FILE_IN_OUTPUT, the `<testsuite` / `<test-run` tag regexes were quadratic, the hook
#        was killed after the Stop cap and the claim passed. Bounded by CPU (getrusage), not wall time; a FAILED line at the end of
#        200 KB must still be read (no cut of the failure scan).
#   P1-2 a runner named anywhere in a segment counted as a run: `pip install -q pytest`, `touch pytest.ini`, a heredoc body. Now the
#        runner must BE the command (anchored); `(cd sub && pytest)` and a kit file at any depth still count. A bare `echo $?` that
#        ends the command and prints non-zero is a RED (explicit must-pass); printing 0 is still no green.
#   P1-4 a kit suite borrowed the "all passed" of another kit suite when it was hidden or crashed (`bash x; bash y`, a loop over a
#        literal list): one summary line per unbound kit run is needed once one of them is masked.
#   E4   `trap … EXIT` before the runner: the tool's exit is the trap's, trusted in neither direction.
#   T8   `| tail -N` keeps no verdict of mocha / node --test / go test (failure details after the summary, no overall summary for
#        many go packages); `${PIPESTATUS[0]}` printing non-zero is a RED, printing 0 lets go's 'ok' lines count.
#   Q9   `git -C <repo> commit -q` / `git -c k=v commit -q` print nothing; `git log` after a commit prints the subject; a segment that
#        writes to a file, /dev/null or a PR comment prints nothing in place of a summary, `> /dev/stderr` / `>&2` still does.
#   X    a TEST-*.xml with a count that is not a number (`failures="x"`) crashed the hook (exit 1 = the claim passed).
#   E3   `Unity … -testResults f; cat f` không còn XANH: Unity không xoá f lúc bắt đầu, XML in sau `;` có thể là của lần trước; chỉ
#        `&& cat f` hoặc mã thoát gắn bằng `echo "<nhãn>=$?"` (nhãn có dấu cách: `edit exit=$?`) là bằng chứng (test_evidence_unity.sh
#        §4 nay dùng `&& cat`).
#   (review) vòng kit brace / $VAR mà một lần chạy in `3 failure(s)`; brace dạng dấu phẩy đếm từng lần chạy; ghi ra file rồi segment
#        sau đọc lại file đó (_silent); cờ python trước `-m`, `coverage run`, xvfb-run / stdbuf / sudo / exec / bundle exec / xcrun /
#        arch là lần chạy; trap dọn dẹp trong ngoặc (`trap 'rm -rf $T' EXIT`) giữ mã thoát; `echo $?` cuối với dòng 100 KB `1…1x1`.
# Chưa ở đây, backlog của #427: vòng glob / $VAR qua suite kit với không hoặc một dòng tóm tắt (tests/gates/test_evidence_false_blocks.sh
# section D coi `for f in tests/a/test_*.sh; do …; bash "$f"; done` không dòng tóm tắt là xanh), `docker compose run … pytest`.
#   EG_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
# bash 3.2 compatible wrapper; the scenarios are python3 stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EG_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PYEND'
import json, os, resource, shutil, signal, subprocess, sys, tempfile

KIT = sys.argv[1]
GATE = os.path.join(KIT, "hooks", "test_evidence_gate.sh")
TMP = tempfile.mkdtemp()
CLEAN = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CLAUDE_"))}
fails = 0
n = 0
PASS = "Đã chạy lại bộ test: 12/12 test pass."
FIX = "Đã fix bug X trong src/app.py."


def project(xml=None):
    global n
    n += 1
    p = os.path.join(TMP, "p%d" % n)
    for d in ("src", "tests", os.path.join(".claude", "audit-gate")):
        os.makedirs(os.path.join(p, d))
    open(os.path.join(p, "tests", "test_foo.py"), "w").write("def test_a():\n    assert 1\n")
    open(os.path.join(p, "src", "app.py"), "w").write("def f():\n    return 1\n")
    if xml is not None:   # a Gradle repo with one fresh TEST-*.xml
        open(os.path.join(p, "build.gradle"), "w").write("// gradle\n")
        os.makedirs(os.path.join(p, "app", "build", "test-results", "test"))
        open(os.path.join(p, "app", "build", "test-results", "test", "TEST-x.xml"), "w").write(xml)
    return p


def transcript(p, steps):
    lines = []
    for i, s in enumerate(steps):
        uid = "tu%d" % i
        if s[0] == "bash":
            use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": s[1]}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": s[2], "is_error": bool(s[3]) if len(s) > 3 else False}
        else:   # ["edit"]: src/app.py; ["edit_test"]: tests/test_foo.py, a test file written this session (the RED-check applies)
            f = os.path.join(p, "tests", "test_foo.py") if s[0] == "edit_test" else os.path.join(p, "src", "app.py")
            use = {"type": "tool_use", "id": uid, "name": "Edit", "input": {"file_path": f, "old_string": "1", "new_string": "2"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def run_gate(p, tr, msg):
    """(rc, stderr, CPU seconds of the hook tree). A hook still running after 30 s of wall time is killed with its process group: rc
    'timeout' (the Stop hook would have been cut and the claim let through)."""
    payload = json.dumps({"session_id": "i427-" + os.path.basename(p), "transcript_path": tr, "last_assistant_message": msg})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0", BUG_LINK_REMINDER="0", RED_PROOF="0", AUTO_LINK="0")
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    pr = subprocess.Popen(["bash", GATE], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                          env=env, start_new_session=True)
    try:
        _, err = pr.communicate(payload, timeout=30)
        rc = 99 if "Traceback" in err else pr.returncode
    except subprocess.TimeoutExpired:
        os.killpg(pr.pid, signal.SIGKILL)
        pr.communicate()
        rc, err = "timeout", ""
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    return rc, err, r1.ru_utime - r0.ru_utime + r1.ru_stime - r0.ru_stime


def case(name, steps, want, msg=PASS, xml=None, cpu=None):
    global fails
    p = project(xml)
    rc, err, used = run_gate(p, transcript(p, steps), msg)
    ok = rc == want and (cpu is None or used <= cpu)
    extra = "" if cpu is None else " (CPU %.2f s, cap %.1f s)" % (used, cpu)
    print(("✔ " if ok else "✖ ") + name + extra + ("" if ok else "  — want exit %s, got %s: %s" % (
        want, rc, " ".join(l for l in err.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


E, TE = ["edit"], ["edit_test"]
def after(cmd, out, err=False):          # a source edit, then one Bash call
    return [E, ["bash", cmd, out, err]]
def pair(red_cmd, red_out, green_cmd, green_out, red_err=True):   # a RED run, the fix, a GREEN run: check 7's pair
    return [["bash", red_cmd, red_out, red_err], E, ["bash", green_cmd, green_out, False]]
KIT_OK = "✔ x1\nall passed (1)"
PYOK = "5 passed in 0.10s"

print("-- R1: a masked runner next to a kit suite needs its own pass summary")
case("R1 must block: `pytest -q || true; bash kit`, pytest printed only dots", after("python3 -m pytest -q || true; bash tests/a/test_x.sh", "..F..\n" + KIT_OK), 2)
case("R1 must block: `pytest -q; true; bash kit`, pytest printed only dots", after("python3 -m pytest -q; true; bash tests/a/test_x.sh", "....\n" + KIT_OK), 2)
case("R1 control: the same with pytest's own pass summary stays green", after("python3 -m pytest -q || true; bash tests/a/test_x.sh", PYOK + "\n" + KIT_OK), 0)
case("R1 regression (closed before #427): `pytest > log || true`, no summary", after("python3 -m pytest -q > /tmp/l 2>&1 || true", ""), 2)
case("R1 regression (closed before #427): `pytest > log; true`, no summary", after("python3 -m pytest -q > /tmp/l 2>&1; true", ""), 2)

print("-- R3: a non-kit runner's printed failure is not undone by a kit's summary")
case("R3 must block: go test printed --- FAIL, then a kit suite all passed",
     after("go test ./...; bash tests/a/test_x.sh", "--- FAIL: TestX (0.00s)\nFAIL\texample.com/p\t0.1s\n" + KIT_OK), 2)
case("R3 must block: pytest printed a FAILED line, then a kit suite all passed",
     after("python3 -m pytest -q; bash tests/a/test_x.sh", "FAILED tests/test_a.py::test_x - assert 1\n" + KIT_OK), 2)
case("R3 control: pytest passed, then a kit suite all passed", after("python3 -m pytest -q; bash tests/a/test_x.sh", PYOK + "\n" + KIT_OK), 0)
case("R3 control: kit suites only, check lines with FAIL / ERROR words", after("bash tests/a/test_x.sh; bash tests/a/test_y.sh",
     "✔ REJECT on FAIL\nERROR: x\nall passed (2)\n✔ y\nall passed (1)"), 0)

print("-- R4: 200 KB of tool output is read in linear time, and a failure at its end is still read")
BIG = 200000
case("R4 RED_GRADLE: 200 KB of `XTest > ` with no FAILED in one tool result",
     [E, ["bash", "ls", "XTest > " * (BIG // 8)], ["bash", "python3 -m pytest -q", PYOK]], 0, cpu=3.0)
case("R4 TEST_FILE_IN_OUTPUT: a red run of 200 KB `a/a/…` after a test file edit, then green",
     [TE, E, ["bash", "python3 -m pytest -q", "a/" * (BIG // 2) + "\n1 failed in 0.1s", True], ["bash", "python3 -m pytest -q", PYOK]], 0, cpu=3.0)
case("R4 tag regexes: 100 KB of `<testsuite ` and 100 KB of `<test-run ` in a runner result",
     after("python3 -m pytest -q > /tmp/l 2>&1; echo x", "<testsuite " * (BIG // 22) + "\n" + "<test-run " * (BIG // 20)), 2, cpu=3.0)
case("R4 fail-closed: a FAILED line after 200 KB of output (exit 0) is still red",
     after("python3 -m pytest -q", "a" * BIG + "\nFAILED tests/test_a.py::test_x - assert 1"), 2, cpu=3.0)
case("R4 (review): a bare `echo $?` whose last line is 100 KB of `1…1x1` is read in linear time",
     after("python3 -m pytest -q > /tmp/l 2>&1; echo $?", "1" * (BIG // 2) + "x1"), 2, cpu=3.0)

print("-- P1-2: a runner counts only as the command of its segment")
case("P1-2 must block: a failed `pip install` of a pytest plugin is no RED half of check 7",
     pair("pip install -q pytest-nosuchplugin", "ERROR: Could not find a version that satisfies the requirement pytest-nosuchplugin",
          "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("P1-2 must block: a failed `touch pytest.ini` is no RED half of check 7",
     pair("touch pytest.ini", "touch: pytest.ini: Permission denied", "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("P1-2 must block: a heredoc body that names pytest is no run", after("python3 - <<'PY'\n# later: python3 -m pytest\nprint('12 passed')\nPY", "12 passed"), 2)
case("P1-2 must block: `pip install -q pytest` then a printed pass word", after("pip install -q pytest; echo '5 passed'", "5 passed"), 2)
case("P1-2 control: `pip install -q pytest` alone", after("pip install -q pytest", ""), 2)
case("P1-2 control: a real RED then a real GREEN still pair", pair("python3 -m pytest -q", "1 failed in 0.1s", "python3 -m pytest -q", PYOK), 0, msg=FIX)
case("P1-2 control: a runner inside a subshell `(cd sub && pytest -q)` still counts", after("(cd sub && python3 -m pytest -q)", PYOK), 0)
case("P1-2 control: a kit file deeper than tests/<dir>/ run through a pipe still counts",
     after("bash universal-agent-devkit/tests/x/test_y.sh 2>&1 | tail -5", KIT_OK), 0)
case("P1-2 control: `time ( bash kit | tail -3 )` still counts", after("time (bash tests/a/test_x.sh 2>&1 | tail -3)", KIT_OK), 0)
case("P1-2 control: a helper script given a kit test path still counts", after("S=/tmp/s; bash $S/run.sh tests/a/test_x.sh 80", KIT_OK), 0)
case("P1-2 control: `uv run --frozen --extra dev pytest -q | tail` still counts", after("uv run --frozen --extra dev pytest -q 2>&1 | tail -6", PYOK), 0)
case("P1-2 control: `bash -c 'cd sub && pytest -q'` still counts", after("bash -c 'cd sub && python3 -m pytest -q'", PYOK), 0)
UB = "caffeinate -dimsu env UNITY_TIMEOUT=1200 bash scripts/unity-batch.sh playmode 2>&1 | tail -6"
case("P1-2 control: a Unity run under `caffeinate … env …` is still both halves of check 7",
     pair(UB, "FAIL: PlayMode: 0 passed, 1 failed, 0 skipped (Unity exit 2)", UB, "PASS: PlayMode: 2 passed, 0 failed, 0 skipped", red_err=False),
     0, msg=FIX)
case("P1-2 must pass: a bare `echo $?` ending the command and printing 1 is the RED half of check 7",
     pair("python3 -m pytest -q > /tmp/l 2>&1; echo $?", "1", "python3 -m pytest -q", PYOK, red_err=False), 0, msg=FIX)
case("P1-2 control: a bare `echo $?` printing 0 is still no green", after("python3 -m pytest -q > /tmp/l 2>&1; echo $?", "0"), 2)
# Review #427: cờ của trình thông dịch trước `-m`, `coverage run`, và wrapper giữ mã thoát (xvfb-run, stdbuf, sudo, exec, bundle exec,
# xcrun, arch) vẫn là lần chạy. `docker compose run … pytest` không có ở đây (backlog).
for c in ("python3 -u -m pytest -q", "python3 -B -m pytest -q", "python3 -X dev -m pytest -q", "python3 -W error -m pytest -q",
          "coverage run -m pytest -q", "python3 -m coverage run -m pytest -q", "xvfb-run -a python3 -m pytest -q",
          "stdbuf -oL python3 -m pytest -q", "sudo python3 -m pytest -q", "exec pytest -q", "bundle exec rspec",
          "xcrun xcodebuild test", "arch -arm64 xcodebuild test"):
    case("P1-2 must pass (review): `%s` is a run" % c, after(c, PYOK), 0)
case("P1-2 control (review): `sudo pip install -q pytest` then a printed pass word", after("sudo pip install -q pytest; echo '5 passed'", "5 passed"), 2)
case("P1-2 control (review): `python3 -X dev -m pip install pytest` then a printed pass word",
     after("python3 -X dev -m pip install pytest; echo '5 passed'", "5 passed"), 2)

print("-- P1-4: one summary line per unbound kit run once one of them is masked")
CRASH = "tests/a/test_x.sh: line 3: FOO: unbound variable\n✔ y1\nall passed (1)"
case("P1-4 must block: `bash x; bash y`, x crashed silently, y all passed", after("bash tests/a/test_x.sh; bash tests/a/test_y.sh", CRASH), 2)
case("P1-4 must block: `bash x; bash y`, x crashed silently, y prints ✅ per check (not summaries)",
     after("bash tests/a/test_x.sh; bash tests/a/test_y.sh", "tests/a/test_x.sh: line 3: FOO: unbound variable\n✅ a\n✅ b\n✅ test_y: all passed"), 2)
case("P1-4 must block: `for t in x y; do bash tests/a/test_$t.sh; done`, one summary",
     after("for t in x y; do bash tests/a/test_$t.sh; done", CRASH), 2)
case("P1-4 regression (closed before #427): `bash x > log || true; bash y`",
     after("bash tests/a/test_x.sh > /tmp/lx 2>&1 || true; bash tests/a/test_y.sh", "✔ y1\nall passed (1)"), 2)
case("P1-4 must pass: `bash x | tail -3; bash y | tail -3`, each with its summary",
     after("bash tests/a/test_x.sh 2>&1 | tail -3; bash tests/a/test_y.sh 2>&1 | tail -3", KIT_OK + "\n✔ y1\nall passed (1)"), 0)
case("P1-4 must pass: `pytest | tail -3; pytest b | tail -3`, each with its summary",
     after("python3 -m pytest -q 2>&1 | tail -3; python3 -m pytest -q tests/b 2>&1 | tail -3", "12 passed in 0.50s\n4 passed in 0.10s"), 0)
case("P1-4 control: `for t in x y` with two summaries", after("for t in x y; do bash tests/a/test_$t.sh; done", KIT_OK + "\n✔ y1\nall passed (1)"), 0)
case("P1-4 control: `bash x > log && bash y` (x's exit is the tool's)", after("bash tests/a/test_x.sh > /tmp/l 2>&1 && bash tests/a/test_y.sh", "✔ y1\nall passed (1)"), 0)
case("P1-4 control: one direct kit run at any depth, check marks and no summary line",
     after("bash universal-agent-devkit/tests/x/test_y.sh", "✔ a\n✔ b"), 0)
PSLOOP = 'for t in a b c; do bash tests/a/test_$t.sh 2>&1 | tail -3; echo "$t exit=${pipestatus[1]}"; done'
case("P1-4 control: a loop that prints each run's ${pipestatus[1]} = 0 (summary styles vary)",
     after(PSLOOP, "PASS a\na exit=0\nALL OK\nb exit=0\n✅ c: all passed\nc exit=0"), 0)
case("P1-4 must block: the same loop with one run's ${pipestatus[1]} = 1",
     after(PSLOOP, "PASS a\na exit=0\nb exit=1\n✅ c: all passed\nc exit=0"), 2)
# Review #427: `test_$t.sh` vào nhánh suite kit, nhánh đó chỉ đọc DEVKIT_SUITE_RED (không RUNNER_FAIL_RX), còn danh sách brace / $VAR
# đếm là 1: lỗi `3 failure(s)` của lần chạy đầu bị 'all passed' của lần sau che.
LOOP_TAIL1 = "do bash tests/gates/test_$t.sh 2>&1 | tail -1; done"
FAIL3 = "3 failure(s)\n✅ test_b: all passed"
case("P1-4 must block (review): a brace-list loop whose first run printed `3 failure(s)`",
     after("for t in guard_{kill_by_name,protected_push}; " + LOOP_TAIL1, FAIL3), 2)
case("P1-4 must block (review): a `$SUITES` loop whose first run printed `3 failure(s)`", after("for t in $SUITES; " + LOOP_TAIL1, FAIL3), 2)
case("P1-4 must block (review): a brace-list loop (2 runs), the first crashed silently, one summary",
     after("for t in guard_{kill_by_name,protected_push}; " + LOOP_TAIL1, "tests/gates/test_guard_kill_by_name.sh: line 3: FOO: unbound variable\n✅ test_b: all passed"), 2)
case("P1-4 control (review): the brace-list loop with a summary per run",
     after("for t in guard_{kill_by_name,protected_push}; " + LOOP_TAIL1, "✅ test_a: all passed\n✅ test_b: all passed"), 0)

print("-- E3: Unity -testResults <f> is the run's result sent to a file")
# Unity không xoá file kết quả lúc bắt đầu: Editor chết trước khi ghi thì `cat r.xml` in XML XANH của lần trước. Sau `;` mã thoát
# của Unity không gắn với gì, nên XML đó không là tóm tắt của lần này; `&& cat` thì cat chỉ chạy khi Unity thoát 0.
UNITY = "Unity -batchmode -projectPath . -runTests -testPlatform EditMode -testResults r.xml"
X_GREEN = '<test-run id="2" testcasecount="4" result="Passed" total="4" passed="4" failed="0" inconclusive="0" skipped="0">'
X_RED = '<test-run id="2" testcasecount="4" result="Failed" total="4" passed="3" failed="1" inconclusive="0" skipped="0">'
case("E3 must block: `Unity … -testResults r.xml; cat r.xml` printing a green XML", after(UNITY + "; cat r.xml", X_GREEN), 2)
case("E3 must block: the same with `|| true` before the cat", after(UNITY + " || true; cat r.xml", X_GREEN), 2)
case("E3 control: `Unity … -testResults r.xml && cat r.xml`: cat runs only after exit 0", after(UNITY + " && cat r.xml", X_GREEN), 0)
case("E3 control: `&& cat` RED (failed=\"1\") → fix → GREEN is check 7's pair",
     pair(UNITY + " && cat r.xml", X_RED, UNITY + " && cat r.xml", X_GREEN, red_err=False), 0, msg=FIX)
# Review #427: lệnh Unity thật của repo game, mã thoát gắn bằng `echo "edit exit=$?"` (nhãn có dấu cách).
UNITY_REAL = ('/Applications/Unity/Hub/Editor/6000.0.1f1/Unity.app/Contents/MacOS/Unity -batchmode -projectPath . -runTests '
              '-testPlatform EditMode -testResults "$S/edit.xml" -logFile "$S/edit.log"; echo "edit exit=$?"; '
              "grep -o '<test-run[^>]*' \"$S/edit.xml\" | head -1")
X6 = '<test-run id="2" testcasecount="6" result="Passed" total="6" passed="6" failed="0"'
X6_RED = '<test-run id="2" testcasecount="6" result="Failed" total="6" passed="5" failed="1"'
case("E3 must pass (review): `Unity … -testResults f; echo \"edit exit=$?\"; grep … f` printing exit=0 and a green XML",
     after(UNITY_REAL, "edit exit=0\n" + X6), 0)
case("E3 must pass (review): the same, exit=1 / failed=\"1\" → fix → exit=0 is check 7's pair",
     pair(UNITY_REAL, "edit exit=1\n" + X6_RED, UNITY_REAL, "edit exit=0\n" + X6, red_err=False), 0, msg=FIX)
case("E3 control (review): the same printing `edit exit=2` and a green XML (stale) is no green", after(UNITY_REAL, "edit exit=2\n" + X6), 2)

print("-- N: deep nesting")
# Review #427 (OCR): _segment_is_runner đệ quy vào thân `( … )` không giới hạn: 400 lớp ném RecursionError, hook thoát 0 với traceback
# (claim lọt). Lồng quá sâu thì không phải lần chạy: claim bị chặn, không crash.
NEST = "(" * 400 + "python3 -m pytest -q" + ")" * 400
case("N must block: 400 nested ( … ) around pytest: no RecursionError, the pass claim is blocked", after(NEST, PYOK), 2)
case("N control: 3 nested ( … ) around pytest is still a run", after("(((python3 -m pytest -q)))", PYOK), 0)

print("-- O: OCR review of the review fixes")
# `python -i` với stdin hết trả 0 dù test lỗi; `sudo -b` chạy nền và trả 0 ngay, `sudo -l` không chạy gì; tín hiệu EXIT qua biến; thân
# trap trong ngoặc kép mở rộng lúc đặt trap; `kill $BASHPID` (bash) giết chính shell.
case("O must block: `python3 -i -m pytest -q > log`, exit 0, no output", after("python3 -i -m pytest -q > /tmp/l 2>&1", ""), 2)
case("O must block: `sudo -b python3 -m pytest -q > log`, exit 0, no output", after("sudo -b python3 -m pytest -q > /tmp/l 2>&1", ""), 2)
case("O must block: `sudo -l python3 -m pytest -q > log; echo \"rc=$?\"` printing rc=0",
     after("sudo -l python3 -m pytest -q > /tmp/l 2>&1; echo \"rc=$?\"", "rc=0"), 2)
case("O must block: `A=EXIT; trap 'exit 0' $A` before a hidden run",
     after("A=EXIT; trap 'exit 0' $A; python3 -m pytest -q > /tmp/l 2>&1", ""), 2)
case("O must block: a double-quoted trap body with a variable (expanded when the trap is set)",
     after("X='/tmp/x; exit 0'; trap \"rm -rf $X\" EXIT; python3 -m pytest -q > /tmp/l 2>&1", ""), 2)
case("O must block: `trap 'kill -9 $BASHPID' EXIT` forging the RED half of check 7",
     pair("trap 'kill -9 $BASHPID' EXIT; python3 -m pytest -q", PYOK, "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("O control: `sudo -E python3 -m pytest -q` is still a run", after("sudo -E python3 -m pytest -q", PYOK), 0)
case("O control: `python3 -u -m pytest -q` is still a run", after("python3 -u -m pytest -q", PYOK), 0)

print("-- E4: an EXIT trap owns the tool's exit")
case("E4 must block: `trap 'exit 0' EXIT; pytest -q` with no summary", after("trap 'exit 0' EXIT; python3 -m pytest -q", "....F...."), 2)
case("E4 must block: `trap 'exit 1' EXIT` forging the RED half of check 7",
     pair("trap 'exit 1' EXIT; python3 -m pytest -q", PYOK, "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("E4 control: a trap after the run, with the run's own summary", after("python3 -m pytest -q; trap 'exit 0' EXIT", PYOK), 0)
case("E4 control: the word trap in an echo is no trap", after("echo 'no trap EXIT here' && python3 -m pytest -q", ""), 0)
WRITE_RUN = "cat > tests/a/test_x.sh <<'EOF'\nTMP=$(mktemp -d)\ntrap 'rm -rf \"$TMP\"' EXIT\necho ok\nEOF\nbash tests/a/test_x.sh"
case("E4 control: a trap inside a heredoc body (a test file written, then run) is data: its failure is the RED half",
     pair(WRITE_RUN, "tests/a/test_x.sh: line 4: FOO: unbound variable", "bash tests/a/test_x.sh", KIT_OK), 0, msg=FIX)
# Review #427: thân trap trong ngoặc chỉ dọn dẹp (rm, kill, cd, echo…) không đổi mã thoát: lỗi của runner vẫn là nửa ĐỎ.
case("E4 must pass (review): `trap 'rm -rf $T' EXIT` keeps the run's exit: its failure is the RED half of check 7",
     pair("T=$(mktemp -d); trap 'rm -rf $T' EXIT; bash tests/a/test_x.sh", "tests/a/test_x.sh: line 3: FOO: unbound variable",
          "bash tests/a/test_x.sh", "✅ test_x: all passed"), 0, msg=FIX)
case("E4 must block (review): `trap 'kill $$' EXIT` (the shell kills itself: 143 / 137) forging the RED half of check 7",
     pair("trap 'kill $$' EXIT; python3 -m pytest -q", PYOK, "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("E4 control (review): `trap 'rm -rf $T; exit 0' EXIT` with no summary", after("trap 'rm -rf $T; exit 0' EXIT; python3 -m pytest -q", "....F...."), 2)
case("E4 control (review): `trap cleanup EXIT` (a function: unknown body) with no summary", after("trap cleanup EXIT; python3 -m pytest -q", "....F...."), 2)
case("E4 control (review): `trap \"rm -rf $(cat d)\" EXIT` (command substitution) with no summary",
     after('trap "rm -rf $(cat d)" EXIT; python3 -m pytest -q', "....F...."), 2)

print("-- T8: tail -N of mocha / node --test / go test keeps no verdict")
GO2 = "ok  \texample.com/b\t0.1s\nok  \texample.com/c\t0.1s"
MOCHA_TAIL = "      at Context.<anonymous> (test/a.js:5:9)\n\n12 passing (20ms)"
case("T8 must block: `go test ./... | tail -2 && pytest` (a failing package outside the tail)",
     after("go test ./... 2>&1 | tail -2 && python3 -m pytest -q", GO2 + "\n" + PYOK), 2)
case("T8 must block: `go test ./... | tail -2` alone", after("go test ./... | tail -2", GO2), 2)
case("T8 must block: `go test ./... |` then `tail -2` on the next line", after("go test ./... 2>&1 |\n  tail -2", GO2), 2)
case("T8 must block: `mocha | tail -3; npx mocha other`", after("npx mocha 2>&1 | tail -3; npx mocha other", MOCHA_TAIL), 2)
case("T8 must block: `mocha | tail -3; cat last.log`", after("npx mocha 2>&1 | tail -3; cat last.log", MOCHA_TAIL), 2)
case("T8 must block: `node --test | tail -3; node --test b`", after("node --test 2>&1 | tail -3; node --test b", "    at x\n\nℹ pass 5\nℹ fail 0"), 2)
case("T8 must block: go test through tail with ${PIPESTATUS[0]} printing 1",
     after('go test ./... 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"', "ok  \texample.com/pkg\t0.12s\nrc=1"), 2)
case("T8 control: ${PIPESTATUS[0]} = 127 (`timeout: command not found`) is no RED half of check 7",
     pair('timeout 500 ./gradlew test 2>&1 | tail -30; echo "EXIT=${PIPESTATUS[0]}"', "(eval):1: command not found: timeout\nEXIT=127",
          "python3 -m pytest -q", PYOK, red_err=False), 2, msg=FIX)
case("T8 control: go test through tail with ${PIPESTATUS[0]} printing 0",
     after('go test ./... 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"', "ok  \texample.com/pkg\t0.12s\nrc=0"), 0)
case("T8 control: go test with no pipe", after("go test ./...", GO2), 0)
case("T8 control: one go package through tail (its ok / FAIL line is the last)", after("go test -count=1 . 2>&1 | tail -2", "ok  \tapkmanager\t0.5s"), 0)
case("T8 control: go test ./... through tail -5 that printed only 2 lines (nothing cut)", after("go test ./... 2>&1 | tail -5", GO2), 0)
case("T8 control: mocha through tail alone shows its own summary", after("npx mocha 2>&1 | tail -5", "\n  12 passing (20ms)\n"), 0)

print("-- Q9: what prints in place of a cut summary")
case("Q9 must pass: pytest through tail -N, then `git -C <repo> commit -q` with a pass word",
     after('python3 -m pytest -q 2>&1 | tail -3 && git -C /repo commit -qm "fix: 12 tests passed"', "12 passed in 0.50s"), 0)
case("Q9 must pass: pytest through tail -N, then `git -c k=v commit -qam` with a pass word",
     after("python3 -m pytest -q 2>&1 | tail -3 && git -c user.name=t commit -qam 'x: 12 passed'", "12 passed in 0.50s"), 0)
case("Q9 must block: a failing mocha through tail, `git commit -q`, then `git log --oneline -1`",
     after("npx mocha 2>&1 | tail -3; git commit -q -m 'fix: 12 passing'; git log --oneline -1",
           "      at Context.<anonymous> (test/a.js:5:9)\n\nabc1234 fix: 12 passing"), 2)
case("Q9 must block: a crashed kit suite through tail, `git commit -q`, then `git log` printing 'all passed'",
     after('bash tests/a/test_x.sh 2>&1 | tail -3; git commit -qm "all passed"; git log --oneline -1',
           "tests/a/test_x.sh: line 3: FOO: unbound variable\nabc1234 all passed"), 2)
case("Q9 must pass: pytest through tail -N, then `cat > f <<EOF … passed … EOF`",
     after("python3 -m pytest -q 2>&1 | tail -3; cat > /tmp/n.md <<'EOF'\n12 passed\nEOF", "12 passed in 0.50s"), 0)
case("Q9 must pass: pytest through tail -N, then `printf … > /dev/null`",
     after("python3 -m pytest -q 2>&1 | tail -3; printf '12 passed' > /dev/null", "12 passed in 0.50s"), 0)
case("Q9 must pass: pytest through tail -N, then `gh pr comment --body \"… passed\"`",
     after("python3 -m pytest -q 2>&1 | tail -3; gh pr comment 5 --body 'tests: 12 passed'", "12 passed in 0.50s\nhttps://github.com/o/r/pull/5#issuecomment-1"), 0)
case("Q9 control: a pass word echoed to stderr still stands in", after("npx mocha 2>&1 | tail -3; echo '12 passing' >&2", MOCHA_TAIL), 2)
# Review #427: ghi ra file rồi một segment sau đọc lại file đó: không im lặng.
case("Q9 must block (review): a pass word written to a file that a later segment cats",
     after("python3 -m pytest -q 2>&1 | tail -3; echo '12 passed' > /tmp/s; cat /tmp/s", "....\n12 passed"), 2)
case("Q9 must block (review): a heredoc written to a file, then `cat` of that file",
     after("python3 -m pytest -q 2>&1 | tail -3; cat > /tmp/r.md <<'EOF'\nresult: 12 passed\nEOF\ncat /tmp/r.md", "....\nresult: 12 passed"), 2)
case("Q9 must block (review): a pass word written to a quoted variable target, then a later segment",
     after("python3 -m pytest -q 2>&1 | tail -3; echo '12 passed' > \"$F\"; cat \"$F\"", "....\n12 passed"), 2)
case("Q9 must pass (review): a heredoc to a file that no later segment names",
     after("python3 -m pytest -q 2>&1 | tail -3; cat > /tmp/n.md <<'EOF'\n12 passed\nEOF\ngit status --short", "12 passed in 0.50s"), 0)
case("Q9 must pass (review): `printf … > /dev/null`, then another segment",
     after("python3 -m pytest -q 2>&1 | tail -3; printf '12 passed' > /dev/null; git status --short", "12 passed in 0.50s"), 0)
case("Q9 control: a pass word written to /dev/stderr still stands in",
     after('python3 -m pytest -q 2>&1 | tail -1; echo "12 passed" > /dev/stderr', "....\n12 passed"), 2)

print("-- X: a TEST-*.xml whose count is not a number")
case("X must block: failures=\"x\" in a fresh TEST-*.xml, no traceback",
     [E], 2, xml='<testsuite name="a.FooTest" tests="3" failures="x" errors="0" skipped="0"><testcase classname="a.FooTest" name="t"/></testsuite>')
case("X control: a clean fresh TEST-*.xml backs the claim",
     [E], 0, xml='<testsuite name="a.FooTest" tests="3" failures="0" errors="0" skipped="0"><testcase classname="a.FooTest" name="t"/></testsuite>')

shutil.rmtree(TMP, ignore_errors=True)
print("")
print("test_evidence_issue427: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PYEND
