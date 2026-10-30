#!/usr/bin/env bash
# hooks/proof_gate.sh, #691 (plan r5, mục 3, ca Q1-Q5). Bản cài kit sửa .claude/settings.json của worktree (không commit). tree_fingerprint()
# ghim file đó về HEAD; proof_gate phải coi nó như không bẩn ở mọi cửa đọc `dirty` / dirty_state(), mà vẫn chặn khi có file bẩn KHÁC.
# Mọi ca chạy sau khi xoá kho biên nhận theo cây <git common dir>/postfix-gate/{tree_receipts,scoped_receipts,task_receipts}: gate thật ghi cả ba,
# fp đã ghim nên tree_store_evidence cho XONG qua trước các cửa này (ca xanh sẵn, vô nghĩa). Log: Q1, Q3, Q5 đọc $REPO/.claude/audit-gate/proof_gate.log;
# Q2, Q4 đọc $WT/.claude/audit-gate/proof_gate.log (hook chạy với CLAUDE_PROJECT_DIR=$WT). Chuỗi "worktree bẩn" ở mã chỉ là comment, không vào log.
#   ĐỎ-THẬT (da9ad59e: rc=2 + "block session="; sau sửa: rc=0 + dòng log chấp nhận của đúng nhánh):
#     Q1 foreign_dirty_only (dòng 461: `dirty` của biên nhận còn path ghim) -> "foreign-dirty head="
#     Q2 merged_evidence (b), tree[1] bác worktree bẩn -> "merge-gate pr="
#     Q3 merged_evidence (a), wst[1] -> "worktree-receipt"
#     Q4 merge_receipt_evidence, tree[1] -> "merge-receipt pr="
#   CHỐT-CHẶN: Q5 worktree có THÊM một file bẩn khác settings.json vẫn bị chặn (rc=2, "block session=", không có "worktree-receipt").
# Bước đầu-cuối qua `worktree finish` của Q1 nằm ở test_push_gate_settings_local.sh (P3): ở đây dùng bản chép biên nhận như finish làm.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID DEVKIT_SESSION_ID

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
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

HOOKS_BASE='"Stop":[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/session_lock.sh\""}]}]'
SET_COMMITTED="{\"hooks\":{$HOOKS_BASE}}"
# sửa cục bộ của bản cài kit: thêm một hook có thật của kit, khối hooks vẫn hợp lệ (gate chạy thật kiểm nó)
SET_LOCAL="{\"hooks\":{$HOOKS_BASE,\"PreToolUse\":[{\"matcher\":\"Read\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash \\\"\$CLAUDE_PROJECT_DIR/.claude/hooks/instincts_file_context.sh\\\"\"}]}]}}"

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; GH="$TMP/github"; WT="$TMP/wt"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" || exit 1
git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates docs .agents .claude/bin
  printf '#!/bin/sh\necho merge gate\n' > .claude/bin/super-board-merge-gate.sh
  echo 'exit 0' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  printf '%s\n' "$SET_COMMITTED" > .claude/settings.json
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && echo "def ok(): return 2" > src/core.py && git commit -qam two && git push -q origin main ) || exit 1
git clone -q "$ORIGIN" "$GH" 2>/dev/null && git -C "$GH" config user.email gh@gh && git -C "$GH" config user.name github || exit 1
git -C "$REPO" worktree add -q --detach "$WT" HEAD || exit 1   # worktree của phiên (phiên thật: .claude/worktrees/<tên>)
COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"
STORE="$COMMON/postfix-gate/merge_receipts"
RECEIPT="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
WT_RECEIPT="$(git -C "$WT" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
LOG_R="$REPO/.claude/audit-gate/proof_gate.log"; LOG_W="$WT/.claude/audit-gate/proof_gate.log"

