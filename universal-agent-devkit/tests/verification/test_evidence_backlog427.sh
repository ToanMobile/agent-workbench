#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh, the backlog of issue #427 left after round 1 (PR #452), closed in round 2. Each must-block
# row was green (or a forged RED half of check 7, or past the CPU cap) on the hook before the fix; each must-pass row was blocked. Every
# relaxation sits next to an adversarial row that must stay blocked.
#   1  `_TEST_ARG` backtracked quadratically on one long path component (`tests/` + "test" × 20 000: 4.7 s of CPU per call); `_PS_LABEL`
#      did the same on any long word (24 s); `tests/` repeated 15 000 times made SCRIPT_RUNNER_RX / DEVKIT_SUITE_RX restart at each one.
#      A hook cut at the Stop cap lets the claim through. Bounded by CPU (getrusage), not wall time.
#   2  R5, deliberate spoofing, only NARROWED: a runner after `||` of a command that always succeeds (`true || pytest`) never runs; a
#      function / alias that redefines echo, cat, tail… or the runner itself, in this command (each Bash call is a new shell), makes the
#      exit code and every printed summary untrusted. No verdict either way.
#   3  a later segment that prints a FILE (`cat f`, `tail f`, `sed -n … f`) stands in for the summary of a run before it.
#   4  `npm|yarn|pnpm test | tail -N` printing mocha's shape keeps no verdict from the tail (mocha's failures come after its summary).
#   5  `_kit_count` counts `{1..3}` and nested braces; never below the old count; huge ranges and products stay fast and blocked.
#   6  a glob / $VAR loop over kit suites whose output carries an interpreter error (`line N:`, `unbound variable`, `command not found`,
#      `Traceback`, …) on a line that is not the kit's: one run crashed, another printed the summary.
#   7  `python3 -um pytest`, `-Bum`: combined flags before `-m` (`-uim` still is no run).
#   8  `sudo --user x …` is a run.
#   9  `docker [compose] run|exec … pytest` is a run (not with -d / --detach / --entrypoint).
#  10  P1-4 counting: a standalone `PASS` line and `✅ x: tất cả PASS` are summaries (2 real false blocks of 3029 calls). The part "do not
#      count the last kit run whose exit is the tool's" is NOT done: it lets `bash x; bash y` (x crashed silently) through (P1-4 row of
#      tests/verification/test_evidence_issue427.sh).
#  11  a kit loop whose output has a non-check line like `linter reports 2 errors`: only a line that looks like a runner's own failure counts.
#  12  review of round 2: (a) a bare PASS counts only where a run's output ends (last line, before an echoed `<label>=0`, last line of an
#      exactly filled `2>&1 | tail -N` window); (b) docker's own errors (OCI runtime, no compose file, service with no image) are no RED;
#      (c) `function NAME` / `NAME()` only at command position with a body, judged per call; (d) `sed -i` prints nothing, `echo … || x`
#      skips something only when x is a runner.
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
        else:   # ["edit"]: src/app.py
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p, "src", "app.py"), "old_string": "1", "new_string": "2"}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def run_gate(p, tr, msg):
    """(rc, stderr, CPU seconds of the hook tree). A hook still running after 30 s of wall time is killed with its process group: rc
    'timeout' (the Stop hook would have been cut and the claim let through)."""
    payload = json.dumps({"session_id": "b427-" + os.path.basename(p), "transcript_path": tr, "last_assistant_message": msg})
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


