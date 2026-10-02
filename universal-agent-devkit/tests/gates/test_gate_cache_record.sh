#!/usr/bin/env bash
# Regression test: a full PASS that bin/post-fix-gate.py reuses (same content, cached_full_pass)
# is recorded by bin/regression_checklist.py as that earlier run, not as a fresh one.
# 2026-09-28: every reused row read "exit None" with the reuse's own time, so the checklist
# showed a run that never happened and no exit code for it.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

mkdir -p "$TMP/repo/src" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo run >> runs.txt"}]}]}
JSON
printf 'runs.txt\n' > .gitignore
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt

run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full "$@" 2>&1; }
last() { python3 -c 'import json,sys; print(json.load(open(".agents/regression_status.json"))["items"]["REG-1"]["last"].get(sys.argv[1]))' "$1" 2>/dev/null; }

run_gate >/dev/null; first_ts="$(last ts)"; first_at="$(last at)"
sleep 1.1
out="$(run_gate)"; rc=$?
runs="$(wc -l < runs.txt | tr -d ' ')"
if [ "$rc" != 0 ] || [ "$runs" != 1 ]; then
  echo "✖ setup: the second run must reuse the first PASS (exit $rc, runs $runs)"; printf '%s\n' "$out" | tail -15; exit 1
fi
echo "✔ setup: the second full run reused the first PASS"

[ "$(last exit_code)" = 0 ] && echo "✔ a reused PASS records exit 0" \
  || { echo "✖ a reused PASS records exit '$(last exit_code)'"; FAILS=$((FAILS + 1)); }
[ "$(last ts)" = "$first_ts" ] && [ "$(last at)" = "$first_at" ] && echo "✔ a reused PASS keeps the time of the run that backs it" \
  || { echo "✖ reused PASS time: $(last at) ($(last ts)), the run was at $first_at ($first_ts)"; FAILS=$((FAILS + 1)); }
[ -n "$(last reused_at | grep -v None)" ] && echo "✔ the row says it is a reuse" \
  || { echo "✖ the row does not say it is a reuse (reused_at=$(last reused_at))"; FAILS=$((FAILS + 1)); }
if grep -q "exit None" .agents/CHECKLIST.md 2>/dev/null; then
  echo "✖ CHECKLIST.md shows 'exit None'"; FAILS=$((FAILS + 1))
else
  echo "✔ CHECKLIST.md shows no 'exit None'"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "gate cache record: $FAILS FAILED"; exit 1
fi
echo "gate cache record: all checks passed"
