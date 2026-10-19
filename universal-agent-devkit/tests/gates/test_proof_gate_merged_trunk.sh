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
# git merge-tree --write-tree (hook) cần git >= 2.38; init -b cần 2.28. Thiếu là lỗi môi trường, nói rõ (không phải hook sai).
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
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates docs .agents .claude/bin
  printf '#!/bin/sh\necho merge gate\n' > .claude/bin/super-board-merge-gate.sh
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
# $1 tên công cụ, $2 input JSON, $3 nội dung tool_result (rỗng: không ghi kết quả), $4 = err: kết quả lỗi. Giờ hiện tại.
tool() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
n=sum(1 for _ in open(sys.argv[4]))
print(json.dumps({"type":"assistant","timestamp":t,"cwd":sys.argv[6],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % n,"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))
if sys.argv[3]:
    print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"tu%d" % n,"content":sys.argv[3],"is_error":sys.argv[5] == "err"}]}}))' "$1" "$2" "${3:-}" "$TR" "${4:-}" "${CWD:-$REPO}" >> "$TR.new" && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
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
$REPORT" | PROOF_GATE_ALLOW_LOCAL_ORIGIN="${LOCAL_ORIGIN:-1}" PROOF_GATE_BUDGET_S="${BUDGET:-9}" CLAUDE_PROJECT_DIR="${1:-$REPO}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ')"; }

# P1. Ca thật: merge gate chạy trong lượt, origin có squash của H, main = squash đó, không biên nhận nào: cho qua.
turn_start; rm -f "$RECEIPT"; H=$(new_pr 1) && land 1 && tool Bash "$(GATE_CMD 1 "$H")" "$(GATE_OUT 1 "$H")" || fail "P1 setup"
rm -f "$REPO/.claude/audit-gate/proof_gate.log"; stop; rc=$?
[ "$rc" = 0 ] && ok "P1 merge gate merged H this turn, main holds its squash: XONG allowed" || fail "P1 merged turn blocked ($(why $rc))"
grep -q "merge-gate pr=1" "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null \
  && ok "P1b allowed through the merge-gate rule (logged)" || fail "P1b no merge-gate log line"

# P2. Cây xét là worktree của phiên, còn đứng ở H, sạch: cho qua.
stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "P2 the session's worktree at H, clean: allowed" || fail "P2 worktree at H blocked ($(why $rc))"

# N1. Lượt có sửa code mà không merge gate nào, không biên nhận nào: chặn.
turn_start; new_pr 2 >/dev/null && land 2 || fail "N1 setup"; stop; rc=$?
blocked "$rc" && ok "N1 no merge-gate record, no receipt: blocked" || fail "N1 accepted without evidence ($(why $rc))"

# N2. Thiếu dòng "verified green" (merge gate không xác nhận gate xanh): chặn.
turn_start; H=$(new_pr 3) && land 3 && tool Bash "$(GATE_CMD 3 "$H")" "$(GATE_OUT 3 "$H" | grep -v 'verified green')" || fail "N2 setup"; stop; rc=$?
blocked "$rc" && ok "N2 no 'verified green' line: blocked" || fail "N2 accepted without verified green ($(why $rc))"

# N3. Cùng các dòng đó nhưng do một lệnh echo in ra (không phải lệnh merge gate): chặn.
turn_start; H=$(new_pr 4) && land 4 && tool Bash "{\"command\": \"printf '[merge-gate #4] verified green against main\\\\n[merge-gate #4] merged $H\\\\n'\"}" "$(GATE_OUT 4 "$H")" || fail "N3 setup"; stop; rc=$?
blocked "$rc" && ok "N3 the lines printed by an echo: blocked" || fail "N3 echo accepted ($(why $rc))"

