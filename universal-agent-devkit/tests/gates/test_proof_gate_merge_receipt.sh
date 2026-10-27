#!/usr/bin/env bash
# Test hồi quy: hooks/proof_gate.sh nhận BIÊN NHẬN MERGE của super-board-merge-gate.sh (<git common dir>/postfix-gate/merge_receipts) làm
# bằng chứng cổng ở trunk mode (27/10, proof_gate.log của main: "task-push check: this turn pushed outside a PR branch push" rồi block).
# Lượt đó làm đúng luật mới (gate impacted, PR gộp qua merge gate), nhưng mọi đường cũ trượt: push `git push -u origin X 2>&1 | tail -4`
# bị regex push tách thành "… 2>" (lượt bị đánh "đẩy ngoài nhánh PR"), merge gate chạy NỀN ghi output vào file nên không có dòng
# "merged <H>" trong tool_result. Biên nhận (pr, head, base gate kiểm, cây gate kiểm, session) được nhận khi git chứng thực: origin THẬT
# có squash S với S^1 = base và cây S = cây gate kiểm; cây xét đứng ở H / S, hoặc là con cháu S trên origin mà mọi commit giữa là squash
# có biên nhận; chỉ bẩn file phiên này không đụng. Biên nhận ở đây dựng tay đúng schema của merge gate; ca đầu-cuối với merge gate THẬT:
# tests/super-board/test_merge_gate_proof_receipt.sh (ở repo chứa super-board). Mỗi ca chặn chỉ khác ca cho qua đúng một biến.
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

turn_start() { rm -rf "$STORE"; python3 -c 'import datetime,json
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
bash_cmd() { tool Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")" "$2" "${3:-}"; }
# Các lệnh của lượt thật 27/10: push nhánh PR qua pipe, xoá nhánh bị guard chặn, merge gate chạy nền ghi vào file.
incident_cmds() {
  bash_cmd "git push -u origin pr-$1 2>&1 | tail -4" "branch 'pr-$1' set up to track 'origin/pr-$1'." \
    && bash_cmd "git push origin --delete old-$1" "BLOCKED by block-dangerous-git" err \
    && bash_cmd ".claude/bin/super-board-merge-gate.sh --config c.json --pr $1 --expect-head $2 --standalone > $TMP/mg-$1.log 2>&1; echo \"exit=\$?\" >> $TMP/mg-$1.log" \
                "Command running in background with ID: b$1"
}

# new_pr N: commit H của worktree trên đỉnh origin/main, đẩy lên origin/pr-N. In H.
new_pr() {
  git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main \
    && echo "def ok(): return $1  # pr $1" > "$WT/src/core.py" && git -C "$WT" commit -qam "pr $1" \
    && git -C "$WT" push -q origin "HEAD:refs/heads/pr-$1" && git -C "$WT" rev-parse HEAD
}
# receipt N H [session] [k=json …]: biên nhận như merge gate ghi khi verify xong (base = origin/main lúc đó, cây = gộp base vào H).
receipt() {
  local n="$1" h="$2" sid="${3-s-m}"; shift 3 2>/dev/null || shift $#   # ${3-…}: "" là session rỗng (ca N4b), không phải mặc định
  git -C "$REPO" fetch -q origin || return 1
  local b t; b=$(git -C "$REPO" rev-parse origin/main) && t=$(git -C "$REPO" merge-tree --write-tree "$b" "$h") || return 1
  mkdir -p "$STORE" && python3 - "$STORE/$n-$h.json" "$n" "$h" "$b" "$t" "$sid" "$@" <<'PY'
import json, sys, time
p, n, h, b, t, sid = sys.argv[1:7]
r = {"pr": int(n), "head": h, "base": b, "verified_tree": t, "squash": None, "time": time.time(), "session": sid}
for kv in sys.argv[7:]:
    k, v = kv.split("=", 1); r[k] = json.loads(v)
json.dump(r, open(p, "w"))
PY
}
# land N: GitHub squash pr-N vào main, rồi main local nhận nó (git pull --ff-only).
land() {
  ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 \
    && git commit -qm "squash pr $1 (#$1)" && git push -q origin main ) && git -C "$REPO" pull -q --ff-only origin main
}
direct_push() {   # một commit đẩy thẳng lên origin main, không qua merge gate
  ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && mkdir -p docs && echo "$1" > "docs/$1.md" && git add -A \
    && git commit -qm "direct $1" && git push -q origin main ) && git -C "$REPO" pull -q --ff-only origin main
}
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "${1:-$REPO}/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã gộp PR qua merge gate. Gate exit 0, ảnh: không cần — backend
$REPORT" "${SID:-s-m}" | PROOF_GATE_ALLOW_LOCAL_ORIGIN="${LOCAL_ORIGIN:-1}" PROOF_GATE_BUDGET_S="${BUDGET:-9}" CLAUDE_PROJECT_DIR="${1:-$REPO}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ')"; }
LOG="$REPO/.claude/audit-gate/proof_gate.log"

