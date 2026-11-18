#!/usr/bin/env bash
# Test (18/11 board agent-workbench): the gate_full run on 249d395d found `agent-kit test` red and commented on open card #685
# (2026-10-30), but #685 was on no project board, so no lane saw it. Rule: after commenting on a reused open card, file_card runs
# the card command with `--ensure-on-board <url>` (puts an off-board card in Backlog); a comment that failed does not call it;
# a failed ensure is logged and does not hide the red (the comment already reported it). bash 3.2.
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cat > "$T/drive.py" <<'PY'
import os, sys, json
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import gate_full as g
calls = []
comment_rc = int(os.environ["COMMENT_RC"]); ensure_rc = int(os.environ["ENSURE_RC"])
def sh(cmd, cwd=None, timeout=None):
    calls.append(cmd)
    if cmd[:3] == ["gh", "issue", "comment"]:
        return comment_rc, ""
    if "--ensure-on-board" in cmd:
        return ensure_rc, "ensure out"
    return 0, ""
g.sh = sh
g.open_issue_for = lambda slug, sid: "https://github.com/o/r/issues/685"
g.git_out = lambda *a, **k: ""
g.shutil.which = lambda n: "/usr/bin/" + n
os.environ["DEVKIT_GATE_FULL_CARD_CMD"] = "sh fakecard.sh"
os.environ["DEVKIT_GATE_FULL_BOARD_CMD"] = os.environ.get("BOARD_CMD", "")
run = g.Run(sys.argv[2])
run.info.update({"result": "red", "ref": "origin/main", "red": ["agent-kit test"], "suspect": "", "suspect_note": "",
                 "new_red_detail": {"agent-kit test": {"paths": [], "cases": []}}})
g.file_card(run, sys.argv[2], "o/r", "a" * 40)
ens = [c for c in calls if "--ensure-on-board" in c]
print(json.dumps({"ensure": ens, "unreported": run.info["unreported"], "log": open(run.log_path).read()}))
PY
drive() { BOARD_CMD="${BOARD_CMD-sh fakecard.sh}" COMMENT_RC=$1 ENSURE_RC=$2 python3 "$T/drive.py" "$KIT" "$T/log$1$2" 2>/dev/null | tail -1; }   # run.log also prints to stdout: the JSON is the last line
q() { python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print($1)"; }

# A. comment ok: card command called with --ensure-on-board <url> and --repo
out=$(drive 0 0)
[ "$(echo "$out" | q 'len(d["ensure"])')" = 1 ] && echo "$out" | q 'd["ensure"][0]' | grep -q "'sh', 'fakecard.sh'" \
  && echo "$out" | q 'd["ensure"][0]' | grep -q "'--ensure-on-board', 'https://github.com/o/r/issues/685'" \
  && echo "$out" | q 'd["ensure"][0]' | grep -q "'--repo', 'o/r'" \
  && ok "A reused card: ensure-on-board called with its url" || fail "A: $out"

# B. comment failed: no ensure call, red stays unreported
out=$(drive 1 0)
[ "$(echo "$out" | q 'len(d["ensure"])')" = 0 ] && [ "$(echo "$out" | q 'd["unreported"]')" = "['agent-kit test']" ] \
  && ok "B comment failed: no ensure, red unreported" || fail "B: $out"

# C. ensure failed: logged, red still counted as reported
out=$(drive 0 3)
[ "$(echo "$out" | q 'd["unreported"]')" = "[]" ] && echo "$out" | q 'd["log"]' | grep -q "ensure-on-board" \
  && ok "C ensure failed: logged, red not hidden" || fail "C: $out"

# D. harness sets only DEVKIT_GATE_FULL_CARD_CMD (old card tests): no ensure call, so their card counts stay exact
out=$(BOARD_CMD="" drive 0 0)
[ "$(echo "$out" | q 'len(d["ensure"])')" = 0 ] \
  && ok "D card harness without board cmd: ensure skipped" || fail "D: $out"

[ "$FAILS" -eq 0 ] && { echo "✅ test_gate_full_dup_card_on_board: all passed"; exit 0; } || { echo "❌ test_gate_full_dup_card_on_board: $FAILS failed"; exit 1; }