# N4. H chưa từng lên origin main (PR chưa gộp): chặn.
turn_start; H=$(new_pr 5) && tool Bash "$(GATE_CMD 5 "$H")" "$(GATE_OUT 5 "$H")" || fail "N4 setup"; stop; rc=$?
blocked "$rc" && ok "N4 H not on origin main: blocked" || fail "N4 unmerged H accepted ($(why $rc))"

# N5. Squash của H có trên origin nhưng từ trước lượt này (bản ghi cũ dán lại): chặn.
turn_start; H=$(new_pr 6) && land 6 old && tool Bash "$(GATE_CMD 6 "$H")" "$(GATE_OUT 6 "$H")" || fail "N5 setup"; stop; rc=$?
blocked "$rc" && ok "N5 squash landed before the turn: blocked" || fail "N5 old squash accepted ($(why $rc))"

# N6. "origin/main" giả do agent ghi (update-ref refs/remotes + main local), origin thật không có: chặn (INSTINCT-027: ls-remote).
turn_start; H=$(new_pr 7) && git -C "$REPO" fetch -q origin \
  && S=$(git -C "$REPO" commit-tree -p origin/main -m "fake squash (#7)" "$H^{tree}") \
  && git -C "$REPO" update-ref refs/remotes/origin/main "$S" && git -C "$REPO" reset -q --hard "$S" \
  && tool Bash "$(GATE_CMD 7 "$H")" "$(GATE_OUT 7 "$H")" || fail "N6 setup"; stop; rc=$?
git -C "$REPO" fetch -q origin && git -C "$REPO" reset -q --hard origin/main || { fail "restore after N6"; exit 1; }
blocked "$rc" && ok "N6 forged local origin ref: blocked" || fail "N6 forged refs/remotes accepted ($(why $rc))"

# N7. Sau merge, main có file chính phiên này sửa (chưa gộp): chặn.
turn_start; H=$(new_pr 8) && land 8 && tool Bash "$(GATE_CMD 8 "$H")" "$(GATE_OUT 8 "$H")" \
  && echo "x" > "$REPO/docs/own.md" && tool Write "{\"file_path\": \"$REPO/docs/own.md\", \"content\": \"x\"}" || fail "N7 setup"; stop; rc=$?
rm -f "$REPO/docs/own.md"
blocked "$rc" && ok "N7 main dirty with this session's file: blocked" || fail "N7 own dirty file accepted ($(why $rc))"

# N7b. File bẩn của phiên khác ở main (phiên này không nhắc tới): cho qua như luật foreign-dirty.
turn_start; H=$(new_pr 9) && land 9 && tool Bash "$(GATE_CMD 9 "$H")" "$(GATE_OUT 9 "$H")" && echo "y" > "$REPO/docs/foreign.md" || fail "N7b setup"; stop; rc=$?
rm -f "$REPO/docs/foreign.md"
[ "$rc" = 0 ] && ok "N7b another session's dirty file in main: allowed" || fail "N7b foreign dirty file blocked ($(why $rc))"

# N8. Trunk mode tắt: luật mới không áp, chặn.
turn_start; H=$(new_pr 10) && land 10 && tool Bash "$(GATE_CMD 10 "$H")" "$(GATE_OUT 10 "$H")" || fail "N8 setup"
git -C "$REPO" config devkit.trunkMode false; stop; rc=$?; git -C "$REPO" config --unset devkit.trunkMode || { fail "restore after N8"; exit 1; }
blocked "$rc" && ok "N8 trunk mode off: blocked" || fail "N8 accepted with trunk mode off ($(why $rc))"

# N9. main có commit riêng chưa lên origin sau squash: chặn.
turn_start; H=$(new_pr 11) && land 11 && tool Bash "$(GATE_CMD 11 "$H")" "$(GATE_OUT 11 "$H")" \
  && echo "z" > "$REPO/docs/local.md" && git -C "$REPO" add docs/local.md && git -C "$REPO" commit -qm local || fail "N9 setup"; stop; rc=$?
