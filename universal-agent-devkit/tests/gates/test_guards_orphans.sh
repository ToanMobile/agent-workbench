#!/usr/bin/env bash
# Regression test: two ways a fixed bug fell out of the regression checklist (GeelyEx2 28/09/2026).
#   A. A guard in .agents/local/guards.json (measured fix + test + red patch) is a checklist bug
#      row: id = guard id, linked to the suites that run its tests, never PASS without a run and a
#      RED proof; an existing row with the same red patch (or, one-to-one, the same test) is that
#      guard's row — no duplicate. No guards.json: nothing changes.
#   B. A test file no suite of the matrix executes is an ⚠️ ORPHAN_TEST row; `post-fix-gate --full`
#      fails when the current diff ADDS such a file (an existing orphan only warns).
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
RC="$DEVKIT_DIR/bin/regression_checklist.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"
py() { python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as rc; d=json.load(open('$R/.agents/regression_status.json')); I=d['items']; print($1)"; }
render() { python3 "$RC" --project "$R" render >"$TMP/render.out" 2>&1; }
gate() { CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/.agents/regression_matrix.active.json" "$@" >"$TMP/out" 2>&1; }

mkdir -p "$R/src/test" "$R/src/iosTest" "$R/lib/src/test" "$R/tests" "$R/.agents/local" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
echo "class FooTest" > src/test/FooTest.kt
echo "class BarTest" > src/test/BarTest.kt
echo "class BazTest" > src/test/BazTest.kt
echo "class QuxTest" > src/test/QuxTest.kt
echo "class ThingTests" > src/iosTest/ThingTests.swift
echo "class NarrowTest" > lib/src/test/NarrowTest.kt
echo "class OtherTest" > lib/src/test/OtherTest.kt
echo "print('a')" > tests/test_a.py
echo "print('b')" > tests/test-b.py
echo "exit 0" > tests/test_c.sh
echo "X = 1" > tests/helper.py
printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew
touch src/build.gradle lib/build.gradle   # two Gradle modules: :src and :lib
printf 'python3 tests/test_a.py\n' > run.sh
printf 'for t in tests/test_*.sh; do sh "$t" || exit 1; done\n' > runall.sh
mkdir -p more && echo "print('q')" > more/test_q.py
printf 'for t in "$ROOT/more"/test_*.py; do :; done\n' > runq.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[
 {"component":"App","watch_files":["src/*"],
  "mandatory_regression_tests":[{"id":"REG-MOD","name":"app unit","command":"./gradlew :src:testDebugUnitTest"}]},
 {"component":"Lib","watch_files":["lib/*"],
  "mandatory_regression_tests":[{"id":"REG-LIB","name":"lib narrow","command":"./gradlew :lib:testDebugUnitTest --tests com.x.NarrowTest"}]},
 {"component":"Scripts","watch_files":["tests/*","run.sh","runall.sh"],
  "mandatory_regression_tests":[{"id":"REG-PY","name":"py","command":"sh run.sh"},
                                {"id":"REG-SH","name":"sh","command":"sh runall.sh"},
                                {"id":"REG-Q","name":"quoted glob","command":"sh runq.sh"}]}]}
JSON
git add -A && git commit -qm init
cp -R "$R" "$TMP/noguards"   # the same project without guards.json (case A8)

# Existing bug rows a guard may already be: one proven with a red patch, one linked to a test.
python3 "$RC" --project "$R" add "old bug with a patch" --fixed --test src/test/FooTest.kt --id BUG-OLD >/dev/null
python3 "$RC" --project "$R" add "bug of test c" --fixed --test tests/test_c.sh --id BUG-C >/dev/null
python3 "$RC" --project "$R" add "bug of bar" --fixed --test src/test/BarTest.kt --id BUG-BAR >/dev/null
# `bugs add --id G-PFX` stores the row as BUG-G-PFX (GeelyEx2 RELAY-0928, 28/09).
python3 "$RC" --project "$R" add "a guard added by hand first" --fixed --test src/test/FooTest.kt --id G-PFX >/dev/null
# A row proven with ITS OWN red patch: a guard with another patch on the same test is another bug.
python3 "$RC" --project "$R" add "baz bug" --fixed --test src/test/BazTest.kt --id BUG-BAZ >/dev/null
python3 - "$R/.agents/regression_status.json" <<'PY'
import json, sys, time
p = sys.argv[1]; d = json.load(open(p))
d["items"]["BUG-BAZ"]["red_proof"] = {"status": "PROVEN", "ts": time.time(), "mode": "patch",
    "patch": ".agents/local/red-patches/BUG-BAZ.patch", "files": {"src/test/BazTest.kt": "x"}}
# A row proven by REVERTING its fix (no patch): a guard with its own red patch has not been seen RED.
d["items"]["BUG-REV"] = {"id": "BUG-REV", "kind": "bug", "title": "rev bug", "component": "-", "fixed": True,
    "state": "confirmed", "tests": ["REG-MOD"], "runs_in_suite": ["src/test/QuxTest.kt"], "last": None, "history": [],
    "red_proof": {"status": "PROVEN", "ts": time.time(), "mode": "revert", "fix_commit": "abc1234",
                  "files": {"src/test/QuxTest.kt": "x"}}}
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
cat > .agents/local/guards.json <<'JSON'
{"_doc":"measured fixes","guards":[
 {"id":"G-NEW","title":"new guard only guards.json knows","file":"tests/test_a.py","tests":["tests/test_a.py"],
  "test_command":"python3 tests/test_a.py","red_patch":".agents/local/red-patches/G-NEW.patch","handbook":"sổ tay mục 1"},
 {"id":"G-PATCH","title":"the old bug, by its patch","file":"src/Core.kt","tests":["src/test/FooTest.kt"],
  "red_patch":".agents/local/red-patches/BUG-OLD.patch"},
 {"id":"G-ONE","title":"the bug of test c","file":"tests/test_c.sh","tests":["tests/test_c.sh"],
  "red_patch":".agents/local/red-patches/G-ONE.patch"},
 {"id":"G-SAME1","title":"first guard of BarTest","file":"src/Core.kt","tests":["src/test/BarTest.kt"]},
 {"id":"G-SAME2","title":"second guard of BarTest","file":"src/Core.kt","tests":["src/test/BarTest.kt"]},
 {"id":"G-PFX","title":"a guard added by hand first","file":"src/Core.kt","tests":["src/test/FooTest.kt"]},
 {"id":"G-BAZ","title":"another bug on BazTest","file":"src/Core.kt","tests":["src/test/BazTest.kt"],
  "red_patch":".agents/local/red-patches/G-BAZ.patch"},
 {"id":"G-REV","title":"a patch guard on a revert-proven test","file":"src/Core.kt","tests":["src/test/QuxTest.kt"],
  "red_patch":".agents/local/red-patches/G-REV.patch"},
 {"id":"REG-MOD","title":"a guard named like a suite","file":"src/Core.kt","tests":["src/test/FooTest.kt"]},
 {"id":"G-STR","title":"tests given as one string","file":"tests/test_a.py","tests":"tests/test_a.py"},
 {"title":"a guard without an id"}, "not a guard", null]}
JSON
render

# ── A. guards → checklist ──────────────────────────────────────────────────────
[ "$(py "I.get('G-NEW',{}).get('kind')")" = bug ] && [ "$(py "I['G-NEW']['title']")" = "new guard only guards.json knows" ] \
  && ok "A1 a guard only guards.json knows becomes a bug row (id + title)" || fail "A1 no G-NEW row: $(cat "$TMP/render.out")"
[ "$(py "'REG-PY' in I.get('G-NEW',{}).get('tests',[])")" = True ] && [ "$(py "'tests/test_a.py' in I.get('G-NEW',{}).get('runs_in_suite',[])")" = True ] \
  && ok "A2 its test is linked to the suite that runs it (REG-PY)" || fail "A2 G-NEW links: $(py "I.get('G-NEW')")"
st="$(py "rc.effective_status(d, I['G-NEW']) if 'G-NEW' in I else 'MISSING'")"
[ "$st" = NOT_RUN ] && ok "A3 a new guard row is NOT_RUN until a real run (never PASS)" || fail "A3 G-NEW status $st"
[ "$(py "'G-PATCH' in I")" = False ] && [ "$(py "I['BUG-OLD'].get('guards')")" = "['G-PATCH']" ] \
  && ok "A4 a guard whose red patch is an existing row's patch is that row (no duplicate)" || fail "A4 G-PATCH: $(py "('G-PATCH' in I, I['BUG-OLD'].get('guards'))")"
[ "$(py "'G-ONE' in I")" = False ] && [ "$(py "I['BUG-C'].get('guards')")" = "['G-ONE']" ] \
  && ok "A5 a guard whose one test an existing row links (one-to-one) is that row" || fail "A5 G-ONE: $(py "('G-ONE' in I, I['BUG-C'].get('guards'))")"
[ "$(py "'G-SAME1' in I and 'G-SAME2' in I and not I['BUG-BAR'].get('guards')")" = True ] \
  && ok "A6 two guards sharing one test are two rows (a shared test is no identity)" || fail "A6 BarTest guards: $(py "('G-SAME1' in I, 'G-SAME2' in I, I['BUG-BAR'].get('guards'))")"
[ "$(py "'G-PFX' in I")" = False ] && [ "$(py "I['BUG-G-PFX'].get('guards')")" = "['G-PFX']" ] \
  && [ "$(py "I['BUG-G-PFX']['tests']")" = "['REG-MOD']" ] \
  && ok "A6b a row stored as BUG-<guard id> is that guard's row, its links untouched" || fail "A6b G-PFX: $(py "('G-PFX' in I, I['BUG-G-PFX'].get('guards'), I['BUG-G-PFX']['tests'])")"
[ "$(py "'G-BAZ' in I and not I['BUG-BAZ'].get('guards')")" = True ] \
  && [ "$(py "rc.effective_status(d, I['G-BAZ']) if 'G-BAZ' in I else 'MISSING'")" != PASS ] \
  && ok "A6c a row proven with another red patch is not the guard's row (its PROVEN is not inherited)" \
  || fail "A6c G-BAZ: $(py "('G-BAZ' in I, I['BUG-BAZ'].get('guards'))")"
[ "$(py "'G-REV' in I and not I['BUG-REV'].get('guards')")" = True ] \
  && ok "A6d a row proven by revert (no patch) is not the row of a guard with its own red patch" \
  || fail "A6d G-REV: $(py "('G-REV' in I, I['BUG-REV'].get('guards'))")"
[ "$(py "I['BUG-C'].get('red_patch')")" = ".agents/local/red-patches/G-ONE.patch" ] \
  && ok "A6e a guard merged into an existing row brings its red_patch" || fail "A6e BUG-C red_patch: $(py "I['BUG-C'].get('red_patch')")"
[ "$(py "I.get('BUG-REG-MOD',{}).get('guards')")" = "['REG-MOD']" ] && [ "$(py "I['REG-MOD']['kind']")" = test ] \
  && ok "A6f a guard id equal to a suite id gets the row BUG-<id>, the suite stays" || fail "A6f: $(py "(I.get('BUG-REG-MOD'), I['REG-MOD']['kind'])")"
[ "$(py "I.get('G-STR',{}).get('runs_in_suite')")" = "['tests/test_a.py']" ] \
  && ok "A6g tests given as one string is one test file, not its characters" || fail "A6g G-STR: $(py "I.get('G-STR')")"
n1="$(py "len(I)")"; render; n2="$(py "len(I)")"
[ "$n1" = "$n2" ] && ok "A7 a second sync adds nothing ($n2 rows)" || fail "A7 rows $n1 → $n2"
python3 "$RC" --project "$TMP/noguards" render >/dev/null 2>&1
[ "$(python3 -c "import json; print(sum(1 for v in json.load(open('$TMP/noguards/.agents/regression_status.json'))['items'].values() if v.get('kind')=='bug'))")" = 0 ] \
  && ok "A8 no guards.json: no bug row is made" || fail "A8 bug rows appeared without guards.json"
N="$TMP/noguards"
for bad in '{"guards": null}' '"just a string"' '{"guards": 7}'; do
  printf '%s\n' "$bad" > "$N/.agents/local/guards.json"
  python3 "$RC" --project "$N" render >"$TMP/bad.out" 2>&1; rc=$?
  echo "fun ok() = 9" > "$N/src/Core.kt"
  CLAUDE_PROJECT_DIR="$N" python3 "$GATE" --matrix "$N/.agents/regression_matrix.active.json" --run-tests >>"$TMP/bad.out" 2>&1; grc=$?
  [ "$rc" = 0 ] && [ "$grc" = 0 ] && ! grep -q Traceback "$TMP/bad.out" \
    && ok "A8b guards.json $bad: render and gate still work (exit 0, no traceback)" || fail "A8b $bad: render $rc gate $grc $(grep -m2 -E 'Error|Traceback' "$TMP/bad.out")"
done
echo "print('a2')" > tests/test_a.py
gate --run-tests
st="$(py "rc.effective_status(d, I['G-NEW']) if 'G-NEW' in I else 'MISSING'")"
[ "$(py "I['REG-PY']['last']['status']")" = PASS ] && [ "$st" = UNPROVEN ] \
  && ok "A9 after its suite ran green the guard row is UNPROVEN (no RED proof), not PASS" || fail "A9 G-NEW after run: $st"
git checkout -q -- tests/test_a.py

# ── B. orphan tests ────────────────────────────────────────────────────────────
has() { py "'ORPHAN_TEST:$1' in I"; }
[ "$(has tests/test-b.py)" = True ] && ok "B1 a test no suite command or script names is ORPHAN_TEST" || fail "B1 tests/test-b.py not flagged"
[ "$(has tests/test_a.py)" = False ] && ok "B2 a test a suite's script runs by path is not orphan" || fail "B2 test_a.py flagged"
[ "$(has tests/test_c.sh)" = False ] && ok "B3 a test a suite's script runs through a glob (tests/test_*.sh) is not orphan" || fail "B3 test_c.sh flagged"
[ "$(has more/test_q.py)" = False ] && ok "B3b a quoted \$VAR glob (\"\$ROOT/more\"/test_*.py) is read as more/test_*.py" || fail "B3b more/test_q.py flagged"
[ "$(has src/test/FooTest.kt)" = False ] && ok "B4 a Kotlin test under a whole-module Gradle suite is not orphan" || fail "B4 FooTest flagged"
[ "$(has lib/src/test/NarrowTest.kt)" = False ] && [ "$(has lib/src/test/OtherTest.kt)" = True ] \
  && ok "B5 a --tests suite runs only the classes it names: the other test is orphan" || fail "B5 Narrow/Other: $(has lib/src/test/NarrowTest.kt)/$(has lib/src/test/OtherTest.kt)"
[ "$(has src/iosTest/ThingTests.swift)" = True ] && ok "B6 a Swift test under a Gradle-only suite is orphan (Gradle does not run XCTest)" || fail "B6 swift not flagged"
[ "$(py "any(k.startswith('ORPHAN_TEST:') and 'helper' in k for k in I)")" = False ] && ok "B7 a helper in tests/ (not a test file) is never orphan" || fail "B7 helper flagged"
grep -q 'ORPHAN_TEST:tests/test-b.py' .agents/CHECKLIST.md && grep 'ORPHAN_TEST:tests/test-b.py' .agents/CHECKLIST.md | grep -q '⚠️' \
  && ok "B8 the orphan is a ⚠️ row of the checklist with its fix" || fail "B8 CHECKLIST.md lacks the orphan row"
printf 'python3 tests/test_a.py\npython3 tests/test-b.py\n' > run.sh
render
[ "$(has tests/test-b.py)" = False ] && ok "B9 the row goes away once a suite script runs the test" || fail "B9 still orphan after run.sh names it"
git add run.sh && git commit -qm "run test-b"

# The gate blocks only a SURE orphan: a new test no rule watches and no suite command / script names
# (extra/ here). A new test under a watched dir is never blocked, only listed (checklist ⚠️).
mkdir -p extra
echo "print('new')" > extra/test_new.py; echo "fun ok() = 2" > src/Core.kt
gate --run-tests --full; rc=$?
[ "$rc" = 2 ] && grep -q 'file test MỚI mà không suite.*extra/test_new.py' "$TMP/out" && ok "B10 --full fails (exit 2) on a new test no rule watches and no suite names" \
  || fail "B10 --full exit $rc: $(tail -5 "$TMP/out")"
gate --run-tests --full --allow-orphan-tests; rc=$?
[ "$rc" = 0 ] && ok "B10b --allow-orphan-tests lets --full pass with a new orphan test" || fail "B10b exit $rc: $(tail -3 "$TMP/out")"
gate --run-tests; rc=$?
[ "$rc" = 0 ] && ok "B11 the impacted run (Stop hook) only warns about it" || fail "B11 impacted exit $rc: $(tail -5 "$TMP/out")"
git add extra src && git commit -qm "an orphan, committed"
echo "fun ok() = 3" > src/Core.kt
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B12 an orphan already committed does not fail --full (checklist row only)" || fail "B12 exit $rc: $(tail -5 "$TMP/out")"
[ "$(has extra/test_new.py)" = True ] && ok "B13 the committed orphan is a checklist row" || fail "B13 no row for extra/test_new.py"
echo "print('ok')" > tests/test_d.py
printf 'for t in tests/test_*.sh; do sh "$t" || exit 1; done\npython3 tests/test_d.py\n' > runall.sh
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B14 a new test that a changed suite script runs passes --full" || fail "B14 exit $rc: $(tail -5 "$TMP/out")"
echo "fun ok() = 1" > src/Core.kt
git add -A tests runall.sh src && git commit -qm "test_d"
git mv extra/test_new.py extra/test_renamed.py; echo "fun ok() = 4" > src/Core.kt
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B15 renaming an orphan test already committed does not fail --full" || fail "B15 exit $rc: $(tail -4 "$TMP/out")"
git add -A extra src && git commit -qm "rename"
echo "print('in range')" > extra/test_range.py && echo "fun ok() = 5" > src/Core.kt && git add extra src && git commit -qm "an orphan in a commit"
gate --run-tests --full --diff HEAD~1..HEAD; rc=$?
[ "$rc" = 2 ] && grep -q 'file test MỚI mà không suite.*extra/test_range.py' "$TMP/out" && ok "B16 --diff A..B checks the tests the range adds (base = A)" || fail "B16 exit $rc: $(tail -4 "$TMP/out")"
cp extra/test_range.py extra/test_copy.py && echo "print('changed')" >> extra/test_range.py && echo "fun ok() = 6" > src/Core.kt && git add extra src
gate --run-tests --full; rc=$?
[ "$rc" = 2 ] && grep -q 'file test MỚI mà không suite.*extra/test_copy.py' "$TMP/out" && ok "B17 a copied test is a new test (only a rename keeps its history)" || fail "B17 exit $rc: $(grep -m2 -E 'KẾT LUẬN|mồ côi' "$TMP/out")"
git commit -qm "copy"
echo "print('w')" > tests/test_watched_new.py
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B18 a new test under a watched dir is never blocked (whatever the runner analysis says)" || fail "B18 exit $rc: $(grep -m2 -E 'KẾT LUẬN|mồ côi' "$TMP/out")"

# ── C. suites that run tests through a runner (not by naming the file) ─────────
covered() {  # <repo> <test path> → True when some suite of its matrix runs it
  python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as rc; from pathlib import Path
p=Path('$1'); m=json.load(open(p/'.agents/regression_matrix.active.json'))
print(not rc.orphan_tests(p, m, candidates=['$2']))"
}
mkcase() {  # <dir> <command> <watch glob>
  mkdir -p "$1/.agents" "$1/tests" "$1/src" && (cd "$1" && git init -q . && git config user.email t@t && git config user.name t)
  printf '{"project":"c","rules":[{"component":"C","watch_files":["%s"],"mandatory_regression_tests":[{"id":"REG-C","name":"c","command":"%s"}]}]}\n' "$3" "$2" > "$1/.agents/regression_matrix.active.json"
}
C="$TMP/c1"; mkcase "$C" "sh scripts/run-tests.sh" "src/*.py"; mkdir -p "$C/scripts"
printf 'cd "$(dirname "$0")/.."\npython3 -m unittest discover -s tests -t .\n' > "$C/scripts/run-tests.sh"
echo "x = 1" > "$C/src/app.py"; touch "$C/tests/__init__.py"; printf 'import unittest\nclass T(unittest.TestCase):\n    def test_x(self): self.assertEqual(1, 1)\n' > "$C/tests/test_b.py"
[ "$(covered "$C" tests/test_b.py)" = True ] && ok "C1 a wrapper script whose runner is unittest discover runs tests/test_b.py" || fail "C1 wrapper unittest"
(cd "$C" && git add -A && git commit -qm init && cp tests/test_b.py tests/test_new.py && echo "x = 2" > src/app.py)
CLAUDE_PROJECT_DIR="$C" python3 "$GATE" --run-tests --full >"$TMP/c.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "C1b --full passes a new test the wrapper's runner collects" || fail "C1b exit $rc: $(grep -m3 -E 'CHƯA|UNVERIFIED|mồ côi' "$TMP/c.out")"
C="$TMP/c2"; mkcase "$C" "make test" "src/*.py"; printf 'test:\n\tpytest tests/\n' > "$C/Makefile"; echo "x=1" > "$C/tests/test_m.py"
[ "$(covered "$C" tests/test_m.py)" = True ] && ok "C2 make test → the Makefile recipe pytest tests/" || fail "C2 make test"
C="$TMP/c3"; mkcase "$C" "tox -e py" "src/*.py"; printf '[testenv]\ncommands = pytest\n' > "$C/tox.ini"; echo "x=1" > "$C/tests/test_t.py"
[ "$(covered "$C" tests/test_t.py)" = True ] && ok "C3 tox -e py → tox.ini commands" || fail "C3 tox"
C="$TMP/c4"; mkcase "$C" "npm run unit" "src/*.js"; mkdir -p "$C/test"; printf '{"scripts":{"unit":"node --test test/"}}\n' > "$C/package.json"; echo "1" > "$C/test/foo.test.js"
[ "$(covered "$C" test/foo.test.js)" = True ] && ok "C4 npm run unit → the package.json script node --test" || fail "C4 npm run unit"
C="$TMP/c5"; mkcase "$C" "python3 -m unittest" "src/*.py"; echo "x=1" > "$C/tests/test_u.py"
[ "$(covered "$C" tests/test_u.py)" = True ] && ok "C5 python3 -m unittest (discovery) runs tests/test_u.py" || fail "C5 unittest"
C="$TMP/c6"; mkcase "$C" "./gradlew build" "src/main/*"; mkdir -p "$C/src/test"; echo "class XTest" > "$C/src/test/XTest.kt"
[ "$(covered "$C" src/test/XTest.kt)" = True ] && ok "C6 ./gradlew build runs the unit tests (watch only src/main)" || fail "C6 gradlew build"
C="$TMP/c7"; mkcase "$C" "mvn verify" "src/main/*"; mkdir -p "$C/src/test/java"; echo "class YTest {}" > "$C/src/test/java/YTest.java"
[ "$(covered "$C" src/test/java/YTest.java)" = True ] && ok "C7 mvn verify runs the unit tests" || fail "C7 mvn verify"
C="$TMP/c8"; mkcase "$C" "pytest -q" "src/*.py"; echo "x=1" > "$C/tests/test_p.py"
[ "$(covered "$C" tests/test_p.py)" = True ] && ok "C8 pytest at the root runs tests/ although only src/*.py is watched" || fail "C8 pytest watch"
C="$TMP/c9"; mkcase "$C" "sh ci.sh" "tests/*"; { echo true; python3 -c "print(('#' * 99 + chr(10)) * 21000, end='')"; } > "$C/ci.sh"; echo "x=1" > "$C/tests/test_o.py"
(cd "$C" && git add -A && git commit -qm init && echo "x=2" > tests/test_new.py)
CLAUDE_PROJECT_DIR="$C" python3 "$GATE" --run-tests --full >"$TMP/c.out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'tests/test_new.py' "$TMP/c.out" && ok "C9 a wrapper whose runner cannot be read only warns about a new orphan" \
  || fail "C9 exit $rc: $(grep -m3 -E 'CHƯA|mồ côi|orphan' "$TMP/c.out")"

# ── D. what a wrapper runs is read narrowly: no runner from another target, a help text or a path
#       the runner is not given (a false "covered" hides a real orphan) ──────────────────────────
runs() {  # <repo> <path> → the suites that run it
  python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as rc; from pathlib import Path
p=Path('$1'); m=json.load(open(p/'.agents/regression_matrix.active.json')); print(rc.running_suites(p, '$2', rc.suite_index(p, m)))"
}
C="$TMP/d1"; mkcase "$C" "make lint" "src/*.py"; printf 'lint:\n\tflake8 src\ntest:\n\tpytest\n' > "$C/Makefile"
mkdir -p "$C/tests/other"; echo "x=1" > "$C/tests/other/test_unrelated.py"
[ "$(covered "$C" tests/other/test_unrelated.py)" = False ] && ok "D1 make lint reads only the lint recipe (not the test target's pytest)" || fail "D1 make lint covers a test"
C="$TMP/d2"; mkcase "$C" "npm run lint" "src/*.js"; printf '{"scripts":{"lint":"eslint .","test":"vitest run"}}\n' > "$C/package.json"; echo 1 > "$C/bar.test.js"
[ "$(covered "$C" bar.test.js)" = False ] && ok "D2 npm run lint reads only scripts.lint (not scripts.test)" || fail "D2 npm run lint covers bar.test.js"
C="$TMP/d3"; mkcase "$C" "tox -e lint" "src/*.py"; printf '[testenv:lint]\ndeps = pytest\ncommands = flake8 src\n[testenv:unit]\ncommands = pytest\n' > "$C/tox.ini"; echo "x=1" > "$C/tests/test_t.py"
[ "$(covered "$C" tests/test_t.py)" = False ] && ok "D3 tox -e lint reads only the commands of [testenv:lint]" || fail "D3 tox -e lint covers a test"
C="$TMP/d4"; mkcase "$C" "sh run.sh" "src/*.py"
printf 'echo "usage: run pytest yourself"\nprintf "%%s\\n" "or pytest -q"\n# pytest used to run here\ncat <<EOF\n  pytest tests/\nEOF\nflake8 src\n' > "$C/run.sh"; echo "x=1" > "$C/tests/test_x.py"
[ "$(covered "$C" tests/test_x.py)" = False ] && ok "D4 echo / printf / comment / heredoc lines of a script are not its runner" || fail "D4 help text counted as a runner"
C="$TMP/d5"; mkcase "$C" "bash ctl.sh health" "src/*.js"; mkdir -p "$C/test"
printf 'case "$1" in\n  test) node --test test/ ;;\n  health) echo ok ;;\nesac\n' > "$C/ctl.sh"; echo 1 > "$C/test/a.test.mjs"
[ "$(covered "$C" test/a.test.mjs)" = False ] && ok "D5 a runner under another subcommand (case \"\$1\") of the script does not count" || fail "D5 subcommand runner counted"
C="$TMP/d6"; mkdir -p "$C/.agents" "$C/tests" "$C/scripts" && (cd "$C" && git init -q . && git config user.email t@t && git config user.name t)
printf '{"project":"d","rules":[{"component":"T","watch_files":["tests/*"],"mandatory_regression_tests":[{"id":"REG-T","name":"t","command":"python3 tests/test_a.py"}]},{"component":"F","watch_files":["scripts/*.sh"],"mandatory_regression_tests":[{"id":"REG-FMT","name":"fmt","command":"sh scripts/fmt.sh"},{"id":"REG-GOFMT","name":"gofmt","command":"sh scripts/gofmt.sh"}]}]}\n' > "$C/.agents/regression_matrix.active.json"
echo "echo fmt-ok" > "$C/scripts/fmt.sh"; echo "gofmt -l . || true" > "$C/scripts/gofmt.sh"; echo "print(1)" > "$C/tests/test_a.py"
(cd "$C" && git add -A && git commit -qm init && mkdir -p extra && echo "print(2)" > extra/test_new.py && echo "echo x" > scripts/other.sh)
CLAUDE_PROJECT_DIR="$C" python3 "$GATE" --run-tests --full >"$TMP/d.out" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q 'file test MỚI mà không suite.*extra/test_new.py' "$TMP/d.out" && ! grep -E 'file test MỚI|có thể' "$TMP/d.out" | grep -q 'REG-FMT\|REG-GOFMT' \
  && ok "D6 a sure orphan (no watch, no name) still blocks; wrappers that run no test are not named" \
  || fail "D6 exit $rc: $(grep -m3 -E 'KẾT LUẬN|mồ côi|REG-FMT' "$TMP/d.out")"
C="$TMP/d7"; mkcase "$C" "python3 -m pytest tests/unit" "src/*.py"; mkdir -p "$C/tests/unit" "$C/tests/other"
echo "x=1" > "$C/tests/unit/test_one.py"; echo "x=1" > "$C/tests/other/test_unrelated.py"
[ "$(covered "$C" tests/unit/test_one.py)" = True ] && [ "$(covered "$C" tests/other/test_unrelated.py)" = False ] \
  && ok "D7 pytest tests/unit runs tests/unit only (its path argument is its scope)" || fail "D7 pytest path scope: $(covered "$C" tests/unit/test_one.py)/$(covered "$C" tests/other/test_unrelated.py)"
C="$TMP/d8"; mkcase "$C" "node --test tests/a.test.mjs" "src/*.js"; echo 1 > "$C/tests/a.test.mjs"; echo 1 > "$C/tests/unrelated.test.mjs"
[ "$(covered "$C" tests/a.test.mjs)" = True ] && [ "$(covered "$C" tests/unrelated.test.mjs)" = False ] \
  && ok "D8 node --test <file> runs that file only" || fail "D8 node file scope"
C="$TMP/d9"; mkcase "$C" "sh loop.sh" "src/*.py"; mkdir -p "$C/tests/unit" "$C/tests/other"
printf 'for f in tests/unit/test_one.py; do python3 -m pytest "$f"; done\n' > "$C/loop.sh"
echo "x=1" > "$C/tests/unit/test_one.py"; echo "x=1" > "$C/tests/other/test_two.py"
[ "$(covered "$C" tests/unit/test_one.py)" = True ] && [ "$(covered "$C" tests/other/test_two.py)" = True ] \
  && ok "D9 a runner given \$VAR runs an unknown set: never called an orphan" || fail "D9 \$VAR scope: $(covered "$C" tests/other/test_two.py)"
C="$TMP/d10"; mkcase "$C" "./gradlew :app:build" "app/*"; mkdir -p "$C/app/src/test" "$C/core/src/test"
touch "$C/app/build.gradle" "$C/core/build.gradle"; echo "class ATest" > "$C/app/src/test/ATest.kt"; echo "class CTest" > "$C/core/src/test/CTest.kt"
[ "$(covered "$C" app/src/test/ATest.kt)" = True ] && [ "$(covered "$C" core/src/test/CTest.kt)" = False ] \
  && ok "D10 ./gradlew :app:build runs the :app tests only" || fail "D10 :app:build scope: $(covered "$C" app/src/test/ATest.kt)/$(covered "$C" core/src/test/CTest.kt)"
C="$TMP/d11"; mkcase "$C" "mvn package -DskipTests" "src/main/*"; mkdir -p "$C/src/test/java"; echo "class ZTest {}" > "$C/src/test/java/ZTest.java"
[ "$(covered "$C" src/test/java/ZTest.java)" = False ] && ok "D11 mvn package -DskipTests runs no test" || fail "D11 -DskipTests counted"
C="$TMP/d12"; mkcase "$C" "./gradlew build -x test" "src/main/*"; mkdir -p "$C/src/test"; echo "class WTest" > "$C/src/test/WTest.kt"
[ "$(covered "$C" src/test/WTest.kt)" = False ] && ok "D12 ./gradlew build -x test runs no test" || fail "D12 -x test counted"
C="$TMP/d13"; mkcase "$C" "cd rs && cargo test --test smoke" "rs/*"
[ "$(runs "$C" rs/tests/other_test.rs)" = "[]" ] && ok "D13 cargo test --test smoke runs that test target only" || fail "D13 cargo --test: $(runs "$C" rs/tests/other_test.rs)"
# The agent-workbench shape: agent-kit (a subcommand script whose help text says pytest and whose
# `test` subcommand runs node --test) must not cover a new test in a folder no suite runs.
C="$TMP/d14"; mkcase "$C" "bash universal-agent-devkit/bin/agent-kit health -t ." ".claude/settings.json"
mkdir -p "$C/universal-agent-devkit/bin" "$C/zz_demo"; cp "$DEVKIT_DIR/bin/agent-kit" "$C/universal-agent-devkit/bin/agent-kit"
echo "x=1" > "$C/zz_demo/test_orphan_demo.py"; echo 1 > "$C/zz_demo/orphan_demo.test.mjs"
[ "$(covered "$C" zz_demo/test_orphan_demo.py)" = False ] && [ "$(covered "$C" zz_demo/orphan_demo.test.mjs)" = False ] \
  && ok "D14 agent-kit health (agent-workbench) does not cover new tests in zz_demo/" || fail "D14 zz_demo covered: $(covered "$C" zz_demo/test_orphan_demo.py)/$(covered "$C" zz_demo/orphan_demo.test.mjs)"

# ── E. real-world suites the runner analysis misread (8d5d39b blocked each one) ─
FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
for b in make npm bun pytest mocha xcodebuild dotnet cargo node; do printf '#!/bin/sh\nexit 0\n' > "$FAKE/$b"; chmod +x "$FAKE/$b"; done
egate() {  # <case> <command> <watch> <new test> — the gate on a new test the suite may run: exit code
  local C="$TMP/$1"
  (cd "$C" && git add -A && git commit -qm init && mkdir -p "$(dirname "$4")" && echo "x = 1" > "$4")
  PATH="$FAKE:$PATH" CLAUDE_PROJECT_DIR="$C" python3 "$GATE" --run-tests --full >"$TMP/$1.out" 2>&1; echo $?
}
ecase() {  # <case> <command> <watch> <new test> <label> [setup: shell run inside the repo]
  local C="$TMP/$1"; mkcase "$C" "$2" "$3"; (cd "$C" && eval "${6:-true}")
  rc="$(egate "$1" "$2" "$3" "$4")"
  [ "$rc" = 0 ] && ok "$1 $5: --full passes" || fail "$1 $5: --full exit $rc $(grep -m2 -E 'KẾT LUẬN' "$TMP/$1.out")"
}
ecase E1 "pytest -x tests/" "tests/*" tests/test_e.py "pytest -x (not Gradle's -x test)"
ecase E2 "./gradlew check -x connectedAndroidTest" "src/*" src/test/ETest.kt "gradle check -x connectedAndroidTest" "printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew"
ecase E3 "make test" "tests/*" tests/test_m.py "make test → prerequisite unit" "printf 'test: unit\nunit:\n\tpytest tests/\n' > Makefile"
ecase E4 "make check" "tests/*" tests/test_m.py "make check: lint test" "printf 'check: lint test\nlint:\n\ttrue\ntest:\n\tpytest\n' > Makefile"
ecase E5 "make" "tests/*" tests/test_m.py "make (all: test)" "printf 'all: test\ntest:\n\tpytest\n' > Makefile"
ecase E6 "make test" "tests/*" tests/test_m.py "make recipe \$(PYTEST)" "printf 'PYTEST ?= pytest\ntest:\n\t\$(PYTEST) tests/\n' > Makefile"
ecase E7 "npm test" "src/*" src/a.test.js "scripts.test = npm run test:unit" "printf '{\"scripts\":{\"test\":\"npm run test:unit\",\"test:unit\":\"vitest run\"}}' > package.json"
ecase E8 "npm test" "src/*" src/a.test.js "scripts.test = run-s" "printf '{\"scripts\":{\"test\":\"run-s lint unit\",\"unit\":\"vitest run\",\"lint\":\"eslint .\"}}' > package.json"
ecase E9 "npm test" "src/*" src/a.test.js "react-scripts test" "printf '{\"scripts\":{\"test\":\"react-scripts test\"}}' > package.json"
ecase E10 "npm test" "src/*" src/a.spec.ts "ng test" "printf '{\"scripts\":{\"test\":\"ng test\"}}' > package.json"
ecase E11 "npm test" "src/*" src/a.spec.ts "playwright test" "printf '{\"scripts\":{\"test\":\"playwright test\"}}' > package.json"
ecase E12 "npm test" "src/*" src/a.test.js "scripts.test calls a sh script" "mkdir -p scripts && printf 'vitest run\n' > scripts/test.sh && printf '{\"scripts\":{\"test\":\"sh scripts/test.sh\"}}' > package.json"
ecase E13 "bun test" "src/*" src/a.test.ts "bun test"
ecase E14 "sh run.sh" "tests/*" tests/test_w.py 'wrapper pytest "$@"' "printf 'pytest \"\$@\"\n' > run.sh"
ecase E15 "sh run.sh" "tests/*" tests/test_w.py 'wrapper pytest $PYTEST_ARGS' "printf 'pytest \$PYTEST_ARGS\n' > run.sh"
ecase E16 "sh run.sh" "tests/*" tests/test_w.py 'case "$1" parsing an option' "printf 'case \"\$1\" in\n  -v) V=1 ;;\nesac\npytest tests/\n' > run.sh"
ecase E17 "pytest --ignore tests/slow" "tests/*" tests/test_i.py "pytest --ignore tests/slow"
ecase E18 "pytest --cov src" "tests/*" tests/test_i.py "pytest --cov src"
ecase E19 "pytest --basetemp /tmp/pt" "tests/*" tests/test_i.py "pytest --basetemp /tmp/pt"
ecase E20 "mocha --require x 'test/**/*.spec.js'" "test/*" test/unit/a.spec.js "mocha --require x 'glob'"
ecase E21 "xcodebuild test -project App.xcodeproj -scheme App -resultBundlePath out/r" "AppTests/*" AppTests/LoginTests.swift "xcodebuild -project/-scheme/-resultBundlePath" "mkdir -p App out"
ecase E22 "dotnet test App.sln" "tests/*" tests/Unit/CalcTests.cs "dotnet test App.sln" "touch App.sln"
ecase E24 "node --test 'tests/**/*.test.mjs'" "tests/*" tests/deep/a.test.mjs "node --test 'glob' (fnmatch, not startswith)"
# the checklist reads these runs too (no ⚠️ row)
for c in E1:tests/test_e.py E2:src/test/ETest.kt E3:tests/test_m.py E5:tests/test_m.py E6:tests/test_m.py E13:src/a.test.ts E14:tests/test_w.py E15:tests/test_w.py E16:tests/test_w.py E17:tests/test_i.py E20:test/unit/a.spec.js E22:tests/Unit/CalcTests.cs E24:tests/deep/a.test.mjs; do
  [ "$(covered "$TMP/${c%%:*}" "${c#*:}")" = True ] && ok "${c%%:*} the checklist sees the suite run ${c#*:}" || fail "${c%%:*} checklist still calls ${c#*:} an orphan"
done
C="$TMP/e23"; mkcase "$C" "cargo test --manifest-path rs/Cargo.toml" "rs/*"
[ "$(runs "$C" rs/tests/it.rs)" = "['REG-C']" ] && ok "E23 cargo --manifest-path is no test path scope" || fail "E23 cargo manifest: $(runs "$C" rs/tests/it.rs)"
C="$TMP/e25"; mkcase "$C" "make test" "src/*.py"; printf 'test:\n\t@echo running && pytest\n\t-@true\n' > "$C/Makefile"; echo "x=1" > "$C/tests/test_r.py"
[ "$(covered "$C" tests/test_r.py)" = True ] && ok "E25 a make recipe line with @ / - and echo && pytest runs pytest" || fail "E25 @ recipe"
C="$TMP/e26"; mkcase "$C" "sh run.sh" "src/*.py"; printf 'N=$((1<<2))\npytest\n' > "$C/run.sh"; echo "x=1" > "$C/tests/test_h.py"
[ "$(covered "$C" tests/test_h.py)" = True ] && ok "E26 \$((1<<2)) is no heredoc: the lines after it are read" || fail "E26 arithmetic shift read as heredoc"

# ── F. the block rule itself: the new test is OUTSIDE every watch (watch src/*.py, test in tests/).
#       A suite the analysis cannot follow may run it: nothing is sure, --full passes (⚠️ row only).
for b in pnpm yarn tox; do printf '#!/bin/sh\nexit 0\n' > "$FAKE/$b"; chmod +x "$FAKE/$b"; done
fcase() {  # <case> <command> <label> <setup> [expected exit=0] [watch] [new test] [changed file]
  local C="$TMP/$1" want="${5:-0}" nt="${7:-tests/test_new.py}" ch="${8:-src/app.py}"
  mkcase "$C" "$2" "${6:-src/*.py}"; touch "$C/tests/__init__.py"; mkdir -p "$(dirname "$C/$ch")"; echo "x = 1" > "$C/$ch"
  (cd "$C" && eval "$4" && git add -A && git commit -qm init && mkdir -p "$(dirname "$nt")" && echo "x = 2" > "$ch" \
    && case "$nt" in *.py) printf 'import unittest\nclass T(unittest.TestCase):\n    def test_x(self):\n        self.assertEqual(1 + 1, 2)\n' > "$nt" ;; *) echo "class CTest" > "$nt" ;; esac)
  PATH="$FAKE:$PATH" CLAUDE_PROJECT_DIR="$C" python3 "$GATE" --run-tests --full >"$TMP/$1.out" 2>&1; local rc=$?
  [ "$rc" = "$want" ] && ok "$1 $3: --full exit $rc" || fail "$1 $3: --full exit $rc (want $want) $(grep -m1 -E 'KẾT LUẬN' "$TMP/$1.out")"
}
fcase F1 "make test" "make with include ci.mk" "printf 'include ci.mk\ntest: ci-test\n' > Makefile && printf 'ci-test:\n\tpytest tests/\n' > ci.mk"
fcase F2 "make test" "make recipe \$(MAKE) -C tests" "printf 'test:\n\t\$(MAKE) -C tests\n' > Makefile && printf 'all:\n\tpytest\n' > tests/Makefile"
fcase F3 "make -f ci.mk test" "make -f ci.mk test" "printf 'test:\n\tpytest\n' > ci.mk"
fcase F4 "pnpm -r test" "pnpm -r test" "true"
fcase F5 "npm --prefix web test" "npm --prefix web test" "mkdir -p web && printf '{\"scripts\":{\"test\":\"vitest run\"}}' > web/package.json"
fcase F6 "npm test --workspaces" "npm test --workspaces" "printf '{\"scripts\":{\"test\":\"echo root\"}}' > package.json"
fcase F7 "yarn workspace web test" "yarn workspace web test" "printf '{\"scripts\":{\"build\":\"tsc\"}}' > package.json"
fcase F8 "sh a.sh" "a 3-level script chain" "printf 'sh b.sh\n' > a.sh && printf 'sh c.sh\n' > b.sh && printf 'pytest tests/\n' > c.sh"
fcase F9 "sh run.sh" 'case "$1" in ci) … esac then pytest tests/' "printf 'case \"\$1\" in\n  ci) CI=1 ;;\n  *) ;;\nesac\npytest tests/\n' > run.sh"
fcase F10 "tox" "tox configured in pyproject.toml" "printf '[tool.tox]\nlegacy_tox_ini = \"\"\"\n[testenv]\ncommands = pytest\n\"\"\"\n' > pyproject.toml"
fcase F11 "python3 -m unittest -v" "python3 -m unittest -v" "true"
# …and a sure orphan still blocks when every suite is read to the end:
fcase F12 "./gradlew :app:testDebugUnitTest" "gradle :app:testDebugUnitTest, new test in core/" \
  "printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew && mkdir -p app/src/main core/src/test && touch app/build.gradle core/build.gradle" \
  2 "app/*" core/src/test/CTest.kt app/src/main/A.kt
grep -q 'file test MỚI mà không suite.*core/src/test/CTest.kt' "$TMP/F12.out" && ok "F12 names the sure orphan" || fail "F12 message"
[ "$(python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as rc; from pathlib import Path
p=Path('$TMP/F11'); print(bool(rc.running_suites(p, 'tests/test_new.py', rc.suite_index(p, json.load(open(p/'.agents/regression_matrix.active.json'))))))")" = True ] \
  && ok "F11b python3 -m unittest -v is read as a discovery run" || fail "F11b -m unittest -v not a runner"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