# P1. Ca thật 27/10: lệnh push qua pipe + xoá nhánh bị chặn + merge gate nền; biên nhận của phiên; main = S, còn file bẩn của phiên khác.
turn_start; H=$(new_pr 1) && incident_cmds 1 "$H" && receipt 1 "$H" && land 1 && echo y > "$REPO/docs/foreign.md" || fail "P1 setup"
rm -f "$LOG"; stop; rc=$?
[ "$rc" = 0 ] && ok "P1 merge receipt of this session, main at its squash, foreign dirty file: XONG allowed" || fail "P1 merged turn blocked ($(why $rc))"
grep -q "merge-receipt pr=1" "$LOG" 2>/dev/null && ok "P1b allowed through the merge-receipt rule (logged)" || fail "P1b no merge-receipt log line"
rm -f "$REPO/docs/foreign.md"
# P1c. Đối chứng: cùng lượt KHÔNG có biên nhận (như trước bản sửa): chặn (đường cũ trượt đúng như sự cố).
rm -rf "$STORE"; stop; rc=$?
blocked "$rc" && ok "P1c same turn without the receipt: blocked (the incident)" || fail "P1c accepted without a receipt ($(why $rc))"

# P2. PR của phiên khác gộp qua merge gate SAU S (biên nhận của nó), main theo origin: cho qua.
turn_start; H=$(new_pr 2) && incident_cmds 2 "$H" && receipt 2 "$H" && land 2 && H3=$(new_pr 3) && receipt 3 "$H3" other && land 3 || fail "P2 setup"
stop; rc=$?
[ "$rc" = 0 ] && ok "P2 another session's gated PR landed after S: allowed" || fail "P2 later gated foreign merge blocked ($(why $rc))"

# P3. Cây xét là worktree của phiên, còn đứng ở H, sạch: cho qua.
turn_start; H=$(new_pr 4) && receipt 4 "$H" && land 4 || fail "P3 setup"; stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "P3 the session's worktree at H, clean: allowed" || fail "P3 worktree at H blocked ($(why $rc))"

# N1. Biên nhận ghi TRƯỚC lượt này: chặn.
turn_start; H=$(new_pr 5) && receipt 5 "$H" s-m "time=$(( $(date +%s) - 600 ))" && land 5 || fail "N1 setup"; stop; rc=$?
blocked "$rc" && ok "N1 receipt written before the turn: blocked" || fail "N1 old receipt accepted ($(why $rc))"

# N2. Biên nhận có, nhưng squash chưa lên origin (PR chưa gộp): chặn.
turn_start; H=$(new_pr 6) && receipt 6 "$H" || fail "N2 setup"; stop; rc=$?
blocked "$rc" && ok "N2 squash not on origin: blocked" || fail "N2 unmerged PR accepted ($(why $rc))"

# N3. Main bẩn đúng file phiên này sửa (Write): chặn.
turn_start; H=$(new_pr 7) && receipt 7 "$H" && land 7 && echo x > "$REPO/docs/own.md" \
  && tool Write "{\"file_path\": \"$REPO/docs/own.md\", \"content\": \"x\"}" || fail "N3 setup"; stop; rc=$?
rm -f "$REPO/docs/own.md"
blocked "$rc" && ok "N3 main dirty with this session's file: blocked" || fail "N3 own dirty file accepted ($(why $rc))"

# N4. Biên nhận của phiên KHÁC (dòng merge của PR phiên khác): chặn.
turn_start; H=$(new_pr 8) && receipt 8 "$H" other && land 8 || fail "N4 setup"; stop; rc=$?
blocked "$rc" && ok "N4 receipt of another session: blocked" || fail "N4 foreign receipt accepted ($(why $rc))"
# N4b. Biên nhận không có session (môi trường không có id phiên): chặn.
turn_start; H=$(new_pr 9) && receipt 9 "$H" "" && land 9 || fail "N4b setup"; stop; rc=$?
blocked "$rc" && ok "N4b receipt without a session id: blocked" || fail "N4b session-less receipt accepted ($(why $rc))"

