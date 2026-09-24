#!/usr/bin/env bash
# Regression test: impacted-test selection in bin/post-fix-gate.py (matrix "impacted_command").
# A fake ./gradlew records the arguments it was called with, so each case checks WHICH
# tests the gate asked for, not only the verdict:
#   - a changed class with a <Class>Test          -> --tests pkg.FooTest only, "PASS (impacted: 1 tests)"
#   - a changed class a test only references      -> that test
#   - a new test file                             -> itself
#   - a build-file change / cap exceeded / shared code / no test names the class /
#     conftest.py / {gradle_tests} spanning two modules -> full command
#   - --full, POSTFIX_GATE_FULL=1                 -> full command
#   - an impacted FAIL is a REJECT; an impacted PASS never becomes the checklist row's PASS
#   - {gradle_module_tests:<task>}, {pytest_nodes}, {unity_filter} expand to their runner syntax
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# These cases test WHICH tests the selection runs, with a fake runner that is always green:
# the gate's vacuity check (VACUITY_REVERT — revert the production diff, the impacted test must
# go red) would call every one of them vacuous. It is off here and tested on its own at the end.
export VACUITY_REVERT=0
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARGS="$TMP/runner.args"

FAILS=0
ok()   { echo "✔ $1"; }
bad()  { echo "✖ $1"; FAILS=$((FAILS + 1)); }
check_exit() { [ "$2" = "$3" ] && ok "$1 (exit $3)" || bad "$1: exit $3, expected $2"; }
has()  { printf '%s' "$3" | grep -qF -- "$2" && ok "$1" || bad "$1: missing '$2'"; }
hasnt() { printf '%s' "$3" | grep -qF -- "$2" && bad "$1: contains '$2'" || ok "$1"; }

kt_test() { # file package class [body-reference]
  mkdir -p "$(dirname "$1")"
  printf 'package %s\n\nimport org.junit.Test\n\nclass %s {\n    @Test fun works() { %s }\n}\n' "$2" "$3" "${4:-}" > "$1"
}

make_repo() { # $1 = impacted_command (JSON-escaped), $2 = full command
  rm -rf "$TMP/repo" "$ARGS" && mkdir -p "$TMP/repo"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  mkdir -p app/src/main/kotlin/pkg
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nobject Foo {\n    fun value() = 1\n}\n' > app/src/main/kotlin/pkg/Foo.kt
  printf 'package pkg\n\nclass Bar {\n    fun value() = 2\n}\n' > app/src/main/kotlin/pkg/Bar.kt
  printf 'package pkg\n\nclass Shared {\n    fun value() = 3\n}\n' > app/src/main/kotlin/pkg/Shared.kt
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  kt_test app/src/test/kotlin/pkg/FooTest.kt pkg FooTest "Foo.value()"
  kt_test app/src/test/kotlin/pkg/BarUserTest.kt pkg BarUserTest "Bar().value()"
  kt_test app/src/test/kotlin/pkg/SharedOneTest.kt pkg SharedOneTest "Shared().value()"
  kt_test app/src/test/kotlin/pkg/SharedTwoTest.kt pkg SharedTwoTest "Shared().value()"
  printf '#!/bin/sh\necho "$@" > "%s"\nexit "${FAKE_EXIT:-0}"\n' "$ARGS" > gradlew && chmod +x gradlew
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests",
   "command":"$2","impacted_command":"$1"}]}]}
JSON
  git add -A && git commit -qm init
}

run_gate() {
  rm -f "$ARGS"
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --lang en --json "$@" 2>&1
}
ran() { cat "$ARGS" 2>/dev/null; }

IMPACTED='./gradlew :app:testDebugUnitTest {gradle_tests}'
FULL='./gradlew testDebugUnitTest'

