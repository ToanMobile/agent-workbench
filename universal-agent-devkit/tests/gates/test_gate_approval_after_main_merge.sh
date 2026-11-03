#!/usr/bin/env bash
# Đợt 2 gate, lane A mục 1: mục duyệt test sửa (approved_tests.json) và trailer `Test-approved-by:` còn hiệu lực sau khi gộp main mới
# vào nhánh PR (hoặc scratch của merge gate = main + PR). Luật: base = merge-base(trunk, HEAD); auditedHead phải nằm trên chuỗi
# first-parent của PR tip trong trunk..PR tip (hoặc là cây làm việc sau PR tip), không là tổ tiên của trunk, là audit MỚI NHẤT có nội
# dung khác (luật mới: gặp audit mới hơn có blob khác thì gate từ chối audit cũ), blob hiện tại == blob ở auditedHead, và blob của file ở base hiện tại
# == blob ở merge-base(auditedHead, trunk) (main không đổi chính test đó kể từ lúc audit).
#  A1-A3: ĐỎ trên code cũ ("auditedHead không nằm sau base") — merge main vào PR, scratch main+PR, scratch merge gate (PR + main, trailer).
#  R1-R4: vẫn từ chối — replay audit cũ hơn sau khi test được làm mạnh; auditedHead đã nằm trên main; audit tới qua merge nhánh bỏ dở
#         (second parent); main đổi chính test đó sau audit. Mỗi ca có đối chứng chỉ khác đúng một điểm.
#  Sửa sau review đợt 2: R5 (G2) main đổi test mà PR chưa gộp main; R6 (F1) audit mới hơn bị ghi đè thành fail vẫn tính qua
#  verdicts.auditHistory; R7 (F3/G3) author alias grok-build / phiên grok = reviewer PM grok -> tự duyệt; R8 (F2) trailer grok
#  trong phiên grok (GROK_SESSION_ID) không duyệt. Đều có đối chứng.
#  Vòng kiểm lại: R9 (H4) DEVKIT_AGENT_ID=codex + GROK_SESSION_ID: tập danh tính phiên có grok -> mục duyệt và trailer grok không duyệt.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT   # danh tính phiên (push_gate.session_agent): từng ca tự đặt
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # biên bản giả dưới $TMP, không bao giờ ~/.antigravity-pm thật
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
pm_task() {   # pm_task <task-id> <project> <auditedHead>: audit pass, biên bản cũ (reviewer pm, không dispatches)
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"pm","notes":"audit ok\\nauditedHead: %s"}}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$3" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
approve() {   # approve <repo> <task-id>: mục duyệt chéo cho tests/t.sh với nội dung hiện tại
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
root, tid = sys.argv[1:3]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": "antigravity", "author": "claude", "task_id": tid,
                          "reason": "fixture"}]}, open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
}
V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'              # PR sửa dòng 2 (không phải nối thêm)
V2='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "=" src/Core.kt\n'   # bản làm mạnh
V3='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun ok" src/Core.kt\n'           # main đổi dòng 3
mk() {   # mk <dir>: main M0 (test V0), nhánh feat
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt; echo 'fun other()=1' > src/Other.kt; printf "$V0" > tests/t.sh
  git add -A && git commit -qm "M0"
  git checkout -q -b feat
}
pr_commit() {   # pr_commit <test-version> <msg>: sửa test + code trên nhánh hiện tại, in sha
  printf "$1" > tests/t.sh; echo "fun ok()=$RANDOM" > src/Core.kt; git commit -qam "$2"; git rev-parse HEAD
}
main_moves() {  # main tiến một commit không chạm test
  git checkout -q main && echo "fun other()=$RANDOM" > src/Other.kt && git commit -qam "main tiến" && git checkout -q "${1:-feat}"
}
run_gate() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
accepted() { [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity" && has "$1"; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi" && has "$1"; }
tailout()  { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|exit" | tail -6; }

# A1. PR sửa test ở X (audit T0801 tại X), main tiến (không chạm test), gộp main vào nhánh PR -> mục duyệt vẫn nhận
mk "$TMP/a1"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0801-a1 "$TMP/a1" "$X"
main_moves; git merge -q --no-ff --no-edit main
approve "$TMP/a1" T0801-a1; run_gate "$TMP/a1"
if accepted T0801-a1; then ok "A1: gộp main vào PR sau audit -> mục duyệt vẫn nhận (exit 0)"
else bad "A1: gộp main vào PR: rc=$RC, $(tailout)"; fi

# A2. scratch dạng main + merge PR (HEAD tách rời, parent đầu = main) -> nhận
mk "$TMP/a2"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0802-a2 "$TMP/a2" "$X"
main_moves; git checkout -q --detach main && git merge -q --no-ff --no-edit feat
approve "$TMP/a2" T0802-a2; run_gate "$TMP/a2"
if accepted T0802-a2; then ok "A2: scratch main + merge PR -> mục duyệt nhận (exit 0)"
else bad "A2: scratch main + merge PR: rc=$RC, $(tailout)"; fi

# A3. scratch như merge gate thật: tách rời ở đầu PR (commit rỗng mang trailer trên cây đã audit), gộp main; KHÔNG có approved_tests.json
mk "$TMP/a3"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0803-a3 "$TMP/a3" "$X"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0803-a3"
main_moves; git checkout -q --detach feat && git merge -q --no-ff --no-edit main
run_gate "$TMP/a3"
if accepted T0803-a3; then ok "A3: scratch merge gate (PR + main), trailer -> nhận (exit 0)"
else bad "A3: scratch merge gate, trailer: rc=$RC, $(tailout)"; fi

# A4. làm trực tiếp trên main đang đứng ở một merge --no-ff, sửa test chưa commit, audit cây làm việc (`git stash create`) -> nhận
#     (HEAD đã thuộc trunk: đầu PR là HEAD, không phải parent thứ hai)
mk "$TMP/a4"; echo 'fun other()=4' > src/Other.kt && git commit -qam "feat code"
git checkout -q main && git merge -q --no-ff --no-edit feat
printf "$V1" > tests/t.sh; echo 'fun ok()=4' > src/Core.kt; pm_task T0804-a4 "$TMP/a4" "$(git stash create)"
approve "$TMP/a4" T0804-a4; run_gate "$TMP/a4"
if accepted T0804-a4; then ok "A4: trên main ở merge --no-ff, audit cây làm việc -> nhận (exit 0)"
else bad "A4: main ở merge, audit cây làm việc: rc=$RC, $(tailout)"; fi

# R1. replay: audit T0811 tại X1 (V1), test làm mạnh V2 ở X2 (audit T0812), chép về V1 rồi khai T0811 -> từ chối (có audit mới hơn)
mk "$TMP/r1"; X1="$(pr_commit "$V1" "V1")"; pm_task T0811-r1 "$TMP/r1" "$X1"
X2="$(pr_commit "$V2" "V2 làm mạnh")"; pm_task T0812-r1 "$TMP/r1" "$X2"
pr_commit "$V1" "chép về V1" >/dev/null
approve "$TMP/r1" T0811-r1; run_gate "$TMP/r1"
if refused "audit mới hơn"; then ok "R1: replay audit cũ hơn sau khi test được làm mạnh -> từ chối (audit mới hơn)"
else bad "R1: replay audit cũ: rc=$RC, $(tailout)"; fi
# R1c. đối chứng: nội dung = V2, khai audit mới nhất T0812 -> nhận
pr_commit "$V2" "về lại V2" >/dev/null
approve "$TMP/r1" T0812-r1; run_gate "$TMP/r1"
if accepted T0812-r1; then ok "R1c: audit mới nhất, nội dung khớp -> nhận"
else bad "R1c: đối chứng audit mới nhất: rc=$RC, $(tailout)"; fi

# R2. auditedHead đã nằm trên main: nhánh phụ S (V1, audit T0821) gộp vào main, main làm mạnh V2, PR mới chép V1 về -> từ chối
mk "$TMP/r2"; git checkout -q -b side main; S="$(pr_commit "$V1" "side V1")"; pm_task T0821-r2 "$TMP/r2" "$S"
git checkout -q main && git merge -q --no-ff --no-edit side && printf "$V2" > tests/t.sh && git commit -qam "main V2"
git checkout -q -B feat main; pr_commit "$V1" "chép V1 về" >/dev/null
approve "$TMP/r2" T0821-r2; run_gate "$TMP/r2"
if refused "đã nằm trên nhánh đích"; then ok "R2: auditedHead đã nằm trên main -> từ chối"
else bad "R2: auditedHead trên main: rc=$RC, $(tailout)"; fi

# R3. audit tới qua merge nhánh bỏ dở (second parent): nhánh ab đổi test (audit T0831), PR gộp ab --no-ff -> từ chối
mk "$TMP/r3"; git checkout -q -b ab main; A="$(pr_commit "$V1" "ab V1")"; pm_task T0831-r3 "$TMP/r3" "$A"
git checkout -q feat && echo 'fun other()=9' > src/Other.kt && git commit -qam "PR code" && git merge -q --no-ff --no-edit ab
approve "$TMP/r3" T0831-r3; run_gate "$TMP/r3"
if refused "first-parent"; then ok "R3: audit tới qua second parent (nhánh bỏ dở) -> từ chối"
else bad "R3: audit qua second parent: rc=$RC, $(tailout)"; fi
# R3c. đối chứng: cùng cây, audit T0832 tại chính merge commit (trên chuỗi first-parent) -> nhận
pm_task T0832-r3 "$TMP/r3" "$(git rev-parse HEAD)"
approve "$TMP/r3" T0832-r3; run_gate "$TMP/r3"
if accepted T0832-r3; then ok "R3c: audit trên chuỗi first-parent của PR -> nhận"
else bad "R3c: đối chứng first-parent: rc=$RC, $(tailout)"; fi

# R4. main đổi chính test đó sau audit; gộp main vào PR và giữ test = blob ở auditedHead -> từ chối (main đã đổi file)
mk "$TMP/r4"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0841-r4 "$TMP/r4" "$X"
git checkout -q main && printf "$V3" > tests/t.sh && git commit -qam "main đổi test" && git checkout -q feat
git merge -q --no-ff --no-commit main >/dev/null 2>&1; git checkout "$X" -- tests/t.sh && git commit -qm "gộp main, giữ test của PR"
if [ "$(git rev-parse HEAD:tests/t.sh)" != "$(git rev-parse "$X:tests/t.sh")" ]; then bad "R4: fixture: test sau gộp khác blob ở auditedHead"; fi
approve "$TMP/r4" T0841-r4; run_gate "$TMP/r4"
if refused "nhánh đích đã đổi"; then ok "R4: main đổi chính test sau audit -> từ chối"
else bad "R4: main đổi test sau audit: rc=$RC, $(tailout)"; fi

# ── Đợt 2, sửa sau review (F1, G2, F3/G3, F2) ─────────────────────────────────────────────────────────────────────────────
pm_task_grok() {   # pm_task_grok <task-id> <project> <auditedHead>: audit pass do PM tự chạy grok (reviewer grok, lượt audit gần nhất grok)
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-03T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$3" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
pm_task_failed() {   # pm_task_failed <task-id> <project> <head> <yes|no>: verdicts.audit bị ghi đè thành fail; yes = auditHistory còn giữ head pass
  local hist=""
  [ "$4" = yes ] && hist=",\"auditHistory\":[{\"auditedHead\":\"$3\",\"reviewer\":\"antigravity\",\"at\":\"2026-11-02T00:00:00Z\"}]"
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","verdicts":{"audit":{"verdict":"fail","round":2,"reviewer":"pm","notes":"fail"}%s}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$hist" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
approve_as() {   # approve_as <repo> <task-id> <reviewer> <author>
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import hashlib, json, os, sys
root, tid, rv, au = sys.argv[1:5]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": rv, "author": au, "task_id": tid, "reason": "fixture"}]},
          open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
}
run_gate_env() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }

# R5 (G2). main đổi chính test đó sau audit, PR CHƯA gộp main -> từ chối (code cũ so base cũ của PR: nhận)
mk "$TMP/r5"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0851-r5 "$TMP/r5" "$X"
git checkout -q main && printf "$V3" > tests/t.sh && git commit -qam "main đổi test" && git checkout -q feat
approve "$TMP/r5" T0851-r5; run_gate "$TMP/r5"
if refused "nhánh đích đã đổi"; then ok "R5: main đổi test sau audit, PR chưa gộp main -> từ chối"
else bad "R5: main đổi test, PR chưa gộp: rc=$RC, $(tailout)"; fi
# R5c. đối chứng: main tiến KHÔNG chạm test, PR chưa gộp main -> nhận
mk "$TMP/r5c"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task T0852-r5c "$TMP/r5c" "$X"
main_moves; approve "$TMP/r5c" T0852-r5c; run_gate "$TMP/r5c"
if accepted T0852-r5c; then ok "R5c: main tiến không chạm test, PR chưa gộp -> nhận"
else bad "R5c: đối chứng main không chạm test: rc=$RC, $(tailout)"; fi

# R6 (F1). replay qua verdict fail: T0861 pass ở X1 (V1); T0862 pass ở X2 (V2) rồi verdicts.audit bị ghi đè thành fail, auditHistory
#     còn X2; chép test về V1, khai T0861 -> từ chối (audit mới hơn)
mk "$TMP/r6"; X1="$(pr_commit "$V1" "V1")"; pm_task T0861-r6 "$TMP/r6" "$X1"
X2="$(pr_commit "$V2" "V2 làm mạnh")"; pm_task_failed T0862-r6 "$TMP/r6" "$X2" yes
pr_commit "$V1" "chép về V1" >/dev/null
approve "$TMP/r6" T0861-r6; run_gate "$TMP/r6"
if refused "audit mới hơn"; then ok "R6: audit mới hơn bị ghi đè thành fail vẫn còn trong auditHistory -> từ chối replay"
else bad "R6: replay qua verdict fail: rc=$RC, $(tailout)"; fi
# R6c. đối chứng: cùng chuỗi, biên bản fail KHÔNG có auditHistory (biên bản cũ) -> nhận như hôm nay
mk "$TMP/r6c"; X1="$(pr_commit "$V1" "V1")"; pm_task T0863-r6c "$TMP/r6c" "$X1"
X2="$(pr_commit "$V2" "V2 làm mạnh")"; pm_task_failed T0864-r6c "$TMP/r6c" "$X2" no
pr_commit "$V1" "chép về V1" >/dev/null
approve "$TMP/r6c" T0863-r6c; run_gate "$TMP/r6c"
if accepted T0863-r6c; then ok "R6c: biên bản fail không có auditHistory -> như trước (nhận)"
else bad "R6c: đối chứng không history: rc=$RC, $(tailout)"; fi

# R7 (F3/G3). reviewer PM grok, author ghi "grok-build" -> tự duyệt, từ chối; R7b phiên là grok (GROK_WORKSPACE_ROOT) -> từ chối;
#     R7c đối chứng author claude, không env grok -> nhận
mk "$TMP/r7"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task_grok T0871-r7 "$TMP/r7" "$X"
approve_as "$TMP/r7" T0871-r7 grok grok-build; run_gate "$TMP/r7"
if refused "tự duyệt"; then ok "R7: author grok-build = reviewer PM grok -> từ chối (tự duyệt)"
else bad "R7: author alias grok: rc=$RC, $(tailout)"; fi
approve_as "$TMP/r7" T0871-r7 grok claude; run_gate_env "$TMP/r7" GROK_WORKSPACE_ROOT="$TMP/r7"
if refused "tự duyệt"; then ok "R7b: phiên là grok (GROK_WORKSPACE_ROOT), reviewer PM grok -> từ chối (tự duyệt)"
else bad "R7b: phiên grok, mục author claude: rc=$RC, $(tailout)"; fi
run_gate "$TMP/r7"
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task T0871-r7)"; then ok "R7c: author claude, phiên không phải grok -> nhận"
else bad "R7c: đối chứng author claude: rc=$RC, $(tailout)"; fi

# R8 (F2). trailer `Test-approved-by: grok`, phiên là grok (GROK_SESSION_ID, không DEVKIT_AGENT_ID) -> không duyệt; R8c không env -> nhận
mk "$TMP/r8"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task_grok T0881-r8 "$TMP/r8" "$X"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: grok T0881-r8"
run_gate_env "$TMP/r8" GROK_SESSION_ID=g-1
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "R8: trailer grok, phiên là grok -> không duyệt (exit 2)"
else bad "R8: trailer grok trong phiên grok: rc=$RC, $(tailout)"; fi
run_gate "$TMP/r8"
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task T0881-r8)"; then ok "R8c: trailer grok, phiên không phải grok -> nhận"
else bad "R8c: đối chứng trailer grok: rc=$RC, $(tailout)"; fi

# R9 (H4, vòng kiểm lại). DEVKIT_AGENT_ID=codex nhưng phiên có GROK_SESSION_ID (tập danh tính {codex, grok}), reviewer PM grok:
#     mục duyệt (author claude) -> tự duyệt, từ chối; R9b trailer grok cùng env -> không duyệt. Đối chứng: R7c / R8c (không env grok).
mk "$TMP/r9"; X="$(pr_commit "$V1" "PR sửa test")"; pm_task_grok T0891-r9 "$TMP/r9" "$X"
approve_as "$TMP/r9" T0891-r9 grok claude; run_gate_env "$TMP/r9" DEVKIT_AGENT_ID=codex GROK_SESSION_ID=g-1
if refused "tự duyệt"; then ok "R9: DEVKIT_AGENT_ID=codex + GROK_SESSION_ID, reviewer PM grok -> từ chối (tự duyệt)"
else bad "R9: codex + phiên grok, mục author claude: rc=$RC, $(tailout)"; fi
rm -f "$TMP/r9/.claude/audit-gate/approved_tests.json"
git -C "$TMP/r9" commit -q --allow-empty -m "audit" -m "Test-approved-by: grok T0891-r9"
run_gate_env "$TMP/r9" DEVKIT_AGENT_ID=codex GROK_SESSION_ID=g-1
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "R9b: trailer grok, DEVKIT_AGENT_ID=codex + GROK_SESSION_ID -> không duyệt (exit 2)"
else bad "R9b: trailer grok, codex + phiên grok: rc=$RC, $(tailout)"; fi
run_gate_env "$TMP/r9" DEVKIT_AGENT_ID=codex
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task T0891-r9)"; then ok "R9c: trailer grok, DEVKIT_AGENT_ID=codex không env grok -> nhận"
else bad "R9c: đối chứng codex không grok: rc=$RC, $(tailout)"; fi

# R10 (review cuối F-1). push_gate.approved() (fallback push không biên nhận, _covered, since_test_weakened) cũng từ chối trailer
#     grok trong phiên grok; R10c đối chứng không env grok -> nhận. Repo r8: commit rỗng mang trailer grok trên cây đã audit.
approved_rc() { (cd "$TMP/r8" && env "$@" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate; ok, why = push_gate.approved(".", "main..HEAD"); print(why); sys.exit(0 if ok else 2)' "$DEVKIT_DIR/bin" 2>&1); }
OUT="$(approved_rc GROK_SESSION_ID=g-1)"; RC=$?
if [ "$RC" = 2 ] && has "tự duyệt"; then ok "R10: approved() trailer grok, phiên grok -> không duyệt (tự duyệt)"
else bad "R10: approved() trailer grok trong phiên grok: rc=$RC, $OUT"; fi
OUT="$(approved_rc DEVKIT_AGENT_ID=claude)"; RC=$?
if [ "$RC" = 0 ]; then ok "R10c: approved() trailer grok, phiên không phải grok -> nhận"
else bad "R10c: đối chứng approved(): rc=$RC, $OUT"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
