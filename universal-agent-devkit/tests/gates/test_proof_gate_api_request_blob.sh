#!/usr/bin/env bash
# Test hồi quy #722 (Gốc 2): transcript của Claude Code có dòng `{"type":"api-request-blob","sessionId","hash","message":{…tool_use…}}`
# KHÔNG có `timestamp` (bản sao request API; đo 30/10: 6712 dòng trên 30 transcript, mọi id tool_use đều có ở một dòng `assistant`
# thường, 0 dòng có `cwd`). merge_receipt_evidence coi một dòng như vậy nhắc "postfix-gate" là "dòng không đọc được có thể ghi vào kho",
# nên cửa biên nhận merge (merge gate chạy nền) không bao giờ mở ở phiên có nhắc tới gate. Sửa: dòng blob không cần timestamp; tool_use
# của nó đã có bản ghi `assistant` (có timestamp hợp lệ, id là chuỗi khác rỗng) thì đã được xét ở bản ghi đó; không có bản ghi mà không
# chỉ đọc thì CHẶN (fail-closed). Main sạch: chỉ xét cửa merge-receipt. Mỗi ca chặn chỉ khác một ca cho qua đúng một biến.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID DEVKIT_SESSION_ID

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
GV=$(git version | sed -E 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/')
set -- $GV
if [ "${1:-0}" -lt 2 ] || { [ "${1:-0}" -eq 2 ] && [ "${2:-0}" -lt 38 ]; }; then
  echo "✖ environment: git >= 2.38 needed (git merge-tree --write-tree), have $(git version)"; exit 1
fi
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; GH="$TMP/github"; WT="$TMP/wt"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" || exit 1
git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src docs .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git clone -q "$ORIGIN" "$GH" 2>/dev/null && git -C "$GH" config user.email gh@gh && git -C "$GH" config user.name github || exit 1
git -C "$REPO" worktree add -q --detach "$WT" HEAD || exit 1
STORE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/merge_receipts"

# Các helper dưới đây chép từ tests/gates/test_proof_gate_merge_receipt.sh (cùng schema biên nhận, cùng cách gộp).
turn_start() { rm -rf "$STORE"; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi gộp"}}))' > "$TR"; sleep 1; }
tool() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
n=sum(1 for _ in open(sys.argv[4]))
print(json.dumps({"type":"assistant","timestamp":t,"cwd":sys.argv[6],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % n,"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))
if sys.argv[3]:
    print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"tu%d" % n,"content":sys.argv[3],"is_error":sys.argv[5] == "err"}]}}))' "$1" "$2" "${3:-}" "$TR" "${4:-}" "$REPO" >> "$TR.new" && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
bash_cmd() { tool Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")" "$2" "${3:-}"; }
incident_cmds() {
  bash_cmd "git push -u origin pr-$1 2>&1 | tail -4" "branch 'pr-$1' set up to track 'origin/pr-$1'." \
    && bash_cmd "git push origin --delete old-$1" "BLOCKED by block-dangerous-git" err \
    && bash_cmd ".claude/bin/super-board-merge-gate.sh --config c.json --pr $1 --expect-head $2 --standalone > $TMP/mg-$1.log 2>&1; echo \"exit=\$?\" >> $TMP/mg-$1.log" \
                "Command running in background with ID: b$1"
}
new_pr() {
  git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main \
    && echo "def ok(): return $1  # pr $1" > "$WT/src/core.py" && git -C "$WT" commit -qam "pr $1" \
    && git -C "$WT" push -q origin "HEAD:refs/heads/pr-$1" && git -C "$WT" rev-parse HEAD
}
receipt() {
  local n="$1" h="$2" sid="${3-s-m}"
  git -C "$REPO" fetch -q origin || return 1
  local b t; b=$(git -C "$REPO" rev-parse origin/main) && t=$(git -C "$REPO" merge-tree --write-tree "$b" "$h") || return 1
  mkdir -p "$STORE" && python3 - "$STORE/$n-$h.json" "$n" "$h" "$b" "$t" "$sid" <<'PY'
import json, sys, time
p, n, h, b, t, sid = sys.argv[1:7]
json.dump({"pr": int(n), "head": h, "base": b, "verified_tree": t, "squash": None, "time": time.time(), "session": sid}, open(p, "w"))
PY
}
land() {
  ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 \
    && git commit -qm "squash pr $1 (#$1)" && git push -q origin main ) && git -C "$REPO" pull -q --ff-only origin main
}
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
LOG="$REPO/.claude/audit-gate/proof_gate.log"
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "${1:-$REPO}/.claude/audit-gate/proof_gate.state" "$LOG" "${1:-$REPO}/.claude/audit-gate/proof_gate.log"
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã gộp PR qua merge gate. Gate exit 0, ảnh: không cần — backend
$REPORT" "s-m" | PROOF_GATE_ALLOW_LOCAL_ORIGIN=1 PROOF_GATE_BUDGET_S=9 CLAUDE_PROJECT_DIR="${1:-$REPO}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err" && grep -q "${2:?}" "${3:-$REPO}/.claude/audit-gate/proof_gate.log" 2>/dev/null; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ') log=$(tail -2 "${2:-$REPO}/.claude/audit-gate/proof_gate.log" 2>/dev/null | tr '\n' ' ')"; }