# --- (a) selection by name -------------------------------------------------------------
make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(run_gate --run-tests)"; check_exit "changed class with a <Class>Test -> PASS" 0 $?
has "only FooTest was asked for" ":app:testDebugUnitTest --tests pkg.FooTest" "$(ran)"
hasnt "BarUserTest not selected" "BarUserTest" "$(ran)"
has "PASS labelled as impacted in the output" "PASS (impacted: 1 tests)" "$out"
has "mode and reason printed" "mode IMPACTED" "$out"
has "JSON test_mode impacted" '"test_mode": "impacted"' "$out"
has "JSON label" '"label": "PASS (impacted: 1 tests)"' "$out"
has "JSON says a full run is still required" '"full_run_required": true' "$out"
hasnt "verdict is not the handover PASS" "READY FOR ACCEPTANCE" "$out"
has "report carries the impacted label" "PASS (impacted: 1 tests)" "$(cat .git/postfix-gate/last_report.md)"
python3 - "$TMP/repo/.agents/regression_status.json" <<'PY' && ok "impacted PASS is not recorded as the checklist row's PASS" || bad "impacted PASS recorded as a full PASS in the checklist"
import json, sys
row = json.load(open(sys.argv[1]))["items"]["REG-APP"]
sys.exit(0 if (row.get("last") or {}).get("status") != "PASS" and row.get("impacted_at") else 1)
PY

# --- (b) selection by reference --------------------------------------------------------
make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Bar.kt
out="$(run_gate --run-tests)"; check_exit "changed class referenced by a test -> PASS" 0 $?
has "the referencing test was asked for" "--tests pkg.BarUserTest" "$(ran)"
hasnt "FooTest not selected" "FooTest" "$(ran)"
has "reason names the reference" "reference: 1" "$out"

# --- (c) a new test file selects itself ------------------------------------------------
make_repo "$IMPACTED" "$FULL"
kt_test app/src/test/kotlin/pkg/NewCaseTest.kt pkg NewCaseTest "org.junit.Assert.assertEquals(1, Foo.value())"
out="$(run_gate --run-tests)"; check_exit "new test file -> PASS" 0 $?
has "the new test itself was asked for" "--tests pkg.NewCaseTest" "$(ran)"

# --- fallbacks to the full command -----------------------------------------------------
make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
echo "// tweak" >> app/build.gradle.kts
out="$(run_gate --run-tests)"; check_exit "build-file change -> PASS on the full command" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "build-file change ran the full command" || bad "build-file change ran: $(ran)"
has "full-mode reason names the build file" "app/build.gradle.kts is not source code" "$out"
has "full run keeps the handover verdict" "READY FOR ACCEPTANCE" "$out"
has "JSON test_mode full" '"test_mode": "full"' "$out"

make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
echo "// tweak" >> app/src/main/kotlin/pkg/Bar.kt
out="$(POSTFIX_GATE_IMPACTED_CAP=1 run_gate --run-tests)"; check_exit "cap exceeded -> PASS on the full command" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "cap exceeded ran the full command" || bad "cap exceeded ran: $(ran)"
has "reason names the cap" "2 tests selected > cap 1" "$out"

make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Shared.kt
out="$(POSTFIX_GATE_IMPACTED_REF_CAP=1 run_gate --run-tests)"; check_exit "shared code -> full" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "shared code ran the full command" || bad "shared code ran: $(ran)"
has "reason says shared code" "shared code" "$out"

make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
out="$(run_gate --run-tests)"; check_exit "class no test names -> full when placeholder is {gradle_tests}" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "unnamed class ran the full command" || bad "unnamed class ran: $(ran)"

# {gradle_module_tests}: a class no test names falls back to its package, not the other module.
MOD='./gradlew {gradle_module_tests:testDebugUnitTest}'
WIDE='./gradlew :app:testDebugUnitTest :core:testDebugUnitTest'
make_repo "$MOD" "$WIDE"
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
out="$(run_gate --run-tests)"; check_exit "unnamed class -> package filter" 0 $?
has "package filter on the app module" ":app:testDebugUnitTest --tests pkg.*" "$(ran)"
hasnt "other module not run" ":core:testDebugUnitTest" "$(ran)"
has "package mode printed" "mode PACKAGE" "$out"

make_repo "$MOD" "$WIDE"
mkdir -p app/src/main/res/values
printf '<resources></resources>\n' > app/src/main/res/values/strings.xml
out="$(run_gate --run-tests)"; check_exit "resource xml -> no JVM suite" 0 $?
has "resource mode printed" "mode RESOURCE" "$out"
[ ! -f "$ARGS" ] && ok "resource xml did not launch gradle" || bad "resource xml ran: $(ran)"

