#!/usr/bin/env bash
# #1146 (agent-workbench): 03:05:22 +07 ngày 11/11 một worker board Grok (review #774, cwd = checkout chính) chạy
# `git fetch origin && git checkout --detach origin/issue-774-init-sync-superboard`, và checkout chính - đích deploy của .agents/devkit
# ở 5 repo app - đứng detached 30 giờ. Grok chạy hook của project (nó ánh xạ matcher `Bash` sang `run_terminal_command` của nó) và hook
# ĐÃ chạy: 8 hook pre_tool_use `success`. Nhưng bin/session_lock.py chỉ xét tool_name == "Bash"; payload Grok mang tool_name
# "run_terminal_command", nên luật trunk mode "main chỉ để gộp" chưa bao giờ nhìn lệnh (replay hook thật: Bash rc 2, run_terminal_command rc 0).
# Công cụ shell dưới mọi tên - tên Grok / Cursor, hoặc một tên chưa ai thấy mà mang chuỗi `command` - nay được xét theo luật trunk mode
# y như Bash. Nó KHÔNG bị áp khoá một-phiên-một-checkout (trước nay PreToolUse của shell Grok không qua luật khoá; áp vào sẽ đổi cách các
# lane Grok của board chạy), và công cụ MCP hay công cụ không có `command` thì không bị xét.
# Phong bì bên dưới là phong bì thật của Grok (camelCase + các bí danh snake nó gửi); test_hook_camelcase_payload.sh dùng toolName "Bash"
# trong đó, không phải điều Grok gửi - chỗ lệch đã để lọt lỗi này.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT SB_BOARD_WORKER
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

M="$TMP/main"; W="$M/.claude/worktrees/issue-774-review"; W2="$M/.claude/worktrees/lane-grok"; W3="$M/.claude/worktrees/lane-bash"
mkdir -p "$M" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '.agents/local/memory/\n.claude/audit-gate/\n/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/a.txt" && git -C "$M" add -A && git -C "$M" commit -qm i && git -C "$M" branch topic
git -C "$M" worktree add -q --detach "$W" HEAD
git -C "$M" worktree add -q --detach "$W2" HEAD
git -C "$M" worktree add -q --detach "$W3" HEAD
git -C "$M" config devkit.trunkMode true