# Dòng mới của bài này. blob ID NAME INPUT_JSON: dòng api-request-blob (không timestamp, không cwd) mang MỘT tool_use; ID là JSON
# ("\"tu1\"", "\"\"", "null"). own ID NAME INPUT_JSON [notime]: dòng assistant thường với id cho trước; notime: không có timestamp.
blob() { python3 -c 'import json,sys
print(json.dumps({"type":"api-request-blob","sessionId":"s-m","hash":"h%d" % sum(1 for _ in open(sys.argv[4])),"message":{"role":"assistant",
  "content":[{"type":"tool_use","id":json.loads(sys.argv[1]),"name":sys.argv[2],"input":json.loads(sys.argv[3])}]}}))' "$1" "$2" "$3" "$TR" >> "$TR.new" \
  && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
own() { python3 -c 'import datetime,json,sys
e={"type":"assistant","cwd":sys.argv[5],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":json.loads(sys.argv[1]),"name":sys.argv[2],"input":json.loads(sys.argv[3])}]}}
if sys.argv[4] != "notime": e["timestamp"]=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps(e))' "$1" "$2" "$3" "${4:-}" "$REPO" >> "$TR.new" && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
cmd() { python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }
n=30
merged() { n=$((n + 1)); turn_start; H=$(new_pr $n) && incident_cmds $n "$H" && receipt $n "$H" && land $n; }   # ca P1 của merge_receipt, main sạch

# B0. Đối chứng: lượt gộp qua merge gate chạy nền, biên nhận của phiên, không dòng blob: cho qua (cả trước lẫn sau bản sửa).
merged || fail "B0 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "B0 merge-receipt turn without blob lines: allowed" || fail "B0 blocked ($(why $rc))"
# B1. Sự cố: dòng blob (không timestamp) chép một lệnh chỉ đọc nhắc kho, id đã có ở dòng assistant thường: cho qua.
merged && own '"tu-ls"' Bash "$(cmd 'ls .git/postfix-gate/merge_receipts')" && blob '"tu-ls"' Bash "$(cmd 'ls .git/postfix-gate/merge_receipts')" \
  || fail "B1 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "B1 an api-request-blob copy of a logged tool_use naming the store: allowed" || fail "B1 blocked ($(why $rc))"
# B2. Blob mang công cụ chỉ đọc (Read) không có bản ghi thường: cho qua.
merged && blob '"tu-rd"' Read "{\"file_path\": \"$REPO/.git/postfix-gate/merge_receipts/x.json\"}" || fail "B2 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "B2 a read-only tool in a blob with no logged twin: allowed" || fail "B2 blocked ($(why $rc))"
# B3. Đối chứng cho NB1b(i): cây xét là worktree của phiên ở H, sạch: cho qua.
n=$((n + 1)); turn_start; H=$(new_pr $n) && receipt $n "$H" && land $n || fail "B3 setup"; stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "B3 the session's worktree at H: allowed" || fail "B3 blocked ($(why $rc))"

# NB1. Blob, id không có bản ghi thường, GHI vào kho: chặn.
merged && blob '"tu-w1"' Bash "$(cmd 'echo {} > .git/postfix-gate/merge_receipts/1-0000.json')" || fail "NB1 setup"; stop; rc=$?
blocked "$rc" "with no logged twin" && ok "NB1 an unlogged blob tool_use writing the store: blocked" || fail "NB1 accepted ($(why "$rc"))"
# NB1b(i). Như B3, cộng blob id lạ ghi tương đối vào kho (blob không có cwd; cây xét là linked worktree): chặn.
n=$((n + 1)); turn_start; H=$(new_pr $n) && receipt $n "$H" && land $n \
  && blob '"tu-w2"' Bash "$(cmd 'echo {} > .git/postfix-gate/merge_receipts/1.json')" || fail "NB1b(i) setup"; stop "$WT"; rc=$?
blocked "$rc" "with no logged twin" "$WT" && ok "NB1b(i) unlogged relative store write while judging a linked worktree: blocked" || fail "NB1b(i) accepted ($(why "$rc" "$WT"))"
# NB1b(ii). Blob id lạ ghi kho qua `..` từ thư mục con: chặn.
merged && blob '"tu-w3"' Bash "$(cmd 'cd docs && cp /tmp/x ../.git/postfix-gate/merge_receipts/y.json')" || fail "NB1b(ii) setup"; stop; rc=$?
blocked "$rc" "with no logged twin" && ok "NB1b(ii) unlogged store write through .. from a subdirectory: blocked" || fail "NB1b(ii) accepted ($(why "$rc"))"
# NB2. Blob id lạ gộp thẳng (gh pr merge): chặn.
merged && blob '"tu-gh"' Bash "$(cmd 'gh pr merge 5 --squash')" || fail "NB2 setup"; stop; rc=$?
blocked "$rc" "with no logged twin" && ok "NB2 an unlogged gh pr merge in a blob: blocked" || fail "NB2 accepted ($(why "$rc"))"
# NB3. Dòng không parse được nhắc kho (hoặc bất kỳ dòng "tool_use" hỏng JSON / không phải JSON object): chặn.
merged && printf '%s\n' '{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "echo > .git/postfix-gate/merge_receipts/z.json"' >> "$TR" \
  || fail "NB3 setup"; stop; rc=$?
blocked "$rc" "unreadable tool_use line" && ok "NB3 an unparseable line naming the store: blocked" || fail "NB3 accepted ($(why "$rc"))"
# NB3b. Dòng JSON hợp lệ nhưng là mảng (không phải object) chứa chuỗi "tool_use": không crash fail-open, chặn.
merged && printf '%s\n' '[{"type": "tool_use", "name": "Bash"}]' >> "$TR" || fail "NB3b setup"; stop; rc=$?
blocked "$rc" "unreadable tool_use line" && ok "NB3b a non-dict JSON line with tool_use: blocked" || fail "NB3b accepted ($(why "$rc"))"
# NB4. Dòng assistant không timestamp nhắc kho: chặn (như cũ).
merged && own '"tu-nt"' Bash "$(cmd 'cat .git/postfix-gate/merge_receipts/a.json')" notime || fail "NB4 setup"; stop; rc=$?
blocked "$rc" "unreadable tool_use line" && ok "NB4 an assistant line without timestamp naming the store: blocked" || fail "NB4 accepted ($(why "$rc"))"
# NB4b. Dòng assistant không timestamp chạy gh pr merge (không nhắc kho) + bản sao blob trùng id: chặn.
merged && own '"tu-ng"' Bash "$(cmd 'gh pr merge 5 --squash')" notime && blob '"tu-ng"' Bash "$(cmd 'gh pr merge 5 --squash')" \
  || fail "NB4b setup"; stop; rc=$?
blocked "$rc" "unreadable tool_use line" && ok "NB4b timestamp-less gh pr merge + blob twin: blocked" || fail "NB4b accepted ($(why "$rc"))"
# NB4c. Dòng assistant không timestamp chạy gh pr merge (không nhắc kho, không có bản sao blob): chặn (không được lọt qua continue).
merged && own '"tu-ng0"' Bash "$(cmd 'gh pr merge 5 --squash')" notime || fail "NB4c setup"; stop; rc=$?
blocked "$rc" "unreadable tool_use line" && ok "NB4c timestamp-less gh pr merge without blob twin: blocked" || fail "NB4c accepted ($(why "$rc"))"
# NB4d. Dòng khác kiểu assistant (có timestamp hợp lệ) mang tool_use + bản sao blob trùng id: không đóng dấu seen, chặn.
merged && python3 -c 'import datetime,json
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"system","timestamp":t,"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu-sys","name":"Bash","input":{"command":"gh pr merge 5 --squash"}}]}}))' >> "$TR" \
  && blob '"tu-sys"' Bash "$(cmd 'gh pr merge 5 --squash')" || fail "NB4d setup"; stop; rc=$?