make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(run_gate --full)"; check_exit "--full -> PASS" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "--full ran the full command (no --tests)" || bad "--full ran: $(ran)"
has "--full reason printed" "full run forced (--full)" "$out"
out="$(POSTFIX_GATE_FULL=1 run_gate --run-tests)"
[ "$(ran)" = "testDebugUnitTest" ] && ok "POSTFIX_GATE_FULL=1 ran the full command" || bad "POSTFIX_GATE_FULL=1 ran: $(ran)"

# --- an impacted FAIL is a real failure ------------------------------------------------
make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(FAKE_EXIT=1 run_gate --run-tests)"; check_exit "failing impacted run -> REJECT" 1 $?
hasnt "a failing impacted run is not labelled PASS" "PASS (impacted" "$out"

# --- {gradle_module_tests:<task>}: per-module tasks, only modules the full command runs --
make_repo './gradlew {gradle_module_tests:testDebugUnitTest} --continue' './gradlew :core:testDebugUnitTest :feature:testDebugUnitTest --continue'
printf 'include(":app", ":core", ":feature")\n' > settings.gradle.kts
mkdir -p core/src/main/kotlin/pkg && printf 'package pkg\n\nclass CoreThing\n' > core/src/main/kotlin/pkg/CoreThing.kt
kt_test core/src/test/kotlin/pkg/CoreThingTest.kt pkg CoreThingTest "CoreThing()"
kt_test feature/src/test/kotlin/pkg/FeatureUsesCoreTest.kt pkg FeatureUsesCoreTest "CoreThing()"
kt_test app/src/test/kotlin/pkg/AppUsesCoreTest.kt pkg AppUsesCoreTest "CoreThing()"
sed -i.bak 's#"app/\*"#"app/*","core/*","feature/*"#' matrix.json && rm -f matrix.json.bak
git add -A && git commit -qm modules
echo "// tweak" >> core/src/main/kotlin/pkg/CoreThing.kt
out="$(run_gate --run-tests)"; check_exit "multi-module selection -> PASS" 0 $?
has "core module task with its test" ":core:testDebugUnitTest --tests pkg.CoreThingTest" "$(ran)"
has "feature module task with the referencing test" ":feature:testDebugUnitTest --tests pkg.FeatureUsesCoreTest" "$(ran)"
hasnt "a module the full command does not run is left out" "AppUsesCoreTest" "$(ran)"

# --- {gradle_tests} cannot span modules -> full ---------------------------------------
make_repo "$IMPACTED" "$FULL"
mkdir -p lib/src/test/kotlin/pkg && kt_test lib/src/test/kotlin/pkg/LibUsesFooTest.kt pkg LibUsesFooTest "Foo.value()"
git add -A && git commit -qm lib
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(run_gate --run-tests)"; check_exit "{gradle_tests} across modules -> full" 0 $?
[ "$(ran)" = "testDebugUnitTest" ] && ok "cross-module {gradle_tests} ran the full command" || bad "cross-module ran: $(ran)"

# --- {pytest_nodes} ---------------------------------------------------------------------
rm -rf "$TMP/py" && mkdir -p "$TMP/py/tool" "$TMP/py/tests" && cd "$TMP/py" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf 'def parse(x):\n    return x\n' > tool/parser.py
printf 'from tool.parser import parse\n\ndef test_parse():\n    assert parse(1) == 1\n' > tests/test_parser.py
printf 'def test_other():\n    assert True\n' > tests/test_other.py
printf '#!/bin/sh\necho "$@" > "%s"\n' "$ARGS" > runner.sh && chmod +x runner.sh
cat > matrix.json <<'JSON'
{"project":"py","rules":[{"component":"tool","watch_files":["tool/*.py"],
 "mandatory_regression_tests":[{"id":"REG-PY","name":"pytest","command":"./runner.sh -q","impacted_command":"./runner.sh -q {pytest_nodes}"}]}]}
