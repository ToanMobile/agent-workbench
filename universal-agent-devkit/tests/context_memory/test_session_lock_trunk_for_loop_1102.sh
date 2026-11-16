#!/usr/bin/env bash
# #1102 (#1099, #1151; orchestrator decision 14/11: no static for-loop expansion in the hook, INSTINCT-104): (a) a redirect whose target holds a variable
# the line does not assign stays refused, for-loop shapes included (the QA worker writes to literal paths instead: test_qa_detached_worktree.sh);
# (b) the Grok edit tools (search_replace, hashline_edit) writing into main are refused like Edit, into a worktree they pass. Replays the real session_lock.sh hook.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT SB_BOARD_WORKER
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

M="$TMP/main"; W2="$M/.claude/worktrees/lane-grok"
mkdir -p "$M" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '.agents/local/memory/\n.claude/audit-gate/\n/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/a.txt" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W2" HEAD
git -C "$M" config devkit.trunkMode true
OUT="$TMP/out"; mkdir -p "$OUT/sub"; ln -s "$M" "$TMP/lnk"

# hook <tool_name> <cwd> <session> <command> [tool_input JSON] -> mã thoát của hook
hook() {
  python3 -I -c '
import json, sys
tool, cwd, sid, cmd = sys.argv[1:5]
ti = json.loads(sys.argv[5]) if len(sys.argv) > 5 else {"command": cmd}
print(json.dumps({"hookEventName": "pre_tool_use", "hook_event_name": "PreToolUse", "sessionId": sid, "session_id": sid,
                  "cwd": cwd, "workspaceRoot": cwd, "toolName": tool, "tool_name": tool, "toolInput": ti, "tool_input": ti}))
' "$1" "$2" "$3" "$4" ${5:+"$5"} > "$TMP/in.json"
  ( cd "$2" && CLAUDE_PROJECT_DIR="$2" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
}
# want <rc> <tool> <cwd> <command> <label> [tool_input JSON]
want() {
  local rc
  hook "$2" "$3" "g-$$" "$4" ${6:+"$6"}; rc=$?
  [ "$rc" = "$1" ] && ok "$5 [$2: rc $rc]" || fail "$5 [$2: rc $rc, want $1] $(head -c 140 "$TMP/err" | tr '\n' ' ')"
}

# (a) variable redirect targets stay refused (same as before #1102)
want 2 Bash "$M" 'for t in a b; do bash x.sh >/tmp/q-$t.log; done' "variable redirect in a for-loop: refused"
want 2 Bash "$W2" 'for t in a b; do bash x.sh >/tmp/q-$t.log; done' "variable redirect in a for-loop from a worktree: refused"
want 2 Bash "$M" 'echo x >/tmp/q-$u.log' "unknown variable in a redirect: refused"
want 2 Bash "$M" 'for a in c; do for b in d; do for t in a.txt; do $a$b /m; echo x > $t; done; done; done' "nested loop R12: refused"
want 0 Bash "$M" 'bash x.sh >/tmp/q-a.log' "literal redirect outside main: allowed"
want 0 Bash "$W2" 'bash x.sh >/tmp/q-a.log 2>&1' "literal redirect from a worktree: allowed"
want 2 Bash "$M" "echo x > $M/a.txt" "literal redirect into main: refused"

# (b) công cụ sửa file của Grok
for T in search_replace hashline_edit; do
  want 2 "$T" "$M" "" "$T vào a.txt của checkout chính (file_path)" '{"file_path":"'"$M"'/a.txt","old_string":"a","new_string":"b"}'
  want 2 "$T" "$M" "" "$T vào checkout chính (khoá path)" '{"path":"'"$M"'/a.txt"}'
  want 0 "$T" "$W2" "" "$T vào worktree" '{"file_path":"'"$W2"'/a.txt","old_string":"a","new_string":"b"}'
done

[ "$FAILS" = 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS fail"; exit 1; }
