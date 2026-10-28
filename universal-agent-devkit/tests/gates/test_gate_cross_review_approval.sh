#!/usr/bin/env bash
# #605 (lane A): test có sẵn bị sửa chỉ được duyệt CHÉO — agent khác (Antigravity /giao audit, phiên reviewer) ghi
# .claude/audit-gate/approved_tests.json dạng {"approvals": [{path, sha256, reviewer, author, task_id, reason}]}.
# Gate nhận khi reviewer != author (và != DEVKIT_AGENT_ID), sha256 khớp nội dung hiện tại, đủ 6 trường chuỗi khác rỗng.
# Tự duyệt (--auto-approve-tests, DEVKIT_AUTO_APPROVE_TESTS=1, dòng `AUTO-APPROVE:`) và dạng cũ không nguồn (list,
# {path: sha256}) không còn duyệt: exit 2; dạng cũ in "cần duyệt lại" kèm path + sha256 hiện tại (#534 mục 3, #576).
# Audit T0066: mục duyệt và trailer chỉ tính khi antigravity-pm (ngoài repo) ghi audit pass kèm `auditedHead: <sha40>` trong
# verdicts.audit.notes, và nội dung hiện tại của test đúng bằng blob của nó ở auditedHead (chặn tự ghi file duyệt, chặn replay task_id).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID
export HOME="$TMP/home"   # HOME riêng: không quét transcript / log Antigravity thật
mkdir -p "$HOME/.claude/projects"
FAILS=0
# Biên bản antigravity-pm giả, ngoài repo (như push_gate.audited_head đọc); nằm dưới $TMP nên không chạm ~/.antigravity-pm thật.
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
pm_task() {   # pm_task <task-id> <project> <verdict> [auditedHead]: notes ghi `auditedHead: <sha>` khi có đối số 4
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","verdicts":{"audit":{"verdict":"%s","round":1,"reviewer":"pm","notes":"%s"}}}\n' "$1" "$2" "$3" \
    "${4:+audit ok\\nauditedHead: $4}" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/src" "$R/tests" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf '.claude/audit-gate/\n' > .gitignore
mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh"}]}]}
JSON
echo 'fun ok()=1' > src/Core.kt
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
git add -A && git commit -qm init
# sửa test có sẵn (không phải nối thêm) + sửa code
printf '#!/bin/sh\nexit 0\n' > tests/test_old.sh
echo 'fun ok()=2' > src/Core.kt
SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' tests/test_old.sh)"
APPR="$R/.claude/audit-gate/approved_tests.json"; mkdir -p "$(dirname "$APPR")"
TR="$TMP/tr/session.jsonl"; mkdir -p "$(dirname "$TR")"; : > "$TR"
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang vi --run-tests --transcript "$TR" "$@" 2>&1)"; RC=$?; }
entry() {   # entry <sha> <reviewer> <author> <task_id>
  printf '{"approvals": [{"path": "tests/test_old.sh", "sha256": "%s", "reviewer": "%s", "author": "%s", "task_id": "%s", "reason": "chỉ đổi true thành exit 0, không nới assertion"}]}\n' "$1" "$2" "$3" "$4" > "$APPR"
}
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }

# 1. (d) duyệt chéo hợp lệ (audit pass, auditedHead = cây hiện tại) -> exit 0, dòng duyệt ghi reviewer + task_id,
# không phải "người dùng" hay "agent tự duyệt". `git stash create`: commit của cây làm việc, không đổi index/HEAD/refs.
pm_task T605 "$R" pass "$(git stash create)"
entry "$SHA" antigravity claude-lane-a T605
run_gate
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity" && has "T605" && ! has "agent tự duyệt"; then ok "1: duyệt chéo hợp lệ -> exit 0, in reviewer + task_id"
else bad "1: duyệt chéo hợp lệ: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 2. reviewer == author (khác hoa/thường, có khoảng trắng) -> exit 2, nói rõ lý do
entry "$SHA" " Claude-Lane-A" claude-lane-a T605
run_gate
if [ "$RC" = 2 ] && has "reviewer trùng author"; then ok "2: reviewer == author -> exit 2 (reviewer trùng author)"
else bad "2: reviewer == author: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 3. DEVKIT_AGENT_ID (agent đang chạy gate) == reviewer -> exit 2
entry "$SHA" antigravity claude-lane-a T605
OUT="$(DEVKIT_AGENT_ID=Antigravity CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang vi --run-tests --transcript "$TR" 2>&1)"; RC=$?
if [ "$RC" = 2 ] && has "reviewer trùng author"; then ok "3: DEVKIT_AGENT_ID == reviewer -> exit 2"
else bad "3: DEVKIT_AGENT_ID == reviewer: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 4. sha256 lệch nội dung hiện tại -> exit 2
entry "0000000000000000000000000000000000000000000000000000000000000000" antigravity claude-lane-a T605
run_gate
if [ "$RC" = 2 ] && has "sha256 lệch"; then ok "4: sha256 lệch -> exit 2"
else bad "4: sha256 lệch: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 5. dạng cũ {path: sha256} đúng nội dung, không nguồn -> exit 2, "cần duyệt lại" + path + sha hiện tại
printf '{"tests/test_old.sh": "%s"}\n' "$SHA" > "$APPR"
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại" && has "tests/test_old.sh" && has "$SHA"; then ok "5: dạng cũ {path: sha} -> exit 2, cần duyệt lại + path + sha"
else bad "5: dạng cũ {path: sha}: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 6. dạng cũ list -> exit 2, cần duyệt lại
printf '["tests/test_old.sh"]\n' > "$APPR"
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại" && has "$SHA"; then ok "6: dạng cũ list -> exit 2, cần duyệt lại"
else bad "6: dạng cũ list: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 7. mục thiếu trường (task_id rỗng) -> exit 2, cần duyệt lại (fail-closed)
entry "$SHA" antigravity claude-lane-a ""
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại"; then ok "7: mục thiếu task_id -> exit 2, cần duyệt lại"
else bad "7: mục thiếu task_id: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 8. --auto-approve-tests một mình (không file duyệt) -> vẫn exit 2, in tự duyệt bị từ chối
rm -f "$APPR"
run_gate --auto-approve-tests
if [ "$RC" = 2 ] && has "tự duyệt bị từ chối"; then ok "8: --auto-approve-tests -> exit 2 (tự duyệt bị từ chối)"
else bad "8: --auto-approve-tests: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 9. DEVKIT_AUTO_APPROVE_TESTS=1 -> vẫn exit 2
OUT="$(DEVKIT_AUTO_APPROVE_TESTS=1 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang vi --run-tests --transcript "$TR" 2>&1)"; RC=$?
if [ "$RC" = 2 ] && has "tự duyệt bị từ chối"; then ok "9: DEVKIT_AUTO_APPROVE_TESTS=1 -> exit 2"
else bad "9: DEVKIT_AUTO_APPROVE_TESTS=1: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 10. dòng AUTO-APPROVE: trong câu trả lời của chính phiên -> không duyệt (exit 2)
python3 - "$TR" <<'PY'
import json, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + 5))
rec = {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "content": [{"type": "text", "text": "AUTO-APPROVE: tests/test_old.sh"}]}}
open(sys.argv[1], "w").write(json.dumps(rec) + "\n")
PY
run_gate
if [ "$RC" = 2 ] && ! has "agent tự duyệt"; then ok "10: dòng AUTO-APPROVE: -> exit 2"
else bad "10: dòng AUTO-APPROVE:: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi
: > "$TR"

