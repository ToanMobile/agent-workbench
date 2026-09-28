#!/usr/bin/env bash
# Regression test: bin/push_gate.py lets a push through only when the last full PASS of
# bin/post-fix-gate.py (receipt head + dirty blobs) covers what the push sends. Audit 2026-09-28:
# nothing enforced "every push needs the latest gate at exit 0".
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
expect() { # name expected-exit
  local out rc; out="$(python3 "$PG" "$TMP/repo" 2>&1)"; rc=$?
  [ "$rc" = "$2" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $2 — $out"; FAILS=$((FAILS + 1)); }
}
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt; echo "a" > other.txt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1; }

echo "fun ok() = 2" > src/Core.kt
expect "no gate run yet: push blocked" 2
run_gate; expect "tested content, not committed yet: push of HEAD has nothing new" 0
git commit -qam "fix" ; expect "the tested content committed: push allowed" 0
echo "b" > other.txt; expect "another file dirty and not pushed: allowed (ponytail)" 0
echo "fun ok() = 3" > src/Core.kt; git commit -qm "after gate" -- src/Core.kt
expect "a change committed after the gate: push blocked" 2
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0004"
expect "Test-approved-by in the pushed commits: allowed" 0
git reset -q --hard HEAD~2; git checkout -q -- . 2>/dev/null
rm -f .agents/regression_matrix.active.json; git commit -qam "no matrix"
expect "a repo without a regression matrix is not checked" 0

[ "$FAILS" -eq 0 ] && echo "push gate: all checks passed" || { echo "push gate: $FAILS FAILED"; exit 1; }