git -C "$REPO" reset -q --hard origin/main || { fail "restore after N9"; exit 1; }
blocked "$rc" && ok "N9 main ahead of origin: blocked" || fail "N9 unpushed main commit accepted ($(why $rc))"

# N10. Cây xét là worktree, sửa thêm (chưa commit) sau khi gộp: chặn.
turn_start; H=$(new_pr 12) && land 12 && tool Bash "$(GATE_CMD 12 "$H")" "$(GATE_OUT 12 "$H")" \
  && echo "def ok(): return 99" > "$WT/src/core.py" || fail "N10 setup"; stop "$WT"; rc=$?
git -C "$WT" checkout -q -- src/core.py
blocked "$rc" && ok "N10 worktree edited after the merge: blocked" || fail "N10 dirty worktree accepted ($(why $rc))"

# N3b. Tên script chỉ nằm trong comment của một lệnh in dòng giả: không phải lệnh merge gate, chặn.
turn_start; H=$(new_pr 17) && land 17 && tool Bash "{\"command\": \"printf x # .claude/bin/super-board-merge-gate.sh --pr 17 --expect-head $H\"}" "$(GATE_OUT 17 "$H")" || fail "N3b setup"; stop; rc=$?
blocked "$rc" && ok "N3b script name only in a comment: blocked" || fail "N3b comment-forged call accepted ($(why $rc))"
# N3c. Lệnh merge gate trả lỗi (is_error): chặn.
turn_start; H=$(new_pr 18) && land 18 && tool Bash "$(GATE_CMD 18 "$H")" "$(GATE_OUT 18 "$H")" err || fail "N3c setup"; stop; rc=$?
blocked "$rc" && ok "N3c merge-gate result is an error: blocked" || fail "N3c error result accepted ($(why $rc))"
# N3d. --pr của lệnh khác số PR trong kết quả: chặn.
turn_start; H=$(new_pr 19) && land 19 && tool Bash "$(GATE_CMD 99 "$H")" "$(GATE_OUT 19 "$H")
[merge-gate #99] verified green against main (1 command(s))" || fail "N3d setup"; stop; rc=$?
blocked "$rc" && ok "N3d --pr differs from the reported PR: blocked" || fail "N3d --pr mismatch accepted ($(why $rc))"
# N3e. --expect-head của lệnh khác H trong kết quả: chặn.
turn_start; H=$(new_pr 20) && land 20 && tool Bash "$(GATE_CMD 20 0123456789abcdef0123456789abcdef01234567)" "$(GATE_OUT 20 "$H")" || fail "N3e setup"; stop; rc=$?
blocked "$rc" && ok "N3e --expect-head differs from the merged head: blocked" || fail "N3e --expect-head mismatch accepted ($(why $rc))"
# P3. Dạng lệnh thật hay gặp: cd vào repo, 2>&1 | tail: cho qua.
turn_start; H=$(new_pr 21) && land 21 && tool Bash "{\"command\": \"cd $REPO && bash .claude/bin/super-board-merge-gate.sh --config c.json --pr 21 --expect-head ${H:0:12} 2>&1 | tail -40\"}" "$(GATE_OUT 21 "$H")" || fail "P3 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "P3 cd … && bash …merge-gate.sh … 2>&1 | tail -40: allowed" || fail "P3 real command form blocked ($(why $rc))"
# N12. PR phiên khác gộp sau S, main đi theo origin: cho qua (lượt này không tự gộp thẳng).
turn_start; H=$(new_pr 22) && land 22 && tool Bash '{"command": "git push -u origin fix-pr-22"}' "ok" \
  && tool Bash "$(GATE_CMD 22 "$H")" "$(GATE_OUT 22 "$H")" && new_pr 23 >/dev/null && land 23 || fail "N12 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "N12 another PR landed after S, main follows origin: allowed" || fail "N12 later foreign merge blocked ($(why $rc))"
# N13. Như N12 nhưng chính lượt này gộp thẳng PR sau (gh pr merge, không qua merge gate): chặn.
turn_start; H=$(new_pr 24) && land 24 && tool Bash "$(GATE_CMD 24 "$H")" "$(GATE_OUT 24 "$H")" && new_pr 25 >/dev/null && land 25 \
  && tool Bash '{"command": "gh pr merge 25 --squash"}' "merged" || fail "N13 setup"; stop; rc=$?
blocked "$rc" && ok "N13 this turn merged another PR directly: blocked" || fail "N13 direct gh merge accepted ($(why $rc))"
# N11. P0 (principal review): origin trỏ về chính repo (`remote.origin.url .`) và main mang một "squash" tự dựng của H (chưa từng lên
# GitHub). Bật biến test (origin cục bộ được nhận) thì bản giả này QUA: chứng minh ca dưới bị chặn đúng vì kiểm origin; như máy thật
# (LOCAL_ORIGIN=0, chỉ nhận GitHub) thì chặn.
forge_self_origin() {
  git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main && echo "def ok(): return $1" > "$WT/src/core.py" \
    && git -C "$WT" commit -qam "pr $1" && H=$(git -C "$WT" rev-parse HEAD) \
    && S=$(git -C "$REPO" commit-tree -p HEAD -m "fake squash (#$1)" "$H^{tree}") && git -C "$REPO" reset -q --hard "$S" \
    && git -C "$REPO" config remote.origin.url . && tool Bash "$(GATE_CMD "$1" "$H")" "$(GATE_OUT "$1" "$H")"
}
unforge() { git -C "$REPO" config remote.origin.url "$ORIGIN" && git -C "$REPO" fetch -q origin && git -C "$REPO" reset -q --hard origin/main \
  || { fail "restore after $1"; exit 1; }; }
turn_start; forge_self_origin 26 || fail "N11a setup"; stop; rc=$?; unforge N11a
[ "$rc" = 0 ] && ok "N11a self-origin forgery passes when local origins are allowed (control)" || fail "N11a control blocked ($(why $rc))"
turn_start; forge_self_origin 27 || fail "N11 setup"; LOCAL_ORIGIN=0 stop; rc=$?; unforge N11
blocked "$rc" && ok "N11 origin pointed at the repo itself (GitHub only): blocked" || fail "N11 self-origin accepted ($(why $rc))"
# N3f. --expect-head ngắn hơn 7 ký tự (khớp gần như mọi sha): chặn.
turn_start; H=$(new_pr 28) && land 28 && tool Bash "$(GATE_CMD 28 "${H:0:4}")" "$(GATE_OUT 28 "$H")" || fail "N3f setup"; stop; rc=$?
blocked "$rc" && ok "N3f 4-char --expect-head: blocked" || fail "N3f short prefix accepted ($(why $rc))"
# N3g. Một script cùng tên ở thư mục khác (in dòng giả): không phải merge gate của repo, chặn.
turn_start; H=$(new_pr 29) && land 29 && tool Bash "{\"command\": \"$TMP/x/.claude/bin/super-board-merge-gate.sh --pr 29 --expect-head $H\"}" "$(GATE_OUT 29 "$H")" || fail "N3g setup"; stop; rc=$?
blocked "$rc" && ok "N3g a same-named script elsewhere: blocked" || fail "N3g foreign script accepted ($(why $rc))"
# N13b. Như N12 nhưng lượt này đẩy thẳng lên main (git push … main): chặn.
turn_start; H=$(new_pr 30) && land 30 && tool Bash "$(GATE_CMD 30 "$H")" "$(GATE_OUT 30 "$H")" && new_pr 31 >/dev/null && land 31 \
  && tool Bash '{"command": "git push origin HEAD:main"}' "ok" || fail "N13b setup"; stop; rc=$?
blocked "$rc" && ok "N13b this turn pushed straight to main: blocked" || fail "N13b direct push accepted ($(why $rc))"
# N14. Bản ghi merge gate của lượt TRƯỚC (cùng transcript), squash vẫn trong cửa sổ lệch giờ: chặn.
turn_start; H=$(new_pr 32) && land 32 && tool Bash "$(GATE_CMD 32 "$H")" "$(GATE_OUT 32 "$H")" || fail "N14 setup"; sleep 1
python3 -c 'import datetime,json
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"việc khác"}}))' >> "$TR"; sleep 1; stop; rc=$?
blocked "$rc" && ok "N14 merge-gate record from the previous turn: blocked" || fail "N14 old record accepted ($(why $rc))"
# N13c/N13d. Như N12 nhưng lượt này có `git push` trần / `git push origin refs/heads/main` (đích không chắc là nhánh PR): chặn.
turn_start; H=$(new_pr 35) && land 35 && tool Bash "$(GATE_CMD 35 "$H")" "$(GATE_OUT 35 "$H")" && new_pr 36 >/dev/null && land 36 \
  && tool Bash '{"command": "git push"}' "ok" || fail "N13c setup"; stop; rc=$?