# 11. file duyệt hỏng (JSON sai) -> exit 2, không traceback
printf '{"approvals": [' > "$APPR"
run_gate
if [ "$RC" = 2 ] && ! has "Traceback"; then ok "11: approved_tests.json hỏng -> exit 2, không traceback"
else bad "11: file hỏng: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 12. --brief vẫn hiện "cần duyệt lại" + sha (agent chạy lệnh chuẩn chỉ đọc bản rút gọn)
printf '{"tests/test_old.sh": "%s"}\n' "$SHA" > "$APPR"
run_gate --brief
if [ "$RC" = 2 ] && has "cần duyệt lại" && has "$SHA"; then ok "12: --brief vẫn in cần duyệt lại + sha"
else bad "12: --brief: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# --- #605 lane E: trailer `Test-approved-by: antigravity <task-id>` là nguồn duyệt chéo thứ hai (đi theo commit, tới được
# scratch worktree của merge gate, nơi .claude/audit-gate/ không được chép). Biên bản audit antigravity-pm giả qua
# ANTIGRAVITY_PM_STATE_HOME (ngoài repo, như push_gate.audit_record đọc). Mỗi ca một thư mục mới (mktemp dọn cả $TMP).
mk_trailer_repo() {   # mk_trailer_repo <dir mới>: main có test cũ; nhánh feat sửa test trong commit có trailer <task-id>
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cp "$R/matrix.json" matrix.json
  echo 'fun ok()=1' > src/Core.kt
  printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
  git add -A && git commit -qm init
  git checkout -q -b feat
  printf '#!/bin/sh\nexit 0\n' > tests/test_old.sh; echo 'fun ok()=2' > src/Core.kt
  git commit -qam "đổi test + code" -m "Test-approved-by: antigravity $2"
}
run_at() {   # run_at <dir>: gate kiểm merge-base(main, HEAD) → cây, không file duyệt, không transcript
  OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?
}

