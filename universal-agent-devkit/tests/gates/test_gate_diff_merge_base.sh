#!/usr/bin/env bash
# Regression test (#300, 23/10): `--diff origin/main` compared the working tree with the TIP of main. Commits that landed on main
# after the branch was built (another PR's test edit, a matrix change) looked like the branch's own edits: exit 2 on a clean branch.
# A plain ref is now resolved to merge-base(ref, HEAD), so only the branch's own change is audited. The two blocking directions stay.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# main@v1, then branch `feat` cut from it; the caller advances main afterwards.
make_repo() {
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src" "$TMP/repo/tests"
  cd "$TMP/repo" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
  printf 'import sys\nsys.path.insert(0, "src")\nfrom calc import sub\nassert sub(3, 1) == 2, "sub"\nassert sub(1, 1) == 0, "zero"\n' > tests/test_calc.py
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Calc","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"calc","command":"for f in tests/test_*.py; do python3 \"$f\" || exit 1; done"}]}]}
JSON
  git add -A && git commit -qm init
  git checkout -q -b feat
}
advance_main() {   # another PR lands on main: a test is edited and the matrix is rewritten
  git checkout -q main
  sed -i.bak '/"zero"/d' tests/test_calc.py && rm -f tests/test_calc.py.bak
  sed -i.bak 's/"name":"calc"/"name":"calc2"/' matrix.json && rm -f matrix.json.bak
  git commit -qam "other PR: test + matrix"
  git checkout -q feat
}
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --lang en "$@" > "$TMP/out" 2>&1; }

# 1. The branch edits only src; main moved on (test + matrix edited by someone else): not the branch's edit
make_repo
printf 'def sub(a, b):\n    return a - b  # touched\n' > src/calc.py
git commit -qam "src edit"
advance_main
run_gate --diff main; rc=$?
[ "$rc" = 0 ] && ok "main moved on with a test + matrix edit: the branch is still PASS (exit 0)" \
  || fail "main's own commits counted as the branch's edit: exit $rc (want 0): $(tail -6 "$TMP/out")"

# 2. The branch weakens an existing test itself: still UNVERIFIED
make_repo
sed -i.bak '/"zero"/d' tests/test_calc.py && rm -f tests/test_calc.py.bak
git commit -qam "weaken"
advance_main
run_gate --diff main; rc=$?
[ "$rc" = 2 ] && ok "the branch's own weakened test is still UNVERIFIED (exit 2)" || fail "own test edit: exit $rc (want 2)"

# 3. The branch rewrites an existing matrix rule itself: still UNVERIFIED
make_repo
sed -i.bak 's/"name":"calc"/"name":"calc3"/' matrix.json && rm -f matrix.json.bak
git commit -qam "matrix"
advance_main
run_gate --diff main; rc=$?
[ "$rc" = 2 ] && ok "the branch's own matrix edit is still not trusted (exit 2)" || fail "own matrix edit: exit $rc (want 2)"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_diff_merge_base: all passed" || { echo "❌ test_gate_diff_merge_base: $FAILS failed"; exit 1; }
