#!/usr/bin/env bash
# Test hồi quy Pha 1 (T0061, bước 3): hooks/proof_gate.sh nhận XONG bằng biên nhận task (lượt `post-fix-gate --run-tests`, không --full)
# chỉ trong đúng lượt, theo ba đường:
#   (a) worktree còn sống: task_pass.json của chính nó khớp dấu vân tay cây và có mục task_receipts/ cùng fp;
#   (b) worktree đã gỡ, lượt này `git push` nhánh PR: SHA nhánh đọc từ origin THẬT (git ls-remote, không phải refs/remotes/*) có mục
#       task_receipts/<commit_fingerprint(SHA)>.json của lượt này;
#   (c) trunk-finish: worktree gộp vào main rồi gỡ, main (trunk mode) đứng ở cây có biên nhận task của lượt này.
# Chặn: biên nhận của lượt trước, fp lệch (sửa sau lượt gate), refs/remotes sửa tay (origin không có SHA đó), lượt có push lên nhánh đích.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_GATE_MERGE_CHECK CI

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export PROOF_GATE_ALLOW_LOCAL_ORIGIN=1   # origin của fixture là đường dẫn cục bộ (merged_evidence dùng cùng công tắc)
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src .agents
  echo 'exit 0' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: XONG không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git -C "$REPO" remote set-head origin main >/dev/null 2>&1

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi giao"}}))' > "$TR"; sleep 1; }
tool_use() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % len(sys.argv[2]),"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))' "$1" "$2" >> "$TR"; }
wt_new() { WT="$TMP/wt-$1"; git -C "$REPO" worktree add -q --detach "$WT" origin/main || exit 1; }
wt_edit() { echo "def ok(): return $1" > "$WT/src/core.py"; tool_use Write "{\"file_path\": \"$WT/src/core.py\", \"content\": \"x\"}"; }
task_gate() { CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --run-tests --no-checklist >"$TMP/gate" 2>&1 \
  || fail "tiền đề: lượt task exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {   # stop DIR
  rm -f "$1/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-t","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã giao. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' ')"; }
plog() { cat "$1/.claude/audit-gate/proof_gate.log" 2>/dev/null; }