# N5. Sau S có một commit đẩy thẳng lên main (không biên nhận), main kéo về: chặn.
turn_start; H=$(new_pr 10) && receipt 10 "$H" && land 10 && direct_push d10 && bash_cmd "git push origin HEAD:main" "ok" || fail "N5 setup"; stop; rc=$?
blocked "$rc" && ok "N5 an ungated commit on main after S: blocked" || fail "N5 direct push after S accepted ($(why $rc))"
# N5b. Như N5 nhưng commit đẩy thẳng mang ngày commit giả từ trước lượt: vẫn chặn (xét theo tổ tiên, không theo giờ).
turn_start; H=$(new_pr 11) && receipt 11 "$H" && land 11 \
  && ( cd "$GH" && git fetch -q origin && git reset -q --hard origin/main && mkdir -p docs && echo d > docs/d11.md && git add -A \
       && GIT_COMMITTER_DATE="@$(( $(date +%s) - 7200 )) +0000" git commit -qm "direct d11" && git push -q origin main ) \
  && git -C "$REPO" pull -q --ff-only origin main || fail "N5b setup"; stop; rc=$?
blocked "$rc" && ok "N5b a back-dated ungated commit after S: blocked" || fail "N5b back-dated direct push accepted ($(why $rc))"

# N6. Một commit chưa qua gate lên origin giữa lúc verify và lúc gộp (S^1 khác base gate kiểm): chặn.
turn_start; H=$(new_pr 12) && receipt 12 "$H" && direct_push d12 && land 12 || fail "N6 setup"; stop; rc=$?
blocked "$rc" && ok "N6 squash parent differs from the verified base: blocked" || fail "N6 unverified base accepted ($(why $rc))"

# N7. Main có commit riêng chưa lên origin sau squash: chặn.
turn_start; H=$(new_pr 13) && receipt 13 "$H" && land 13 && echo z > "$REPO/docs/local.md" && git -C "$REPO" add docs/local.md \
  && git -C "$REPO" commit -qm local || fail "N7 setup"; stop; rc=$?
git -C "$REPO" reset -q --hard origin/main || { fail "restore after N7"; exit 1; }
blocked "$rc" && ok "N7 main ahead of origin: blocked" || fail "N7 unpushed main commit accepted ($(why $rc))"

# N8. Trunk mode tắt: chặn.
turn_start; H=$(new_pr 14) && receipt 14 "$H" && land 14 || fail "N8 setup"
git -C "$REPO" config devkit.trunkMode false; stop; rc=$?; git -C "$REPO" config --unset devkit.trunkMode || { fail "restore after N8"; exit 1; }
blocked "$rc" && ok "N8 trunk mode off: blocked" || fail "N8 accepted with trunk mode off ($(why $rc))"

# N9. Biên nhận hỏng: pr là bool / head khác tên file / time là chuỗi / cây gate kiểm khác: chặn, mỗi dạng một lần.
n=15
for bad in 'pr=true' 'head="0123456789abcdef0123456789abcdef01234567"' 'time="now"' 'verified_tree="0123456789abcdef0123456789abcdef01234567"'; do
  turn_start; H=$(new_pr $n) && receipt $n "$H" s-m "$bad" && land $n || fail "N9 setup ($bad)"; stop; rc=$?
  blocked "$rc" && ok "N9 malformed receipt ($bad): blocked" || fail "N9 malformed receipt ($bad) accepted ($(why $rc))"
  n=$((n + 1))
done

# N10. Lượt này còn gộp thẳng (gh pr merge) ngoài merge gate: chặn.
turn_start; H=$(new_pr 20) && receipt 20 "$H" && land 20 && bash_cmd "gh pr merge 99 --squash" "merged" || fail "N10 setup"; stop; rc=$?
blocked "$rc" && ok "N10 gh pr merge this turn: blocked" || fail "N10 direct gh merge accepted ($(why $rc))"
# N10b. Gộp qua công cụ MCP: chặn.
turn_start; H=$(new_pr 21) && receipt 21 "$H" && land 21 && tool mcp__github__merge_pull_request '{"pullNumber": 61}' "merged" || fail "N10b setup"; stop; rc=$?
blocked "$rc" && ok "N10b MCP merge_pull_request this turn: blocked" || fail "N10b MCP merge accepted ($(why $rc))"

# N11. Phiên tự ghi vào kho biên nhận merge: chặn.
turn_start; H=$(new_pr 22) && receipt 22 "$H" && land 22 && bash_cmd "cp /tmp/r.json .git/postfix-gate/merge_receipts/22-$H.json" "" || fail "N11 setup"; stop; rc=$?
blocked "$rc" && ok "N11 this session wrote into merge_receipts: blocked" || fail "N11 hand-written receipt accepted ($(why $rc))"

