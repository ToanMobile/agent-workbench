#!/usr/bin/env bash
# Regression test: `agent-kit bugs unlink <BUG-ID> <test>` — undo a link that is context, not a guard
# (an imported row that also linked a broad suite next to the real test). Under the strict RED-proof
# rule every linked test must go red, so a wrong extra link would keep the row unprovable forever.
#  - removes that file / class from the row; drops a matrix suite only when no remaining test of the
#    row still maps to it; a suite linked directly by id can be unlinked by its id
#  - the RED-proof becomes OUTDATED (what it proved changed); the unlink is noted on the row
#  - unknown bug / test not linked → error, nothing changed
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "x = 1" > src/a.py
printf 'def test_a(): pass\n' > tests/test_guard.py; printf 'def test_b(): pass\n' > tests/test_broad.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"A","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"python3 -m pytest tests"},
                               {"id":"REG-X","name":"x","command":"python3 -m pytest tests -k x"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
row() { python3 -c "import json,sys;it=json.load(open('$P/.agents/regression_status.json'))['items']['$1'];print(json.dumps({k:it.get(k) for k in ('tests','runs_in_suite','test_refs')},sort_keys=True)); print((it.get('red_proof') or {}).get('status')); print(it.get('unlinked'))"; }

B="$(bash "$KIT" bugs add "Sai A" --fixed --test tests/test_guard.py 2>&1 | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
bash "$KIT" bugs link "$B" tests/test_broad.py >/dev/null 2>&1
bash "$KIT" bugs link "$B" REG-X >/dev/null 2>&1
python3 - "$P" "$B" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
d["items"][sys.argv[2]]["red_proof"] = {"status": "INCONCLUSIVE", "reason": "chỉ 1/2 file test đỏ"}; json.dump(d, open(p, "w"))
PY
out="$(bash "$KIT" bugs unlink "$B" tests/test_broad.py 2>&1)"; rc=$?
r="$(row "$B")"
[ $rc = 0 ] && printf '%s' "$r" | head -1 | grep -q '"runs_in_suite": \["tests/test_guard.py"\]' && ok "unlink removes the file, keeps the guard" || fail "unlink file: rc=$rc $out / $r"
printf '%s' "$r" | head -1 | grep -q '"REG-A"' && ok "the suite the guard still maps to (REG-A) stays linked" || fail "suite dropped: $r"
[ "$(printf '%s' "$r" | sed -n 2p)" = OUTDATED ] && ok "the RED-proof becomes OUTDATED" || fail "proof: $(printf '%s' "$r" | sed -n 2p)"
printf '%s' "$r" | sed -n 3p | grep -q "test_broad" && ok "the unlink is noted on the row" || fail "no note: $r"
bash "$KIT" bugs unlink "$B" REG-X >/dev/null 2>&1
row "$B" | head -1 | grep -q '"REG-X"' && fail "suite linked by id not unlinked" || ok "a suite linked by id is unlinked by its id"
bash "$KIT" bugs unlink "$B" tests/test_nope.py >/dev/null 2>&1; [ $? != 0 ] && ok "test not linked → error" || fail "unlinking an unlinked test succeeded"
bash "$KIT" bugs unlink BUG-nope tests/test_guard.py >/dev/null 2>&1; [ $? != 0 ] && ok "unknown bug → error" || fail "unknown bug accepted"

[ "$FAILS" -eq 0 ] && echo "✅ test_bug_unlink: all passed" || { echo "❌ test_bug_unlink: $FAILS failed"; exit 1; }
