#!/usr/bin/env bash
# #528: SB_BOARD_WORKER=1 trên main thì sáu hook Stop trả 0 và ghi log SB_BOARD_WORKER.
# Cùng payload, không có cờ: regression_gate vẫn chạy suite (rc 2, ran.marker).
# Worker trong worktree liên kết vẫn chạy suite ở worktree đó.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
N=0
change() { N=$((N + 1)); echo "fun ok() = $N" > src/Core.kt; }

mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git config devkit.trunkMode false
echo "fun ok() = 0" > src/Core.kt
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
echo 'touch ran.marker; exit 1' > result.sh
printf 'ran.marker\n.claude/\n' > .gitignore
git add -A && git commit -qm init || exit 1
printf '%s\n' '{"type":"user","timestamp":"2026-10-18T00:00:00Z","message":{"role":"user","content":"go"}}' > "$TMP/t.jsonl"
PAYLOAD="{\"session_id\":\"s-1\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$TMP/t.jsonl\",\"last_assistant_message\":\"XONG\"}"

run_hook() {
  # $1 hook  $2 extra env name=value or empty
  local hook="$1" extra="${2:-}"
  if [ -n "$extra" ]; then
    printf '%s' "$PAYLOAD" | env -u WORKTREE_TRUNK_MODE REGRESSION_GATE_MAX_SESSION_BLOCKS=99 \
      CLAUDE_PROJECT_DIR="$REPO" "$extra" bash "$hook" >"$TMP/out" 2>"$TMP/err"
  else
    printf '%s' "$PAYLOAD" | env -u WORKTREE_TRUNK_MODE REGRESSION_GATE_MAX_SESSION_BLOCKS=99 \
      CLAUDE_PROJECT_DIR="$REPO" bash "$hook" >"$TMP/out" 2>"$TMP/err"
  fi
}

# Không có cờ worker: suite đỏ chặn Stop.
change; rm -f ran.marker
run_hook "$DEVKIT_DIR/hooks/regression_gate.sh"; rc=$?
[ "$rc" = 2 ] && [ -e ran.marker ] && ok "no worker flag: failing suite runs (rc 2)" \
  || fail "no worker flag: rc $rc (want 2), marker=$( [ -e ran.marker ] && echo yes || echo no); err=$(head -c 400 "$TMP/err")"

# Worker trên main: không chạy suite, log có SB_BOARD_WORKER.
change; rm -f ran.marker
rm -f .claude/audit-gate/regression_gate.log
run_hook "$DEVKIT_DIR/hooks/regression_gate.sh" SB_BOARD_WORKER=1; rc=$?
[ "$rc" = 0 ] && [ ! -e ran.marker ] && ok "worker on main: suite not started (rc 0)" \
  || fail "worker on main: rc $rc (want 0), marker=$( [ -e ran.marker ] && echo yes || echo no); err=$(head -c 400 "$TMP/err")"
grep -q "SB_BOARD_WORKER" .claude/audit-gate/regression_gate.log && ok "worker on main: log names SB_BOARD_WORKER" \
  || fail "worker on main: log missing SB_BOARD_WORKER"

# Worker trong worktree liên kết: suite vẫn chạy ở worktree.
git checkout -q -- src/Core.kt
git worktree add -q --detach "$REPO/.claude/worktrees/w5" HEAD || exit 1
mkdir -p .claude/audit-gate/session_worktree
printf '%s\n' "$REPO/.claude/worktrees/w5" > .claude/audit-gate/session_worktree/s-5
echo "fun ok() = 55" > "$REPO/.claude/worktrees/w5/src/Core.kt"
rm -f "$REPO/.claude/worktrees/w5/ran.marker"
WT_PAYLOAD="{\"session_id\":\"s-5\",\"hook_event_name\":\"Stop\",\"cwd\":\"$REPO/.claude/worktrees/w5\",\"transcript_path\":\"$TMP/t.jsonl\",\"last_assistant_message\":\"XONG\"}"
printf '%s' "$WT_PAYLOAD" | env -u WORKTREE_TRUNK_MODE SB_BOARD_WORKER=1 REGRESSION_GATE_MAX_SESSION_BLOCKS=99 \
  CLAUDE_PROJECT_DIR="$REPO" bash "$DEVKIT_DIR/hooks/regression_gate.sh" >"$TMP/out" 2>"$TMP/err"
rc=$?
[ "$rc" = 2 ] && [ -e "$REPO/.claude/worktrees/w5/ran.marker" ] \
  && ok "worker in linked worktree: suite still runs there (rc 2)" \
  || fail "worker in linked worktree: rc $rc, marker=$( [ -e "$REPO/.claude/worktrees/w5/ran.marker" ] && echo yes || echo no); err=$(head -c 400 "$TMP/err")"

# Năm hook còn lại, worker trên main: rc 0 và log có SB_BOARD_WORKER.
check_skip() {
  local name="$1" hook="$2" log="$3"
  rm -f "$log"
  run_hook "$hook" SB_BOARD_WORKER=1; rc=$?
  [ "$rc" = 0 ] && ok "$name worker on main: rc 0" || fail "$name worker on main: rc $rc (want 0); err=$(head -c 300 "$TMP/err")"
  grep -q "SB_BOARD_WORKER" "$log" && ok "$name worker on main: log names SB_BOARD_WORKER" \
    || fail "$name worker on main: log missing SB_BOARD_WORKER ($(head -c 200 "$log" 2>/dev/null))"
}
check_skip proof "$DEVKIT_DIR/hooks/proof_gate.sh" "$REPO/.claude/audit-gate/proof_gate.log"
check_skip test_evidence "$DEVKIT_DIR/hooks/test_evidence_gate.sh" "$REPO/.claude/audit-gate/test_evidence_gate.log"
check_skip review "$DEVKIT_DIR/hooks/review_gate.sh" "$REPO/.claude/audit-gate/review_gate.log"
check_skip testsourceset "$DEVKIT_DIR/hooks/testsourceset_gate.sh" "$REPO/.claude/audit-gate/testsourceset_gate.log"
check_skip security "$DEVKIT_DIR/hooks/security_gate.sh" "$REPO/.claude/audit-gate/security_gate.log"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_worker_main: PASS"; exit 0; }
echo "test_gate_worker_main: FAIL ($FAILS)"
exit 1
