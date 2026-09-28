#!/usr/bin/env bash
# Regression test: two ways a fixed bug fell out of the regression checklist (GeelyEx2 28/09/2026).
#   A. A guard in .agents/local/guards.json (measured fix + test + red patch) is a checklist bug
#      row: id = guard id, linked to the suites that run its tests, never PASS without a run and a
#      RED proof; an existing row with the same red patch (or, one-to-one, the same test) is that
#      guard's row — no duplicate. No guards.json: nothing changes.
#   B. A test file no suite of the matrix executes is an ⚠️ ORPHAN_TEST row; `post-fix-gate --full`
#      fails when the current diff ADDS such a file (an existing orphan only warns).
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
echo "class ThingTests" > src/iosTest/ThingTests.swift
echo "class NarrowTest" > lib/src/test/NarrowTest.kt
echo "class OtherTest" > lib/src/test/OtherTest.kt
echo "print('a')" > tests/test_a.py
echo "print('b')" > tests/test-b.py
echo "exit 0" > tests/test_c.sh
echo "X = 1" > tests/helper.py
printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew
printf 'python3 tests/test_a.py\n' > run.sh
printf 'for t in tests/test_*.sh; do sh "$t" || exit 1; done\n' > runall.sh
mkdir -p more && echo "print('q')" > more/test_q.py
printf 'for t in "$ROOT/more"/test_*.py; do :; done\n' > runq.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[
 {"component":"App","watch_files":["src/*"],
  "mandatory_regression_tests":[{"id":"REG-MOD","name":"app unit","command":"./gradlew testDebugUnitTest"}]},
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
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
cat > .agents/local/guards.json <<'JSON'
{"_doc":"measured fixes","guards":[
 {"id":"G-NEW","title":"new guard only guards.json knows","file":"tests/test_a.py","tests":["tests/test_a.py"],
  "test_command":"python3 tests/test_a.py","red_patch":".agents/local/red-patches/G-NEW.patch","handbook":"sổ tay mục 1"},
 {"id":"G-PATCH","title":"the old bug, by its patch","file":"src/Core.kt","tests":["src/test/FooTest.kt"],
  "red_patch":".agents/local/red-patches/BUG-OLD.patch"},
 {"id":"G-ONE","title":"the bug of test c","file":"tests/test_c.sh","tests":["tests/test_c.sh"]},
 {"id":"G-SAME1","title":"first guard of BarTest","file":"src/Core.kt","tests":["src/test/BarTest.kt"]},
 {"id":"G-SAME2","title":"second guard of BarTest","file":"src/Core.kt","tests":["src/test/BarTest.kt"]},
 {"id":"G-PFX","title":"a guard added by hand first","file":"src/Core.kt","tests":["src/test/FooTest.kt"]},
 {"id":"G-BAZ","title":"another bug on BazTest","file":"src/Core.kt","tests":["src/test/BazTest.kt"],
  "red_patch":".agents/local/red-patches/G-BAZ.patch"}]}
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
n1="$(py "len(I)")"; render; n2="$(py "len(I)")"
[ "$n1" = "$n2" ] && ok "A7 a second sync adds nothing ($n2 rows)" || fail "A7 rows $n1 → $n2"
python3 "$RC" --project "$TMP/noguards" render >/dev/null 2>&1
[ "$(python3 -c "import json; print(sum(1 for v in json.load(open('$TMP/noguards/.agents/regression_status.json'))['items'].values() if v.get('kind')=='bug'))")" = 0 ] \
  && ok "A8 no guards.json: no bug row is made" || fail "A8 bug rows appeared without guards.json"
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

# The gate: a NEW orphan test in the diff fails --full; the same file once committed only warns.
echo "print('new')" > tests/test-new.py
gate --run-tests --full; rc=$?
[ "$rc" != 0 ] && grep -q 'tests/test-new.py' "$TMP/out" && ok "B10 --full fails (exit $rc) on a new test no suite runs, naming it" \
  || fail "B10 --full exit $rc: $(tail -5 "$TMP/out")"
gate --run-tests; rc=$?
[ "$rc" = 0 ] && ok "B11 the impacted run (Stop hook) only warns about it" || fail "B11 impacted exit $rc: $(tail -5 "$TMP/out")"
git add tests/test-new.py && git commit -qm "an orphan, committed"
echo "fun ok() = 3" > src/Core.kt
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B12 an orphan already committed does not fail --full (checklist row only)" || fail "B12 exit $rc: $(tail -5 "$TMP/out")"
[ "$(has tests/test-new.py)" = True ] && ok "B13 the committed orphan is a checklist row" || fail "B13 no row for test-new.py"
echo "print('ok')" > tests/test_d.py
printf 'for t in tests/test_*.sh; do sh "$t" || exit 1; done\npython3 tests/test_d.py\n' > runall.sh
gate --run-tests --full; rc=$?
[ "$rc" = 0 ] && ok "B14 a new test that a changed suite script runs passes --full" || fail "B14 exit $rc: $(tail -5 "$TMP/out")"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