blocked "$rc" && ok "N13c a bare git push this turn: blocked" || fail "N13c bare push accepted ($(why $rc))"
turn_start; H=$(new_pr 37) && land 37 && tool Bash "$(GATE_CMD 37 "$H")" "$(GATE_OUT 37 "$H")" && new_pr 38 >/dev/null && land 38 \
  && tool Bash '{"command": "git push origin refs/heads/main"}' "ok" || fail "N13d setup"; stop; rc=$?
blocked "$rc" && ok "N13d git push origin refs/heads/main: blocked" || fail "N13d refs/heads/main push accepted ($(why $rc))"
# N3h. Xuống dòng là dấu tách lệnh của bash: lệnh merge gate + dòng sau in bản ghi giả, chặn.
turn_start; H=$(new_pr 39) && land 39 && tool Bash "{\"command\": \".claude/bin/super-board-merge-gate.sh --pr 39 --expect-head $H\\ncat /tmp/fake\"}" "$(GATE_OUT 39 "$H")" || fail "N3h setup"; stop; rc=$?
blocked "$rc" && ok "N3h newline-separated second command: blocked" || fail "N3h newline command accepted ($(why $rc))"
# N3i. Script merge gate của main bị sửa (chưa commit), cây xét là worktree sạch ở H: chặn.
turn_start; H=$(new_pr 40) && land 40 && git -C "$WT" checkout -q --detach "$H" && echo 'echo forged' >> "$REPO/.claude/bin/super-board-merge-gate.sh" \
  && tool Bash "{\"command\": \"cd $REPO && .claude/bin/super-board-merge-gate.sh --pr 40 --expect-head $H\"}" "$(GATE_OUT 40 "$H")" || fail "N3i setup"; stop "$WT"; rc=$?
