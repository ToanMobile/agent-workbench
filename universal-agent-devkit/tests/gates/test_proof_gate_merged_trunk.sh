#!/usr/bin/env bash
# Test hồi quy: hooks/proof_gate.sh ở trunk mode sau merge gate (18/10, 5 phiên: GeelyEx2 #63, OfficeReader #149, Goods #40, NFH #49,
# kit #67). Việc đã gộp qua `.claude/bin/super-board-merge-gate.sh` (gate --full xanh trong scratch của nó), nhưng proof_gate đòi một
# biên nhận --full của chính lượt trong cây nó xét (main sau khi worktree bị dọn), mà trunk mode cấm chạy gate ở main: XONG bị chặn mãi.
# Hai bằng chứng có thật trong lượt được nhận:
#   (b) kết quả lệnh merge gate trong transcript ("verified green" + "merged <H>"), khi git chứng thực: origin THẬT (ls-remote, không
#       phải refs/remotes agent ghi được) có một commit squash của H đẩy lên trong lượt, cây xét chứa nó, sạch;
#   (a) biên nhận --full exit 0 của một worktree trong lượt, vẫn khớp worktree đó, cùng cây với HEAD của cây xét.
# Mỗi ca chặn chỉ khác ca cho qua đúng một biến.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE   # trunk mode mặc định bật; ca N8 tự tắt nó bằng git config

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; GH="$TMP/github"; WT="$TMP/wt"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" || exit 1
git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates docs .agents
  echo 'exit 0' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git clone -q "$ORIGIN" "$GH" 2>/dev/null && git -C "$GH" config user.email gh@gh && git -C "$GH" config user.name github || exit 1
git -C "$REPO" worktree add -q --detach "$WT" HEAD || exit 1   # worktree của phiên (phiên thật: .claude/worktrees/<tên>)
RECEIPT="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
WT_RECEIPT="$(git -C "$WT" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi gộp"}}))' > "$TR"; sleep 1; }
# $1 tên công cụ, $2 input JSON, $3 nội dung tool_result (rỗng: không ghi kết quả). Giờ hiện tại.
tool() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
n=sum(1 for _ in open(sys.argv[4]))
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % n,"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))
if sys.argv[3]:
    print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"tu%d" % n,"content":sys.argv[3]}]}}))' "$1" "$2" "${3:-}" "$TR" >> "$TR.new" && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
GATE_CMD() { printf '{"command": ".claude/bin/super-board-merge-gate.sh --config .claude/super-board/configs/t.json --pr %s --expect-head %s"}' "$1" "$2"; }
GATE_OUT() { printf '[merge-gate #%s] lock taken; verifying against main as it is now\n[merge-gate #%s] verify: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --diff origin/main --force-full\n[merge-gate #%s] verified green against main (1 command(s))\n✓ Squashed and merged pull request #%s\n[merge-gate #%s] merged %s\n' "$1" "$1" "$1" "$1" "$1" "$2"; }

# new_pr N: một commit H của worktree trên đỉnh origin/main, đẩy lên origin/pr-N. In H.
new_pr() {
  git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main \
    && echo "def ok(): return $1  # pr $1" > "$WT/src/core.py" && git -C "$WT" commit -qam "pr $1" \
    && git -C "$WT" push -q origin "HEAD:refs/heads/pr-$1" && git -C "$WT" rev-parse HEAD
}
# land N [old]: GitHub squash pr-N vào main (old: commit squash ghi giờ 1 h trước), rồi main local nhận nó như merge gate (ff).
land() {
  ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 \
    && if [ "${2:-}" = old ]; then GIT_COMMITTER_DATE="@$(( $(date +%s) - 3600 )) +0000" git commit -qm "squash pr $1 (#$1)"
       else git commit -qm "squash pr $1 (#$1)"; fi && git push -q origin main ) && git -C "$REPO" pull -q --ff-only origin main
}
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
# stop [thư mục xét]: Stop với XONG; mặc định xét main (worktree đã bị merge gate dọn).
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "${1:-$REPO}/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-m","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã gộp PR qua merge gate. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="${1:-$REPO}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ')"; }

