#!/usr/bin/env bash
# Regression (workflow audit 2026-10-04): the gate asked for --allow-no-tests / a human review of changes no test
# could catch, against the essentials contract ("a Markdown-only change needs no regression test").
#  1. Goods: an untracked reports/tour-<time>/… (a test's own output) next to an AGENTS.md edit made
#     docs_only false → exit 2. tree_fp already treats reports/ as tool output; needs_no_test did not.
#  2. GeelyEx2 docs/specs/*.md and OfficeReader app/src/test/snapshots/README.md are documentation, but
#     a directory named specs/test made them an "edited existing test" → exit 2.
#  Kept as they were (negative controls): a Markdown FIXTURE a test reads (androidTest/assets/…), a CI
#  workflow, and code no matrix rule covers still stop at exit 2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk() {
  R="$TMP/$1"; mkdir -p "$R/src" "$R/lib" "$R/.agents" "$R/docs/specs" "$R/app/src/test/snapshots" "$R/reports/tests" \
    "$R/src/test/logs" "$R/app/src/androidTest/assets/test_files" "$R/.github/workflows" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt; echo "fun lib() = 1" > lib/X.kt; echo "# a" > AGENTS.md
  echo "spec a" > docs/specs/a.md; echo "snap" > app/src/test/snapshots/README.md
  echo "fixture a" > app/src/androidTest/assets/test_files/s.md; echo "name: ci" > .github/workflows/ci.yml
  mkdir -p tests tests/docs; echo "readme parser a" > tests/readme_parser_test.md; echo "doc test a" > tests/docs/test_parser.md; echo "golden a" > app/src/test/snapshots/expected.md; echo "def v(): return 1" > reports/views.py
  printf 'def test_v():\n    assert v() == 1\n' > reports/tests/test_views.py; echo "crash a" > src/test/logs/crash_sample.log
  printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"true"}]}]}\n' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
}
exit_of() { ( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json > "$TMP/$1.out" 2>&1; echo $? ); }
expect() {   # name, description, expected exit
  local rc; rc="$(exit_of "$1")"
  [ "$rc" = "$3" ] && ok "$2 → exit $rc" || fail "$2: exit $rc, expected $3 ($(grep -o '"verdict": "[^"]*"' "$TMP/$1.out" | tail -1 | cut -c1-110))"
}

mk a; echo "# b" > AGENTS.md
expect a "AGENTS.md only" 0
mk b; echo "# b" > AGENTS.md; mkdir -p reports/tour-1; echo '{}' > reports/tour-1/a.json; echo "r" > reports/tour-1/REPORT.md
expect b "AGENTS.md + untracked reports/tour-1/ output (Goods)" 0
mk c; echo "spec b" > docs/specs/a.md
expect c "docs/specs/a.md edited (GeelyEx2: specs/ is not a test dir for a document)" 0
mk d; echo "snap 2" > app/src/test/snapshots/README.md
expect d "app/src/test/snapshots/README.md edited (OfficeReader)" 0
mk e; echo "fixture b" > app/src/androidTest/assets/test_files/s.md
expect e "a Markdown FIXTURE under androidTest/assets is still an edited test" 2
mk f; echo "name: ci2" > .github/workflows/ci.yml
expect f "a CI workflow change is not exempt (--allow-no-tests is the way out)" 2
mk g; echo "fun lib() = 2" > lib/X.kt
expect g "code no rule covers still stops" 2
mk h; echo "fun ok() = 2" > src/Core.kt
expect h "watched code with a passing suite passes" 0
# found by the clean-context review (2026-10-04): the first version switched the oracle guard off for these
mk i; echo "golden b" > app/src/test/snapshots/expected.md
expect i "a golden .md beside the snapshot README is still an edited test" 2
mk j; printf 'def test_v():\n    assert v() == 2\n' > reports/tests/test_views.py
expect j "a test inside a Django-style reports/ app is still an edited test" 2
mk k; echo "crash b" > src/test/logs/crash_sample.log
expect k "a .log fixture under a test dir is still an edited test" 2
mk m; echo "readme parser b" > tests/readme_parser_test.md
expect m "tests/readme_parser_test.md is a test, not a README (Antigravity audit)" 2
mk n; echo "doc test b" > tests/docs/test_parser.md
expect n "tests/docs/test_parser.md is a test: only the TOP-LEVEL docs/ is documentation (Antigravity audit r2)" 2
mk l; echo "# b" > AGENTS.md; echo "def v(): return 2" > reports/views.py
expect l "code under reports/ next to a doc edit is not docs-only" 2

[ "$FAILS" -eq 0 ] && echo "gate non-test changes: all checks passed" || { echo "gate non-test changes: $FAILS FAILED"; exit 1; }
