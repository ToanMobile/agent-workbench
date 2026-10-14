#!/usr/bin/env bash
# issues-bugs.md A.4 (14/10) / W1 v6 item 2: after EnterWorktree, CLAUDE_PROJECT_DIR still names the main checkout (code.claude.com docs),
# so regression_gate, proof_gate, test_evidence_gate, precode_gate and read_ledger judged a clean main and let the session's work in its
# worktree through. They now ask hooks/session_worktree.py: the worktree the session entered (its PostToolUse record), or the one the
# harness started a subagent in (its meta worktreePath). Shown on the two that are observable without a whole session:
#   - regression_gate's probe reads the matrix of the tree it would gate: main has none, the worktree has one;
#   - read_ledger writes its ledger in the tree it judges.
# A session without a record, and a forged record (another repo), keep the old answer: main.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"; O="$TMP/other"
for r in "$M" "$O"; do
  mkdir -p "$r/src" && git -C "$r" init -q -b main && git -C "$r" config user.email t@t && git -C "$r" config user.name t \
    && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$r/.gitignore" && echo 'x = 1' > "$r/src/a.py" && git -C "$r" add -A && git -C "$r" commit -qm i
done
git -C "$M" worktree add -q --detach "$W" HEAD && git -C "$O" worktree add -q --detach "$TMP/other-wt" HEAD
mkdir -p "$W/.agents" && printf '{"project":"t","rules":[{"component":"App","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-T-01","name":"t","command":"true"}]}]}\n' \
  > "$W/.agents/regression_matrix.active.json" && git -C "$W" add -A && git -C "$W" commit -qm "matrix in the worktree only"
mkdir -p "$M/.claude/audit-gate/session_worktree" && printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s1"
TP="$TMP/proj/s1.jsonl"; mkdir -p "$TMP/proj/s1/subagents" && : > "$TP"
printf '{"worktreePath": "%s"}\n' "$W" > "$TMP/proj/s1/subagents/agent-a1.meta.json"

probe() {   # probe <session> <cwd>: regression_gate's state for a Stop of that session
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$1" "$2" "$TP" \
    | CLAUDE_PROJECT_DIR="$M" REGRESSION_GATE_PROBE=1 bash "$DEVKIT_DIR/hooks/regression_gate.sh" 2>/dev/null | tail -1
}
state() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("state"))' "$1" 2>/dev/null; }
s1="$(state "$(probe s1 "$W")")"; s2="$(state "$(probe s2 "$M")")"
[ "$s1" != none ] && [ -n "$s1" ] && [ "$s2" = none ] && ok "regression_gate: the session in its worktree is gated there (matrix: $s1); a session in main: main (none)" \
  || fail "regression_gate probe: entered=$s1 other=$s2"

ledger_read() {   # ledger_read <session> <cwd> <file> [agent_id]: read_ledger for one Read
  python3 -c 'import json,sys; s,cwd,f,a,tp=sys.argv[1:6]; d={"hook_event_name":"PostToolUse","session_id":s,"cwd":cwd,"transcript_path":tp,"tool_name":"Read","tool_input":{"file_path":f}}; a and d.update(agent_id=a); print(json.dumps(d))' "$1" "$2" "$3" "${4:-}" "$TP" \
    | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/read_ledger.sh" >/dev/null 2>&1
}
ledger_read s1 "$W" "$W/src/a.py"
grep -q "$W/src/a.py" "$W/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && ! grep -q "$W/src/a.py" "$M/.claude/audit-gate/read_ledger.tsv" 2>/dev/null \
  && ok "read_ledger: the entered session's read lands in its worktree's ledger (precode_gate reads the same one)" || fail "read_ledger with a record: not in the worktree's ledger"
ledger_read s2 "$M" "$M/src/a.py"
grep -q "$M/src/a.py" "$M/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && ok "  … a session without a record: main's ledger, as before" || fail "read_ledger without a record"
ledger_read s9 "$W" "$W/src/a.py" a1   # a harness subagent runs in its worktree: its hook cwd is that worktree
[ "$(grep -c "s9" "$W/.claude/audit-gate/read_ledger.tsv" 2>/dev/null)" -ge 1 ] && ok "  … a harness subagent in the worktree: the worktree's ledger" || fail "subagent meta not followed"
s4="$(state "$(probe s1 "$M")")"
[ "$s4" = none ] && ok "trunk mode off, the session in main: its record does not move the gates (main)" || fail "record followed from main without trunk mode: $s4"
git -C "$M" config devkit.trunkMode true; s5="$(state "$(probe s1 "$M")")"; git -C "$M" config devkit.trunkMode false
[ "$s5" != none ] && [ -n "$s5" ] && ok "  … trunk mode on: the record alone (cwd main, no worktree in the payload) moves the gates ($s5)" || fail "record-only trigger: $s5"
mkdir -p "$TMP/lone" && cp "$DEVKIT_DIR/hooks/regression_gate.sh" "$TMP/lone/"   # a gate with no session_worktree.py beside it
lone="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","cwd":sys.argv[1],"transcript_path":sys.argv[2]}))' "$W" "$TP" \
  | CLAUDE_PROJECT_DIR="$M" REGRESSION_GATE_PROBE=1 bash "$TMP/lone/regression_gate.sh" 2>"$TMP/lone.err" | tail -1)"
grep -q "could not be resolved" "$TMP/lone.err" && ok "a gate whose session_worktree.py is missing says so on stderr (never silent)" || fail "missing module was silent: $(head -c 200 "$TMP/lone.err")"
printf '%s\n' "$TMP/other-wt" > "$M/.claude/audit-gate/session_worktree/s3"; s3="$(state "$(probe s3 "$TMP/other-wt")")"
[ "$s3" = none ] && ok "a forged record naming another repo's worktree: main, as before" || fail "forged record followed: $s3"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gates_follow_session_worktree: PASS"; exit 0; } || { echo "test_gates_follow_session_worktree: FAIL ($FAILS)"; exit 1; }
