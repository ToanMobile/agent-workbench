#!/usr/bin/env bash
# Nguồn duyệt thứ 3 cho test cũ bị sửa (04/11, không bước người): post-fix-gate tra THẲNG biên bản antigravity-pm (push_gate.audited_heads)
# — không cần mục approved_tests.json, trailer `Test-approved-by:` hay comment PR. Cùng luật audit_covers (head trên chuỗi first-parent
# của PR, không trên trunk, audit mới nhất, blob khớp, main không đổi file) và audit_reviewer(legacy=False) khác danh tính phiên.
#  P1: biên bản grok (PM tự chạy, lượt audit gần nhất grok) tại head PR, không json/trailer -> nhận (code cũ: exit 2). P2: scratch merge gate
#      (PR + main) -> nhận. P3: thông điệp CHƯA XÁC MINH chỉ cách PM audit, không bảo ghi json.
#  N1-N8: phiên là grok; audit mới hơn khác blob; pm home lạ không phải fixture; reviewer pm không dispatch (biên bản cũ); auditedHead đã
#      nằm trên main; mục json tự khai author grok-build; head chỉ còn trong auditHistory; hai biên bản cùng task id (reviewer khác biên bản).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
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
pm_grok() {   # pm_grok <task-id> <project> <auditedHead> [dir]: audit pass do PM tự chạy grok (reviewer grok, lượt audit gần nhất grok)
  local d="${4:-p-$1}"
  mkdir -p "$TMP/pm/projects/$d/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"},"auditHistory":[{"auditedHead":"%s","reviewer":"grok","at":"2026-11-04T00:00:01Z"}]}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$3" "$3" > "$TMP/pm/projects/$d/tasks/$1/task.json"
}
V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V2='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "=" src/Core.kt\n'
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
pr_commit() { printf "$1" > tests/t.sh; echo "fun ok()=$RANDOM" > src/Core.kt; git commit -qam "$2"; git rev-parse HEAD; }
main_moves() { git checkout -q main && echo "fun other()=$RANDOM" > src/Other.kt && git commit -qam "main tiến" && git checkout -q "${1:-feat}"; }
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
accepted() { [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task $1)"; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; }
tailout()  { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|CHƯA XÁC MINH|exit" | tail -4 | cut -c1-240; }

# P1. biên bản PM grok tại head PR; KHÔNG approved_tests.json, KHÔNG trailer, KHÔNG comment -> nhận
mk "$TMP/p1"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1001-p1 "$TMP/p1" "$X"
run_gate "$TMP/p1"
if accepted T1001-p1 && [ ! -e "$TMP/p1/.claude/audit-gate/approved_tests.json" ]; then ok "P1: biên bản PM grok tại head PR, không json/trailer -> nhận"
else bad "P1: tra thẳng biên bản PM: rc=$RC, $(tailout)"; fi

# P2. scratch như merge gate: tách rời ở đầu PR, gộp main mới (không chạm test) -> nhận
mk "$TMP/p2"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1002-p2 "$TMP/p2" "$X"
main_moves; git checkout -q --detach feat && git merge -q --no-ff --no-edit main
run_gate "$TMP/p2"
if accepted T1002-p2; then ok "P2: scratch merge gate (PR + main) -> nhận"
else bad "P2: scratch merge gate: rc=$RC, $(tailout)"; fi

# P3. chưa có audit: CHƯA XÁC MINH chỉ cách PM audit grok/Antigravity trên head PR rồi chạy lại; không bảo agent ghi json
mk "$TMP/p3"; pr_commit "$V1" "PR sửa test" >/dev/null
run_gate "$TMP/p3"
if refused && has "pm_dispatch kind=audit agent=grok" && ! has "approved_tests.json\` (khoá"; then ok "P3: thông điệp chỉ luồng PM audit, không bảo ghi json"
else bad "P3: thông điệp CHƯA XÁC MINH: rc=$RC, $(tailout)"; fi

# N1. phiên là grok (GROK_SESSION_ID) -> không duyệt (tự duyệt); DEVKIT_AGENT_ID=grok-build cũng vậy
mk "$TMP/n1"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1011-n1 "$TMP/n1" "$X"
run_gate "$TMP/n1" GROK_SESSION_ID=g-1
if refused; then ok "N1: phiên grok, reviewer PM grok -> không duyệt"; else bad "N1: phiên grok: rc=$RC, $(tailout)"; fi
run_gate "$TMP/n1" DEVKIT_AGENT_ID=grok-build
if refused; then ok "N1b: DEVKIT_AGENT_ID=grok-build -> không duyệt"; else bad "N1b: grok-build: rc=$RC, $(tailout)"; fi

# N2. audit mới hơn (V2, T1022) có blob khác; test chép về V1 đã audit ở T1021 -> không duyệt (chỉ audit mới nhất)
mk "$TMP/n2"; X1="$(pr_commit "$V1" "V1")"; pm_grok T1021-n2 "$TMP/n2" "$X1"
X2="$(pr_commit "$V2" "V2 làm mạnh")"; pm_grok T1022-n2 "$TMP/n2" "$X2"
pr_commit "$V1" "chép về V1" >/dev/null
run_gate "$TMP/n2"
if refused; then ok "N2: audit mới hơn khác blob -> không duyệt"; else bad "N2: replay audit cũ: rc=$RC, $(tailout)"; fi
pr_commit "$V2" "về lại V2" >/dev/null; run_gate "$TMP/n2"
if accepted T1022-n2; then ok "N2c: đối chứng nội dung = audit mới nhất -> nhận"; else bad "N2c: đối chứng: rc=$RC, $(tailout)"; fi

# N3. pm home lạ, không phải fixture (DEVKIT_PM_HOME_TEST tắt) -> không duyệt
mk "$TMP/n3"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1031-n3 "$TMP/n3" "$X"
run_gate "$TMP/n3" DEVKIT_PM_HOME_TEST=0
if refused; then ok "N3: pm home lạ không phải fixture -> không duyệt"; else bad "N3: pm home lạ: rc=$RC, $(tailout)"; fi

# N4. biên bản cũ: reviewer pm, không lượt audit nào trong dispatches -> không duyệt (legacy=False: thiếu bằng chứng reviewer)
mk "$TMP/n4"; X="$(pr_commit "$V1" "PR sửa test")"
mkdir -p "$TMP/pm/projects/p-n4/tasks/T1041-n4"
printf '{"id":"T1041-n4","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"pm","notes":"auditedHead: %s"}}}\n' \
  "$(pwd -P)" "$X" > "$TMP/pm/projects/p-n4/tasks/T1041-n4/task.json"
run_gate "$TMP/n4"
if refused; then ok "N4: reviewer pm, không dispatch -> không duyệt"; else bad "N4: biên bản cũ: rc=$RC, $(tailout)"; fi

# N5. auditedHead đã nằm trên main (nhánh phụ gộp vào main), PR mới chép test về bản đó -> không duyệt
mk "$TMP/n5"; git checkout -q -b side main; S="$(pr_commit "$V1" "side V1")"; pm_grok T1051-n5 "$TMP/n5" "$S"
git checkout -q main && git merge -q --no-ff --no-edit side && printf "$V2" > tests/t.sh && git commit -qam "main V2"
git checkout -q -B feat main; pr_commit "$V1" "chép V1 về" >/dev/null
run_gate "$TMP/n5"
if refused; then ok "N5: auditedHead trên main -> không duyệt"; else bad "N5: head trên main: rc=$RC, $(tailout)"; fi

# N6. mục json tự khai author grok-build (= reviewer PM grok) bị từ chối là tự duyệt: đường tra thẳng không được duyệt lại file đó
mk "$TMP/n6"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1061-n6 "$TMP/n6" "$X"
mkdir -p .claude/audit-gate
python3 - "$TMP/n6" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": "grok", "author": "grok-build", "task_id": "T1061-n6",
                          "reason": "fixture"}]}, open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