def case(name, steps, want, msg=PASS, cpu=None):
    global fails
    p = project()
    rc, err, used = run_gate(p, transcript(p, steps), msg)
    ok = rc == want and (cpu is None or used <= cpu)
    extra = "" if cpu is None else " (CPU %.2f s, cap %.1f s)" % (used, cpu)
    print(("✔ " if ok else "✖ ") + name + extra + ("" if ok else "  — want exit %s, got %s: %s" % (
        want, rc, " ".join(l for l in err.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


E = ["edit"]
def after(cmd, out, err=False):          # a source edit, then one Bash call
    return [E, ["bash", cmd, out, err]]
def pair(red_cmd, red_out, green_cmd, green_out, red_err=True):   # a RED run, the fix, a GREEN run: check 7's pair
    return [["bash", red_cmd, red_out, red_err], E, ["bash", green_cmd, green_out, False]]
KIT_OK = "✔ x1\nall passed (1)"
PYOK = "5 passed in 0.10s"
CRASH_X = "tests/a/test_x.sh: line 3: FOO: unbound variable\n"

print("-- 1: long words are read in linear time")
case("1 must block: `bash $S/run.sh tests/<\"test\" x 20 000> pytest` (_TEST_ARG)",
     after("S=x; bash $S/run.sh tests/" + "test" * 20000 + " pytest", PYOK), 2, cpu=3.0)
case("1 must block: `bash tests/<\"test\" x 10 000> tests/a/test_x.sh`, no summary (_PS_LABEL, _TEST_ARG)",
     after("bash tests/" + "test" * 10000 + " tests/a/test_x.sh", "✔ x1"), 2, cpu=3.0)
case("1 must block: `bash tests/<\"tests/\" x 15 000>x.sh pytest` (a test path of 15 000 components is none)",
     after("bash tests/" + "tests/" * 15000 + "x.sh pytest", PYOK), 2, cpu=3.0)
case("1 control: a kit file 40 directories deep is still a run", after("bash tests/" + "a/" * 40 + "test_x.sh", KIT_OK), 0)
case("1 control: `python3 runtests.py r3 tests/gates/test_x.sh` (a test path as an argument) is still a run",
     after("python3 runtests.py r3 tests/gates/test_x.sh", KIT_OK), 0)

print("-- 2: R5, a runner that never runs, a redefined echo / cat / tail / runner (narrowed, not closed)")
case("2a must block: `true || python3 -m pytest -q` (pytest never runs)", after("true || python3 -m pytest -q", PYOK), 2)
case("2a must block: `: || python3 -m pytest -q`", after(": || python3 -m pytest -q", PYOK), 2)
case("2a must block: `echo go || python3 -m pytest -q`", after("echo go || python3 -m pytest -q", PYOK), 2)
case("2a must block: `(true || python3 -m pytest -q)`", after("(true || python3 -m pytest -q)", PYOK), 2)
case("2a must block: `bash -c 'true || python3 -m pytest -q'`", after("bash -c 'true || python3 -m pytest -q'", PYOK), 2)
case("2a must block: `true || pytest; exit 1` forging the RED half of check 7",
     pair("true || python3 -m pytest -q; exit 1", "", "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("2a control: `python3 -m pytest -q || true` with its own summary", after("python3 -m pytest -q || true", PYOK), 0)
case("2a control: `false || python3 -m pytest -q` with its own summary", after("false || python3 -m pytest -q", PYOK), 0)
case("2b must block: `cat() { …; }` then pytest piped through cat", after("cat() { echo '5 passed'; }; python3 -m pytest -q 2>&1 | cat", PYOK), 2)
case("2b must block: `function tail { …; }` then pytest piped through tail",
     after("function tail { echo '5 passed'; }; python3 -m pytest -q 2>&1 | tail -3", PYOK), 2)
case("2b must block: `alias tail='echo 5 passed #'` then pytest piped through tail",
     after("alias tail='echo 5 passed #'; python3 -m pytest -q 2>&1 | tail -3", PYOK), 2)
case("2b must block: `pytest() { echo '5 passed'; }; pytest -q` (the runner itself)", after("pytest() { echo '5 passed'; }; pytest -q", PYOK), 2)
case("2b must pass: `cat() { …; }` in an EARLIER Bash call does not reach a later one (each call is a new shell)",
     [E, ["bash", "cat() { echo '5 passed'; }", ""], ["bash", "python3 -m pytest -q 2>&1 | cat", PYOK]], 0)
case("2b control: a heredoc body that defines echo() is data", after("cat > /tmp/lib.sh <<'EOF'\necho() { :; }\nEOF\npython3 -m pytest -q", PYOK), 0)
case("2b control: `echo() {` inside a quoted commit message is data",
     after("git commit -qm 'drop the echo() { } helper' && python3 -m pytest -q", PYOK), 0)
case("2b control: a helper function with another name", after("run() { :; }; python3 -m pytest -q", PYOK), 0)

print("-- 3: a later segment that prints a file stands in for the summary")
DOTS = "....\n12 passed in 0.50s"
for c in ("cat /tmp/old.log", "tail -5 /tmp/old.log", "head -n 3 /tmp/old.log", "sed -n '1,5p' /tmp/old.log", "less /tmp/old.log",
          "cat < /tmp/old.log", "grep passed /tmp/old.log"):
    case("3 must block: `pytest -q | tail -3; %s`" % c, after("python3 -m pytest -q 2>&1 | tail -3; " + c, DOTS), 2)
case("3 must block (suite branch): `bash x; cat old.log`, x crashed silently, the file holds 'all passed (3)'",
     after("bash tests/a/test_x.sh; cat /tmp/old.log", CRASH_X + "all passed (3)"), 2)
case("3 must block (suite branch): `bash x | tail -3; cat old.log`, x crashed silently",
     after("bash tests/a/test_x.sh 2>&1 | tail -3; cat /tmp/old.log", CRASH_X + "all passed (3)"), 2)
case("3 control: `pytest -q | tail -3; git status --short`", after("python3 -m pytest -q 2>&1 | tail -3; git status --short", DOTS), 0)
case("3 control: `pytest -q | tail -3; echo x | cat` (cat is a pipe stage)", after("python3 -m pytest -q 2>&1 | tail -3; echo x | cat", DOTS), 0)
case("3 control: `pytest > log && tail -3 log` (the tool's exit is the run's)",
     after("python3 -m pytest -q > /tmp/l 2>&1 && tail -3 /tmp/l", PYOK), 0)
case("3 control: `pytest | tail -3; cat > f <<EOF … EOF` (a writer)",
     after("python3 -m pytest -q 2>&1 | tail -3; cat > /tmp/n.md <<'EOF'\n12 passed\nEOF", DOTS), 0)
case("3 control: `pytest | tail -3; cat f > /dev/null`", after("python3 -m pytest -q 2>&1 | tail -3; cat /tmp/f > /dev/null", DOTS), 0)
case("3 control: `bash x | tail -3; bash y | tail -3`, each with its summary",
     after("bash tests/a/test_x.sh 2>&1 | tail -3; bash tests/a/test_y.sh 2>&1 | tail -3", KIT_OK + "\n✔ y1\nall passed (1)"), 0)

print("-- 4: npm / yarn / pnpm test through tail -N, printing mocha's shape")
MOCHA5 = "      at Context.<anonymous> (test/a.js:5:9)\n      at process.processImmediate (node:internal/timers:476:21)\n\n\n12 passing (20ms)"
case("4 must block: `npm test | tail -5; node scripts/report.js` (mocha shape)", after("npm test 2>&1 | tail -5; node scripts/report.js", MOCHA5), 2)
case("4 must block: `yarn test | tail -5; echo done`", after("yarn test 2>&1 | tail -5; echo done", MOCHA5 + "\ndone"), 2)
case("4 must block: `pnpm test | tail -5; npx eslint .`", after("pnpm test 2>&1 | tail -5; npx eslint .", MOCHA5), 2)
case("4 control: `npm test | tail -5` alone, mocha's summary in sight", after("npm test 2>&1 | tail -5", "\n  12 passing (20ms)\n\n\n"), 0)
JEST5 = "PASS src/a.test.js\nPASS src/b.test.js\n\nTest Suites: 2 passed, 2 total\nTests:       12 passed, 12 total"
case("4 control: `npm test | tail -5; echo done` printing jest's shape", after("npm test 2>&1 | tail -5; echo done", JEST5 + "\ndone"), 0)

print("-- 5: _kit_count counts ranges and nested braces")
LOOP = "do bash tests/gates/test_$t.sh 2>&1 | tail -1; done"
case("5 must block: `for t in {1..3}` with two summaries", after("for t in {1..3}; " + LOOP, "✅ a: all passed\n✅ b: all passed"), 2)
case("5 must block: `for t in g_{a,b_{c,d}}` (3 runs) with two summaries", after("for t in g_{a,b_{c,d}}; " + LOOP, "✅ a: all passed\n✅ b: all passed"), 2)
case("5 control: `for t in {1..3}` with three summaries", after("for t in {1..3}; " + LOOP, "✅ a: all passed\n✅ b: all passed\n✅ c: all passed"), 0)
case("5 must block: `{1..<5 000 nines>}` with one summary: fast, no traceback",
     after("for t in {1.." + "9" * 5000 + "}; " + LOOP, "✅ a: all passed"), 2, cpu=2.0)
case("5 regression: 30 `{a,b}` groups in one word: fast, blocked", after("for t in x" + "{a,b}" * 30 + "; " + LOOP, "✅ a: all passed"), 2, cpu=2.0)

print("-- 6: a loop of unknown size over kit suites, one run crashed")
for marker in ("tests/a/test_x.sh: line 3: FOO: unbound variable", "tests/a/test_x.sh: line 9: jq: command not found",
               "Traceback (most recent call last):", "Segmentation fault: 11"):
    case("6 must block: glob loop, `%s` then a summary" % marker[-30:],
         after('for f in tests/a/test_*.sh; do bash "$f"; done', marker + "\n✔ y1\nall passed (1)"), 2)
case("6 must block: `$SUITES` loop of kit suites, a crash line then one summary",
     after("for t in $SUITES; " + LOOP, "tests/gates/test_a.sh: line 3: FOO: unbound variable\n✅ test_b: all passed"), 2)
case("6 must block: `while read t` loop of kit suites, a crash line then one summary",
     after("while read t; do bash tests/gates/test_$t.sh 2>&1 | tail -1; done < /tmp/list.txt",
           "tests/gates/test_a.sh: line 3: FOO: unbound variable\n✅ test_b: all passed"), 2)
case("6 control: the glob loop of tests/gates/test_evidence_false_blocks.sh section D stays green",
     after('for f in tests/a/test_*.sh; do echo "== $f" >> /tmp/ran.txt; bash "$f"; done', "✔ case 1\nok: done\n✔ case 2"), 0)
case("6 control: an error word on a kit check line is the kit's",
     after('for f in tests/a/test_*.sh; do bash "$f"; done', "✔ a missing tool prints command not found\nall passed (3)"), 0)

print("-- 7: combined python flags before -m")
for c in ("python3 -um pytest -q", "python3 -Bum pytest -q"):
    case("7 must pass: `%s` is a run" % c, after(c, PYOK), 0)
case("7 control: `python3 -uim pytest -q > log` (-i) is no run", after("python3 -uim pytest -q > /tmp/l 2>&1", ""), 2)
case("7 control: `python3 -ui -m pytest -q > log` is no run", after("python3 -ui -m pytest -q > /tmp/l 2>&1", ""), 2)
case("7 control: `python3 -um pip install pytest` then a printed pass word", after("python3 -um pip install pytest; echo '5 passed'", "5 passed"), 2)

print("-- 8: sudo --user x")
case("8 must pass: `sudo --user x python3 -m pytest -q` is a run", after("sudo --user x python3 -m pytest -q", PYOK), 0)
for c in ("sudo --user=x python3 -m pytest -q", "sudo -u x python3 -m pytest -q"):
    case("8 control: `%s` is still a run" % c, after(c, PYOK), 0)
case("8 control: `sudo -l --user x python3 -m pytest -q > log; echo \"rc=$?\"` printing rc=0 is no run",
     after("sudo -l --user x python3 -m pytest -q > /tmp/l 2>&1; echo \"rc=$?\"", "rc=0"), 2)

print("-- 9: docker / docker compose run|exec")
for c in ("docker compose run --rm -e K=V web pytest -q", "docker compose run web python3 -m pytest -q", "docker compose exec web pytest -q",
          "docker compose exec -T web pytest -q", "docker run --rm -v /a:/b -w /src img pytest -q", "docker exec -it ctr pytest -q",
          "docker-compose -f x.yml run --rm web pytest -q", "docker --context ci run img pytest -q"):
    case("9 must pass: `%s` is a run" % c, after(c, PYOK), 0)
case("9 must pass: a RED `docker compose run web pytest`, the fix, a GREEN one is check 7's pair",
     pair("docker compose run --rm web pytest -q", "1 failed in 0.1s", "docker compose run --rm web pytest -q", PYOK), 0, msg=FIX)
for out in ("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
            "Error response from daemon: No such container: ctr", "no such service: web"):
    case("9 must block: a docker-level error (`%s`) is no RED half of check 7" % out[:40],
         pair("docker compose run --rm web pytest -q", out, "python3 -m pytest -q", PYOK), 2, msg=FIX)
for c in ("docker run -d img pytest -q", "docker run -dit img pytest -q", "docker run --detach=true img pytest -q",
          "docker compose exec -d web pytest -q", "docker run --entrypoint sh img -c pytest", "docker compose up -d"):
    case("9 control: `%s` is no run (background / another entrypoint)" % c, after(c, PYOK), 2)

print("-- 10: P1-4 counting accepts a standalone PASS and `tất cả PASS`")
RELINK = ('bash tests/worktree_git/test_relink_prune.sh 2>&1 | tail -5; echo "rc=${pipestatus[1]}"; bash tests/worktree_git/test_relink.sh 2>&1'
          ' | tail -1; bash tests/worktree_git/test_relink_skills.sh 2>&1 | tail -1; bash tests/worktree_git/test_relink_alias.sh 2>&1 | tail -1')
RELINK_OUT = ("✔ linked worktree: nothing pruned\n✔ commands dir is a symlink into the kit: the kit's tracked links stay\n"
              "✔ skills dir is a symlink into the kit: the kit's tracked links stay\n✔ project inside the kit (self-install): nothing pruned\n"
              "PASS\nrc=0\nrelink: all checks passed\n✅ test_relink_skills: all passed\n✅ test_relink_alias: all passed")
case("10 must pass: the real blocked relink command (4 kit runs, one prints PASS)", after(RELINK, RELINK_OUT), 0)
case("10 must pass: `x | tail -2; y | tail -1`, x prints PASS",
     after("bash tests/super-board/test_agents_md_block_size.sh 2>&1 | tail -2; bash tests/verification/test_repo_consistency.sh 2>&1 | tail -1",
           "✔ run.md: the every-lane section points every lane at the pipeline\nPASS\nrepo consistency: all checks passed"), 0)
case("10 must pass: two runs, one prints `✅ x: tất cả PASS`",
     after("bash tests/a/test_x.sh 2>&1 | tail -1; bash tests/a/test_y.sh 2>&1 | tail -1", "✅ test_x: tất cả PASS\n✅ test_y: all passed"), 0)
case("10 must pass: a loop of three runs, two print PASS, the last `all passed`",
     after("for t in a b c; do bash tests/super-board/test_$t.sh 2>&1 | tail -1; done", "PASS\nPASS\n✅ test_c: all passed"), 0)
case("10 must block: x crashed silently, y prints `✅ y: all passed` then PASS (one run, two lines)",
     after("bash tests/a/test_x.sh; bash tests/a/test_y.sh", CRASH_X + "✅ test_y: all passed\nPASS"), 2)
case("10 must block: three runs, one PASS line and one `all passed`",
     after("for t in a b c; do bash tests/super-board/test_$t.sh 2>&1 | tail -1; done", "PASS\n✅ test_c: all passed"), 2)
case("10 control: `PASS` inside a sentence is no summary",
     after("bash tests/a/test_x.sh 2>&1 | tail -1; bash tests/a/test_y.sh 2>&1 | tail -1", "the PASS line\n✅ test_y: all passed"), 2)

print("-- 11: a kit loop: only a runner's own failure line counts")
L2 = "do bash tests/gates/test_$t.sh 2>&1 | tail -2; done"
case("11 must pass: `linter reports 2 errors` (a check's description) in a two-run loop with two summaries",
     after("for t in a b; " + L2, "linter reports 2 errors\n✅ test_a: all passed\nok: b\n✅ test_b: all passed"), 0)
for line in ("3 failure(s)", "test_a: 2 errors", "FAIL (3)", "ERROR: config missing", "FAILED tests/test_a.py::x - assert 1"):
    case("11 must block: `%s` in a two-run loop with two summaries" % line,
         after("for t in a b; " + L2, line + "\n✅ test_a: all passed\n✅ test_b: all passed"), 2)
case("11 must block: `Error: ENOENT` (not counted) in a two-run loop with one summary (the count still holds)",
     after("for t in a b; " + L2, "Error: ENOENT x\n✅ test_b: all passed"), 2)

print("-- 12: review of round 2 (four P2 findings)")
# 12a: a bare PASS counts only where a run's output ends: the last line, a line before the echo of an exit code the command prints, or
# the last line of a `2>&1 | tail -N` window whose size the output fills exactly.
case("12a must block: `bash x; bash y`, x crashed silently, y prints PASS then `✅ y: all passed`",
     after("bash tests/a/test_x.sh; bash tests/a/test_y.sh", "PASS\n✅ test_y: all passed"), 2)
case("12a must block: `bash x; bash y` printing `PASS`, `rc=0`, a summary, but the command echoes no rc",
     after("bash tests/a/test_x.sh; bash tests/a/test_y.sh", "PASS\nrc=0\n✅ test_y: all passed"), 2)
case("12a must pass: `x | tail -1; echo \"x exit=$?\"; y | tail -1`, x prints PASS",
     after('bash tests/a/test_x.sh 2>&1 | tail -1; echo "x exit=$?"; bash tests/a/test_y.sh 2>&1 | tail -1',
           "PASS\nx exit=0\n✅ test_y: all passed"), 0)
AGENTS = ("bash tests/super-board/test_agents_md_block_size.sh 2>&1 | tail -2; bash tests/verification/test_repo_consistency.sh 2>&1"
          " | tail -1")
case("12a must block: the agents_md command, PASS is not the last line of the first window",
     after(AGENTS, "PASS\n✔ a\nrepo consistency: all checks passed"), 2)
case("12a must block: the agents_md command, 2 lines for 3 window lines (a run printed less: the windows are unknown)",
     after(AGENTS, "PASS\nrepo consistency: all checks passed"), 2)
case("12a must block: the agents_md command without 2>&1 on the first run (stderr skips tail)",
     after(AGENTS.replace(" 2>&1 | tail -2", " | tail -2"), "✔ run.md: x\nPASS\nrepo consistency: all checks passed"), 2)
case("12a must block: the agents_md command then `; echo done`",
     after(AGENTS + "; echo done", "✔ run.md: x\nPASS\nrepo consistency: all checks passed\ndone"), 2)
LOOP1 = "for t in a b c; do bash tests/super-board/test_$t.sh 2>&1 | tail -1; done"
case("12a must pass: a real `for … 2>&1 | tail -1` loop of three runs, then `python3 tests/…/test_d.py 2>&1 | tail -1` (4 windows)",
     after(LOOP1 + "; python3 tests/super-board/test_d.py 2>&1 | tail -1", "PASS\n✅ test_b: all passed\nPASS\nALL PASS"), 0)
case("12a must block: a two-run `tail -2` loop, the first window holds PASS and its summary, the second none",
     after("for t in a b; do bash tests/super-board/test_$t.sh 2>&1 | tail -2; done", "PASS\n✅ test_a: all passed\n✔ b1\n✔ b2"), 2)
case("12a must block: the three-run loop without 2>&1 (stderr skips tail: the windows are unknown)",
     after(LOOP1.replace(" 2>&1", ""), "PASS\nPASS\n✅ test_c: all passed"), 2)
CRASH_A = "tests/a/test_a.sh: line 3: FOO: unbound variable"
case("12a must block: the loop then `cat old.log 2>&1 | tail -1` (a reader's window is no run's)",
     after(LOOP1 + "; cat /tmp/old.log 2>&1 | tail -1", CRASH_A + "\nPASS\n✅ test_c: all passed\nALL PASS"), 2)
case("12a must block: `x 2>&1 | tail -1; echo PASS 2>&1 | tail -1; y 2>&1 | tail -1` (an echo's window is no run's)",
     after("bash tests/a/test_x.sh 2>&1 | tail -1; echo PASS 2>&1 | tail -1; bash tests/a/test_y.sh 2>&1 | tail -1",
           CRASH_A + "\nPASS\n✅ test_y: all passed"), 2)

# 12b: docker's own errors are no RED half of check 7.
for out in ('OCI runtime exec failed: exec failed: unable to start container process: exec: "pytest": executable file not found in $PATH',
            "no configuration file provided: not found",
            'service "web" has neither an image nor a build context specified: invalid compose project'):
    case("12b must block: a docker-level error (`%s`) is no RED half of check 7" % out[:40],
         pair("docker compose exec web pytest -q", out, "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("12b control: a pytest RED in docker whose assertion quotes a docker message is a RED half",
     pair("docker compose run --rm web pytest -q", "E   AssertionError: no configuration file provided\n1 failed in 0.1s",
          "docker compose run --rm web pytest -q", PYOK), 0, msg=FIX)

# 12c: a definition is `function NAME {` / `NAME() {` at command position, judged per call (a Bash call keeps no function).
case("12c must pass: `rg -n function test` in an earlier call, then pytest",
     [E, ["bash", "rg -n function test", ""], ["bash", "python3 -m pytest -q", PYOK]], 0)
case("12c must pass: `rg -n function test src; python3 -m pytest -q` in one call", after("rg -n function test src; python3 -m pytest -q", PYOK), 0)
case("12c must block: `function tail() { …; }` then pytest through tail",
     after("function tail() { echo '5 passed'; }; python3 -m pytest -q 2>&1 | tail -3", PYOK), 2)
case("12c must block: `if true; then tail() { …; }; fi` then pytest through tail",
     after("if true; then tail() { echo '5 passed'; }; fi; python3 -m pytest -q 2>&1 | tail -3", PYOK), 2)
case("12c must block: `for …; do cat() { …; }; done` then pytest through cat",
     after("for i in 1; do cat() { echo '5 passed'; }; done; python3 -m pytest -q 2>&1 | cat", PYOK), 2)
case("12c must block: a `case` arm `*) tail() { …; };;` then pytest through tail",
     after("case 1 in *) tail() { echo '5 passed'; };; esac; python3 -m pytest -q 2>&1 | tail -3", PYOK), 2)

# 12d: `sed -i` prints nothing; an echo before `||` skips only a runner after it.
for c in ("sed -i '' 's/a/b/' src/app.py", "sed --in-place=.bak 's/a/b/' src/app.py", "sed -Ei 's/a+/b/' src/app.py"):
    case("12d must pass: `pytest -q | tail -3; %s` (in place: prints nothing)" % c,
         after("python3 -m pytest -q 2>&1 | tail -3; " + c, DOTS), 0)
case("12d must block: `sed -i … f; cat f` after the run", after("python3 -m pytest -q 2>&1 | tail -3; sed -i '' 's/a/b/' /tmp/old.log; cat /tmp/old.log", DOTS), 2)
case("12d must block: `sed -i 's/x/y/w /dev/stdout' f` prints", after("python3 -m pytest -q 2>&1 | tail -3; sed -i 's/x/y/w /dev/stdout' /tmp/old.log", DOTS), 2)
case("12d must block: `grep -i passed f` prints", after("python3 -m pytest -q 2>&1 | tail -3; grep -i passed /tmp/old.log", DOTS), 2)
case("12d must pass: `pytest -q; echo \"exit=$?\" || true`", after('python3 -m pytest -q; echo "exit=$?" || true', PYOK + "\nexit=0"), 0)
case("12d must block: `echo \"exit=$?\" || python3 -m pytest -q` (pytest never runs)", after('echo "exit=$?" || python3 -m pytest -q', PYOK), 2)
case("12d must block: `true || { python3 -m pytest -q; }`", after("true || { python3 -m pytest -q; }", PYOK), 2)

shutil.rmtree(TMP, ignore_errors=True)
print("-- 13: a call Claude Code refused never ran: no RED half of check 7")
# Câu từ chối của kiểm an toàn dựng sẵn ("Permission for this command was denied by a built-in Claude Code safety check") chưa có
# trong NOT_RUN_RX: lần gọi không chạy vẫn thành nửa ĐỎ của cặp check 7 (review #427 vòng 2).
DENIED = "Permission for this command was denied by a built-in Claude Code safety check. Reason: x"
case("13 must block: a safety-check refusal is no RED half (then fix, then green)",
     pair("python3 -m pytest -q", DENIED, "python3 -m pytest -q", PYOK), 2, msg=FIX)
case("13 control: a real RED, the fix, a green run still pair",
     pair("python3 -m pytest -q", "FAILED tests/test_foo.py::test_a - assert 1 == 2\n1 failed in 0.1s", "python3 -m pytest -q", PYOK), 0, msg=FIX)

print("")
print("test_evidence_backlog427: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PYEND
