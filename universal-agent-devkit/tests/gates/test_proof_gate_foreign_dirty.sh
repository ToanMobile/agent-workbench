#!/usr/bin/env bash
# Test hồi quy: hooks/proof_gate.sh ở trunk mode (17/10). Main chỉ nhận merge; `agent-kit worktree finish` chép biên nhận gate --full
# của worktree sang main (`carried_from`). Main lại giữ file chưa commit của phiên khác / runner của board (docs/super-board/runs/*.md),
# nên dấu vân tay của main không bao giờ khớp biên nhận và XONG bị chặn "code đã đổi sau lần exit 0" ở mọi phiên.
# Luật hẹp: biên nhận của lượt này, chép từ worktree, `head` = HEAD của main, `dirty` rỗng (đã gate đúng HEAD), và mọi file main khác
# HEAD đều không có trong transcript của phiên → chấp nhận. Mỗi ca chặn chỉ khác ca qua đúng một biến và phải nêu đúng lý do.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE   # trunk mode mặc định bật; ca 5a tự tắt nó bằng git config

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$TMP/repo"; TR="$TMP/transcript.jsonl"; mkdir -p "$REPO/src" "$REPO/templates" "$REPO/docs"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo 'exit 0' > result.sh && echo "def ok(): return 1" > src/core.py
  mkdir -p .agents && echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét biên nhận
  printf '.claude/audit-gate/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && echo "def ok(): return 2" > src/core.py && git commit -qam two ) || exit 1
