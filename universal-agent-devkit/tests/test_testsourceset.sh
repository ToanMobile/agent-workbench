#!/usr/bin/env bash
# Regression test: hooks/testsourceset_gate.sh compiles each touched module's UNIT-TEST
# source set with the task that module really has. AGP creates unit-test variants only
# for `testBuildType`: a module with `testBuildType = "release"` (OfficeReader's :app) has
# compileReleaseUnitTestKotlin and no compileDebugUnitTestKotlin, and used to be dropped
# as "lacks the task" — its broken src/test passed the gate. The task is derived the way
# scripts/matrix_detect.py reads testBuildType (comment lines ignored). Fake ./gradlew
# only: it records its arguments and answers like Gradle; no real build runs.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/hooks/testsourceset_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# new_repo → sets R to a fresh git work tree with a fake ./gradlew. The fake knows the
# tasks listed in .tasks; a task in .broken fails with a Kotlin compile error; any other
# task is "not found in project", worded as Gradle words it.
new_repo() {
  N=$((N + 1))
  R="$TMP/r$N"
  mkdir -p "$R"
  git -C "$R" init -q
  cat > "$R/gradlew" <<'SH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$here/.calls"
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  grep -qxF -- "$a" "$here/.tasks" 2>/dev/null || {
    echo "Cannot locate tasks that match '$a' as task '${a##*:}' not found in project '${a%:*}'."
    exit 1; }
done
for a in "$@"; do
  if grep -qxF -- "$a" "$here/.broken" 2>/dev/null; then
    echo "e: file://$here/app/src/test/FooTest.kt:3:5 No value passed for parameter 'x'."
    echo "> Task $a FAILED"
    exit 1
  fi
done
exit 0
SH
  chmod +x "$R/gradlew"
  : > "$R/.tasks"; : > "$R/.broken"
}

# module <dir> <build.gradle.kts body> — a module with one uncommitted Kotlin file.
module() {
  mkdir -p "$R/$1/src/main/kotlin"
  printf '%s\n' "$2" > "$R/$1/build.gradle.kts"
  printf 'class Foo\n' > "$R/$1/src/main/kotlin/Foo.kt"
}

gate() {
  ERR="$(printf '{"session_id":"tss-%s"}' "$N" | CLAUDE_PROJECT_DIR="$R" bash "$GATE" 2>&1 >/dev/null)"
  RC=$?
}

RELEASE_APP='plugins { id("com.android.application") }
android {
    // testBuildType = "debug"  (was, before AGP 9)
    testBuildType = "release"
}'

# ── 1. testBuildType = "release": the release unit-test task is compiled ──
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":app:compileReleaseUnitTestKotlin" "$R/.calls"; then
  ok "testBuildType=release → :app:compileReleaseUnitTestKotlin"
else
  fail "testBuildType=release → want :app:compileReleaseUnitTestKotlin, exit 0; got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 2. …and a broken release test source set BLOCKS instead of being skipped ──
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.broken"
gate
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF "compileReleaseUnitTestKotlin"; then
  ok "broken src/test of a release-testBuildType module blocks (exit 2)"
else
  fail "broken release src/test: want exit 2 naming compileReleaseUnitTestKotlin; got exit $RC: $(printf '%s' "$ERR" | head -3 | tr '\n' ' ')"
fi

# ── 3. only `> Task …:compileReleaseUnitTestKotlin FAILED` (no e: line) is still a compile failure
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
cat > "$R/gradlew" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(cd "$(dirname "$0")" && pwd)/.calls"
echo "> Task :app:compileReleaseUnitTestKotlin FAILED"
exit 1
SH
chmod +x "$R/gradlew"
gate
[ "$RC" = 2 ] && ok "'…compileReleaseUnitTestKotlin FAILED' is read as a compile failure" \
  || fail "compileReleaseUnitTestKotlin FAILED read as infra (exit $RC)"

# ── 4. no testBuildType (or only in a comment) → Debug, as before ──────────
new_repo
module lib 'plugins { id("com.android.library") }
// testBuildType = "release"'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":lib:compileDebugUnitTestKotlin" "$R/.calls" && ! grep -qF "Release" "$R/.calls"; then
  ok "no testBuildType (commented one ignored) → :lib:compileDebugUnitTestKotlin"
else
  fail "debug module: got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 5. groovy `testBuildType 'staging'` + a debug module, in one build ─────
new_repo
mkdir -p "$R/core/src/main/java"
printf "android {\n    testBuildType 'staging'\n}\n" > "$R/core/build.gradle"
printf 'class Bar {}\n' > "$R/core/src/main/java/Bar.java"
module lib 'plugins { id("com.android.library") }'
printf ':core:compileStagingUnitTestKotlin\n:lib:compileDebugUnitTestKotlin\n' > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":core:compileStagingUnitTestKotlin" "$R/.calls" \
   && grep -qF ":lib:compileDebugUnitTestKotlin" "$R/.calls"; then
  ok "per-module: groovy testBuildType 'staging' and a debug module side by side"
else
  fail "mixed modules: got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 6. a module that really lacks its task is still skipped, not blamed ────
new_repo
module app "$RELEASE_APP"
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && [ "$(wc -l < "$R/.calls" | tr -d ' ')" = 2 ] && tail -1 "$R/.calls" | grep -qxF ":lib:compileDebugUnitTestKotlin --quiet"; then
  ok "a module without its unit-test task is dropped and the rest re-run"
else
  fail "missing-task retry: got exit $RC, calls: $(tr '\n' '|' < "$R/.calls" 2>/dev/null)"
fi

if [ "$FAILS" -ne 0 ]; then echo "test_testsourceset: $FAILS FAILED"; exit 1; fi
echo "test_testsourceset: all checks passed"