git -C "$REPO" checkout -q -- .claude/bin/super-board-merge-gate.sh || { fail "restore after N3i"; exit 1; }
blocked "$rc" && ok "N3i the repo's merge-gate script edited: blocked" || fail "N3i edited script accepted ($(why $rc))"
# N3i'. Đối chứng: cùng lệnh, script nguyên vẹn: cho qua (N3i bị chặn đúng vì script bị sửa).
stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "N3i control: same call, script intact: allowed" || fail "N3i control blocked ($(why $rc))"
# N15. Hết hạn chót (PROOF_GATE_BUDGET_S=0): không kiểm gì tốn thời gian, chặn (hook bị giết = Stop lọt, nên hết giờ là chặn).
turn_start; H=$(new_pr 41) && land 41 && tool Bash "$(GATE_CMD 41 "$H")" "$(GATE_OUT 41 "$H")" || fail "N15 setup"; BUDGET=0 stop; rc=$?
blocked "$rc" && ok "N15 no time budget left: blocked" || fail "N15 accepted without budget ($(why $rc))"
# N3j. Lệnh trước đã `cd` sang thư mục có script giả cùng tên; lệnh merge gate dùng đường dẫn tương đối (cwd thật của lệnh): chặn.
turn_start; H=$(new_pr 42) && land 42 && mkdir -p "$TMP/x/.claude/bin" && printf '#!/bin/sh\necho forged\n' > "$TMP/x/.claude/bin/super-board-merge-gate.sh" \
  && chmod +x "$TMP/x/.claude/bin/super-board-merge-gate.sh" && CWD="$TMP/x" tool Bash "$(GATE_CMD 42 "$H")" "$(GATE_OUT 42 "$H")" || fail "N3j setup"; stop; rc=$?
