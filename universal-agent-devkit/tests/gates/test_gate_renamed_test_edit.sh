#!/usr/bin/env bash
# Regression test (audit 2026-10-09): the edited-test rule of bin/post-fix-gate.py looked the test up at base:<new path>. A test
# moved with `git mv` and weakened in the same change had no such path, so it was never counted as an edited test: the gate
# passed it, while the same edit in place was UNVERIFIED (exit 2). A rename git records is now judged against its old path. The suite
# finds its tests by glob (as pytest tests/ does): a matrix that names the file would flag the rename on its own.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

make_repo() {
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src" "$TMP/repo/tests"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
  printf 'import sys\nsys.path.insert(0, "src")\nfrom calc import sub\nassert sub(3, 1) == 2, "sub"\nassert sub(1, 1) == 0, "zero"\n' > tests/test_calc.py
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Calc","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"calc","command":"for f in tests/test_*.py; do python3 \"$f\" || exit 1; done"}]}]}
JSON
  git add -A && git commit -qm init
  printf 'def sub(a, b):\n    return a - b  # touched\n' > src/calc.py
}
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --lang en "$@" > "$TMP/out" 2>&1; }

# Control: the same weakening in place -> UNVERIFIED (exit 2)
make_repo
sed -i.bak '/"zero"/d' tests/test_calc.py && rm -f tests/test_calc.py.bak
run_gate; rc=$?
[ "$rc" = 2 ] && ok "control: an assertion removed in place -> UNVERIFIED (exit 2)" || fail "control: in-place edit gave exit $rc"

# git mv + the same weakening -> still an edited test (exit 2)
make_repo
git mv tests/test_calc.py tests/test_calc_core.py
sed -i.bak '/"zero"/d' tests/test_calc_core.py && rm -f tests/test_calc_core.py.bak
run_gate; rc=$?
[ "$rc" = 2 ] && grep -q "test_calc_core.py" "$TMP/out" && ok "git mv + an assertion removed -> UNVERIFIED (exit 2), the test named" \
  || fail "git mv + weakened test: exit $rc (want 2) — the edit hid behind the rename: $(grep -iE 'verdict|PASS|UNVERIFIED' "$TMP/out" | head -2)"

# A pure move, and a move + an appended test, are not edits
make_repo
git mv tests/test_calc.py tests/test_calc_core.py
run_gate; rc=$?
[ "$rc" = 0 ] && ok "a pure git mv of a test is not an edit (exit 0)" || fail "pure rename: exit $rc (want 0): $(tail -3 "$TMP/out")"
make_repo
git mv tests/test_calc.py tests/test_calc_core.py
printf 'assert sub(5, 2) == 3, "five"\n' >> tests/test_calc_core.py
run_gate; rc=$?
[ "$rc" = 0 ] && ok "git mv + an appended assertion is not an edit (exit 0)" || fail "rename + append: exit $rc (want 0): $(tail -3 "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_renamed_test_edit: all passed" || { echo "❌ test_gate_renamed_test_edit: $FAILS failed"; exit 1; }
