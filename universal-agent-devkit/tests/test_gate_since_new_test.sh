#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py --since <ref> (hooks/regression_gate.sh gates the commits
# after the last verified HEAD) must not call a test file ADDED in <ref>..HEAD an "existing test
# edited". 2026-09-28: three new test files, committed in the turn, blocked the Stop hook as
# edited tests — test_change_is_append_only read an empty diff against HEAD as an edit.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
mkdir -p "$TMP/repo/src" "$TMP/repo/tests" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf '#!/bin/sh\n[ 1 = 1 ]\n' > tests/test_old.sh
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh && sh tests/test_new.sh"}]}]}
JSON
printf '#!/bin/sh\ntrue\n' > tests/test_new.sh
git add -A && git commit -qm init && base="$(git rev-parse HEAD)"
printf '#!/bin/sh\n[ 2 = 2 ]\n' > tests/test_new.sh; git rm -q --cached tests/test_new.sh 2>/dev/null
git commit -qm "drop new" && base="$(git rev-parse HEAD)"
printf '#!/bin/sh\n[ 2 = 2 ]\n' > tests/test_new.sh; echo "fun ok() = 2" > src/Core.kt
git add -A && git commit -qm "new test + fix"
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --lang en "$@" 2>&1; }

out="$(run_gate --run-tests --since "$base")"; rc=$?
if printf '%s' "$out" | grep -q "Existing test edited"; then
  echo "✖ a test added in --since..HEAD is called an edited existing test (exit $rc)"; FAILS=$((FAILS + 1))
else
  echo "✔ a test added in --since..HEAD is not an edited existing test (exit $rc)"
fi
[ "$rc" = 0 ] && echo "✔ the --since run passes" || { echo "✖ the --since run: exit $rc"; FAILS=$((FAILS + 1)); }

printf '#!/bin/sh\ntrue\n' > tests/test_old.sh     # control: weakening an existing test still blocks
out="$(run_gate --run-tests --since "$base")"; rc=$?
printf '%s' "$out" | grep -q "Existing test edited" && [ "$rc" = 2 ] && echo "✔ an edited existing test still blocks (exit 2)" \
  || { echo "✖ an edited existing test no longer blocks (exit $rc)"; FAILS=$((FAILS + 1)); }

[ "$FAILS" -eq 0 ] && echo "gate --since new test: all checks passed" || { echo "gate --since new test: $FAILS FAILED"; exit 1; }
