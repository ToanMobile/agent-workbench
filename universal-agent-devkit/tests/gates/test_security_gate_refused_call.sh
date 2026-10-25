#!/usr/bin/env bash
# K3 (18/10, OfficeReader): hooks/security_gate.sh tính cả lệnh đã BỊ CHẶN (hook PreToolUse từ chối, người dùng / quyền từ chối: lệnh
# không hề chạy) là "diff chạm attack surface" và đòi /scan. Luật: chỉ lần gọi đã chạy mới tính.
#   1 Bash ghi vào AndroidManifest.xml mà tool_result là lỗi "PreToolUse:Bash hook error … BLOCKED": không chặn Stop
#   2 Edit vào AndroidManifest.xml bị quyền từ chối ("Permission to use Edit … has been denied"): không chặn
#   3 đối chứng: cùng lệnh Bash đã chạy (kết quả thường): chặn
#   4 lệnh đã chạy nhưng exit khác 0 ("Exit code 1"): vẫn tính (có thể đã ghi một phần), chặn
#   5 một lần chặn của lệnh KHÁC không xoá được lần ghi đã chạy: chặn
#   17-18 lời từ chối cách ly worktree của SUBAGENT ("This agent is isolated …", 25/10): lệnh không chạy, không chặn
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/security_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
SB="$TMP/sb"; mkdir -p "$SB/app/src/main" && cd "$SB" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo '<manifest/>' > app/src/main/AndroidManifest.xml && git add -A && git commit -qm init

python3 - "$SB" <<'PY'
import json, os, sys
sb = sys.argv[1]
man = os.path.join(sb, "app/src/main/AndroidManifest.xml")
sed = lambda i: {"type": "tool_use", "id": i, "name": "Bash", "input": {"command": "sed -i '' 's/a/b/' app/src/main/AndroidManifest.xml"}}
edit = lambda i: {"type": "tool_use", "id": i, "name": "Edit", "input": {"file_path": man, "new_string": "<uses-permission android:name=\"x\"/>"}}
res = lambda i, text, err: {"type": "tool_result", "tool_use_id": i, "is_error": err, "content": text}
def w(name, msgs):
    with open(os.path.join(sb, name), "w") as fh:
        fh.write(json.dumps({"type": "user", "timestamp": "2026-10-18T00:00:00Z", "message": {"role": "user", "content": "go"}}) + "\n")
        for role, b in msgs:
            fh.write(json.dumps({"type": role, "message": {"role": role, "content": [b]}}) + "\n")
hook_block = "PreToolUse:Bash hook error: [bash .claude/hooks/block-dangerous-git.sh]: BLOCKED: 'sed' — user đã chặn"
w("t1.jsonl", [("assistant", sed("a1")), ("user", res("a1", hook_block, True))])
w("t2.jsonl", [("assistant", edit("a2")), ("user", res("a2", [{"type": "text", "text": "Permission to use Edit has been denied."}], True))])
w("t3.jsonl", [("assistant", sed("a3")), ("user", res("a3", "", False))])
w("t4.jsonl", [("assistant", sed("a4")), ("user", res("a4", "Exit code 1\nsed: no input", True))])
w("t5.jsonl", [("assistant", sed("a5")), ("user", res("a5", "", False)), ("assistant", sed("a6")), ("user", res("a6", hook_block, True))])
w("t6.jsonl", [("assistant", edit("a7")), ("user", res("a7", "The file has been updated successfully.", False))])   # đối chứng của ca 2
w("t7.jsonl", [("assistant", sed("a8")), ("user", res("a8", "The user doesn't want to proceed with this tool use. The tool use was rejected", True))])
w("t8.jsonl", [("assistant", sed("a9")), ("user", res("a9", "This session is isolated in the worktree /x, but this command is too complex to verify that it stays "
                                                         "inside the worktree. Refusing to run it — a worktree-isolated session's git operations must target its own worktree.", True))])
w("t9.jsonl", [("assistant", sed("b1")), ("user", res("b1", hook_block, True)), ("assistant", sed("b2")), ("user", res("b2", "", False))])
scan = lambda i: {"type": "tool_use", "id": i, "name": "Skill", "input": {"skill": "security-checklist"}}
w("t10.jsonl", [("assistant", sed("c1")), ("user", res("c1", "", False)), ("assistant", scan("c2")), ("user", res("c2", hook_block.replace("Bash", "Skill"), True))])
w("t11.jsonl", [("assistant", sed("c3")), ("user", res("c3", "", False)), ("assistant", scan("c4")), ("user", res("c4", "Launching skill", False))])
w("t12.jsonl", [("assistant", sed("c5")), ("user", res("c5", hook_block, False))])   # chữ từ chối nhưng không is_error: đã chạy
w("t14.jsonl", [("assistant", sed("d1")), ("user", res("d1", "", False)), ("assistant", scan("d2")),
                ("user", res("d2", "<tool_use_error>Unknown skill: security-checklist</tool_use_error>", True))])
