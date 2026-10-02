#!/usr/bin/env bash
# Regression test: scripts/testing/red_proof.py records evidence for what the sandbox really ran.
#  - revert / patch mode runs HEAD's copy of a tracked test: the proof hashes THAT content, not a
#    half-edited working-tree copy — so a test weakened without a commit reads OUTDATED (mark_stale),
#    never PROVEN for a file that never ran
#  - a RED that is only "the API the fix adds does not exist yet" (AttributeError / NameError /
#    TypeError unexpected keyword naming a symbol the fix diff adds) is no proof → INCONCLUSIVE;
#    an AttributeError on a real None, or on a name the fix does not add, stays a behavioural RED
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROOF="$DEVKIT_DIR/scripts/testing/red_proof.py"; KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_project() {  # new_project <command>
  P="$TMP/p$RANDOM"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    printf 'def add(a, b):\n    return a - b\n' > src/calc.py
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [{"component": "Calc", "watch_files": ["src/*.py", "tests/*.py"],
      "mandatory_regression_tests": [{"id": "REG-CALC", "name": "calc", "command": sys.argv[1]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$1"
    printf '.env\n' > .gitignore
    git add -A && git commit -qm init )
}
field() { python3 -c "import json,sys;print((json.load(open('$P/.agents/regression_status.json'))['items']['$1'].get('red_proof') or {}).get('$2','-'))"; }
recorded_hash() { python3 -c "import json;print(((json.load(open('$P/.agents/regression_status.json'))['items']['$1'].get('red_proof') or {}).get('files') or {}).get('$2','-'))"; }
sha16() { python3 -c "import hashlib,sys;print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:16])"; }
bid() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
UT="python3 -m unittest discover -s tests"
PRE='import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import calc
'

# ── Bug 1: --fix-commit with a committed test weakened in the tree (not committed) ─
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
printf '%sclass TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 2), 4)\n' "$PRE" > tests/test_calc.py
git add -A && git commit -qm "fix add + test"; FIX="$(git rev-parse --short HEAD)"
printf '%sclass TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertTrue(True)\n' "$PRE" > tests/test_calc.py
HEAD_H="$(git show HEAD:tests/test_calc.py | sha16)"; TREE_H="$(sha16 < tests/test_calc.py)"
B1="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add trừ thay vì cộng" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B1" --fix-commit "$FIX" --wait >/dev/null 2>&1
got="$(recorded_hash "$B1" tests/test_calc.py)"
[ "$got" = "$HEAD_H" ] && ok "revert mode records the hash of HEAD's test (the content that ran)" \
  || fail "recorded hash $got — HEAD $HEAD_H, weakened tree $TREE_H"
[ "$got" != "$TREE_H" ] && ok "the weakened working-tree test (never ran) is not what the proof vouches for" \
  || fail "proof hashes the weakened tree copy that never ran"
[ "$(field "$B1" status)" = PROVEN ] && ok "the proof itself stands for HEAD's test (RED without the fix, GREEN with it)" \
  || fail "status after proof: $(field "$B1" status) ($(field "$B1" reason))"
CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null 2>&1
[ "$(field "$B1" status)" = OUTDATED ] && ok "a later STALE pass: the tree's test differs from what was proven → OUTDATED" \
  || fail "after mark_stale: $(field "$B1" status) ($(field "$B1" reason))"
# control: a test HEAD does not have comes in from the tree → the tree content is what ran
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; git commit -qam "fix add"; FIX="$(git rev-parse --short HEAD)"
printf '%sclass TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 2), 4)\n' "$PRE" > tests/test_new.py
B2="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai, test chưa commit" --fixed --test tests/test_new.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B2" --fix-commit "$FIX" --wait >/dev/null 2>&1
[ "$(recorded_hash "$B2" tests/test_new.py)" = "$(sha16 < tests/test_new.py)" ] && [ "$(field "$B2" status)" = PROVEN ] \
  && ok "an uncommitted test copied into the sandbox → its tree hash, PROVEN" \
  || fail "copied test: $(field "$B2" status) $(recorded_hash "$B2" tests/test_new.py)"

# ── Bug 1b: RED only because the fix's new API is missing ────────────────────
# A: the fix adds def mul; the test calls calc.mul → RED is AttributeError on mul → not a proof
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a - b\n\ndef mul(a, b):\n    return a * b\n' > src/calc.py
printf '%sclass TestMul(unittest.TestCase):\n    def test_mul(self):\n        self.assertEqual(calc.mul(2, 3), 6)\n' "$PRE" > tests/test_mul.py
B3="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "thiếu mul" --fixed --test tests/test_mul.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B3" --wait >/dev/null 2>&1
[ "$(field "$B3" status)" = INCONCLUSIVE ] && ok "RED = AttributeError on a function the fix adds → INCONCLUSIVE, not PROVEN" \
  || fail "API-only AttributeError RED: $(field "$B3" status)"
# A2: the fix adds a keyword parameter; the test passes it → TypeError unexpected keyword → not a proof
new_project "$UT"; cd "$P"
printf 'def add(a, b, scale=1):\n    return (a + b) * scale\n' > src/calc.py
printf '%sclass TestScale(unittest.TestCase):\n    def test_scale(self):\n        self.assertEqual(calc.add(1, 2, scale=2), 6)\n' "$PRE" > tests/test_scale.py
B4="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "thiếu scale" --fixed --test tests/test_scale.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B4" --wait >/dev/null 2>&1
[ "$(field "$B4" status)" = INCONCLUSIVE ] && ok "RED = TypeError unexpected keyword the fix adds → INCONCLUSIVE" \
  || fail "API-only TypeError RED: $(field "$B4" status)"
# B (control): AttributeError on a real None — a behavioural RED → PROVEN
new_project "$UT"; cd "$P"
printf 'class Item:\n    name = "x"\n\ndef find(k):\n    return None\n' > src/calc.py; git add -A; git commit -qm find
printf 'class Item:\n    name = "x"\n\ndef find(k):\n    return Item()\n' > src/calc.py
printf '%sclass TestFind(unittest.TestCase):\n    def test_find(self):\n        self.assertEqual(calc.find("x").name, "x")\n' "$PRE" > tests/test_find.py
B5="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "find trả None" --fixed --test tests/test_find.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B5" --wait >/dev/null 2>&1
[ "$(field "$B5" status)" = PROVEN ] && ok "RED = AttributeError on a real None → still PROVEN" \
  || fail "None AttributeError RED: $(field "$B5" status) ($(field "$B5" reason))"
# C (control): AttributeError on a name the fix does not add (it sets self.value) → PROVEN
new_project "$UT"; cd "$P"
printf 'class Box:\n    def __init__(self, v):\n        self.val = v\n' > src/calc.py; git add -A; git commit -qm box
printf 'class Box:\n    def __init__(self, v):\n        self.value = v\n' > src/calc.py
printf '%sclass TestBox(unittest.TestCase):\n    def test_box(self):\n        self.assertEqual(calc.Box(3).value, 3)\n' "$PRE" > tests/test_box.py
B6="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "Box sai tên field" --fixed --test tests/test_box.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B6" --wait >/dev/null 2>&1
[ "$(field "$B6" status)" = PROVEN ] && ok "RED = AttributeError on a name the fix diff does not add as a symbol → still PROVEN" \
  || fail "non-added AttributeError RED: $(field "$B6" status) ($(field "$B6" reason))"

[ "$FAILS" -eq 0 ] && echo "✅ test_red_proof_hash: all passed" || { echo "❌ test_red_proof_hash: $FAILS failed"; exit 1; }
