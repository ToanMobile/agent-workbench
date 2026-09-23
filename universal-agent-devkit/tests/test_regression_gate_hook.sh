#!/usr/bin/env bash
# Regression test: hooks/regression_gate.sh (Stop hook) blocks finishing while a
# related regression test fails or a changed source file has no test — only for a
# project that adopted its own matrix — and never traps the session.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
stop() { printf '{"session_id":"s-1","hook_event_name":"Stop"}' \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
echo 'exit 0' > result.sh
git add -A && git commit -qm init

stop; [ $? = 0 ] && ok "clean tree: allowed" || fail "clean tree blocked"

# A DevKit SAMPLE matrix is not an adopted one: never enforced (placeholder tests).
cp "$DEVKIT_DIR/templates/regression_matrix.json" templates/regression_matrix.json
git add -A && git commit -qm sample
echo "fun ok() = 2" > src/Core.kt
stop; [ $? = 0 ] && ok "sample matrix: not enforced" || fail "sample matrix enforced"

# The project's own committed matrix, with a failing related test => block.
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
echo 'exit 1' > result.sh
git add -A && git commit -qm "own matrix"
echo "fun ok() = 3" > src/Core.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-1" "$TMP/err" && ok "failing related test blocks the stop (reason names REG-1)" || fail "failing test not blocked (rc=$rc)"
grep -q '❌ FAIL | REG-1' .agents/regression_checklist.md && ok "checklist records the real FAIL" || fail "checklist not updated"

# Loop guard: same change blocks MAX_ATTEMPTS(2) times, then releases with a visible warning.
stop; rc2=$?
stop; rc3=$?
[ "$rc2" = 2 ] && [ "$rc3" = 0 ] && grep -q systemMessage "$TMP/out" && ok "loop guard releases after 2 blocks with a user-visible warning" \
  || fail "loop guard wrong (rc2=$rc2 rc3=$rc3)"

# Fixed => allowed, and the result is cached for the same diff (no re-run).
echo 'exit 0' > result.sh
git add result.sh && git commit -qm "fix test"
echo "fun ok() = 4" > src/Core.kt
stop; [ $? = 0 ] && ok "green related test: allowed" || fail "green test still blocked"
runs_before="$(grep -c ' pass ' .claude/audit-gate/regression_gate.log)"
stop
[ "$(grep -c ' pass ' .claude/audit-gate/regression_gate.log)" = "$runs_before" ] && ok "same diff not re-tested (cached)" || fail "cache not used"

# A changed source file no test watches => block with UNCOVERED.
echo "fun other() = 1" > src/Other.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "UNCOVERED:src/Other.kt" "$TMP/err" && ok "uncovered source file blocks the stop" || fail "uncovered not blocked (rc=$rc)"

# Escape hatch.
REGRESSION_GATE=0 bash -c "printf '{}' | CLAUDE_PROJECT_DIR='$REPO' bash '$HOOK'"; [ $? = 0 ] && ok "REGRESSION_GATE=0 skips" || fail "escape hatch ignored"

# The matrix `agent-kit profile` writes (.agents/regression_matrix.active.json) is found.
REPO="$TMP/repo2"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo 'exit 1' > result.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-A","name":"core","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-A" "$TMP/err" && ok ".agents/regression_matrix.active.json is enforced" || fail "active matrix ignored (rc=$rc)"

# A profile matrix marked enforce_as_is (web: auto-detects the project's runner) is
# enforced exactly as installed — here it fails because there is no package.json.
REPO="$TMP/repo3"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "export const a = 1" > src/app.ts
cp "$DEVKIT_DIR/profiles/web/regression_matrix.json" .agents/regression_matrix.active.json
git add -A && git commit -qm init
echo "export const a = 2" > src/app.ts
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-WEB-01" "$TMP/err" && ok "web profile matrix (enforce_as_is) is enforced as installed" || fail "web matrix not enforced (rc=$rc)"

# Gate missing (copy-mode hook, no DevKit reachable): allowed, but said once per session.
mkdir -p "$TMP/copyhooks" && cp "$HOOK" "$TMP/copyhooks/regression_gate.sh"
nostop() { printf '{"session_id":"s-copy","hook_event_name":"Stop"}' | HOME="$TMP/nohome" DEVKIT_ROOT= PATH="/usr/bin:/bin" \
  CLAUDE_PROJECT_DIR="$REPO" bash "$TMP/copyhooks/regression_gate.sh" 2>/dev/null; }
out1="$(nostop)"; rc1=$?; out2="$(nostop)"
[ "$rc1" = 0 ] && printf '%s' "$out1" | grep -q systemMessage && [ -z "$out2" ] \
  && ok "gate not found: visible warning once per session, never blocks" || fail "gate-not-found handling (rc=$rc1, out2='$out2')"

if [ "$FAILS" -ne 0 ]; then echo "regression gate hook: $FAILS FAILED"; exit 1; fi
echo "regression gate hook: all checks passed"
