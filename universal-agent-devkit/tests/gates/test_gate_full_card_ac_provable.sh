#!/usr/bin/env bash
# Test (18/11 board agent-workbench): every new gate_full card carried the AC "Lượt gate_full.py run kế tiếp không còn <suite> đỏ".
# No PR can prove it, so after the fix merged the merge gate kept the card open and the builder parked it in Blocked until the
# next nightly run (#1275 09:59–11:20, #1273 12:16). Rule: a new card's ACs are all provable by the fixing PR ("<suite> chạy lại
# PASS trên origin/main"); the next nightly run still re-checks the suite and files a new card if it is red again. bash 3.2.
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cat > "$T/drive.py" <<'PY'
import os, sys, json
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import gate_full as g
calls = []
def sh(cmd, cwd=None, timeout=None):
    calls.append(cmd)
    return 0, "https://github.com/o/r/issues/900"
g.sh = sh
open_card = os.environ.get("OPEN_CARD", "")
g.open_issue_for = lambda slug, sid: open_card   # "" = no open card for the suite
closed_card = os.environ.get("CLOSED_CARD", "")
g.closed_cards = lambda slug, before: {"REG-X-01": closed_card} if closed_card else {}   # {} = never had a completed card
g.git_out = lambda *a, **k: ""
g.shutil.which = lambda n: "/usr/bin/" + n
os.environ["DEVKIT_GATE_FULL_CARD_CMD"] = "sh fakecard.sh"
run = g.Run(sys.argv[2])
if os.environ.get("MIXED"):   # REG-Y-01 new red bisected to commit c0ffee; REG-X-01 chronic with a closed card
    run.info.update({"result": "red", "ref": "origin/main", "red": ["REG-X-01", "REG-Y-01"], "suspect": "c0ffee" * 6 + "cafe",
                     "suspect_note": "", "suspects": {"REG-Y-01": {"sha": "c0ffee" * 6 + "cafe", "note": ""}},
                     "red_tests": {"REG-X-01": {"paths": ["tests/x.sh"], "cases": []}, "REG-Y-01": {"paths": ["tests/y.sh"], "cases": []}},
                     "new_red_detail": {"REG-Y-01": {"paths": ["tests/y.sh"], "cases": []}}})
elif os.environ.get("CHRONIC"):   # suite red in the baseline too: not a new red
    run.info.update({"result": "red", "ref": "origin/main", "red": ["REG-X-01"], "suspect": "", "suspect_note": "",
                     "red_tests": {"REG-X-01": {"paths": ["tests/x.sh"], "cases": []}}, "new_red_detail": {}})
else:
    run.info.update({"result": "red", "ref": "origin/main", "red": ["REG-X-01"], "suspect": "", "suspect_note": "",
                     "new_red_detail": {"REG-X-01": {"paths": [], "cases": []}}})
g.file_card(run, sys.argv[2], "o/r", "a" * 40)
card = [c for c in calls if c[:2] == ["sh", "fakecard.sh"]]
acs = [c[i + 1] for c in card for i, x in enumerate(c) if x == "--ac"]
probs = [c[i + 1] for c in card for i, x in enumerate(c) if x == "--problem"]
byt = {c[c.index("--title") + 1]: c[c.index("--fix") + 1] for c in card if "--title" in c and "--fix" in c}
print(json.dumps({"cards": len(card), "acs": acs, "problem": probs[0] if probs else "", "fix": byt}))
PY
out=$(python3 "$T/drive.py" "$KIT" "$T/log" 2>/dev/null | tail -1)   # run.log prints to stdout: JSON is the last line
q() { echo "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print($1)"; }

[ "$(q 'd["cards"]')" = 1 ] && ok "A one new card filed" || fail "A: $out"
[ "$(q 'any("PASS trên origin/main" in a and "REG-X-01" in a for a in d["acs"])')" = True ] \
  && ok "B AC: suite re-run PASS on origin/main" || fail "B: $out"
[ "$(q 'any("run kế tiếp" in a for a in d["acs"])')" = False ] \
  && ok "C no AC that only the next nightly run can prove" || fail "C: $out"

