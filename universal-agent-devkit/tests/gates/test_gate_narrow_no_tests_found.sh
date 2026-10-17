#!/usr/bin/env bash
# Test hồi quy: bước narrow (`--tests '*<tên file>*'`, narrow_fallback) của bin/post-fix-gate.py mà Gradle
# trả "No tests found for given includes" thì gate KHÔNG được chấm FAIL chỉ vì bộ lọc không khớp test nào.
# Đo thật 17/10 ở GeelyEx2: sửa một dòng KDoc trong ThemePrefs.kt (không có test tên ThemePrefs) → REG-CAR-01
# FAIL sau ~7 phút, chặn gộp vào main. Cách sửa: chạy lại lệnh FULL của test một lần, và chấm theo lệnh full.
#   (1) narrow "No tests found" + full xanh → PASS, lệnh full đã chạy
#   (2) narrow "No tests found" + full đỏ  → FAIL (không biến FAIL thật thành PASS)
#   (3) narrow đỏ vì test hỏng thật        → FAIL, không chạy lệnh full
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CALLS="$TMP/runner.calls"

FAILS=0
ok()   { echo "✔ $1"; }
bad()  { echo "✖ $1"; FAILS=$((FAILS + 1)); }
check_exit() { [ "$2" = "$3" ] && ok "$1 (exit $3)" || bad "$1: exit $3, expected $2"; }
has()  { printf '%s' "$3" | grep -qF -- "$2" && ok "$1" || bad "$1: missing '$2'"; }
hasnt() { printf '%s' "$3" | grep -qF -- "$2" && bad "$1: contains '$2'" || ok "$1"; }

MOD='./gradlew {gradle_module_tests:testDebugUnitTest}'
WIDE='./gradlew :app:testDebugUnitTest :core:testDebugUnitTest'

make_repo() {
  rm -rf "$TMP/repo" "$CALLS" && mkdir -p "$TMP/repo"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  mkdir -p app/src/main/kotlin/pkg app/src/test/kotlin/pkg
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nclass ThemePrefs {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/ThemePrefs.kt
  printf 'package pkg\n\nimport org.junit.Test\n\nclass FooTest {\n    @Test fun works() { }\n}\n' > app/src/test/kotlin/pkg/FooTest.kt
  # Gradle giả: ghi lại từng lần gọi; lệnh có --tests thì giả lập bộ lọc không khớp (NARROW_NO_TESTS=1)
  # hoặc thoát NARROW_EXIT; lệnh full thoát FULL_EXIT.
  cat > gradlew <<SH
#!/bin/sh
echo "\$@" >> "$CALLS"
case "\$*" in
  *--tests*)
    if [ "\${NARROW_NO_TESTS:-0}" = 1 ]; then
      echo "Execution failed for task ':app:testDebugUnitTest'."
      echo "> No tests found for given includes: [*ThemePrefs*](filter.includeTestsMatching)"
      echo "BUILD FAILED in 3s"
      exit 1
    fi
    if [ "\${NARROW_EXIT:-0}" != 0 ]; then echo "FooTest > works FAILED"; echo "BUILD FAILED"; fi
    exit "\${NARROW_EXIT:-0}" ;;
esac
exit "\${FULL_EXIT:-0}"
SH
  chmod +x gradlew
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests",
   "command":"$WIDE","impacted_command":"$MOD"}]}]}
JSON
  git add -A && git commit -qm init
  echo "// KDoc tweak" >> app/src/main/kotlin/pkg/ThemePrefs.kt
}

run_gate() {
  rm -f "$CALLS"
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --lang en --json --run-tests 2>&1
}
calls() { cat "$CALLS" 2>/dev/null; }

# --- (1) bộ lọc narrow không khớp test nào, lệnh full xanh → PASS ------------------------------------------
make_repo
out="$(NARROW_NO_TESTS=1 FULL_EXIT=0 run_gate)"; check_exit "narrow 'No tests found' + full green -> PASS" 0 $?
has "the narrow filter was tried first" ":app:testDebugUnitTest --tests *ThemePrefs*" "$(calls)"
has "the full command was run after it" ":app:testDebugUnitTest :core:testDebugUnitTest" "$(calls)"
hasnt "no FAIL verdict" '"status": "FAIL"' "$out"

# --- (2) bộ lọc narrow không khớp, lệnh full đỏ → vẫn FAIL --------------------------------------------------
make_repo
out="$(NARROW_NO_TESTS=1 FULL_EXIT=1 run_gate)"; check_exit "narrow 'No tests found' + full red -> FAIL" 1 $?
has "the full command was run" ":app:testDebugUnitTest :core:testDebugUnitTest" "$(calls)"

# --- (3) narrow đỏ vì test hỏng thật → FAIL, không đổi sang lệnh full ---------------------------------------
make_repo
out="$(NARROW_EXIT=1 FULL_EXIT=0 run_gate)"; check_exit "narrow real failure -> FAIL" 1 $?
hasnt "a real narrow failure does not fall back to the full command" ":core:testDebugUnitTest" "$(calls)"

echo
[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$FAILS FAILED"; exit 1; }