# A1. (a) worktree còn sống, sửa chưa commit, lượt task exit 0 trong lượt: XONG qua.
turn_start; wt_new a1; wt_edit 11; task_gate "$WT"; stop "$WT"; rc=$?
[ "$rc" = 0 ] && plog "$WT" | grep -q "task-receipt" && ok "A1 (a) biên nhận task của worktree trong lượt: XONG qua" || fail "A1 bị chặn ($(why $rc))"
# A2. sửa tiếp sau lượt gate: fp lệch, chặn.
wt_edit 12; stop "$WT"; rc=$?
blocked "$rc" && ok "A2 sửa sau lượt task (fp lệch): chặn" || fail "A2 fp lệch vẫn qua ($(why $rc))"
# A3. đưa cây về đúng nội dung đã gate nhưng ở lượt SAU: biên nhận task của lượt trước không được nhận.
wt_edit 11; sleep 3; turn_start; stop "$WT"; rc=$?   # sleep: lời nhắc mới lùi 2 s, phải sau lượt gate
blocked "$rc" && ok "A3 biên nhận task của lượt trước: chặn (không có earlier-turn cho biên nhận task)" || fail "A3 lượt trước vẫn qua ($(why $rc))"
# A4. mục task_receipts/ của cây bị bỏ (một FAIL ở worktree khác cùng cây): task_pass.json một mình không đủ.
task_gate "$WT"; STORE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/task_receipts"
rm -f "$STORE"/*.json; stop "$WT"; rc=$?
blocked "$rc" && ok "A4 task_pass.json còn mà mục store đã bị FAIL xoá: chặn" || fail "A4 thiếu mục store vẫn qua ($(why $rc))"
git -C "$REPO" worktree remove --force "$WT"

# B1. (b) worktree commit, lượt task, push nhánh PR, worktree gỡ; xét main: ls-remote khớp SHA đã gate: XONG qua.
turn_start; wt_new b1; wt_edit 21; git -C "$WT" commit -qam "edit 21"; task_gate "$WT"
tool_use Bash '{"command": "git push origin HEAD:pr-b1"}'; git -C "$WT" push -q origin HEAD:refs/heads/pr-b1 2>/dev/null || fail "B1 tiền đề: push"
git -C "$REPO" worktree remove --force "$WT"; stop "$REPO"; rc=$?
[ "$rc" = 0 ] && plog "$REPO" | grep -q "task-receipt push" && ok "B1 (b) nhánh PR đã push, ls-remote khớp biên nhận task: XONG qua" || fail "B1 bị chặn ($(why $rc))"
# B2. như B1 nhưng lượt này cũng push thẳng lên main: không nhận (fail closed).
tool_use Bash '{"command": "git push origin HEAD:main"}'; stop "$REPO"; rc=$?
blocked "$rc" && ok "B2 lượt có push lên nhánh đích: chặn" || fail "B2 push main vẫn qua ($(why $rc))"

# B3. refs/remotes sửa tay: commit đã gate KHÔNG lên origin (origin pr-b3 là commit khác), refs/remotes/origin/pr-b3 trỏ tay vào commit đã gate.
turn_start; wt_new b3; wt_edit 31; git -C "$WT" commit -qam "edit 31"; task_gate "$WT"; GATED="$(git -C "$WT" rev-parse HEAD)"
wt_edit 32; git -C "$WT" commit -qam "edit 32 chưa gate"; git -C "$WT" push -q origin HEAD:refs/heads/pr-b3 2>/dev/null || fail "B3 tiền đề: push"
git -C "$REPO" update-ref refs/remotes/origin/pr-b3 "$GATED"
tool_use Bash '{"command": "git push origin HEAD:pr-b3"}'
git -C "$REPO" worktree remove --force "$WT"; stop "$REPO"; rc=$?
blocked "$rc" && ok "B3 refs/remotes/origin/pr-b3 sửa tay trỏ vào commit đã gate, origin thật khác: chặn" || fail "B3 tin refs/remotes ($(why $rc))"

# C1. (c) trunk-finish: worktree commit, lượt task, main fast-forward tới nó, worktree gỡ: XONG qua.
turn_start; wt_new c1; wt_edit 41; git -C "$WT" commit -qam "edit 41"; task_gate "$WT"
git -C "$REPO" merge -q --ff-only "$(git -C "$WT" rev-parse HEAD)" && git -C "$REPO" worktree remove --force "$WT"; stop "$REPO"; rc=$?
[ "$rc" = 0 ] && plog "$REPO" | grep -q "task-receipt" && ok "C1 (c) trunk-finish với biên nhận task của lượt: XONG qua" || fail "C1 bị chặn ($(why $rc))"
# C1b. cùng cây đó: biên nhận task không mở được push nhánh đích (push_gate chỉ nhận biên nhận --full).
python3 "$DEVKIT_DIR/bin/push_gate.py" "$REPO" HEAD --dst origin main >"$TMP/pg" 2>&1; pg=$?
[ "$pg" = 2 ] && ok "C1b push main chỉ với biên nhận task: push_gate từ chối" || fail "C1b push main qua với biên nhận task (exit $pg: $(tail -2 "$TMP/pg" | tr '\n' ' '))"
# C2. như C1 nhưng trunk mode tắt: (c) không áp.
git -C "$REPO" config devkit.trunkMode false; stop "$REPO"; rc=$?; git -C "$REPO" config --unset devkit.trunkMode
blocked "$rc" && ok "C2 trunk mode tắt: (c) không áp, chặn" || fail "C2 trunk mode tắt vẫn qua ($(why $rc))"
# C3. lượt sau, cùng cây: biên nhận task không mang sang lượt khác.
sleep 3; turn_start; stop "$REPO"; rc=$?
blocked "$rc" && ok "C3 trunk-finish ở lượt sau: chặn" || fail "C3 lượt sau vẫn qua ($(why $rc))"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