# D. card closed after the fix merged, suite still red the next night (chronic vs baseline) and no open card: a card is filed again
out=$(CHRONIC=1 CLOSED_CARD=https://github.com/o/r/issues/4 python3 "$T/drive.py" "$KIT" "$T/log2" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 1 ] && ok "D closed card, suite still red: card filed again" || fail "D: $out"
[ "$(q '"VẪN ĐỎ sau khi thẻ https://github.com/o/r/issues/4 đóng" in d["problem"] and "đỏ MỚI" not in d["problem"]')" = True ] \
  && ok "H re-filed card says the suite is still red after #4 closed, not 'new red'" || fail "H: $out"

# I. same run: REG-Y-01 new red bisected to c0ffee…, REG-X-01 re-filed: X's card must not blame Y's commit
out=$(MIXED=1 CLOSED_CARD=https://github.com/o/r/issues/4 python3 "$T/drive.py" "$KIT" "$T/log5" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 2 ] \
  && [ "$(q '[f for t, f in d["fix"].items() if "REG-X-01" in t][0].find("c0ffee") < 0')" = True ] \
  && [ "$(q '[f for t, f in d["fix"].items() if "REG-Y-01" in t][0].find("c0ffee") >= 0')" = True ] \
  && ok "I re-filed chronic card does not blame the other suite's bisected commit" || fail "I: $out"

# E. chronic red that still has an open card: no new card (no duplicates)
out=$(CHRONIC=1 CLOSED_CARD=https://github.com/o/r/issues/4 OPEN_CARD=https://github.com/o/r/issues/5 python3 "$T/drive.py" "$KIT" "$T/log3" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 0 ] && ok "E chronic red with an open card: no new card" || fail "E: $out"

# F. chronic red that never had a gate-full card: unchanged rule, no card
out=$(CHRONIC=1 python3 "$T/drive.py" "$KIT" "$T/log4" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 0 ] && ok "F chronic red never carded: no card (old rule)" || fail "F: $out"

# G. closed_cards parses gh: only COMPLETED cards closed before the run started count (title with spaces too); NOT_PLANNED
#    (duplicate / accepted red) and a card closed mid-run (fix merged after the sha was pinned) do not; gh error ⇒ {}
cat > "$T/parse.py" <<'PY'
import os, sys, json, datetime as dt
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import gate_full as g
P = g.CARD_PREFIX
items = [
    {"title": P + " 2026-11-17: REG-A-01 đỏ", "url": "u/1", "stateReason": "COMPLETED", "closedAt": "2026-11-18T01:00:00Z"},
    {"title": P + " 2026-11-17: agent-kit test đỏ", "url": "u/2", "stateReason": "COMPLETED", "closedAt": "2026-11-18T01:00:00Z"},
    {"title": P + " 2026-11-17: REG-B-01 đỏ", "url": "u/3", "stateReason": "NOT_PLANNED", "closedAt": "2026-11-18T01:00:00Z"},
    {"title": P + " 2026-11-17: REG-C-01 đỏ", "url": "u/4", "stateReason": "COMPLETED", "closedAt": "2026-11-18T09:00:00Z"},
    {"title": "🐛 other card: REG-D-01 đỏ", "url": "u/5", "stateReason": "COMPLETED", "closedAt": "2026-11-18T01:00:00Z"},
    # REG-E-01: old COMPLETED card, then the re-filed card closed NOT_PLANNED (red accepted): the latest close wins ⇒ not counted
    {"title": P + " 2026-11-18: REG-E-01 đỏ", "url": "u/7", "stateReason": "NOT_PLANNED", "closedAt": "2026-11-18T03:00:00Z"},
    {"title": P + " 2026-11-10: REG-E-01 đỏ", "url": "u/6", "stateReason": "COMPLETED", "closedAt": "2026-11-11T01:00:00Z"},
    # REG-F-01: an older NOT_PLANNED card, then a newer COMPLETED one: counted (listed old first to check order does not matter)
    {"title": P + " 2026-11-01: REG-F-01 đỏ", "url": "u/8", "stateReason": "NOT_PLANNED", "closedAt": "2026-11-02T01:00:00Z"},
    {"title": P + " 2026-11-16: REG-F-01 đỏ", "url": "u/9", "stateReason": "COMPLETED", "closedAt": "2026-11-17T01:00:00Z"},
]
rc = int(os.environ.get("GH_RC", "0"))
g.sh = lambda cmd, cwd=None, timeout=None: (rc, json.dumps(items))
start = dt.datetime(2026, 11, 18, 5, 0, tzinfo=dt.timezone.utc)   # run started 05:00Z
print(json.dumps(g.closed_cards("o/r", start), sort_keys=True))
PY
got=$(python3 "$T/parse.py" "$KIT")
[ "$got" = '{"REG-A-01": "u/1", "REG-F-01": "u/9", "agent-kit test": "u/2"}' ] \
  && ok "G closed_cards: latest close before run start, COMPLETED only" || fail "G: $got"
got=$(GH_RC=1 python3 "$T/parse.py" "$KIT")
[ "$got" = '{}' ] && ok "G2 closed_cards gh error: {}" || fail "G2: $got"

[ "$FAILS" -eq 0 ] && { echo "✅ test_gate_full_card_ac_provable: all passed"; exit 0; } || { echo "❌ test_gate_full_card_ac_provable: $FAILS failed"; exit 1; }
