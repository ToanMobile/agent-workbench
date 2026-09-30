#!/usr/bin/env bash
# test_multi_session_gate.sh — Verify multi-session optimization for --full:
# When multiple agent sessions are active, test execution only runs impacted tests
# for the current case. Only when checked and confirmed as the final/only active
# session does --full execute.
set -euo pipefail

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
SESSION_LOCK="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; exit 1; }

REPO="$TMP/repo"
mkdir -p "$REPO/.agents"
git -C "$REPO" init -q .
echo "VALUE = 1" > "$REPO/lib.py"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Tester"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "initial commit"

# Create a sample regression matrix with both full command and impacted command
cat << 'EOF' > "$REPO/.agents/regression_matrix.active.json"
{
  "version": "1.0.0",
  "project": "test-project",
  "rules": [
    {
      "component": "core",
      "watch_files": ["*.py"],
      "mandatory_regression_tests": [
        {
          "id": "REG-01",
          "name": "core tests",
          "command": "echo FULL_TEST_EXECUTED",
          "impacted_command": "echo IMPACTED_TEST_EXECUTED: {pytest_nodes}"
        }
      ]
    }
  ]
}
EOF
git -C "$REPO" add .agents/regression_matrix.active.json
git -C "$REPO" commit -qm "add matrix"

# Modify a watched file
echo "VALUE = 2" > "$REPO/lib.py"

# 1. Single session: is_last_active is TRUE
out=$(python3 "$SESSION_LOCK" --check-last-active --session S1 --json "$REPO")
echo "$out" | grep -q '"is_last_active": true' && ok "single session: is_last_active is true" || fail "expected is_last_active: true"

# 2. Register session S2 (simulating a sibling agent working in parallel)
python3 "$SESSION_LOCK" --register --session S2 "$REPO"
out=$(python3 "$SESSION_LOCK" --check-last-active --session S1 --json "$REPO" || true)
echo "$out" | grep -q '"is_last_active": false' && ok "with S2 active: S1 is NOT last active" || fail "expected is_last_active: false"
echo "$out" | grep -q '"other_sessions": \["S2"\]' && ok "  … S2 named in other_sessions" || fail "S2 missing from other_sessions"

# 3. Run gate with --full when S2 is active: should DEFER --full to impacted mode!
gate_out=$(CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --matrix "$REPO/.agents/regression_matrix.active.json" --run-tests --full --session S1 2>&1 || true)
echo "$gate_out" | grep -q "DevKit Optimization" && ok "multi-session active: --full deferred with optimization notice" || fail "optimization notice missing"
# A deferred (impacted) run is not acceptance evidence: it must never claim the full-gate verdict.
! echo "$gate_out" | grep -q "PASS — ĐỦ ĐIỀU KIỆN" && ok "  … impacted run does NOT print the acceptance verdict" || fail "impacted run printed the acceptance verdict"
echo "$gate_out" | grep -q "CHƯA ĐỦ ĐIỀU KIỆN NGHIỆM THU" && ok "  … impacted run says it is NOT acceptance-ready" || fail "impacted verdict missing"
echo "$gate_out" | grep -q -- "--force-full" && ok "  … downgrade notice names --force-full" || fail "--force-full not named"

# 4. S1 with --force-full: bypasses optimization even when S2 is active
force_out=$(CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --matrix "$REPO/.agents/regression_matrix.active.json" --run-tests --full --force-full --session S1 2>&1 || true)
echo "$force_out" | grep -q "FULL_TEST_EXECUTED" && ok "--force-full: forces full execution even with sibling session" || fail "expected full execution"

# 5. S2 completes / unregisters: now S1 is the final/only active session!
python3 "$SESSION_LOCK" --unregister --session S2 "$REPO"
out=$(python3 "$SESSION_LOCK" --check-last-active --session S1 --json "$REPO")
echo "$out" | grep -q '"is_last_active": true' && ok "after S2 unregisters: S1 is last active" || fail "expected is_last_active: true"

# 6. S1 runs --full: now that it's the last session, full execution proceeds!
final_out=$(CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --matrix "$REPO/.agents/regression_matrix.active.json" --run-tests --full --session S1 2>&1 || true)
echo "$final_out" | grep -q "FULL_TEST_EXECUTED" && ok "final session: --full executes in full" || fail "expected full execution for final session"
echo "$final_out" | grep -q "PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU" && ok "  … only a full run prints the acceptance verdict" || fail "final session missing the acceptance verdict"

# 6b. A session working in another linked worktree of the same repo is not a sibling of this checkout:
# its gate run, build dir and receipt are its own (it used to downgrade every other worktree's --full).
WT="$TMP/repo-wt"
git -C "$REPO" worktree add -q -b wt-branch "$WT" >/dev/null 2>&1 || fail "could not create a linked worktree"
python3 "$SESSION_LOCK" --register --session S3 "$WT"
out=$(python3 "$SESSION_LOCK" --check-last-active --session S1 --json "$REPO" || true)
echo "$out" | grep -q '"is_last_active": true' && ok "session in another worktree does not count as a sibling" || fail "worktree session counted as sibling: $out"
python3 "$SESSION_LOCK" --unregister --session S3 "$WT"
# …also when that worktree sits INSIDE the repo (the DevKit's own .sandboxes/<name>)
git -C "$REPO" worktree add -q -b nested-branch "$REPO/.sandboxes/nest" >/dev/null 2>&1 || fail "could not create a nested worktree"
python3 "$SESSION_LOCK" --register --session S4 "$REPO/.sandboxes/nest"
out=$(python3 "$SESSION_LOCK" --check-last-active --session S1 --json "$REPO" || true)
echo "$out" | grep -q '"is_last_active": true' && ok "session in a nested .sandboxes worktree does not count as a sibling" || fail "nested worktree session counted as sibling: $out"
python3 "$SESSION_LOCK" --unregister --session S4 "$REPO/.sandboxes/nest"
# a relative path given to --register is stored absolute
( cd "$REPO" && python3 "$SESSION_LOCK" --register --session S5 . )
stored=$(python3 -c 'import json,glob,sys; print(json.load(open(glob.glob(sys.argv[1]+"/.git/devkit-sessions/S5.json")[0]))["cwd"])' "$REPO")
[ "${stored#/}" != "$stored" ] && ok "--register stores an absolute cwd" || fail "--register stored a relative cwd: $stored"
python3 "$SESSION_LOCK" --unregister --session S5 "$REPO"

# 7. The agent's OWN session, identified only by Claude Code's env var, must not count as "other".
python3 "$SESSION_LOCK" --register --session OWN1 "$REPO"
env_out=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_CODE_SESSION_ID=OWN1 python3 "$GATE" --matrix "$REPO/.agents/regression_matrix.active.json" --run-tests --full 2>&1 || true)
! echo "$env_out" | grep -q "DevKit Optimization" && ok "CLAUDE_CODE_SESSION_ID: own session not counted as other" || fail "own session counted as other (env var ignored)"
echo "$env_out" | grep -q "FULL_TEST_EXECUTED" && ok "  … full test command ran" || fail "expected full execution for the only session"

echo "✅ test_multi_session_gate: all tests passed!"