blocked "$rc" && ok "N3j relative call from a cwd outside the repo: blocked" || fail "N3j call from foreign cwd accepted ($(why $rc))"
# N11b. Bật origin cục bộ (biến test) nhưng origin là ext:: (chạy lệnh tuỳ ý): vẫn chặn.
turn_start; H=$(new_pr 43) && land 43 && tool Bash "$(GATE_CMD 43 "$H")" "$(GATE_OUT 43 "$H")" && git -C "$REPO" config remote.origin.url "ext::sh -c true" \
  || fail "N11b setup"; stop; rc=$?
git -C "$REPO" config remote.origin.url "$ORIGIN" || { fail "restore after N11b"; exit 1; }
blocked "$rc" && ok "N11b ext:: origin with local origins allowed: blocked" || fail "N11b ext:: origin accepted ($(why $rc))"
# N16. Commit squash giả gắn vào đỉnh origin qua refs/replace (agent ghi được): chặn.
turn_start; H=$(new_pr 44) && git -C "$REPO" fetch -q origin && T=$(git -C "$REPO" rev-parse origin/main) \
  && S=$(git -C "$REPO" commit-tree -p "$T^" -m "fake squash (#44)" "$H^{tree}") \
  && F=$(git -C "$REPO" commit-tree -p "$S" -m "fake tip" "$H^{tree}") && git -C "$REPO" replace "$T" "$F" \
  && tool Bash "$(GATE_CMD 44 "$H")" "$(GATE_OUT 44 "$H")" || fail "N16 setup"; stop; rc=$?
git -C "$REPO" replace -d "$T" >/dev/null || { fail "restore after N16"; exit 1; }
blocked "$rc" && ok "N16 fake squash grafted onto origin's tip via refs/replace: blocked" || fail "N16 refs/replace forgery accepted ($(why $rc))"
# N13e. Main đứng đúng ở S (không cần phần nới) nhưng lượt này còn gộp / đẩy thẳng ngoài merge gate: chặn, mỗi dạng một lần.
n=45
for cmd in "gh pr merge 99 --squash" "git push origin main" "git push -f origin main" "git push origin +HEAD:main" "git push origin pr-x:main" \
           "git -C /r push origin main" "git push origin feature main" "gh api -X PUT repos/o/r/pulls/25/merge"; do
  turn_start; H=$(new_pr $n) && land $n && tool Bash "$(GATE_CMD $n "$H")" "$(GATE_OUT $n "$H")" \
    && tool Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$cmd")" "ok" || fail "N13e setup ($cmd)"; stop; rc=$?
  blocked "$rc" && ok "N13e '$cmd' this turn, main at S: blocked" || fail "N13e '$cmd' accepted ($(why $rc))"
  n=$((n + 1))
done
# N13g. Gộp thẳng qua một công cụ MCP (không phải Bash): chặn.
turn_start; H=$(new_pr 60) && land 60 && tool Bash "$(GATE_CMD 60 "$H")" "$(GATE_OUT 60 "$H")" \
  && tool mcp__github__merge_pull_request '{"pullNumber": 61}' "merged" || fail "N13g setup"; stop; rc=$?