OLD_HEAD="$(git -C "$REPO" rev-parse HEAD~1)"
RECEIPT="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; sleep 1; }
# Một tool_use của phiên (tên công cụ, input JSON) ghi vào transcript, giờ hiện tại.
tool_use() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu1","name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))' "$1" "$2" >> "$TR"; }
# Gate --full trên cây sạch (= HEAD), rồi làm như `worktree finish`: thêm carried_from. $1..: sửa thêm field của biên nhận (k=v JSON).
gate_carried() {
  rm -f "$REPO/docs/foreign.md"
  CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --run-tests --full --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1 || { fail "setup: gate --full exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; return 1; }
  rm -rf "$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/tree_receipts"   # kho theo cây (#105) là bằng chứng khác, có test riêng: ở đây chỉ luật này
  python3 - "$RECEIPT" "$@" <<'PY'
import json, sys
p = sys.argv[1]; r = json.load(open(p))
r["carried_from"] = "/somewhere/.claude/worktrees/wt"
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    if v == "DEL": r.pop(k, None)
    else: r[k] = json.loads(v)
json.dump(r, open(p, "w"))
PY
}
foreign() { echo "# run log của runner khác" > "$REPO/docs/foreign.md"; }   # không nằm trong tree_fp.EXCLUDE: đổi dấu vân tay
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-f","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã sửa lỗi X. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

# 1. File bẩn của người khác + biên nhận worktree mới cho đúng HEAD: cho qua.
turn_start; gate_carried && foreign; rm -f "$REPO/.claude/audit-gate/proof_gate.log"; stop; rc=$?
[ "$rc" = 0 ] && ok "foreign dirty file + fresh carried receipt for HEAD: XONG allowed" \
  || fail "foreign dirty file blocked XONG (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"
# 1b. Ca 1 (log xoá ngay trước nó) qua đúng nhánh mới: hook ghi dòng log foreign-dirty kèm tên file.
grep -q "foreign-dirty head=.*docs/foreign.md" "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null \
  && ok "allowed through the foreign-dirty rule (logged with the path)" || fail "no foreign-dirty log line for the allowed XONG"

# 1d. Phiên sửa file CÙNG TÊN trong worktree riêng của nó (ca thường gặp nhất ở trunk mode): không phải file của main, cho qua.
mkdir -p "$TMP/wt/docs"
turn_start; gate_carried && foreign; tool_use Write "{\"file_path\": \"$TMP/wt/docs/foreign.md\", \"content\": \"x\"}"; stop; rc=$?
[ "$rc" = 0 ] && ok "same-named file written in the session's own worktree: allowed" \
  || fail "a Write in the own worktree blocked XONG (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 1e. Prompt của một subagent (Agent) nêu tên file: giao việc không phải sửa (lần sửa của subagent nằm ở transcript riêng), cho qua.
turn_start; gate_carried && foreign; tool_use Agent '{"prompt": "đừng đụng docs/foreign.md"}'; stop; rc=$?
[ "$rc" = 0 ] && ok "an Agent prompt naming the file: allowed" \
  || fail "an Agent prompt blocked XONG (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2. Phiên này đã sửa chính file đó ở main (Write): vẫn chặn.
turn_start; gate_carried && foreign; tool_use Write "{\"file_path\": \"$REPO/docs/foreign.md\", \"content\": \"x\"}"; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "file this session wrote in main: blocked" \
  || fail "own Write in main accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2a. Edit với đường dẫn tương đối (tính từ gốc repo): vẫn chặn.
turn_start; gate_carried && foreign; tool_use Edit '{"file_path": "docs/foreign.md", "old_string": "a", "new_string": "b"}'; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "relative-path Edit of the file in main: blocked" \
  || fail "relative-path Edit accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2b. Phiên này nhắc tên file trong một lệnh Bash: coi là đã đụng (không parse shell), vẫn chặn.
turn_start; gate_carried && foreign; tool_use Bash '{"command": "echo more >> docs/foreign.md"}'; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "file named by this session's Bash command: blocked" \
  || fail "own Bash edit accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2c. Chỉ đọc file đó (Read): không phải sửa, vẫn cho qua.
turn_start; gate_carried && foreign; tool_use Read "{\"file_path\": \"$REPO/docs/foreign.md\"}"; stop; rc=$?
[ "$rc" = 0 ] && ok "file this session only read: allowed" \
  || fail "a Read blocked XONG (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 1c. File bẩn là file tracked bị phiên khác sửa (không chỉ untracked): vẫn cho qua.
turn_start; gate_carried && echo "# sửa bởi runner" >> "$REPO/templates/regression_matrix.json"; stop; rc=$?
git -C "$REPO" checkout -q -- templates/regression_matrix.json
[ "$rc" = 0 ] && ok "foreign edit of a tracked file + fresh carried receipt: allowed" \
  || fail "foreign tracked edit blocked XONG (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2d. Lần sửa nằm trong transcript của subagent (<transcript>/subagents/*.jsonl): vẫn chặn.
SUB="${TR%.jsonl}/subagents"; mkdir -p "$SUB"
turn_start; gate_carried && foreign
tool_use Write "{\"file_path\": \"$REPO/docs/foreign.md\", \"content\": \"x\"}"; tail -1 "$TR" > "$SUB/agent-a1.jsonl"; turn_start   # transcript chính viết lại: chỉ còn subagent giữ lần sửa
stop; rc=$?; rm -rf "${TR%.jsonl}"
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "file a subagent of this session wrote in main: blocked" \
  || fail "subagent Write in main accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2e. Một tool_use có file_path chứa NUL: python không được chết (chết = wrapper exit 0 = XONG lọt); lỗi trong phần kiểm = chặn như cũ.
turn_start; gate_carried && foreign; tool_use Write '{"file_path": "/x\u0000y", "content": "x"}'
tool_use Write "{\"file_path\": \"$REPO/docs/foreign.md\", \"content\": \"x\"}"; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "a NUL file_path is no crash: blocked" \
  || fail "NUL file_path let XONG through (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 2f. Một dòng tool_use lồng sâu (json RecursionError) không đọc được: có thể chứa lần sửa, chặn chứ không bỏ qua hay chết.
turn_start; gate_carried && foreign
python3 -c 'import sys; n = 200000; sys.stdout.write("{\"type\":\"assistant\",\"x\":\"tool_use\",\"y\":" + "[" * n + "]" * n + "}\n")' >> "$TR"
stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "a deeply nested transcript line: blocked, no crash" \
  || fail "nested transcript line let XONG through (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 3. Biên nhận của HEAD cũ hơn: chặn.
turn_start; gate_carried "head=\"$OLD_HEAD\"" && foreign; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "receipt for an older HEAD: blocked" \
  || fail "receipt of an older HEAD accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 4. Biên nhận gate ngay trong main (không carried_from): luật mới không áp, chặn như cũ.
turn_start; gate_carried "carried_from=DEL" && foreign; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "receipt not carried from a worktree: blocked" \
  || fail "receipt without carried_from accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 5. Biên nhận gate trên cây bẩn (dirty khác rỗng): không chứng minh được nó gate đúng HEAD, chặn.
turn_start; gate_carried 'dirty={"src/core.py": "0000000000000000000000000000000000000000"}' && foreign; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "receipt of a dirty tree: blocked" \
  || fail "receipt of a dirty tree accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 5a. Trunk mode tắt (session_lock không còn chặn ghi vào main): luật mới không áp, chặn.
turn_start; gate_carried && foreign; git -C "$REPO" config devkit.trunkMode false; stop; rc=$?; git -C "$REPO" config --unset devkit.trunkMode
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "trunk mode off: blocked" \
  || fail "receipt accepted with trunk mode off (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 5b. Transcript không có lời nhắc người dùng (mốc dự phòng 1 h): luật mới không áp, chặn.
gate_carried && foreign; : > "$TR"; stop; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "no real turn start: blocked" \
  || fail "receipt accepted without a turn start (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

# 6. Biên nhận từ lượt trước: chặn (kiểm tra cũ, giữ nguyên).
gate_carried && foreign; sleep 3; turn_start; stop; rc=$?
[ "$rc" = 2 ] && grep -q "trước lượt" "$TMP/err" && ok "carried receipt from an earlier turn: blocked" \
  || fail "old carried receipt accepted (rc=$rc err=$(head -3 "$TMP/err" | tr '\n' ' '))"

if [ "$FAILS" -ne 0 ]; then echo "proof gate foreign dirty: $FAILS FAILED"; exit 1; fi
echo "proof gate foreign dirty: all checks passed"
