#!/usr/bin/env bash
# Regression test: scripts/nightly.py — the local nightly job (launchd), never in the cloud.
#  - run: for each registered project with a matrix the gate trusts, every suite for real
#    (heavy ones too), a FAIL re-run once (green → FLAKY), evidence logs; then the pending
#    RED-proofs with --heavy; the result lands in the checklist
#  - a notification only when a row TURNS red (FAIL/TIMEOUT/FLAKY/VACUOUS) — silence when all
#    stays green, no repeat while it stays red; the weekly one-line report every 7 days
#  - untrusted matrix → the project is skipped and said so
#  - install/uninstall write/remove the LaunchAgent plist (launchctl injectable for tests);
#    add/remove keep the project list
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NIGHTLY="$DEVKIT_DIR/scripts/nightly.py"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export HOME="$TMP/home"; mkdir -p "$HOME"
export NIGHTLY_NOTIFY_CMD="$TMP/notify.sh"; NOTES="$TMP/notes.txt"; : > "$NOTES"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s\n' "$NOTES" > "$NIGHTLY_NOTIFY_CMD"; chmod +x "$NIGHTLY_NOTIFY_CMD"
export NIGHTLY_LAUNCHCTL="true"

mk() {  # mk <dir> <command-A> <command-B>
  local P="$1"; mkdir -p "$P/src" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    echo 1 > src/a.txt; echo 1 > src/b.txt
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [
      {"component": "A", "watch_files": ["src/a.txt"], "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": sys.argv[1]}]},
      {"component": "B", "watch_files": ["src/b.txt"], "mandatory_regression_tests": [{"id": "REG-B", "name": "b", "command": sys.argv[2]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$2" "$3"
    git add -A && git commit -qm init
    echo 2 > src/a.txt; echo 2 > src/b.txt
    CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
    git add -A && git commit -qm ran )
}
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$1')); print(r.effective_status(d, d['items']['$2']))"; }

GOOD="$TMP/good"; mk "$GOOD" "true" "true || ./gradlew test"
BAD="$TMP/bad"; mk "$BAD" "true" 'grep -q 2 src/b.txt'
FLK="$TMP/flaky"; mk "$FLK" 'if [ -f .ran ]; then true; else touch .ran; exit 1; fi' "true"
rm -f "$FLK/.ran"
[ "$(st "$GOOD" REG-A)" = PASS ] && [ "$(st "$BAD" REG-B)" = PASS ] && ok "setup: suites PASS" || fail "setup"

python3 "$NIGHTLY" add "$GOOD" >/dev/null && python3 "$NIGHTLY" add "$BAD" >/dev/null && python3 "$NIGHTLY" add "$FLK" >/dev/null
python3 "$NIGHTLY" add "$GOOD" >/dev/null
[ "$(grep -c . "$HOME/.config/agent-kit/nightly-projects")" = 3 ] && ok "add: project list without duplicates" || fail "list: $(cat "$HOME/.config/agent-kit/nightly-projects")"

echo 3 > "$BAD/src/b.txt"                       # breaks REG-B
python3 "$NIGHTLY" run > "$TMP/run1" 2>&1
[ "$(st "$BAD" REG-B)" = FAIL ] && ok "a suite broken since its PASS → FAIL recorded by the nightly run" || fail "bad: $(st "$BAD" REG-B) $(cat "$TMP/run1")"
[ "$(st "$GOOD" REG-B)" = PASS ] && ok "heavy suite (Gradle) runs at night" || fail "heavy: $(st "$GOOD" REG-B)"
ls "$BAD"/.agents/evidence/REG-B/*.log >/dev/null 2>&1 && ok "nightly runs keep evidence logs" || fail "no evidence"
grep -q "REG-B" "$NOTES" && grep -q "bad" "$NOTES" && ok "notification when a row turns red (project + suite)" || fail "notes: $(cat "$NOTES")"
grep "chuyển sang đỏ" "$NOTES" | grep -q "good" && fail "notified for an all-green project" || ok "all green → no red notification"
[ "$(st "$FLK" REG-A)" = FLAKY ] && grep -q "FLAKY" "$NOTES" && ok "red then green on re-run → FLAKY + notified" || fail "flaky: $(st "$FLK" REG-A)"
grep -q "tuần" "$NOTES" && ls "$GOOD/.agents/evidence/weekly.log" >/dev/null 2>&1 && ok "first run writes the weekly one-line report" || fail "weekly: $(cat "$NOTES")"

: > "$NOTES"; python3 "$NIGHTLY" run >/dev/null 2>&1
grep -q "REG-B" "$NOTES" && fail "notified again while still red" || ok "still red next night → no repeat"
grep -q "tuần" "$NOTES" && fail "weekly report repeated within 7 days" || ok "weekly report once per 7 days"

python3 - "$BAD" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "echo changed"; json.dump(d, open(p, "w"))
PY
out="$(python3 "$NIGHTLY" run 2>&1)"
printf '%s' "$out" | grep -q "bad.*không được gate tin" && ok "untrusted matrix → project skipped, said so" || fail "untrusted: $out"

python3 "$NIGHTLY" install --hour 2 --minute 17 >/dev/null 2>&1
PL="$HOME/Library/LaunchAgents/com.universal-agent-devkit.nightly.plist"
[ -f "$PL" ] && grep -q "nightly.py" "$PL" && grep -q "<integer>2</integer>" "$PL" && grep -q "<integer>17</integer>" "$PL" \
  && ok "install writes the LaunchAgent (daily 02:17)" || fail "plist: $(cat "$PL" 2>/dev/null | head -20)"
python3 "$NIGHTLY" status 2>&1 | grep -q "02:17" && ok "status shows the schedule and projects" || fail "status"
python3 "$NIGHTLY" uninstall >/dev/null 2>&1; [ ! -f "$PL" ] && ok "uninstall removes it" || fail "uninstall"
python3 "$NIGHTLY" remove "$FLK" >/dev/null; [ "$(grep -c . "$HOME/.config/agent-kit/nightly-projects")" = 2 ] && ok "remove drops a project" || fail "remove"

[ "$FAILS" -eq 0 ] && echo "✅ test_nightly: all passed" || { echo "❌ test_nightly: $FAILS failed"; exit 1; }