blocked "$rc" && ok "N13g MCP merge_pull_request this turn: blocked" || fail "N13g MCP merge accepted ($(why $rc))"
# N13h. Subagent của phiên gộp thẳng (transcript subagents/*.jsonl): chặn.
SUB="${TR%.jsonl}/subagents"
turn_start; H=$(new_pr 62) && land 62 && tool Bash "$(GATE_CMD 62 "$H")" "$(GATE_OUT 62 "$H")" && mkdir -p "$SUB" \
  && tool Bash '{"command": "gh pr merge 63 --squash"}' "ok" && tail -2 "$TR" > "$SUB/agent-a1.jsonl" \
  && python3 - "$TR" <<'PY' || fail "N13h setup"
import sys
p = sys.argv[1]; lines = open(p).read().splitlines(True); open(p, "w").writelines(lines[:-2])   # chỉ subagent giữ lần gộp thẳng
PY
stop; rc=$?; rm -rf "${TR%.jsonl}"
blocked "$rc" && ok "N13h a subagent merged directly: blocked" || fail "N13h subagent merge accepted ($(why $rc))"
# N7c. File của phiên ở main tạo qua Bash (nhánh so chữ của untouched_by_session): chặn.
turn_start; H=$(new_pr 64) && land 64 && tool Bash "$(GATE_CMD 64 "$H")" "$(GATE_OUT 64 "$H")" \
  && mkdir -p "$REPO/docs" && echo "x" > "$REPO/docs/own.md" && tool Bash '{"command": "echo x > docs/own.md"}' "" || fail "N7c setup"; stop; rc=$?
rm -f "$REPO/docs/own.md"
blocked "$rc" && ok "N7c main dirty with a file this session wrote via Bash: blocked" || fail "N7c Bash-written own file accepted ($(why $rc))"
# N13i. Nhánh mặc định của origin tên khác (develop): lệnh đẩy thẳng lên nó (trông như nhánh PR) vẫn bị chặn.
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/develop && git -C "$REPO" push -q origin "refs/remotes/origin/main:refs/heads/develop" || fail "N13i setup (develop)"
turn_start; H=$(new_pr 66) && land 66 && git -C "$GH" push -q origin main:develop && tool Bash "$(GATE_CMD 66 "$H")" "$(GATE_OUT 66 "$H")" \
  && tool Bash '{"command": "git push origin develop"}' "ok" && git -C "$REPO" fetch -q origin || fail "N13i setup"; stop; rc=$?
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main || { fail "restore after N13i"; exit 1; }
blocked "$rc" && ok "N13i push to a default branch named develop: blocked" || fail "N13i push to develop accepted ($(why $rc))"
# N15b. PROOF_GATE_BUDGET_S hỏng (không phải số / nan): hook không chết (chết = wrapper exit 0 = Stop lọt), chạy với hạn chót mặc định.
n=70
for b in abc nan; do
  turn_start; H=$(new_pr $n) && land $n && tool Bash "$(GATE_CMD $n "$H")" "$(GATE_OUT $n "$H")" || fail "N15b setup ($b)"; BUDGET=$b stop; rc=$?
  [ "$rc" = 0 ] && grep -q "merge-gate pr=$n" "$REPO/.claude/audit-gate/proof_gate.log" \
    && ok "N15b PROOF_GATE_BUDGET_S=$b: default budget, merged turn allowed" || fail "N15b budget=$b mishandled ($(why $rc))"
  n=$((n + 1))
done

