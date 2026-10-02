#!/usr/bin/env bash
# Regression test: the vacuity check (VACUITY_REVERT) of bin/post-fix-gate.py when the fix is
# already COMMITTED and the gate runs with --since <base> (what hooks/regression_gate.sh does for
# unverified commits). The revert must put the production files back to the --since base, not to
# HEAD: HEAD already holds the fix, so a revert to HEAD changes nothing, every test stays green
# and is labelled VACUOUS (OfficeReader, 2026-09-28: three bugs PROVEN by red_proof.py were still
# rejected as "vacuous" after they were committed).
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok()   { echo "✔ $1"; }
bad()  { echo "✖ $1"; FAILS=$((FAILS + 1)); }
check_exit() { [ "$2" = "$3" ] && ok "$1 (exit $3)" || bad "$1: exit $3, expected $2"; }
has()  { printf '%s' "$3" | grep -qF -- "$2" && ok "$1" || bad "$1: missing '$2'"; }
hasnt() { printf '%s' "$3" | grep -qF -- "$2" && bad "$1: contains '$2'" || ok "$1"; }

make_repo() { # $1 = runner script body
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  mkdir -p app/src/main/kotlin/pkg app/src/test/kotlin/pkg
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nobject Foo {\n    fun value() = 1\n}\n' > app/src/main/kotlin/pkg/Foo.kt
  printf 'package pkg\n\nimport org.junit.Test\n\nclass FooTest {\n    @Test fun works() { Foo.value() }\n}\n' \
    > app/src/test/kotlin/pkg/FooTest.kt
  printf '%s' "$1" > gradlew && chmod +x gradlew
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests",
   "command":"./gradlew testDebugUnitTest","impacted_command":"./gradlew :app:testDebugUnitTest {gradle_tests}"}]}]}
JSON
  git add -A && git commit -qm init
}

run_gate() {
  CLAUDE_PROJECT_DIR="$TMP/repo" VACUITY_REVERT=1 python3 "$GATE" --matrix "$TMP/repo/matrix.json" \
    --lang en --json --run-tests "$@" 2>&1
}

# A runner whose test fails unless the fix ("tweak") is in Foo.kt.
SEES_FIX='#!/bin/sh
grep -q tweak app/src/main/kotlin/pkg/Foo.kt || { echo "java.lang.AssertionError: expected 2 but was 1"; echo "FooTest > works FAILED"; exit 1; }
'

# --- (a) fix committed, gate --since the commit before it: the test was red there -> PASS -----
make_repo "$SEES_FIX"
base="$(git rev-parse HEAD)"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
git commit -qam "fix"
out="$(run_gate --since "$base")"; check_exit "committed fix, --since base: red at the base -> PASS" 0 $?
hasnt "committed fix: not labelled VACUOUS" '"label": "VACUOUS"' "$out"
grep -q tweak app/src/main/kotlin/pkg/Foo.kt && ok "committed fix: the working tree is restored after the revert" \
  || bad "committed fix: Foo.kt not restored"
[ -z "$(git status --porcelain -- app)" ] && ok "committed fix: nothing left modified under app/" || bad "committed fix: tree dirty: $(git status --porcelain -- app)"

# --- (b) a test that is green at the base too is still VACUOUS with --since ------------------
make_repo '#!/bin/sh
exit 0
'
base="$(git rev-parse HEAD)"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
git commit -qam "fix"
out="$(run_gate --since "$base")"; check_exit "committed fix, test green at the base too -> FAIL" 1 $?
has "green at the base: labelled VACUOUS" '"label": "VACUOUS"' "$out"

# --- (c) uncommitted fix, no --since: unchanged (revert to HEAD) -------------------------------
make_repo "$SEES_FIX"
echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt
out="$(run_gate)"; check_exit "uncommitted fix: red at HEAD -> PASS" 0 $?
grep -q tweak app/src/main/kotlin/pkg/Foo.kt && ok "uncommitted fix: working tree restored" || bad "uncommitted fix: Foo.kt not restored"

# --- (d) a --since that git would read as an option is refused --------------------------------
out="$(run_gate --since=--output=/tmp/x)"; check_exit "--since starting with '-' -> refused" 2 $?
has "--since refusal names the flag" "invalid --since" "$out"

echo
[ "$FAILS" -eq 0 ] && { echo "test_vacuity_since: all passed"; exit 0; }
echo "test_vacuity_since: $FAILS failed"; exit 1