# N12. squash ghi trong biên nhận khác commit gộp thật: chặn.
turn_start; H=$(new_pr 23) && receipt 23 "$H" s-m 'squash="0123456789abcdef0123456789abcdef01234567"' && land 23 || fail "N12 setup"; stop; rc=$?
blocked "$rc" && ok "N12 receipt names another squash commit: blocked" || fail "N12 squash mismatch accepted ($(why $rc))"
# P4. squash ghi trong biên nhận đúng commit gộp thật: cho qua.
turn_start; H=$(new_pr 24) && receipt 24 "$H" && land 24 \
  && python3 - "$STORE/24-$H.json" "$(git -C "$REPO" rev-parse HEAD)" <<'PY' || fail "P4 setup"
import json, sys
r = json.load(open(sys.argv[1])); r["squash"] = sys.argv[2]; json.dump(r, open(sys.argv[1], "w"))
PY
stop; rc=$?
[ "$rc" = 0 ] && ok "P4 receipt names the real squash: allowed" || fail "P4 matching squash blocked ($(why $rc))"

# N13. Origin không phải GitHub (như máy thật: biến test tắt): chặn.
turn_start; H=$(new_pr 25) && receipt 25 "$H" && land 25 || fail "N13 setup"; LOCAL_ORIGIN=0 stop; rc=$?
blocked "$rc" && ok "N13 non-GitHub origin on a real machine: blocked" || fail "N13 local origin accepted ($(why $rc))"
# N14. Hết hạn chót: chặn.
turn_start; H=$(new_pr 26) && receipt 26 "$H" && land 26 || fail "N14 setup"; BUDGET=0 stop; rc=$?
blocked "$rc" && ok "N14 no time budget: blocked" || fail "N14 accepted without budget ($(why $rc))"
# N15. Worktree của phiên ở H nhưng sửa thêm chưa commit: chặn.
turn_start; H=$(new_pr 27) && receipt 27 "$H" && land 27 && echo "def ok(): return 99" > "$WT/src/core.py" || fail "N15 setup"; stop "$WT"; rc=$?
git -C "$WT" checkout -q -- src/core.py
blocked "$rc" && ok "N15 worktree edited after the merge: blocked" || fail "N15 dirty worktree accepted ($(why $rc))"

# P5 (plan review T0062). Lượt sửa chính proof_gate (Edit nhắc kho trong nội dung), commit / mở PR có chữ merge_receipts và gh pr merge
# trong chuỗi trích dẫn, grep kho: không phải ghi vào kho, không phải gộp thẳng: cho qua.
turn_start; H=$(new_pr 28) && receipt 28 "$H" && land 28 \
  && tool Edit "{\"file_path\": \"$REPO/src/core.py\", \"old_string\": \"a\", \"new_string\": \"merge_receipts gh pr merge\"}" "ok" \
  && bash_cmd 'git commit -qm "hooks: đọc postfix-gate/merge_receipts thay cho gh pr merge"' "ok" \
  && bash_cmd 'gh pr create --title "x" --body "cấm gh pr merge; kho .git/postfix-gate/merge_receipts"' "https://x/pull/1" \
  && bash_cmd 'grep -rn merge_receipts .git/postfix-gate | head -3' "" || fail "P5 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "P5 edits / commit / PR text naming the store or gh pr merge: allowed" || fail "P5 quoted mentions blocked ($(why $rc))"
# N10c. gh pr merge có cờ chen giữa (gh pr --repo o/r merge): chặn.
turn_start; H=$(new_pr 29) && receipt 29 "$H" && land 29 && bash_cmd "gh pr --repo o/r merge 77 --squash" "merged" || fail "N10c setup"; stop; rc=$?
blocked "$rc" && ok "N10c gh pr --repo o/r merge: blocked" || fail "N10c flagged gh merge accepted ($(why $rc))"
# N16. Phiên ghi vào kho biên nhận ở lượt TRƯỚC (biên nhận ghi trước, time tương lai), lượt này báo XONG: chặn.
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=30)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"lượt trước"}}))
print(json.dumps({"type":"assistant","timestamp":t,"cwd":"/","message":{"role":"assistant","content":[{"type":"tool_use","id":"old1","name":"Write",
  "input":{"file_path":"'"$STORE"'/30-x.json","content":"{}"}}]}}))' > "$TMP/prev.jsonl"