# (a) Biên nhận --full của worktree (gate chạy trong worktree ở lượt này), cùng cây với main sau squash.
wt_gate() { CLAUDE_PROJECT_DIR="$WT" python3 "$GATE" --run-tests --full --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1 \
  || { fail "setup: gate --full in the worktree exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; return 1; }
  rm -rf "$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/tree_receipts"; }   # kho theo cây (#105) có test riêng: ở đây chỉ luật (a)
# A1. Không bản ghi merge gate, main = squash của cây worktree đã gate trong lượt: cho qua.
turn_start; new_pr 13 >/dev/null && wt_gate && land 13 || fail "A1 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "A1 worktree --full receipt this turn for main's tree: allowed" || fail "A1 worktree receipt refused ($(why $rc))"
# A2. Biên nhận đó từ lượt trước: chặn.
sleep 4; turn_start; stop; rc=$?
blocked "$rc" && ok "A2 worktree receipt from an earlier turn: blocked" || fail "A2 old worktree receipt accepted ($(why $rc))"
# A3. Worktree đổi sau biên nhận (dấu vân tay không khớp): chặn.
turn_start; new_pr 14 >/dev/null && wt_gate && land 14 && echo "# sau gate" >> "$WT/src/core.py" || fail "A3 setup"; stop; rc=$?
git -C "$WT" checkout -q -- src/core.py
blocked "$rc" && ok "A3 worktree changed after its receipt: blocked" || fail "A3 stale worktree receipt accepted ($(why $rc))"
# A4. Cây worktree đã gate khác cây main (main chưa nhận squash): chặn.
turn_start; new_pr 15 >/dev/null && wt_gate || fail "A4 setup"; stop; rc=$?
blocked "$rc" && ok "A4 receipt tree differs from main's tree: blocked" || fail "A4 other tree accepted ($(why $rc))"
# A5. Worktree sạch nhưng đã commit thêm sau biên nhận (biên nhận của cây khác), squash của cây mới lên main: chặn.
turn_start; new_pr 16 >/dev/null && wt_gate && echo "# sau gate" >> "$WT/src/core.py" && git -C "$WT" commit -qam "pr 16 more" \
  && git -C "$WT" push -q origin "HEAD:refs/heads/pr-16" && land 16 || fail "A5 setup"; stop; rc=$?
blocked "$rc" && ok "A5 receipt of an earlier commit of the worktree: blocked" || fail "A5 receipt of another tree accepted ($(why $rc))"
# A6/A7. Như A1 nhưng biên nhận của worktree là gate ĐỎ (exit 1) / là bản chép (carried_from): chặn.
receipt_set() { python3 - "$WT_RECEIPT" "$1" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); k, v = sys.argv[2].split("=", 1); r[k] = json.loads(v); json.dump(r, open(sys.argv[1], "w"))
PY
}
turn_start; new_pr 33 >/dev/null && wt_gate && land 33 && receipt_set 'exit=1' || fail "A6 setup"; stop; rc=$?
blocked "$rc" && ok "A6 worktree receipt of a red gate: blocked" || fail "A6 red receipt accepted ($(why $rc))"
turn_start; new_pr 34 >/dev/null && wt_gate && land 34 && receipt_set 'carried_from="/x"' || fail "A7 setup"; stop; rc=$?
blocked "$rc" && ok "A7 carried worktree receipt: blocked" || fail "A7 carried receipt accepted ($(why $rc))"
# A8. Biên nhận trong git dir của worktree nhưng "project" trỏ sang main (cùng nội dung): không phải biên nhận của worktree đó, chặn.
turn_start; new_pr 65 >/dev/null && wt_gate && land 65 && receipt_set "project=\"$REPO\"" || fail "A8 setup"; stop; rc=$?
blocked "$rc" && ok "A8 worktree receipt naming another project: blocked" || fail "A8 mismatched receipt accepted ($(why $rc))"
# A9. Biên nhận của một lần DÙNG LẠI (tested_at cũ, không chạy suite): chặn.
turn_start; new_pr 67 >/dev/null && wt_gate && land 67 && receipt_set "tested_at=$(( $(date +%s) - 600 ))" || fail "A9 setup"; stop; rc=$?
blocked "$rc" && ok "A9 receipt of a reused run (old tested_at): blocked" || fail "A9 reused receipt accepted ($(why $rc))"
rm -f "$WT_RECEIPT"

if [ "$FAILS" -ne 0 ]; then echo "proof gate merged trunk: $FAILS FAILED"; exit 1; fi
echo "proof gate merged trunk: all checks passed"
