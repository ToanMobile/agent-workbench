#!/usr/bin/env bash
# Regression test: a PASS whose code changed since the run is 🟡 CẦN CHẠY LẠI (STALE), never PASS.
#  - a file the suite watches changed after the run (edited, a new untracked file, a later
#    commit checked out) → STALE; a bug linked to that suite → STALE; other suites keep PASS
#  - a change that was already in the tree when it ran (a dirty run, committed afterwards)
#    is not a change since the run → still PASS
#  - the run's commit no longer resolves → STALE (nothing proves the code is the same)
#  - the gate selected the suite but ran only part of it (impacted) after the PASS → STALE
#  - a new real run clears it; SessionStart reports the count
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; RC="$DEVKIT_DIR/bin/regression_checklist.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src/a" "$P/src/b" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "a = 1" > src/a/x.py; echo "b = 1" > src/b/y.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[
 {"component":"A","watch_files":["src/a/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"true"}]},
 {"component":"B","watch_files":["src/b/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b","command":"true"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
# The gate runs the suites that watch a changed file: each run touches one file per suite.
full_run() { date +%s%N > src/a/_run.txt; date +%s%N > src/b/_run.txt
             python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1; }
refresh() { python3 "$RC" render >/dev/null 2>&1; }
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }

# A dirty run (the edit is in the tree when the suites run), committed afterwards.
echo "a = 2" > src/a/x.py; echo "b = 2" > src/b/y.py
full_run; sleep 1.1
git add -A && git commit -qm "commit what ran"; refresh
[ "$(st REG-A)" = PASS ] && [ "$(st REG-B)" = PASS ] && ok "a change already in the tree when it ran, committed later → still PASS" \
  || fail "dirty-then-commit: A=$(st REG-A) B=$(st REG-B)"
bash "$DEVKIT_DIR/bin/agent-kit" bugs add "Sai tổng A" --fixed --test REG-A >/dev/null 2>&1
BUG="$(python3 -c "import json;print([k for k,v in json.load(open('.agents/regression_status.json'))['items'].items() if v.get('kind')=='bug'][0])")"
# its test already proven RED without the fix (scripts/red_proof.py) — this test is about STALE
python3 -c "import json;p='.agents/regression_status.json';d=json.load(open(p));d['items']['$BUG']['red_proof']={'status':'PROVEN'};json.dump(d,open(p,'w'))"
full_run; refresh
[ "$(st "$BUG")" = PASS ] && ok "bug linked to REG-A, re-run after the link → PASS" || fail "bug: $(st "$BUG")"

echo "a = 3" > src/a/x.py; refresh
[ "$(st REG-A)" = STALE ] && ok "watched file edited after the run → STALE" || fail "edit: $(st REG-A)"
[ "$(st REG-B)" = PASS ] && ok "a suite that does not watch it keeps PASS" || fail "B: $(st REG-B)"
[ "$(st "$BUG")" = STALE ] && ok "a bug linked to a stale suite → STALE, not PASS" || fail "bug stale: $(st "$BUG")"
grep -q "CẦN CHẠY LẠI" .agents/regression_checklist.md && ok "view shows 🟡 CẦN CHẠY LẠI" || fail "view"
out="$(echo '{}' | bash "$DEVKIT_DIR/hooks/session_context.sh" 2>&1)"
printf '%s' "$out" | grep -q "STALE" && ok "SessionStart counts STALE" || fail "session: $out"

full_run; refresh
[ "$(st REG-A)" = PASS ] && ok "a new real run clears STALE" || fail "rerun: $(st REG-A)"

sleep 1.1; echo "n = 1" > src/b/new.py; refresh
[ "$(st REG-B)" = STALE ] && ok "new untracked file under a watched path → STALE" || fail "untracked: $(st REG-B)"
rm src/b/new.py; full_run; refresh

git checkout -q -b other && sleep 1.1 && echo "b = 9" > src/b/y.py && git commit -qam "other" && git checkout -q -
git merge -q --ff-only other 2>/dev/null || git merge -q other; refresh
[ "$(st REG-B)" = STALE ] && ok "a later commit checked out → STALE" || fail "checkout: $(st REG-B)"
full_run; refresh

python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
d["items"]["REG-B"]["last"]["commit"] = "deadbee"; json.dump(d, open(p, "w"))
PY
refresh
[ "$(st REG-B)" = STALE ] && ok "run's commit no longer resolves → STALE" || fail "unresolvable: $(st REG-B)"
full_run; refresh

python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys, time, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
time.sleep(1.1)
p = pathlib.Path(sys.argv[1]); d = r.load(p)
r.record_results(d, [{"id": "REG-A", "status": "PASS_IMPACTED"}], task=None, commit=None); r.save(p, d)
PY
[ "$(st REG-A)" = STALE ] && ok "only part of the suite ran after the PASS (impacted) → STALE" || fail "impacted: $(st REG-A)"

[ "$FAILS" -eq 0 ] && echo "✅ test_stale: all passed" || { echo "❌ test_stale: $FAILS failed"; exit 1; }