turn_start; H=$(new_pr 30) && receipt 30 "$H" && land 30 && cat "$TR" >> "$TMP/prev.jsonl" && mv "$TMP/prev.jsonl" "$TR" || fail "N16 setup"; stop; rc=$?
blocked "$rc" && ok "N16 a Write into the receipt store in an earlier turn: blocked" || fail "N16 earlier store write accepted ($(why $rc))"
# P6 (plan review T0062). PR chậm hơn base: gate đẩy merge commit M = [H0, base] lên nhánh PR rồi gộp M; worktree của phiên vẫn ở H0: cho qua.
turn_start; git -C "$WT" fetch -q origin && git -C "$WT" checkout -q --detach origin/main && mkdir -p "$WT/docs" && echo p31 > "$WT/docs/p31.md" \
  && git -C "$WT" add docs/p31.md && git -C "$WT" commit -qm "pr 31" && git -C "$WT" push -q origin "HEAD:refs/heads/pr-31" \
  && H0=$(git -C "$WT" rev-parse HEAD) && new_pr 32 >/dev/null && land 32 && git -C "$REPO" fetch -q origin \
  && B=$(git -C "$REPO" rev-parse origin/main) && T=$(git -C "$REPO" merge-tree --write-tree "$B" "$H0") \
  && M=$(git -C "$REPO" commit-tree -p "$H0" -p "$B" -m "Merge main into pr-31" "$T") && git -C "$REPO" push -q -f origin "$M:refs/heads/pr-31" \
  && receipt 31 "$M" && land 31 && git -C "$WT" checkout -q --detach "$H0" || fail "P6 setup"; stop "$WT"; rc=$?
[ "$rc" = 0 ] && ok "P6 worktree at the reviewed head, gate merged [H0, base]: allowed" || fail "P6 reviewed head blocked ($(why $rc))"
# N17. Như P6 nhưng worktree ở một commit khác (không phải cha thứ nhất của M): chặn.
git -C "$WT" checkout -q --detach "$B" || fail "N17 setup"; stop "$WT"; rc=$?
blocked "$rc" && ok "N17 worktree at a commit that is not the merge commit's first parent: blocked" || fail "N17 wrong head accepted ($(why $rc))"

# N18 (plan review r1). Worktree của phiên còn ở H, nhưng origin nhận một commit đẩy thẳng (không biên nhận) sau S: chặn.
turn_start; H=$(new_pr 33) && receipt 33 "$H" && land 33 && direct_push d33 && git -C "$WT" checkout -q --detach "$H" || fail "N18 setup"; stop "$WT"; rc=$?
blocked "$rc" && ok "N18 session worktree at H, origin has an ungated commit after S: blocked" || fail "N18 later direct push accepted ($(why $rc))"
# N19. Ghi vào kho bằng thân heredoc của python / bash, và bằng đường dẫn tương đối từ thư mục khác: chặn, mỗi dạng một lần.
n=34
for cmd in "python3 - <<'PY'
open('$STORE/x.json', 'w').write('{}')
PY" "bash <<'SH'
cat > $STORE/x.json
SH" "cd $STORE && echo {} > x.json" "cd $REPO/docs && cp x ../.git/postfix-gate/merge_receipts/y.json"; do
  turn_start; H=$(new_pr $n) && receipt $n "$H" && land $n && bash_cmd "$cmd" "" || fail "N19 setup ($n)"; stop; rc=$?
  blocked "$rc" && ok "N19 store write form $n: blocked" || fail "N19 store write form $n accepted ($(why $rc))"
  n=$((n + 1))
done
# P7 (plan review r1). Công cụ điều phối (pm_task_create / pm_plan: chữ nhắc kho trong brief) và grep kho: không phải ghi vào kho: cho qua.
turn_start; H=$(new_pr 40) && receipt 40 "$H" && land 40 \
  && tool mcp__antigravity-pm__pm_task_create '{"title": "t", "brief": "ghi biên nhận vào postfix-gate/merge_receipts, gh pr merge cấm"}' "ok" \
  && tool mcp__antigravity-pm__pm_plan '{"taskId": "T1", "content": "đọc merge_receipts"}' "ok" || fail "P7 setup"; stop; rc=$?
[ "$rc" = 0 ] && ok "P7 orchestration tools naming the store in text: allowed" || fail "P7 orchestration text blocked ($(why $rc))"

if [ "$FAILS" -ne 0 ]; then echo "proof gate merge receipt: $FAILS FAILED"; exit 1; fi
echo "proof gate merge receipt: all checks passed"