# hook <tool_name> <cwd> <session> <command> -> mã thoát của hook. Phong bì Grok: khoá camelCase cộng bí danh snake.
hook() {   # tham số 5 (tuỳ chọn): tool_input dạng JSON thô thay cho {"command": <lệnh>}
  python3 -I -c '
import json, sys
tool, cwd, sid, cmd = sys.argv[1:5]
ti = json.loads(sys.argv[5]) if len(sys.argv) > 5 else {"command": cmd}
print(json.dumps({"hookEventName": "pre_tool_use", "hook_event_name": "PreToolUse", "sessionId": sid, "session_id": sid,
                  "cwd": cwd, "workspaceRoot": cwd, "toolName": tool, "tool_name": tool, "toolInput": ti, "tool_input": ti}))
' "$1" "$2" "$3" "$4" ${5:+"$5"} > "$TMP/in.json"
  ( cd "$2" && CLAUDE_PROJECT_DIR="$2" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
}
# want <rc> <tool> <cwd> <command> <label>
want() {
  local rc
  hook "$2" "$3" "g-$$" "$4"; rc=$?
  [ "$rc" = "$1" ] && ok "$5 [$2: rc $rc]" || fail "$5 [$2: rc $rc, want $1] $(head -c 140 "$TMP/err" | tr '\n' ' ')"
}

CHECKOUT='git fetch origin && git checkout --detach origin/topic && git rev-parse HEAD && git merge-base --is-ancestor origin/main HEAD; echo ANCESTOR:$?'
ADD='command -v agent-kit || true; python3 .agents/devkit/scripts/git/worktree.py add .claude/worktrees/issue-774-review --lane=review --base=origin/topic'

# 1. lệnh của sự cố và các cách khác một shell đổi hoặc ghi main: bị chặn dưới mọi tên công cụ shell
for T in Bash run_terminal_command run_terminal_cmd Shell exec_shell_tool; do
  want 2 "$T" "$M" "$CHECKOUT" "the 11/11 command in main (git checkout --detach origin/<branch>)"
  want 2 "$T" "$M" 'git checkout topic' "git checkout <branch> in main"
  want 2 "$T" "$M" 'git switch topic' "git switch <branch> in main"
  want 2 "$T" "$M" 'echo x > a.txt' "a redirect into main"
  want 2 "$T" "$M" 'git commit -qm x' "a commit in main"
  want 2 "$T" "$W" "echo evil > $M/a.txt" "from the worktree: a redirect into main by its literal path"
done

# 2. điều một lane board làm hợp lệ từ main (cwd = main, không có cd bền) vẫn được qua
for T in Bash run_terminal_command run_terminal_cmd Shell exec_shell_tool; do
  want 0 "$T" "$M" 'git fetch origin' "git fetch in main"
  want 0 "$T" "$M" 'git status --short && git rev-parse --abbrev-ref HEAD' "read-only git in main"
  want 0 "$T" "$M" "git -C $W checkout --detach topic" "git -C <worktree> checkout --detach"
  want 0 "$T" "$M" "cd $W && git checkout --detach topic" "cd <worktree> && git checkout --detach"
  want 0 "$T" "$M" "$ADD" "worktree.py add --lane=review from main"
  want 0 "$T" "$M" 'echo x > /tmp/pr1108.json' "a redirect outside main"
  want 0 "$T" "$W" 'git checkout --detach topic' "git checkout --detach inside the worktree"
done

# 3. công cụ không phải shell thì không bị xét: công cụ MCP (tên Claude mcp__… và tên Grok <server>__<tool>), công cụ không có command
want 0 mcp__x__run "$M" 'git checkout topic' "an MCP tool (Claude name) carrying a command key"
want 0 server__run "$M" 'git checkout topic' "an MCP tool (Grok name <server>__<tool>) carrying a command key"
hook read_file "$M" "g-$$" '' '{"target_file": "'"$M"'/a.txt"}'; rc=$?
[ "$rc" = 0 ] && ok "read_file: no command key, not judged" || fail "read_file rc $rc"
hook read_file "$M" "g-$$" '' '{"command": ["git", "checkout", "topic"]}'; rc=$?
[ "$rc" = 0 ] && ok "a tool whose command is not a string: not judged (Grok's schema makes it a string)" || fail "list command rc $rc"

# 4. một lệnh ghi của shell Grok trong worktree không phải ghi vào trunk: được qua (và theo thiết kế không lấy khoá một-phiên-một-checkout)
want 0 run_terminal_command "$W" 'echo y > f2.txt' "a Grok write inside the worktree"
# khoá một-phiên-một-checkout: shell Grok ghi trong worktree KHÔNG tạo file khoá; một phiên Bash ghi ở worktree khác thì có (đối chứng:
# tên file khoá và cơ chế tạo khoá đúng). Bỏ nhánh `shell_alias` sau khối trunk và nhánh `foreign` làm ca này ĐỎ.
LK=devkit-session.lock
want 0 run_terminal_command "$W2" 'echo y > g1.txt' "a Grok write inside a second worktree"
[ ! -e "$(git -C "$W2" rev-parse --absolute-git-dir)/$LK" ] && ok "a Grok shell write takes no one-session-per-checkout lock" || fail "a Grok shell write took the lock"
want 0 Bash "$W3" 'echo y > b1.txt' "a Bash write inside a third worktree"
[ -e "$(git -C "$W3" rev-parse --absolute-git-dir)/$LK" ] && ok "control: the same write under the name Bash takes the lock" || fail "control: no lock file after a Bash write ($LK): the case above proves nothing"

# 5. trunk mode tắt: shell Grok cũng không bị xét gì
git -C "$M" config devkit.trunkMode false
want 0 run_terminal_command "$M" 'git checkout topic' "trunk mode off: a Grok checkout in main passes"
git -C "$M" config devkit.trunkMode true

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_grok_shell: all passed" || { echo "❌ test_session_lock_grok_shell: $FAILS failed"; exit 1; }