JSON
git add -A && git commit -qm init
echo "# tweak" >> tool/parser.py
rm -f "$ARGS"
out="$(CLAUDE_PROJECT_DIR="$TMP/py" python3 "$GATE" --matrix "$TMP/py/matrix.json" --lang en --run-tests 2>&1)"
check_exit "pytest selection -> PASS" 0 $?
has "pytest got the matching test file" "tests/test_parser.py" "$(ran)"
hasnt "pytest did not get the unrelated test" "test_other.py" "$(ran)"
git checkout -q -- tool/parser.py
printf 'import pytest\n' > tool/conftest.py
rm -f "$ARGS"
out="$(CLAUDE_PROJECT_DIR="$TMP/py" python3 "$GATE" --matrix "$TMP/py/matrix.json" --lang en --run-tests 2>&1)"
[ "$(ran)" = "-q" ] && ok "conftest.py (autouse fixtures) runs the full command" || bad "conftest.py ran: $(ran)"

# --- {unity_filter}: EditMode tests only, as unity-batch.sh --filter ------------------
rm -rf "$TMP/u" && mkdir -p "$TMP/u/Assets/Scripts" "$TMP/u/Assets/Tests/EditMode" "$TMP/u/Assets/Tests/PlayMode" && cd "$TMP/u" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf 'namespace Game {\n  public class Shelf { }\n}\n' > Assets/Scripts/Shelf.cs
printf '{"name":"EditTests","includePlatforms":["Editor"]}\n' > Assets/Tests/EditMode/EditTests.asmdef
printf '{"name":"PlayTests","includePlatforms":[]}\n' > Assets/Tests/PlayMode/PlayTests.asmdef
printf 'using NUnit.Framework;\nnamespace Game.Tests {\n  public class ShelfTests {\n    [Test] public void Works() { new Shelf(); }\n  }\n}\n' > Assets/Tests/EditMode/ShelfTests.cs
printf 'using NUnit.Framework;\nnamespace Game.Play {\n  public class ShelfPlayTests {\n    [Test] public void Works() { new Shelf(); }\n  }\n}\n' > Assets/Tests/PlayMode/ShelfPlayTests.cs
printf '#!/bin/sh\necho "$@" > "%s"\n' "$ARGS" > unity-batch.sh && chmod +x unity-batch.sh
cat > matrix.json <<'JSON'
{"project":"u","rules":[{"component":"code","watch_files":["Assets/*.cs"],
 "mandatory_regression_tests":[{"id":"REG-EDIT","name":"editmode","command":"./unity-batch.sh editmode","impacted_command":"./unity-batch.sh editmode {unity_filter}"}]}]}
JSON
git add -A && git commit -qm init
echo "// tweak" >> Assets/Scripts/Shelf.cs
rm -f "$ARGS"
out="$(CLAUDE_PROJECT_DIR="$TMP/u" python3 "$GATE" --matrix "$TMP/u/matrix.json" --lang en --run-tests 2>&1)"
check_exit "unity selection -> PASS" 0 $?
[ "$(ran)" = "editmode --filter Game.Tests.ShelfTests" ] && ok "unity-batch.sh got the EditMode test as --filter" || bad "unity ran: $(ran)"

echo

# --- vacuity check (VACUITY_REVERT=1): the impacted test must go red on the unfixed code ---
make_repo "$IMPACTED" "$FULL"
printf '#!/bin/sh\necho "$@" > "%s"\ngrep -q tweak app/src/main/kotlin/pkg/Foo.kt || { echo "java.lang.AssertionError: expected 2 but was 1"; echo "FooTest > works FAILED"; exit 1; }\n' "$ARGS" > gradlew
git commit -qam "runner sees the fix"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(VACUITY_REVERT=1 run_gate --run-tests)"; check_exit "vacuity: test red without the change, green with it -> PASS" 0 $?
grep -q "tweak" app/src/main/kotlin/pkg/Foo.kt && ok "vacuity: the working tree is restored after the revert" || bad "vacuity: Foo.kt not restored"
make_repo "$IMPACTED" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(VACUITY_REVERT=1 run_gate --run-tests)"; check_exit "vacuity: test green without the change too -> FAIL" 1 $?
has "vacuity: labelled VACUOUS" '"label": "VACUOUS"' "$out"
if [ "$FAILS" -eq 0 ]; then echo "ALL IMPACTED-SELECTION TESTS PASSED"; else echo "$FAILS FAILED"; exit 1; fi
