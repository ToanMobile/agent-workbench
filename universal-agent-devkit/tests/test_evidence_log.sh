#!/usr/bin/env bash
# Regression test: acceptance evidence and the checklist lock in post-fix-gate --run-tests.
#  - every real test run keeps the runner's full output in .agents/evidence/<test-id>/<ts>.log
#    (a header with command, mode, status, exit code, commit), the checklist row's last
#    result links it, only the last 10 logs per test are kept, and the folder is
#    git-ignored (a runner can print secrets). `agent-kit clean` never touches it.
#  - the gate's checklist update waits for the checklist lock (the prompt hook and
#    `agent-kit bugs` write the same file): no lost rows between two writers.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "x = 1" > src/core.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Core","watch_files":["src/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CORE","name":"core","command":"echo evidence-marker-$RANDOM; echo second-line"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
run_gate() { echo "x = $1" > src/core.py; python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1; }

run_gate 2
logs() { ls "$P/.agents/evidence/REG-CORE/" 2>/dev/null | grep -c '\.log$'; }
LOG="$(ls "$P"/.agents/evidence/REG-CORE/*.log 2>/dev/null | head -1)"
[ -n "$LOG" ] && grep -q "evidence-marker-" "$LOG" && grep -q "second-line" "$LOG" \
  && ok "a real run keeps the runner's full output as evidence" || fail "no evidence log: $(ls -R "$P/.agents" 2>&1 | head)"
[ -n "$LOG" ] && grep -q "^# command:" "$LOG" && grep -q "^# status: PASS" "$LOG" && grep -q "^# exit: 0" "$LOG" \
  && ok "evidence header: command, status, exit code" || fail "header: $(head -6 "${LOG:-/dev/null}")"
rel="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['REG-CORE']['last'].get('log') or '')")"
[ -n "$rel" ] && [ -f "$P/$rel" ] && ok "checklist row's last result links the log ($rel)" || fail "last.log: '$rel'"
[ -f "$P/.agents/evidence/.gitignore" ] && git -C "$P" check-ignore -q "$LOG" && ok "evidence folder is git-ignored" || fail "evidence not ignored"
for i in 3 4 5 6 7 8 9 10 11 12 13; do run_gate "$i"; done
[ "$(logs)" = 10 ] && ok "only the last 10 logs per test are kept" || fail "kept $(logs) logs"
python3 "$DEVKIT_DIR/scripts/devkit_clean.py" "$P" --days=0 --apply >/dev/null 2>&1
[ "$(logs)" = 10 ] && ok "agent-kit clean leaves the evidence alone" || fail "clean removed evidence: $(logs)"

# Lock: while another writer holds the checklist lock, the gate must not write.
python3 - "$P" "$DEVKIT_DIR" <<'PY' &
import sys, time, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
with r.locked(pathlib.Path(sys.argv[1])):
    open(sys.argv[1] + "/.locked", "w").close()
    time.sleep(3)
PY
HOLDER=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$P/.locked" ] && break; sleep 0.2; done
before="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['REG-CORE']['last']['at'])")"
sleep 1.1   # the gate's timestamp has second resolution
run_gate 99 &
GATE_PID=$!
sleep 1.5
mid="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['REG-CORE']['last']['at'])")"
wait "$GATE_PID"; wait "$HOLDER"
after="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['REG-CORE']['last']['at'])")"
[ "$mid" = "$before" ] && [ "$after" != "$before" ] && ok "gate waits for the checklist lock, then records" \
  || fail "lock ignored: before=$before mid=$mid after=$after"

[ "$FAILS" -eq 0 ] && echo "✅ test_evidence_log: all passed" || { echo "❌ test_evidence_log: $FAILS failed"; exit 1; }