# P1. Ca thật: merge gate chạy trong lượt, origin có squash của H, main = squash đó, không biên nhận nào: cho qua.
turn_start; rm -f "$RECEIPT"; H=$(new_pr 1) && land 1 && tool Bash "$(GATE_CMD 1 "$H")" "$(GATE_OUT 1 "$H")"
rm -f "$REPO/.claude/audit-gate/proof_gate.log"; stop; rc=$?
[ "$rc" = 0 ] && ok "P1 merge gate merged H this turn, main holds its squash: XONG allowed" || fail "P1 merged turn blocked ($(why $rc))"
grep -q "merge-gate pr=1" "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null \
  && ok "P1b allowed through the merge-gate rule (logged)" || fail "P1b no merge-gate log line"

# P2. Cây xét là worktree của phiên, còn đứng ở H, sạch: cho qua.
stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "P2 the session's worktree at H, clean: allowed" || fail "P2 worktree at H blocked ($(why $rc))"

# N1. Lượt có sửa code mà không merge gate nào, không biên nhận nào: chặn.
turn_start; new_pr 2 >/dev/null && land 2; stop; rc=$?
blocked "$rc" && ok "N1 no merge-gate record, no receipt: blocked" || fail "N1 accepted without evidence ($(why $rc))"

# N2. Thiếu dòng "verified green" (merge gate không xác nhận gate xanh): chặn.
turn_start; H=$(new_pr 3) && land 3 && tool Bash "$(GATE_CMD 3 "$H")" "$(GATE_OUT 3 "$H" | grep -v 'verified green')"; stop; rc=$?
blocked "$rc" && ok "N2 no 'verified green' line: blocked" || fail "N2 accepted without verified green ($(why $rc))"

# N3. Cùng các dòng đó nhưng do một lệnh echo in ra (không phải lệnh merge gate): chặn.
turn_start; H=$(new_pr 4) && land 4 && tool Bash "{\"command\": \"printf '[merge-gate #4] verified green against main\\\\n[merge-gate #4] merged $H\\\\n'\"}" "$(GATE_OUT 4 "$H")"; stop; rc=$?
blocked "$rc" && ok "N3 the lines printed by an echo: blocked" || fail "N3 echo accepted ($(why $rc))"

# N4. H chưa từng lên origin main (PR chưa gộp): chặn.
turn_start; H=$(new_pr 5) && tool Bash "$(GATE_CMD 5 "$H")" "$(GATE_OUT 5 "$H")"; stop; rc=$?
blocked "$rc" && ok "N4 H not on origin main: blocked" || fail "N4 unmerged H accepted ($(why $rc))"

# N5. Squash của H có trên origin nhưng từ trước lượt này (bản ghi cũ dán lại): chặn.
turn_start; H=$(new_pr 6) && land 6 old && tool Bash "$(GATE_CMD 6 "$H")" "$(GATE_OUT 6 "$H")"; stop; rc=$?
blocked "$rc" && ok "N5 squash landed before the turn: blocked" || fail "N5 old squash accepted ($(why $rc))"

# N6. "origin/main" giả do agent ghi (update-ref refs/remotes + main local), origin thật không có: chặn (INSTINCT-027: ls-remote).
turn_start; H=$(new_pr 7) && git -C "$REPO" fetch -q origin \
  && S=$(git -C "$REPO" commit-tree -p origin/main -m "fake squash (#7)" "$H^{tree}") \
  && git -C "$REPO" update-ref refs/remotes/origin/main "$S" && git -C "$REPO" reset -q --hard "$S" \
  && tool Bash "$(GATE_CMD 7 "$H")" "$(GATE_OUT 7 "$H")"; stop; rc=$?
git -C "$REPO" fetch -q origin && git -C "$REPO" reset -q --hard origin/main
blocked "$rc" && ok "N6 forged local origin ref: blocked" || fail "N6 forged refs/remotes accepted ($(why $rc))"

# N7. Sau merge, main có file chính phiên này sửa (chưa gộp): chặn.
turn_start; H=$(new_pr 8) && land 8 && tool Bash "$(GATE_CMD 8 "$H")" "$(GATE_OUT 8 "$H")" \
  && echo "x" > "$REPO/docs/own.md" && tool Write "{\"file_path\": \"$REPO/docs/own.md\", \"content\": \"x\"}"; stop; rc=$?
rm -f "$REPO/docs/own.md"
blocked "$rc" && ok "N7 main dirty with this session's file: blocked" || fail "N7 own dirty file accepted ($(why $rc))"