blocked "$rc" "with no logged twin" && ok "NB4d non-assistant timestamped tool_use + blob twin: blocked" || fail "NB4d accepted ($(why "$rc"))"
# NB5. Blob id lạ, lệnh chỉ đọc nhắc kho: vẫn chặn (fail-closed có chủ ý: mọi tool_use không chỉ đọc phải có bản ghi thường).
merged && blob '"tu-l2"' Bash "$(cmd 'ls .git/postfix-gate/merge_receipts')" || fail "NB5 setup"; stop; rc=$?
blocked "$rc" "with no logged twin" && ok "NB5 an unlogged Bash in a blob, even a read: blocked" || fail "NB5 accepted ($(why "$rc"))"
# NB6. Blob nhắc kho mà không có khối tool_use dạng object: chặn.
merged && printf '%s\n' '{"type":"api-request-blob","sessionId":"s-m","hash":"hx","message":{"role":"assistant","content":["tool_use","merge_receipts"]}}' >> "$TR" \
  || fail "NB6 setup"; stop; rc=$?
blocked "$rc" "without a tool_use" && ok "NB6 a blob naming the store without a tool_use object: blocked" || fail "NB6 accepted ($(why "$rc"))"
# NB7. id rỗng / null ở cả dòng thường lẫn blob: không coi là "có bản ghi": chặn.
for id in '""' 'null'; do
  merged && own "$id" Bash "$(cmd 'ls .git/postfix-gate/merge_receipts')" && blob "$id" Bash "$(cmd 'ls .git/postfix-gate/merge_receipts')" \
    || fail "NB7 setup ($id)"; stop; rc=$?
  blocked "$rc" "with no logged twin" && ok "NB7 tool_use id $id never counts as logged: blocked" || fail "NB7 id $id accepted ($(why "$rc"))"
done

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
