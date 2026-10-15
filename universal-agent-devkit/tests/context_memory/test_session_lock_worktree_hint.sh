#!/usr/bin/env bash
# Regression test (user, 2026-10-12): a session blocked by another live session's checkout stopped and asked the user
# "unlock with ! agent-kit allow-shared, or let me create a worktree" — because rules/essentials.md said "no new worktree unless the
# user asks" and "exit 3 → ask for a worktree", and the lock messages said "ask the user". The user: handle it yourself, stop only
# when the work is done. The rule is now: a held checkout → the blocked agent makes its OWN detached worktree
# (`agent-kit worktree add`, pre-authorized), works and gates there, then `agent-kit worktree finish` merges it into the trunk and
# removes it. Checked here: every message a blocked session sees names that path and does not send the agent back to the user; the
# worktree command itself is not blocked for the second session while a git commit still is; the rules say the same.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export WORKTREE_TRUNK_MODE=0   # these cases test the one-checkout-one-session mode; trunk mode is the default since 2026-10-15 (tests/worktree_git/test_trunk_default.sh)
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
export DEVKIT_SCRATCH_CLEANUP=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
mkdir -p "$REPO/src" && git -C "$REPO" init -q . && echo x > "$REPO/src/A.kt"
git -C "$REPO" -c user.email=t@t -c user.name=t add -A >/dev/null && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init

# hook <session> <event> <tool> <cwd> [bash command]
hook() {
  python3 - "$@" <<'PY' > "$TMP/in.json"
import json, sys
sid, ev, tool, cwd = sys.argv[1:5]
d = {"session_id": sid, "hook_event_name": ev, "cwd": cwd}
if tool:
    d["tool_name"] = tool
    d["tool_input"] = {"command": sys.argv[5]} if tool == "Bash" else {"file_path": cwd + "/src/A.kt"}
print(json.dumps(d))
PY
  CLAUDE_PROJECT_DIR="$4" bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err"
}
# says_worktree <file>: names the worktree path as the agent's own, pre-approved move, and does not send it back to the user
says_worktree() { grep -q 'agent-kit worktree add' "$1" && grep -q 'duyệt sẵn' "$1" && ! grep -qi 'xin người dùng\|nhờ người dùng\|người dùng tạo' "$1"; }

hook A PreToolUse Edit "$REPO"; [ $? = 0 ] || fail "first session did not take the checkout: $(cat "$TMP/err")"

# 1. the block message of a second session's Edit (hook, stderr)
hook B PreToolUse Edit "$REPO"; rc=$?
[ "$rc" = 2 ] && says_worktree "$TMP/err" && ok "blocked Edit: the message tells the agent to make its own worktree (pre-approved), not to ask" \
  || fail "blocked Edit message (rc=$rc): $(cat "$TMP/err")"

# 2. a write-to-another-checkout Bash block (session B works in its own repo and reaches into the held checkout)
OTHER="$TMP/other"; mkdir -p "$OTHER" && git -C "$OTHER" init -q .
hook B PreToolUse Bash "$OTHER" "git -C $REPO commit -m x -- src/A.kt"; rc=$?
[ "$rc" = 2 ] && says_worktree "$TMP/err" && ok "blocked git commit in the held checkout: same instruction" \
  || fail "blocked git commit message (rc=$rc): $(cat "$TMP/err")"

# 3. session_lock.py --status (what an agent without hooks runs)
( cd "$REPO" && python3 "$DEVKIT_DIR/bin/session_lock.py" --status > "$TMP/status" 2>&1; echo $? > "$TMP/status.rc" )
[ "$(cat "$TMP/status.rc")" = 3 ] && says_worktree "$TMP/status" && ok "--status exits 3 and names the worktree path" \
  || fail "--status (rc=$(cat "$TMP/status.rc")): $(cat "$TMP/status")"

# 4. the worktree command is not itself blocked for the second session, the commit still is
hook B PreToolUse Bash "$REPO" "agent-kit worktree add ../repo-task"; rc=$?
[ "$rc" = 0 ] && ok "second session: agent-kit worktree add passes the lock" || fail "agent-kit worktree add blocked for the second session (rc=$rc): $(cat "$TMP/err")"
hook B PreToolUse Bash "$REPO" "git commit -m x -- src/A.kt"; rc=$?
[ "$rc" = 2 ] && ok "second session: git commit in the held checkout is still blocked" || fail "git commit passed (rc=$rc)"

# 4b. the raw `git worktree add` is still refused by the git guard (the project keeps one branch), and its message now points at the
#     pre-approved path instead of leaving the agent with "only when the user asks"
python3 -I -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"git worktree add ../x"},"cwd":sys.argv[1]}))' "$REPO" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$DEVKIT_DIR/hooks/block-dangerous-git.sh" > "$TMP/gout" 2> "$TMP/gerr"; rc=$?
[ "$rc" = 2 ] && grep -q 'agent-kit worktree add' "$TMP/gerr" && grep -q 'đã duyệt sẵn' "$TMP/gerr" \
  && ok "raw git worktree add: refused, and the message names agent-kit worktree add as the pre-approved path" \
  || fail "git guard message (rc=$rc): $(head -c 300 "$TMP/gerr")"

# 5. the written rules say the same
E="$DEVKIT_DIR/rules/essentials.md"
grep -q 'ask for a worktree' "$E" && fail "essentials.md still says: ask for a worktree" || ok "essentials.md no longer tells the agent to ask for a worktree"
grep -q 'agent-kit worktree add' "$E" && grep -q 'agent-kit worktree finish' "$E" && grep -qi 'pre-authorized' "$E" \
  && ok "essentials.md: the held-checkout worktree is pre-authorized (add, then finish)" || fail "essentials.md does not pre-authorize the worktree path"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