w("t15.jsonl", [("assistant", sed("d3")), ("user", res("d3", "Permission for this action was denied by the Claude Code auto mode classifier. Reason: x", True))])
w("t16.jsonl", [("assistant", sed("d4")), ("user", res("d4", "Permission to use Bash with command cat <<'EOF'\nline\nEOF\n has been denied.", True))])
# A SUBAGENT gets "This agent is isolated …" for the same refusal (25/10, agent-workbench audit D.7): not a run either.
w("t17.jsonl", [("assistant", sed("d5")), ("user", res("d5", "This agent is isolated in the worktree /x, but this command names git in a form too complex to verify that "
                                                         "it stays inside the worktree. Refusing to run it — a worktree-isolated agent's git operations must target its own worktree. "
                                                         "Split it into plain, separate commands and run them from /x.", True))])
w("t18.jsonl", [("assistant", sed("d6")), ("user", res("d6", "This agent is isolated in the worktree /x, but this command changes directory to a location computed at "
                                                         "runtime before running git. Refusing to run it — a worktree-isolated agent's git operations must target its own worktree.", True))])
w("t13.jsonl", [("assistant", sed("c6")), ("user", res("c6", "", False)), ("assistant", scan("c7")),
                ("user", res("c7", "The user doesn't want to proceed with this tool use. The tool use was rejected", True))])
PY
run() { printf '{"session_id":"%s","transcript_path":"%s","last_assistant_message":"xong"}' "$1" "$SB/$2" \
  | env -u SECURITY_GATE CLAUDE_PROJECT_DIR="$SB" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

run s1 t1.jsonl; rc=$?; [ "$rc" = 0 ] && ok "a Bash write a PreToolUse hook blocked (never ran): not an attack-surface edit" || fail "blocked Bash counted (rc $rc): $(head -c 200 "$TMP/err")"
run s2 t2.jsonl; rc=$?; [ "$rc" = 0 ] && ok "an Edit the permission system denied: not an edit" || fail "denied Edit counted (rc $rc): $(head -c 200 "$TMP/err")"
run s3 t3.jsonl; rc=$?; [ "$rc" = 2 ] && ok "control: the same Bash write that ran: blocked (rc 2)" || fail "executed Bash write not counted (rc $rc)"
run s4 t4.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a write that ran and exited 1: still counted (rc 2)" || fail "failed-but-ran write dropped (rc $rc)"
run s5 t5.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a later blocked call does not erase an earlier write that ran (rc 2)" || fail "earlier executed write erased (rc $rc)"
run s6 t6.jsonl; rc=$?; [ "$rc" = 2 ] && ok "control for 2: the same Edit that ran: blocked (rc 2)" || fail "executed Edit not counted (rc $rc)"
run s7 t7.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a write the user rejected / cut with Esc: still counted, it may have run in part (rc 2)" || fail "user-rejected write dropped (rc $rc)"
run s8 t8.jsonl; rc=$?; [ "$rc" = 0 ] && ok "a write the harness worktree isolation refused (Claude Code's own wording, 18/10): not an edit" || fail "isolation-refused write counted (rc $rc)"
run s9 t9.jsonl; rc=$?; [ "$rc" = 2 ] && ok "refused first, then the same write ran: blocked (rc 2)" || fail "write after a refusal dropped (rc $rc)"
run s10 t10.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a security review that was REFUSED does not cover the write that ran (rc 2)" || fail "refused review counted as a review (rc $rc)"
run s11 t11.jsonl; rc=$?; [ "$rc" = 0 ] && ok "control for 10: the review that ran covers it (rc 0)" || fail "review that ran not counted (rc $rc)"
run s13 t13.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a security review the user rejected / cut with Esc does not cover the write (rc 2)" || fail "user-rejected review counted as a review (rc $rc)"
run s14 t14.jsonl; rc=$?; [ "$rc" = 2 ] && ok "a review that errored (Unknown skill) covers nothing (rc 2)" || fail "errored review counted (rc $rc)"
run s15 t15.jsonl; rc=$?; [ "$rc" = 0 ] && ok "a write the auto-mode classifier denied: not an edit" || fail "classifier-denied write counted (rc $rc)"
run s16 t16.jsonl; rc=$?; [ "$rc" = 0 ] && ok "a multi-line (heredoc) Bash the permission system denied: not an edit" || fail "multi-line denied write counted (rc $rc)"
run s17 t17.jsonl; rc=$?; [ "$rc" = 0 ] && ok "a write a SUBAGENT's worktree isolation refused ('This agent is isolated …'): not an edit" || fail "subagent isolation-refused write counted (rc $rc)"
run s18 t18.jsonl; rc=$?; [ "$rc" = 0 ] && ok "  … also the 'changes directory … computed at runtime' refusal" || fail "subagent cd-refused write counted (rc $rc)"
run s12 t12.jsonl; rc=$?; [ "$rc" = 2 ] && ok "refusal wording in a result that is NOT an error: the write still counts (rc 2)" || fail "non-error refusal text dropped the write (rc $rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_security_gate_refused_call: PASS"; exit 0; } || { echo "test_security_gate_refused_call: FAIL ($FAILS)"; exit 1; }
