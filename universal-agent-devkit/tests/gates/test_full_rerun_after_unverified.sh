#!/usr/bin/env bash
# Regression test (the time saving itself): a --full that ends exit 2 because an existing test was edited must not make
# the re-run with --auto-approve-tests run every suite again on the same code.
# 2026-10-07 (OfficeReader runs.jsonl): --full exit 2 (269 s) -> the same --full with the approval -> 254 s, all suites again.
# The fake suite counts its runs in $TMP/runs (outside the repo: a file inside would change the code fingerprint).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
export TMP
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

make_repo() { # $1 = extra matrix row ("" or ',{...}')
  rm -rf "$TMP/repo" "$TMP/runs" && mkdir -p "$TMP/repo/app/src/main/kotlin/pkg" "$TMP/repo/app/src/test/kotlin/pkg"
  : > "$TMP/runs"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(4, Lonely().value()) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  printf '#!/bin/sh\necho run >> "%s/runs"\nexit 0\n' "$TMP" > gradlew && chmod +x gradlew
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests","command":"./gradlew :app:testDebugUnitTest","impacted_command":"./gradlew :app:testDebugUnitTest"}$1]}]}
JSON
  git add -A && git commit -qm init
  printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(8, Lonely().value() * 2) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt   # an EXISTING test line rewritten (not appended): the gate wants a review
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
}
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --lang en "$@" 2>&1; }
runs() { wc -l < "$TMP/runs" | tr -d ' '; }
receipt_exit() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["exit"])' "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" 2>/dev/null || echo none; }

# A. every suite runs and passes; only the edited test blocks
make_repo ""
run_gate --run-tests --full >/dev/null; rc=$?
[ "$rc" = 2 ] && [ "$(runs)" = 1 ] && ok "A1: the edited test makes --full exit 2 after one run of the suite" || bad "A1: exit $rc, suite ran $(runs) times"
[ "$(receipt_exit)" = 2 ] && ok "A2: the receipt says exit 2 (proof_gate and push_gate accept only 0: XONG and push stay refused)" || bad "A2: receipt exit is $(receipt_exit)"
out="$(run_gate --run-tests --full --auto-approve-tests)"; rc=$?
[ "$rc" = 0 ] && ok "A3: with the approval the same code passes (exit 0)" || bad "A3: exit $rc: $(printf '%s' "$out" | tail -4)"
[ "$(runs)" = 1 ] && ok "A4: the suite did NOT run again (1 run in total)" || bad "A4: the suite ran $(runs) times, the re-run paid it again"
[ "$(receipt_exit)" = 0 ] && ok "A5: the approved run leaves the exit-0 receipt XONG needs" || bad "A5: receipt exit is $(receipt_exit)"

# B. a suite that cannot run here by design (REG-QC-05 of GeelyEx2): it must not cancel the reuse of the others
make_repo ',{"id":"REG-MANUAL","name":"manual","command":"exit 2","impacted_command":"exit 2","untested_exit":2}'
run_gate --run-tests --full >/dev/null; rc=$?
[ "$rc" = 2 ] && [ "$(runs)" = 1 ] && ok "B1: exit 2 after one run of the suite (REG-MANUAL UNTESTED by design)" || bad "B1: exit $rc, suite ran $(runs) times"
run_gate --run-tests --full --auto-approve-tests >/dev/null; rc=$?
[ "$rc" = 4 ] && ok "B2: the approved run is UNTESTED (exit 4) because of the manual suite, as always" || bad "B2: exit $rc"
[ "$(runs)" = 1 ] && ok "B3: the suite that can run was NOT run again (1 run in total)" || bad "B3: the suite ran $(runs) times: the UNTESTED manual suite cancelled the reuse"

# C. a change after the exit 2 is never reused
make_repo ""
run_gate --run-tests --full >/dev/null
echo "// changed after the exit 2" >> app/src/main/kotlin/pkg/Lonely.kt
run_gate --run-tests --full --auto-approve-tests >/dev/null
[ "$(runs)" = 2 ] && ok "C: code that changed after the exit 2 runs the suite again (2 runs)" || bad "C: the suite ran $(runs) times, expected 2"

[ "$FAILS" -eq 0 ] && echo "full rerun after unverified: all checks passed" || { echo "full rerun after unverified: $FAILS FAILED"; exit 1; }
