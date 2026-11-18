#!/usr/bin/env bash
# Regression #1275 (18/11): gate_full.py files a "P1 gate-full đêm <date>: <SUITE> đỏ" card whose last AC is "the next
# gate_full.py run no longer has <SUITE> red". Nothing ever checked that AC: the builder parked the card in Blocked (ac-open)
# and it waited for a person forever. Rule: after a run, every open gate-full card whose suite PASSED in that run gets a proof
# comment, loses ac-open and is closed as completed (the board's closed-issue sweep then moves it to Done).
# A suite still red, not run, or a non gate-full card is left alone; a failed comment leaves the card open.
# bash 3.2 compatible.
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$KIT/bin" python3 - <<'PY'
import os, sys, json
sys.path.insert(0, os.environ["BIN"])
import gate_full as g

calls = []
LIST = [
    {"number": 1275, "title": g.CARD_PREFIX + " 2026-11-18: REG-A-01 đỏ"},   # passed now -> close
    {"number": 1300, "title": g.CARD_PREFIX + " 2026-11-18: REG-B-01 đỏ"},   # still red -> keep
    {"number": 1301, "title": g.CARD_PREFIX + " 2026-11-18: REG-C-01 đỏ"},   # not run -> keep
    {"number": 1302, "title": "🐛 [fix] something else: REG-A-01 đỏ"},       # not a gate-full card -> keep
]
FAIL_ON = set()        # ("edit"|"close", number) that fail
LIST_REPLY = {"rc": 0, "out": None}

def fake_sh(cmd, cwd=None, timeout=None, env=None, shell=False):
    calls.append(cmd)
    if cmd[:3] == ["gh", "issue", "list"]:
        return LIST_REPLY["rc"], LIST_REPLY["out"] if LIST_REPLY["out"] is not None else json.dumps(LIST)
    if cmd[:2] == ["gh", "issue"] and (cmd[2], cmd[3]) in FAIL_ON:
        return 1, "HTTP 502"
    return 0, ""

g.sh = fake_sh
g.shutil.which = lambda name: "/usr/bin/" + name

class Run:
    def __init__(self):
        import datetime
        self.info = {"passed": ["REG-A-01", "REG-X-01"], "red": ["REG-B-01"], "ref": "origin/main", "sha": "a" * 40}
        self.started = datetime.datetime(2026, 11, 19, 0, 0)
        self.log_path = "/tmp/gate-full.log"
        self.lines = []
    def log(self, m):
        self.lines.append(m)

fails = 0
def check(ok, msg):
    global fails
    print(("✔ " if ok else "✖ ") + msg)
    fails += 0 if ok else 1

if not hasattr(g, "close_proven_cards"):
    check(False, "gate_full.close_proven_cards exists")
    sys.exit(1)

os.environ.pop("DEVKIT_GATE_FULL_CMD", None)
g.close_proven_cards(Run(), "o/r", "a" * 40)
touched = lambda n: [c for c in calls if c[:2] == ["gh", "issue"] and c[2] in ("comment", "edit", "close") and c[3] == str(n)]
writes = lambda: [c for c in calls if c[:2] == ["gh", "issue"] and c[2] in ("comment", "edit", "close")]
c1275 = touched(1275)
check(any(c[2] == "edit" and "ac-open" in c for c in c1275), "A: ac-open removed")
check(any(c[2] == "close" and "--comment" in c and "REG-A-01" in " ".join(c) and "PASS" in " ".join(c) for c in c1275),
      "A: card closed with the proof as its closing comment")
check(not touched(1300), "B: suite still red -> card untouched")
check(not touched(1301), "C: suite not in this run -> card untouched")
check(not touched(1302), "D: non gate-full card -> untouched")

calls.clear(); FAIL_ON.add(("edit", "1275"))
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not any(c[2] == "close" for c in touched(1275)), "E: ac-open removal failed -> card not closed, no proof comment")
FAIL_ON.clear()

calls.clear(); FAIL_ON.add(("close", "1275"))
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not any(c[2] == "comment" for c in touched(1275)), "E2: close failed -> no stand-alone proof comment left on an open card")
FAIL_ON.clear()

calls.clear()
r = Run(); r.info["passed"] = []
g.close_proven_cards(r, "o/r", "a" * 40)
check(not calls, "F: nothing passed -> no GitHub call")

calls.clear()
r = Run(); r.info["ref"] = "origin/fix-branch"
g.close_proven_cards(r, "o/r", "a" * 40)
check(not calls, "G: run on another ref (--ref origin/fix-branch) -> no GitHub call (cards are about origin/main)")

calls.clear(); os.environ["DEVKIT_GATE_FULL_CMD"] = "true"
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not calls, "H: override gate command (DEVKIT_GATE_FULL_CMD) -> no GitHub call")
os.environ.pop("DEVKIT_GATE_FULL_CMD", None)

calls.clear(); LIST_REPLY.update(rc=1, out="HTTP 502")
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not writes(), "I: gh issue list failed -> no comment/edit/close")
calls.clear(); LIST_REPLY.update(rc=0, out="garbage{")
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not writes(), "J: unparsable list output -> no comment/edit/close")
LIST_REPLY.update(rc=0, out=None)

# K: agent-kit test card (title with a space) closes when agent-kit test passed
calls.clear(); LIST[:] = [{"number": 1400, "title": g.CARD_PREFIX + " 2026-11-18: agent-kit test đỏ"}]
r = Run(); r.info["passed"] = ["agent-kit test"]
g.close_proven_cards(r, "o/r", "a" * 40)
check(any(c[2] == "close" and c[3] == "1400" for c in writes()), "K: 'agent-kit test' card closes when agent-kit test passed")

# L: collect_red fills `passed` from a real gate JSON: PASS counts, skip-compile/resource PASS and FAIL do not; kit rc 0 adds agent-kit test
import tempfile
gate_json = json.dumps({"regression_tests": [
    {"id": "REG-P-01", "status": "PASS", "command": "true"},
    {"id": "REG-U-01", "status": "PASS", "mode": "skip-compile", "command": "true"},
    {"id": "REG-R-01", "status": "PASS", "mode": "resource", "command": "true"},
    {"id": "REG-F-01", "status": "FAIL", "command": "false"}]})
r = Run(); r.info.update(notes=[], red=[], passed=None)
r.raw = lambda *a, **k: None
try:
    g.collect_red(r, tempfile.mkdtemp(), "universal-agent-devkit", 1, gate_json, 0, "", record_notes=False)
    got = r.info.get("passed") or []
except Exception as exc:
    got = ["error: %r" % exc]
check(got == ["REG-P-01", "agent-kit test"], "L: collect_red passed=%s (want REG-P-01 + agent-kit test only)" % got)

# M: the call site — cmd_run calls close_proven_cards after collect_red sets the verdict
import ast, inspect
src = inspect.getsource(g.cmd_run)
i_collect = src.find("verdict, checks = collect_red(")
i_close = src.find("close_proven_cards(run,")
check(0 <= i_collect < i_close, "M: cmd_run calls close_proven_cards after the main collect_red")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_gate_full_close_proven_cards: all passed" || echo "❌ test_gate_full_close_proven_cards: failed"
exit "$rc"