# 13. (a) commit có trailer + audit pass + file không đổi sau commit -> exit 0, duyệt chéo bởi antigravity, in task id
mk_trailer_repo "$TMP/t13" T0613-cross; pm_task T0613-cross "$TMP/t13" pass "$(git -C "$TMP/t13" rev-parse HEAD)"
run_at "$TMP/t13"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity" && has "T0613-cross"; then ok "13: trailer + audit pass + file không đổi -> exit 0"
else bad "13: trailer + audit pass: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 14. (b) audit chưa pass -> exit 2
mk_trailer_repo "$TMP/t14" T0614-cross; pm_task T0614-cross "$TMP/t14" fail "$(git -C "$TMP/t14" rev-parse HEAD)"
run_at "$TMP/t14"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "14: audit verdict fail -> exit 2"
else bad "14: audit fail: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 15. (c) file đổi sau commit có trailer (nội dung khác blob đã audit) -> exit 2
mk_trailer_repo "$TMP/t15" T0615-cross; pm_task T0615-cross "$TMP/t15" pass "$(git -C "$TMP/t15" rev-parse HEAD)"
printf '#!/bin/sh\nexit 0 # sau audit\n' > "$TMP/t15/tests/test_old.sh"
run_at "$TMP/t15"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "15: file đổi sau commit trailer -> exit 2"
else bad "15: file đổi sau trailer: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 16. (d) gate chạy trong linked worktree, task.project = checkout chính của cùng repo -> exit 0
mk_trailer_repo "$TMP/t16" T0616-cross; pm_task T0616-cross "$TMP/t16" pass "$(git -C "$TMP/t16" rev-parse HEAD)"
git -C "$TMP/t16" checkout -q main && git -C "$TMP/t16" worktree add -q "$TMP/t16-wt" feat
run_at "$TMP/t16-wt"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity"; then ok "16: linked worktree, task.project = checkout chính -> exit 0"
else bad "16: linked worktree: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 17. (e) task.project = repo khác -> exit 2
mkdir -p "$TMP/other-repo"
mk_trailer_repo "$TMP/t17" T0617-cross; pm_task T0617-cross "$TMP/other-repo" pass "$(git -C "$TMP/t17" rev-parse HEAD)"
run_at "$TMP/t17"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "17: task.project = repo khác -> exit 2"
else bad "17: task.project repo khác: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 18. (e') linked worktree, task.project = repo khác -> exit 2 (nới về checkout chính chỉ cho CÙNG repo)
mk_trailer_repo "$TMP/t18" T0618-cross; pm_task T0618-cross "$TMP/other-repo" pass "$(git -C "$TMP/t18" rev-parse HEAD)"
git -C "$TMP/t18" checkout -q main && git -C "$TMP/t18" worktree add -q "$TMP/t18-wt" feat
run_at "$TMP/t18-wt"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "18: linked worktree, task.project = repo khác -> exit 2"
else bad "18: linked worktree repo khác: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 19. commit sửa test KHÔNG có trailer; audit xong ghi một commit rỗng có trailer (chốt cả cây đã audit) -> exit 0
mk_trailer_repo "$TMP/t19" T0619-none
printf '#!/bin/sh\nexit 0 # sửa lần 2\n' > tests/test_old.sh && git commit -qam "sửa test lần 2, chưa audit"
pm_task T0619-cross "$TMP/t19" pass "$(git rev-parse HEAD)"
git commit -q --allow-empty -m "audit chéo" -m "Test-approved-by: antigravity T0619-cross"
run_at "$TMP/t19"
if [ "$RC" = 0 ] && has "T0619-cross"; then ok "19: commit rỗng có trailer sau lần sửa -> exit 0"
else bad "19: commit rỗng trailer: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 20. sửa test SAU commit rỗng có trailer (nội dung khác cây đã audit) -> exit 2
mk_trailer_repo "$TMP/t20" T0620-none; pm_task T0620-cross "$TMP/t20" pass "$(git rev-parse HEAD)"
git commit -q --allow-empty -m "audit chéo" -m "Test-approved-by: antigravity T0620-cross"
printf '#!/bin/sh\nexit 0 # sau audit\n' > tests/test_old.sh && git commit -qam "sửa sau audit"
run_at "$TMP/t20"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "20: sửa sau commit rỗng trailer -> exit 2"
else bad "20: sửa sau trailer rỗng: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# --- Audit T0066 (#605): biên bản audit ngoài repo phải ghi auditedHead, blob của test phải khớp cây đó.
# 21. (a) mục approved_tests.json đủ trường, reviewer khác author, sha256 đúng, nhưng task_id không có biên bản audit -> exit 2
cd "$R" || exit 1
entry "$SHA" antigravity claude-lane-a T0621-none
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại" && ! has "duyệt chéo bởi antigravity"; then ok "21: mục duyệt không có biên bản audit -> exit 2"
else bad "21: mục duyệt không biên bản: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 22. mục duyệt có audit pass nhưng auditedHead là cây cũ (test đổi sau đó) -> exit 2, cần duyệt lại
pm_task T0622-old "$R" pass "$(git rev-parse HEAD)"
entry "$SHA" antigravity claude-lane-a T0622-old
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại" && ! has "duyệt chéo bởi antigravity"; then ok "22: mục duyệt, auditedHead cũ -> exit 2"
else bad "22: mục duyệt auditedHead cũ: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 23. mục duyệt có audit pass nhưng notes không có auditedHead -> exit 2
pm_task T0623-nohead "$R" pass
entry "$SHA" antigravity claude-lane-a T0623-nohead
run_gate
if [ "$RC" = 2 ] && has "cần duyệt lại" && ! has "duyệt chéo bởi antigravity"; then ok "23: mục duyệt, audit không auditedHead -> exit 2"
else bad "23: mục duyệt không auditedHead: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi
rm -f "$APPR"

# 24. (b) trailer + audit pass nhưng notes không có auditedHead -> exit 2
mk_trailer_repo "$TMP/t24" T0624-cross; pm_task T0624-cross "$TMP/t24" pass
run_at "$TMP/t24"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "24: trailer, audit không auditedHead -> exit 2"
else bad "24: trailer không auditedHead: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 25. (c) replay: task cũ đã pass với auditedHead = commit cũ (main), test sửa sau đó trong commit có trailer task cũ -> exit 2
mk_trailer_repo "$TMP/t25" T0625-old; pm_task T0625-old "$TMP/t25" pass "$(git -C "$TMP/t25" rev-parse main)"
run_at "$TMP/t25"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "25: replay task_id cũ (auditedHead cũ) -> exit 2"
else bad "25: replay task_id cũ: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

# 26. auditedHead là sha không có trong repo -> exit 2 (fail closed)
mk_trailer_repo "$TMP/t26" T0626-cross; pm_task T0626-cross "$TMP/t26" pass 0123456789abcdef0123456789abcdef01234567
run_at "$TMP/t26"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "26: auditedHead không có trong repo -> exit 2"
else bad "26: auditedHead lạ: rc=$RC, $(printf '%s' "$OUT" | tail -15)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
