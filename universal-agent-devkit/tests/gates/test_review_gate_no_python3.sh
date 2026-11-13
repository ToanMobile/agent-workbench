#!/usr/bin/env bash
# #754: review_gate.sh resolved the session worktree (python3, basename) before its `command -v python3` check, so a
# worktree session on a box without python3 got a "worktree could not be resolved" warning plus `basename: command not
# found` as its first stderr lines, and created .claude/audit-gate. Owner decision on #754: the gate stays fail-open
# (exit 0); the first stderr line names python3, no "command not found", nothing written.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# PATH without python3 or basename; mkdir is there so "nothing written" can fail on the old order.
BIN="$TMP/bin"; mkdir -p "$BIN"
for t in cat mkdir; do ln -s "$(command -v "$t")" "$BIN/$t"; done
P="$TMP/proj"; mkdir -p "$P"
printf '{"session_id":"np3","cwd":"%s/.claude/worktrees/x","last_assistant_message":"xong"}' "$P" \
  | env -i PATH="$BIN" HOME="$TMP" CLAUDE_PROJECT_DIR="$P" /bin/bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"
rc=$?
first="$(head -1 "$TMP/err")"
[ "$rc" = 0 ] && ok "fail-open exit 0" || fail "exit $rc (want 0)"
case "$first" in *"review_gate: python3"*) ok "first stderr line names python3" ;; *) fail "first stderr line: $first" ;; esac
grep -q "command not found" "$TMP/err" && fail "stderr has 'command not found': $(grep -m1 'command not found' "$TMP/err")" \
  || ok "no 'command not found'"
[ -e "$P/.claude/audit-gate" ] && fail "wrote $P/.claude/audit-gate" || ok "nothing written"

[ "$FAILS" = 0 ] && { echo "PASS test_review_gate_no_python3"; exit 0; }
echo "FAIL test_review_gate_no_python3 ($FAILS)"; exit 1
