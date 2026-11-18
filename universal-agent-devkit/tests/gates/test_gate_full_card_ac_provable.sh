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
g.closed_card_for = lambda slug, sid: closed_card   # "" = the suite never had a gate-full card
g.git_out = lambda *a, **k: ""
g.shutil.which = lambda n: "/usr/bin/" + n
os.environ["DEVKIT_GATE_FULL_CARD_CMD"] = "sh fakecard.sh"
run = g.Run(sys.argv[2])
if os.environ.get("CHRONIC"):   # suite red in the baseline too: not a new red
    run.info.update({"result": "red", "ref": "origin/main", "red": ["REG-X-01"], "suspect": "", "suspect_note": "",
                     "red_tests": {"REG-X-01": {"paths": ["tests/x.sh"], "cases": []}}, "new_red_detail": {}})
else:
    run.info.update({"result": "red", "ref": "origin/main", "red": ["REG-X-01"], "suspect": "", "suspect_note": "",
                     "new_red_detail": {"REG-X-01": {"paths": [], "cases": []}}})
g.file_card(run, sys.argv[2], "o/r", "a" * 40)
card = [c for c in calls if c[:2] == ["sh", "fakecard.sh"]]
acs = [c[i + 1] for c in card for i, x in enumerate(c) if x == "--ac"]
print(json.dumps({"cards": len(card), "acs": acs}))
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

# E. chronic red that still has an open card: no new card (no duplicates)
out=$(CHRONIC=1 CLOSED_CARD=https://github.com/o/r/issues/4 OPEN_CARD=https://github.com/o/r/issues/5 python3 "$T/drive.py" "$KIT" "$T/log3" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 0 ] && ok "E chronic red with an open card: no new card" || fail "E: $out"

# F. chronic red that never had a gate-full card: unchanged rule, no card
out=$(CHRONIC=1 python3 "$T/drive.py" "$KIT" "$T/log4" 2>/dev/null | tail -1)
[ "$(q 'd["cards"]')" = 0 ] && ok "F chronic red never carded: no card (old rule)" || fail "F: $out"

[ "$FAILS" -eq 0 ] && { echo "✅ test_gate_full_card_ac_provable: all passed"; exit 0; } || { echo "❌ test_gate_full_card_ac_provable: $FAILS failed"; exit 1; }
