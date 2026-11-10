#!/usr/bin/env bash
# Regression test (#836): bin/post-fix-gate.py --since <ref> (hook regression_gate) kept only the NEW name of a file renamed in
# <ref>..HEAD, so since_test_weakened found no such object at <ref> and returned False: `git mv tests/test_a.sh tests/test_z.sh`
# plus a removed assertion, committed in one commit, passed with exit 0. The old name at <ref> is now compared too.
# Controls: a pure rename (R100) and a rename + appended assertion are not edits.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0

mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  printf '#!/bin/sh\n[ 1 = 1 ] || exit 1\n[ 2 = 2 ] || exit 1\n[ 3 = 3 ] || exit 1\n[ 4 = 4 ] || exit 1\ntrue\n' > tests/test_a.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"for f in tests/test_*.sh; do sh \"$f\" || exit 1; done"}]}]}
JSON
  git add -A && git commit -qm init
}
run_gate() { CLAUDE_PROJECT_DIR="$PWD" python3 "$GATE" --matrix "$PWD/matrix.json" --lang en --run-tests --since "$1" 2>&1; }
expect() {  # expect <name> <flagged:yes|no> <want_rc> <base>
  local out rc hit=no
  out="$(run_gate "$4")"; rc=$?
  printf '%s' "$out" | grep -q "test_z.sh" && printf '%s' "$out" | grep -q "Existing test edited" && hit=yes
  if [ "$hit" = "$2" ] && [ "$rc" = "$3" ]; then echo "✔ $1 (flagged=$hit, exit $rc)"
  else echo "✖ $1: flagged=$hit want $2, exit $rc want $3"; printf '%s\n' "$out" | tail -15; FAILS=$((FAILS + 1)); fi
}

# R089: rename + one assertion dropped, one commit (the #836 scenario)
mk weaken; base="$(git rev-parse HEAD)"
git mv tests/test_a.sh tests/test_z.sh
sed -i.bak '/\[ 4 = 4 \]/d' tests/test_z.sh && rm -f tests/test_z.sh.bak
echo "fun ok() = 2" > src/Core.kt
git add -A && git commit -qm "rename test + drop assertion + fix"
expect "rename + removed assertion committed in the range is flagged, test named" yes 2 "$base"

# R100: pure rename
mk pure; base="$(git rev-parse HEAD)"
git mv tests/test_a.sh tests/test_z.sh
echo "fun ok() = 2" > src/Core.kt
git add -A && git commit -qm "rename test + fix"
expect "a pure rename (R100) in the range is not flagged" no 0 "$base"

# rename + append only
mk append; base="$(git rev-parse HEAD)"
git mv tests/test_a.sh tests/test_z.sh
printf '[ 5 = 5 ] || exit 1\n' >> tests/test_z.sh
echo "fun ok() = 2" > src/Core.kt
git add -A && git commit -qm "rename test + append + fix"
expect "rename + appended assertion in the range is not flagged" no 0 "$base"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_since_renamed_weakened: all passed" || { echo "❌ test_gate_since_renamed_weakened: $FAILS failed"; exit 1; }