run_gate "$TMP/n6"
if refused && has "tự duyệt"; then ok "N6: mục json author grok-build bị từ chối -> tra thẳng không duyệt lại"
else bad "N6: author tự khai: rc=$RC, $(tailout)"; fi

# N7. verdicts.audit bị ghi đè thành fail, head pass chỉ còn trong auditHistory -> không duyệt (chỉ head của verdicts.audit hiện tại)
mk "$TMP/n7"; X="$(pr_commit "$V1" "PR sửa test")"
mkdir -p "$TMP/pm/projects/p-n7/tasks/T1071-n7"
printf '{"id":"T1071-n7","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"fail","round":2,"reviewer":"grok","notes":"fail"},"auditHistory":[{"auditedHead":"%s","reviewer":"grok","at":"2026-11-04T00:00:01Z"}]}}\n' \
  "$(pwd -P)" "$X" > "$TMP/pm/projects/p-n7/tasks/T1071-n7/task.json"
run_gate "$TMP/n7"
if refused; then ok "N7: head chỉ còn trong auditHistory (verdict fail) -> không duyệt"; else bad "N7: history head: rc=$RC, $(tailout)"; fi

# N8. hai biên bản cùng task id: A (sắp trước) head PR, reviewer grok nhưng lượt audit gần nhất antigravity -> reviewer không xác định;
#     B reviewer grok hợp lệ nhưng head khác (M0 trên main). Không mượn reviewer của B cho head của A -> không duyệt
mk "$TMP/n8"; M0="$(git rev-parse main)"; X="$(pr_commit "$V1" "PR sửa test")"; P8="$(pwd -P)"
mkdir -p "$TMP/pm/projects/p-a-n8/tasks/T1081" "$TMP/pm/projects/p-b-n8/tasks/T1081"
printf '{"id":"T1081","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T01:00:00Z"},{"kind":"audit","agent":"antigravity","at":"2026-11-04T02:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
  "$P8" "$X" > "$TMP/pm/projects/p-a-n8/tasks/T1081/task.json"
pm_grok T1081 "$TMP/n8" "$M0" p-b-n8
run_gate "$TMP/n8"
if refused; then ok "N8: reviewer và head phải cùng một biên bản -> không duyệt"; else bad "N8: mượn reviewer: rc=$RC, $(tailout)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
