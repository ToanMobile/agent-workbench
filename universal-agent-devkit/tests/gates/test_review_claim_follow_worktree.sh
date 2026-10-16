#!/usr/bin/env bash
# issue #2 (AC3): review_gate.sh and claim_check.sh judged CLAUDE_PROJECT_DIR (a clean main) after EnterWorktree, so the diff of the session's
# own worktree was never the one compared. They now ask hooks/session_worktree.py like regression_gate / proof_gate / precode_gate do.
# Observable: the log each gate writes lands in the worktree's .claude/audit-gate, not in main's; a session with no record stays on main.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"
mkdir -p "$M/src" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t \
  && git -C "$M" config devkit.trunkMode false && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$M/.gitignore" \
  && echo 'x = 1' > "$M/src/a.py" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD
mkdir -p "$M/.claude/audit-gate/session_worktree" && printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s1"
: > "$TMP/tr.jsonl"

for gate in review_gate claim_check; do
  for sid in s1 s2; do
    python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3],"last_assistant_message":"x"}))' \
      "$sid" "$W" "$TMP/tr.jsonl" | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/$gate.sh" >/dev/null 2>&1
    in_w=0; in_m=0
    [ -s "$W/.claude/audit-gate/$gate.log" ] && in_w=1
    [ -s "$M/.claude/audit-gate/$gate.log" ] && in_m=1
    if [ "$sid" = s1 ]; then
      [ "$in_w" = 1 ] && [ "$in_m" = 0 ] && ok "$gate: the session that entered a worktree is judged there (log in the worktree)" \
        || fail "$gate with a record: log in worktree=$in_w main=$in_m (want 1/0)"
    else
      [ "$in_m" = 1 ] && [ "$in_w" = 0 ] && ok "$gate: a session with no record keeps CLAUDE_PROJECT_DIR (main)" \
        || fail "$gate without a record: log in worktree=$in_w main=$in_m (want 0/1)"
    fi
    python3 -c 'import shutil, sys; [shutil.rmtree(d, ignore_errors=True) for d in sys.argv[1:]]' "$W/.claude/audit-gate" "$M/.claude/audit-gate/review_gate.log" 2>/dev/null
    rm -f "$M/.claude/audit-gate/$gate.log" "$M/.claude/audit-gate"/*.attempts 2>/dev/null
    mkdir -p "$M/.claude/audit-gate/session_worktree" && printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s1"
  done
done

if [ "$FAILS" -ne 0 ]; then echo "review/claim follow worktree: $FAILS FAILED"; exit 1; fi
echo "review/claim follow worktree: all checks passed"
