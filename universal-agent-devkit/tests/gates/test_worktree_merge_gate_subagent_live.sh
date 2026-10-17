#!/usr/bin/env bash
# Hồi quy K10 (17/10, đo thật: commit a07752b, 8c5a407): hook Stop của phiên CHA tự gộp worktree của agent CON khi con còn sống và
# đang chờ việc nền (gate). Thông báo "is waiting on its own background work" của harness cũng có <status>completed</status> và
# <worktreePath>, nên hooks/worktree_merge_gate.sh tính con là đã xong: nó commit việc dở thành `wip(agent-…)`, fast-forward main
# và gỡ worktree dưới chân con. Con được SendMessage gọi dậy lại sau thông báo xong cũng bị tính là xong.
# Còn thông báo XONG thật của harness đến dưới dạng attachment queued_command (không phải tin nhắn user), hook chưa từng đọc.
#   1 chỉ có thông báo tạm (con chờ việc nền): Stop qua (rc 0), không gộp, không giữ phiên, worktree còn, main chưa có file
#   2 sau đó thông báo XONG thật (attachment queued_command): Stop gộp và gỡ như cũ
#   3 thông báo xong dạng cũ (tin nhắn user): vẫn gộp như cũ
#   4 thông báo xong rồi SendMessage gọi con dậy: không gộp; thông báo xong lần sau: gộp
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # như test_worktree_merge_gate_owner.sh: chế độ một checkout một phiên
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && echo a > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
TR="$TMP/tr.jsonl"; SUB="$TMP/tr/subagents"; mkdir -p "$SUB"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR"
sleep 1.2
stop() { printf '{"session_id":"p1","hook_event_name":"Stop","transcript_path":"%s"}' "$TR" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
# subagent <id>: worktree $TMP/wt-<id> with one commit main lacks, and the harness meta naming it (spawnedWithWorktree, background)
subagent() {
  G "$P" worktree add -q --detach "$TMP/wt-$1" && echo "$1" > "$TMP/wt-$1/$1.txt" && G "$TMP/wt-$1" add "$1.txt" && G "$TMP/wt-$1" commit -qm "$1"
  printf '{"agentType":"general-purpose","worktreePath":"%s","spawnedWithWorktree":true,"requestShape":"background"}' "$TMP/wt-$1" > "$SUB/agent-$1.meta.json"
}
# note <interim|final> <user|attachment> <id>: a task-notification as the harness writes it (wording of 17/10)
note() {
  python3 - "$TR" "$1" "$2" "$3" "$TMP/wt-$3" <<'PY'
import json, sys
tr, kind, how, aid, wt = sys.argv[1:6]
if kind == "interim":
    body = (f'<status>completed</status>\n<summary>Agent "{aid}" is waiting on its own background work</summary>\n'
            "<note>This agent stopped with background work of its own still running. It may resume on its own when that work completes or "
            "reports, and the same task-id notifies again if it does; the result below may be interim.</note>\n"
            "<result>This agent has not reported yet: it is waiting on its own background work and will deliver its report through "
            "SubagentHandback when that finishes.\n</result>\n")
else:
    body = (f'<status>completed</status>\n<summary>Agent "{aid}" finished</summary>\n'
            "<note>A task-notification fires each time this agent stops with no live background children of its own. The user can send it "
            "another message and resume it, so the same task-id may notify more than once.</note>\n<result>done\n</result>\n")
text = (f"<task-notification>\n<task-id>{aid}</task-id>\n<output-file>/tmp/{aid}.output</output-file>\n{body}"
        f"<worktree><worktreePath>{wt}</worktreePath></worktree>\n</task-notification>")
e = ({"type": "user", "message": {"role": "user", "content": text}} if how == "user" else
     {"type": "attachment", "attachment": {"type": "queued_command", "prompt": text, "commandMode": "task-notification"}})
open(tr, "a").write(json.dumps(e) + "\n")
PY
}
# resume <id>: the leader wakes the subagent up with SendMessage (tool_use and the harness's tool result)
resume() {
  python3 -c 'import json,sys
print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"sm-"+sys.argv[1],"name":"SendMessage","input":{"to":sys.argv[1],"summary":"tiếp","message":"làm tiếp"}}]}}))
print(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"sm-"+sys.argv[1],"content":[{"type":"text","text":"{\"success\":true,\"message\":\"Resuming agent\",\"resumedAgentId\":\""+sys.argv[1]+"\"}"}]}]}}))' "$1" >> "$TR"
}
merged() { [ ! -d "$TMP/wt-$1" ] && [ -f "$P/$1.txt" ]; }
untouched() { [ -d "$TMP/wt-$1" ] && [ ! -f "$P/$1.txt" ] && [ -z "$(G "$TMP/wt-$1" status --porcelain)" ] && [ "$(G "$TMP/wt-$1" log -1 --format=%s)" = "$1" ]; }

# 1: con chờ việc nền (chỉ có thông báo tạm)
subagent a1; note interim user a1
stop; rc=$?
[ "$rc" = 0 ] && untouched a1 && ! grep -q "wt-a1" "$TMP/err" \
  && ok "1: a subagent waiting on its own background work: not merged, not held, its worktree and commit untouched" \
  || fail "1: (rc=$rc merged=$(merged a1 && echo yes || echo no) main=$(G "$P" log -1 --format=%s)): $(cat "$TMP/err") $(cat "$TMP/out")"
note interim attachment a1
stop; rc=$?
[ "$rc" = 0 ] && untouched a1 && ok "  … also when the interim notification comes as a queued_command attachment" || fail "  … attachment interim (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

# 2: thông báo XONG thật đến sau (attachment queued_command, dạng harness ghi 17/10): gộp như cũ
note final attachment a1
stop; rc=$?
[ "$rc" = 0 ] && merged a1 && grep -q "wt-a1" "$TMP/out" && ok "2: once its final notification arrives (queued_command attachment), the Stop merges and removes it" \
  || fail "2: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

# 3: dạng cũ: thông báo xong là tin nhắn user
subagent a2; note final user a2
stop; rc=$?
[ "$rc" = 0 ] && merged a2 && ok "3: a final notification as a user message (the old shape) is merged as before" || fail "3: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

# 4: xong, rồi SendMessage gọi dậy: lại đang chạy
subagent a3; note final user a3; resume a3
stop; rc=$?
[ "$rc" = 0 ] && untouched a3 && ! grep -q "wt-a3" "$TMP/err" && ok "4: a subagent woken up by SendMessage after it finished: not merged, not held" \
  || fail "4: (rc=$rc merged=$(merged a3 && echo yes || echo no)): $(cat "$TMP/err") $(cat "$TMP/out")"
note final attachment a3
stop; rc=$?
[ "$rc" = 0 ] && merged a3 && ok "  … its next final notification: merged" || fail "  … after the resume ended (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate_subagent_live: all passed" || { echo "❌ test_worktree_merge_gate_subagent_live: $FAILS failed"; exit 1; }