turn_start() { rm -rf "$STORE"; rm -f "$RECEIPT" "$WT_RECEIPT"; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi gộp"}}))' > "$TR"; sleep 1; }
# $1 tên công cụ, $2 input JSON, $3 nội dung tool_result (rỗng: không ghi), $4 = err: kết quả lỗi.
tool() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
n=sum(1 for _ in open(sys.argv[4]))
print(json.dumps({"type":"assistant","timestamp":t,"cwd":sys.argv[6],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % n,"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))
if sys.argv[3]:
    print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"tu%d" % n,"content":sys.argv[3],"is_error":sys.argv[5] == "err"}]}}))' "$1" "$2" "${3:-}" "$TR" "${4:-}" "$REPO" >> "$TR.new" && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
GATE_CMD() { printf '{"command": ".claude/bin/super-board-merge-gate.sh --config .claude/super-board/configs/t.json --pr %s --expect-head %s"}' "$1" "$2"; }
GATE_OUT() { printf '[merge-gate #%s] lock taken; verifying against main as it is now\n[merge-gate #%s] verify: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --diff origin/main --force-full\n[merge-gate #%s] verified green against main (1 command(s))\n✓ Squashed and merged pull request #%s\n[merge-gate #%s] merged %s\n' "$1" "$1" "$1" "$1" "$1" "$2"; }
clear_stores() { rm -rf "$COMMON/postfix-gate/tree_receipts" "$COMMON/postfix-gate/scoped_receipts" "$COMMON/postfix-gate/task_receipts"; }
put_local() { printf '%s\n' "$SET_LOCAL" > "$WT/.claude/settings.json"; }   # settings.json sửa cục bộ trong worktree (khối hooks hợp lệ)

