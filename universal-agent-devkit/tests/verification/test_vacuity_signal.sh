#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py's vacuity re-run (VACUITY_REVERT) writes the base version over the production
# files of the LIVE tree and puts the fix back in `finally`. A SIGTERM / SIGHUP (the Stop hook's timeout, a closed
# terminal) killed python without running that `finally`: the agent's uncommitted fix was gone, `git status` clean,
# and the suite it had started (its own session) ran on as an orphan (audit 2026-10-09).
# The fix must survive the signal and the suite must not outlive the gate.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
GATE_PID=""
cleanup() {
  [ -n "$GATE_PID" ] && kill -KILL "$GATE_PID" 2>/dev/null
  [ -f "$TMP/runner.pid" ] && kill -KILL "$(cat "$TMP/runner.pid")" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

for SIG in TERM HUP; do
  rm -rf "$TMP/repo" "$TMP/runner.pid" && mkdir -p "$TMP/repo"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  mkdir -p app/src/main/kotlin/pkg app/src/test/kotlin/pkg
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nobject Foo {\n    fun value() = 1\n}\n' > app/src/main/kotlin/pkg/Foo.kt
  printf 'package pkg\n\nimport org.junit.Test\n\nclass FooTest {\n    @Test fun works() { Foo.value() }\n}\n' \
    > app/src/test/kotlin/pkg/FooTest.kt
  # Green while the fix ("tweak") is in Foo.kt; once the vacuity re-run has reverted it, hang (a long suite) and say so.
  cat > gradlew <<EOF
#!/bin/sh
grep -q tweak app/src/main/kotlin/pkg/Foo.kt && exit 0
echo \$\$ > "$TMP/runner.pid"
sleep 60
exit 1
EOF
  chmod +x gradlew
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests",
   "command":"./gradlew testDebugUnitTest","impacted_command":"./gradlew :app:testDebugUnitTest {gradle_tests}"}]}]}
JSON
  git add -A && git commit -qm init
  echo "// tweak" >> app/src/main/kotlin/pkg/Foo.kt     # the agent's uncommitted fix

  CLAUDE_PROJECT_DIR="$TMP/repo" VACUITY_REVERT=1 python3 "$GATE" --matrix "$TMP/repo/matrix.json" \
    --lang en --json --run-tests >"$TMP/gate.out" 2>&1 &
  GATE_PID=$!
  for _ in $(seq 1 300); do [ -s "$TMP/runner.pid" ] && break; sleep 0.1; done
  if [ ! -s "$TMP/runner.pid" ]; then
    bad "SIG$SIG: the vacuity re-run never started"; sed -n '1,30p' "$TMP/gate.out"; kill -KILL "$GATE_PID" 2>/dev/null
    GATE_PID=""; continue
  fi
  runner="$(cat "$TMP/runner.pid")"
  kill -"$SIG" "$GATE_PID"
  for _ in $(seq 1 100); do kill -0 "$GATE_PID" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$GATE_PID" 2>/dev/null; then bad "SIG$SIG: the gate is still running 10 s after the signal"; kill -KILL "$GATE_PID"; fi
  wait "$GATE_PID" 2>/dev/null
  GATE_PID=""
  grep -q tweak app/src/main/kotlin/pkg/Foo.kt && ok "SIG$SIG during the vacuity re-run: the uncommitted fix is back in Foo.kt" \
    || bad "SIG$SIG during the vacuity re-run: the fix was LOST (Foo.kt left at the base version)"
  sleep 0.3
  # a killed suite whose new parent (pid 1) does not reap it stays a zombie (a container without an init): dead, though kill -0 succeeds
  stat_r="$(ps -o stat= -p "$runner" 2>/dev/null)"
  if [ -n "$stat_r" ] && [ "${stat_r#Z}" = "$stat_r" ]; then
    bad "SIG$SIG: the suite (pid $runner) outlived the gate"; kill -KILL "$runner" 2>/dev/null
  else
    ok "SIG$SIG: the suite did not outlive the gate"
  fi
  cd "$TMP" || exit 1
done

[ "$FAILS" -eq 0 ] && echo "✅ test_vacuity_signal: all tests passed" || { echo "❌ test_vacuity_signal: $FAILS failed"; exit 1; }
