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
FAIL_COMMENT_ON = set()

def fake_sh(cmd, cwd=None, timeout=None, env=None, shell=False):
    calls.append(cmd)
    if cmd[:3] == ["gh", "issue", "list"]:
        return 0, json.dumps(LIST)
    if cmd[:3] == ["gh", "issue", "comment"] and cmd[3] in FAIL_COMMENT_ON:
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

g.close_proven_cards(Run(), "o/r", "a" * 40)
touched = lambda n: [c for c in calls if c[:2] == ["gh", "issue"] and c[2] in ("comment", "edit", "close") and c[3] == str(n)]
c1275 = touched(1275)
check(any(c[2] == "comment" and "REG-A-01" in " ".join(c) and "PASS" in " ".join(c) for c in c1275), "A: passed suite card gets a proof comment")
check(any(c[2] == "edit" and "ac-open" in c for c in c1275), "A: ac-open removed")
check(any(c[2] == "close" for c in c1275), "A: card closed")
check(not touched(1300), "B: suite still red -> card untouched")
check(not touched(1301), "C: suite not in this run -> card untouched")
check(not touched(1302), "D: non gate-full card -> untouched")

calls.clear(); FAIL_COMMENT_ON.add("1275")
g.close_proven_cards(Run(), "o/r", "a" * 40)
check(not any(c[2] == "close" for c in touched(1275)), "E: proof comment failed -> card not closed")

calls.clear(); FAIL_COMMENT_ON.clear()
r = Run(); r.info["passed"] = []
g.close_proven_cards(r, "o/r", "a" * 40)
check(not calls, "F: nothing passed -> no GitHub call")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_gate_full_close_proven_cards: all passed" || echo "❌ test_gate_full_close_proven_cards: failed"
exit "$rc"