# new_pr N: commit H của worktree trên đỉnh origin/main, đẩy lên origin/pr-N. In H. (settings.json sửa cục bộ sống sót qua checkout vì HEAD cùng blob)
new_pr() {
  git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main \
    && echo "def ok(): return $1  # pr $1" > "$WT/src/core.py" && git -C "$WT" commit -qam "pr $1" \
    && git -C "$WT" push -q origin "HEAD:refs/heads/pr-$1" && git -C "$WT" rev-parse HEAD
}
# land N: GitHub squash pr-N vào main, rồi main local nhận nó (ff).
land() {
  ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 \
    && git commit -qm "squash pr $1 (#$1)" && git push -q origin main ) && git -C "$REPO" pull -q --ff-only origin main
}
# receipt N H: biên nhận của merge gate (base = origin/main lúc đó, cây = gộp base vào H), session s-m
receipt() {
  local n="$1" h="$2"
  git -C "$REPO" fetch -q origin || return 1
  local b t; b=$(git -C "$REPO" rev-parse origin/main) && t=$(git -C "$REPO" merge-tree --write-tree "$b" "$h") || return 1
  mkdir -p "$STORE" && python3 - "$STORE/$n-$h.json" "$n" "$h" "$b" "$t" <<'PY'
import json, sys, time
p, n, h, b, t = sys.argv[1:6]
json.dump({"pr": int(n), "head": h, "base": b, "verified_tree": t, "squash": None, "time": time.time(), "session": "s-m"}, open(p, "w"))
PY
}
wt_gate() { CLAUDE_PROJECT_DIR="$WT" python3 "$GATE" --run-tests --full --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1 \
  || { fail "dựng ca: gate --full trong worktree exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; return 1; }; clear_stores; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
# stop [thư mục xét]: Stop với XONG; mặc định xét main
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "${1:-$REPO}/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-m","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã sửa lỗi X. Gate exit 0, ảnh: không cần — backend
$REPORT" | PROOF_GATE_ALLOW_LOCAL_ORIGIN=1 PROOF_GATE_BUDGET_S="${BUDGET:-9}" CLAUDE_PROJECT_DIR="${1:-$REPO}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ' | head -c 300)"; }
want_pass() { # <tên> <rc> <log> <chuỗi log chấp nhận>
  if [ "$2" = 0 ] && grep -qF -- "$4" "$3" 2>/dev/null; then ok "$1: XONG qua, log có \"$4\""
  else fail "$1: rc=$2, log$(grep -qF -- "$4" "$3" 2>/dev/null && echo ' có' || echo ' KHÔNG có') \"$4\" ($(why "$2"))"; fi
}

# Q1 (đỏ-thật): biên nhận do gate thật sinh trong worktree có settings.json sửa, chép sang main như `worktree finish` (carried_from, giữ nguyên dirty);
# main có thêm một file bẩn ngoại lai nên fingerprint lệch và phải qua foreign_dirty_only
turn_start; put_local && wt_gate && mkdir -p "$(dirname "$RECEIPT")" && python3 - "$WT_RECEIPT" "$RECEIPT" <<'PY' || fail "Q1 dựng ca"
import json, sys
r = json.load(open(sys.argv[1])); r["carried_from"] = "/somewhere/.claude/worktrees/wt"
json.dump(r, open(sys.argv[2], "w"))
PY
echo "# run log của runner khác" > "$REPO/docs/foreign.md"; rm -f "$LOG_R"; stop; rc=$?
want_pass "Q1 foreign_dirty_only, biên nhận có settings.json sửa cục bộ" "$rc" "$LOG_R" "foreign-dirty head="
rm -f "$REPO/docs/foreign.md" "$RECEIPT"; git -C "$WT" checkout -q -- .claude/settings.json

# Q2 (đỏ-thật): worktree liên kết chỉ có settings.json sửa cục bộ, đã gộp qua merge gate (nhánh (b)); xét ở worktree
turn_start; H=$(new_pr 2) && land 2 && tool Bash "$(GATE_CMD 2 "$H")" "$(GATE_OUT 2 "$H")" && clear_stores && put_local || fail "Q2 dựng ca"
rm -f "$LOG_W"; stop "$WT"; rc=$?
want_pass "Q2 merged_evidence (b) trong worktree có settings.json sửa" "$rc" "$LOG_W" "merge-gate pr=2"
git -C "$WT" checkout -q -- .claude/settings.json

# Q3 (đỏ-thật): biên nhận --full của worktree (nhánh (a)), cùng cây với main sau squash; worktree chỉ có settings.json sửa; xét ở main
turn_start; H=$(new_pr 3) && put_local && wt_gate && land 3 || fail "Q3 dựng ca"
rm -f "$LOG_R"; stop; rc=$?
want_pass "Q3 merged_evidence (a), worktree-receipt" "$rc" "$LOG_R" "worktree-receipt"
git -C "$WT" checkout -q -- .claude/settings.json

# Q4 (đỏ-thật): biên nhận merge của merge gate, cây xét là worktree có settings.json sửa
turn_start; H=$(new_pr 4) && receipt 4 "$H" && land 4 && clear_stores && put_local || fail "Q4 dựng ca"
rm -f "$LOG_W"; stop "$WT"; rc=$?
want_pass "Q4 merge_receipt_evidence trong worktree có settings.json sửa" "$rc" "$LOG_W" "merge-receipt pr=4"
git -C "$WT" checkout -q -- .claude/settings.json

# Q5 (chốt chặn): như Q3 nhưng worktree CÓ THÊM một file bẩn khác settings.json: vẫn chặn, không qua nhánh (a)
turn_start; H=$(new_pr 5) && put_local && mkdir -p "$WT/docs" && echo "x" > "$WT/docs/own.md" && wt_gate && land 5 || fail "Q5 dựng ca"
rm -f "$LOG_R"; stop; rc=$?
if [ "$rc" = 2 ] && grep -qF "block session=" "$LOG_R" 2>/dev/null && ! grep -qF "worktree-receipt" "$LOG_R" 2>/dev/null; then
  ok "Q5 worktree có thêm file bẩn khác settings.json: chặn (rc=2, block session=, không có worktree-receipt)"
else fail "Q5 chốt chặn hỏng: rc=$rc ($(why "$rc"))"; fi

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