# N7b. File bẩn của phiên khác ở main (phiên này không nhắc tới): cho qua như luật foreign-dirty.
turn_start; H=$(new_pr 9) && land 9 && tool Bash "$(GATE_CMD 9 "$H")" "$(GATE_OUT 9 "$H")" && echo "y" > "$REPO/docs/foreign.md"; stop; rc=$?
rm -f "$REPO/docs/foreign.md"
[ "$rc" = 0 ] && ok "N7b another session's dirty file in main: allowed" || fail "N7b foreign dirty file blocked ($(why $rc))"

# N8. Trunk mode tắt: luật mới không áp, chặn.
turn_start; H=$(new_pr 10) && land 10 && tool Bash "$(GATE_CMD 10 "$H")" "$(GATE_OUT 10 "$H")"
git -C "$REPO" config devkit.trunkMode false; stop; rc=$?; git -C "$REPO" config --unset devkit.trunkMode
blocked "$rc" && ok "N8 trunk mode off: blocked" || fail "N8 accepted with trunk mode off ($(why $rc))"

# N9. main có commit riêng chưa lên origin sau squash: chặn.
turn_start; H=$(new_pr 11) && land 11 && tool Bash "$(GATE_CMD 11 "$H")" "$(GATE_OUT 11 "$H")" \
  && echo "z" > "$REPO/docs/local.md" && git -C "$REPO" add docs/local.md && git -C "$REPO" commit -qm local; stop; rc=$?
git -C "$REPO" reset -q --hard origin/main
blocked "$rc" && ok "N9 main ahead of origin: blocked" || fail "N9 unpushed main commit accepted ($(why $rc))"

# N10. Cây xét là worktree, sửa thêm (chưa commit) sau khi gộp: chặn.
turn_start; H=$(new_pr 12) && land 12 && tool Bash "$(GATE_CMD 12 "$H")" "$(GATE_OUT 12 "$H")" \
  && echo "def ok(): return 99" > "$WT/src/core.py"; stop "$WT"; rc=$?
git -C "$WT" checkout -q -- src/core.py
blocked "$rc" && ok "N10 worktree edited after the merge: blocked" || fail "N10 dirty worktree accepted ($(why $rc))"

# (a) Biên nhận --full của worktree (gate chạy trong worktree ở lượt này), cùng cây với main sau squash.
wt_gate() { CLAUDE_PROJECT_DIR="$WT" python3 "$GATE" --run-tests --full --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1 \
  || { fail "setup: gate --full in the worktree exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; return 1; }; }
# A1. Không bản ghi merge gate, main = squash của cây worktree đã gate trong lượt: cho qua.
turn_start; new_pr 13 >/dev/null && wt_gate && land 13; stop; rc=$?
[ "$rc" = 0 ] && ok "A1 worktree --full receipt this turn for main's tree: allowed" || fail "A1 worktree receipt refused ($(why $rc))"
# A2. Biên nhận đó từ lượt trước: chặn.
sleep 2; turn_start; stop; rc=$?
blocked "$rc" && ok "A2 worktree receipt from an earlier turn: blocked" || fail "A2 old worktree receipt accepted ($(why $rc))"
# A3. Worktree đổi sau biên nhận (dấu vân tay không khớp): chặn.
turn_start; new_pr 14 >/dev/null && wt_gate && land 14 && echo "# sau gate" >> "$WT/src/core.py"; stop; rc=$?
git -C "$WT" checkout -q -- src/core.py
blocked "$rc" && ok "A3 worktree changed after its receipt: blocked" || fail "A3 stale worktree receipt accepted ($(why $rc))"
# A4. Cây worktree đã gate khác cây main (main chưa nhận squash): chặn.
turn_start; new_pr 15 >/dev/null && wt_gate; stop; rc=$?
blocked "$rc" && ok "A4 receipt tree differs from main's tree: blocked" || fail "A4 other tree accepted ($(why $rc))"
# A5. Worktree sạch nhưng đã commit thêm sau biên nhận (biên nhận của cây khác), squash của cây mới lên main: chặn.
turn_start; new_pr 16 >/dev/null && wt_gate && echo "# sau gate" >> "$WT/src/core.py" && git -C "$WT" commit -qam "pr 16 more" \
  && git -C "$WT" push -q origin "HEAD:refs/heads/pr-16" && land 16; stop; rc=$?
blocked "$rc" && ok "A5 receipt of an earlier commit of the worktree: blocked" || fail "A5 receipt of another tree accepted ($(why $rc))"
rm -f "$WT_RECEIPT"

if [ "$FAILS" -ne 0 ]; then echo "proof gate merged trunk: $FAILS FAILED"; exit 1; fi
echo "proof gate merged trunk: all checks passed"
