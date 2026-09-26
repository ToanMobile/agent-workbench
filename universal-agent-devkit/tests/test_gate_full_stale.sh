#!/usr/bin/env bash
# Regression test: `post-fix-gate --run-tests --full` re-runs every STALE suite of the checklist,
# not only the suites the diff touches (GeelyEx2 2026-09-26: --full printed PASS "2/2" while the
# checklist had 143 bug rows "CẦN CHẠY LẠI"). Without --full nothing changes: impacted suites only.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src/a" "$P/src/b" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo 1 > src/a/x.py; echo 1 > src/b/y.py
cat > .agents/regression_matrix.active.json <<JSON
{"adopted": true, "rules":[
 {"component":"A","watch_files":["src/a/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"echo a"}]},
 {"component":"B","watch_files":["src/b/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b",
  "command":"test -f $TMP/b-untested && exit 77; test ! -f $TMP/b-fail && touch $TMP/b-ran", "untested_exit": 77}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
stale_b() {  # B's watched code changes after its PASS and is committed: REG-B goes STALE
  echo "$1" >> src/b/y.py && git add -A && git commit -qm "b $1" && sleep 1.1
  python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null
}

echo 2 >> src/a/x.py; echo 2 >> src/b/y.py
python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
git add -A && git commit -qm ran && sleep 1.1
stale_b 3
[ "$(st REG-A)" = PASS ] && [ "$(st REG-B)" = STALE ] && ok "setup: REG-A PASS, REG-B STALE" \
  || fail "setup: A=$(st REG-A) B=$(st REG-B)"

# Impacted run (no --full): only A's suite; B stays STALE.
rm -f "$TMP/b-ran"; echo 4 >> src/a/x.py
python3 "$GATE" --run-tests --allow-no-tests >/dev/null 2>&1
[ ! -f "$TMP/b-ran" ] && [ "$(st REG-B)" = STALE ] && ok "without --full: STALE suite of another component not run" \
  || fail "impacted run touched REG-B: $(st REG-B)"

# --full: the STALE suite runs too and its row becomes PASS.
rm -f "$TMP/b-ran"
python3 "$GATE" --run-tests --full --allow-no-tests > "$TMP/full.out" 2>&1; rc=$?
[ -f "$TMP/b-ran" ] && [ "$(st REG-B)" = PASS ] && [ "$rc" = 0 ] && ok "--full re-runs the STALE suite → PASS (exit 0)" \
  || fail "--full: ran=$([ -f "$TMP/b-ran" ] && echo yes || echo no) B=$(st REG-B) rc=$rc $(tail -5 "$TMP/full.out")"

# --full with a STALE suite of another component that cannot run on this machine: not the
# change's verdict (still exit 0), the row stays STALE and the output says so.
git add -A && git commit -qm a4 && stale_b 5
touch "$TMP/b-untested"; echo 5 >> src/a/x.py
python3 "$GATE" --run-tests --full --allow-no-tests > "$TMP/full3.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(st REG-B)" = STALE ] && grep -q "REG-B" "$TMP/full3.out" \
  && ok "--full: an unrelated STALE suite that cannot run here does not block, stays STALE" \
  || fail "--full untested stale: rc=$rc B=$(st REG-B) $(tail -5 "$TMP/full3.out")"
rm -f "$TMP/b-untested"

# --full with a STALE suite that now fails: REJECT, row FAIL.
touch "$TMP/b-fail"; echo 6 >> src/a/x.py
python3 "$GATE" --run-tests --full --allow-no-tests > "$TMP/full2.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ "$(st REG-B)" = FAIL ] && ok "--full: a STALE suite that fails now → REJECT (exit 1), row FAIL" \
  || fail "--full failing stale: rc=$rc B=$(st REG-B) $(tail -5 "$TMP/full2.out")"

# --record-lesson (a forced full run) links only the suites of the change to the lesson bug.
rm -f "$TMP/b-fail"; echo 7 >> src/b/y.py
python3 "$GATE" --run-tests --allow-no-tests >/dev/null 2>&1
git add -A && git commit -qm b7 && stale_b 8
echo 9 >> src/a/x.py
python3 "$GATE" --run-tests --allow-no-tests --record-lesson "lesson only in a" >/dev/null 2>&1
tests="$(python3 -c "
import json; d=json.load(open('.agents/regression_status.json'))['items']
print(','.join(sorted(t for it in d.values() if it.get('kind')=='bug' and 'lesson only in a' in (it.get('title') or '') for t in it.get('tests', []))))")"
[ "$tests" = "REG-A" ] && ok "--record-lesson: lesson bug linked to the change's suite only" || fail "lesson linked to: '$tests'"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_full_stale: all passed" || { echo "❌ test_gate_full_stale: $FAILS failed"; exit 1; }
