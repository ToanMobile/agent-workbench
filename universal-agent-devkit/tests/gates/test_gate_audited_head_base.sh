#!/usr/bin/env bash
# Audit T0066 vòng 2 (#605, PR #609): ba lỗ của duyệt chéo dựa trên biên bản antigravity-pm.
#  D  hạ cấp: auditedHead của một task cũ nằm TRƯỚC base của nhánh (main đã thêm assertion sau đó) không được duyệt việc chép lùi test
#     về bản yếu cũ — ở mục approved_tests.json, ở trailer `Test-approved-by:` và ở push_gate.approved (base phải là tổ tiên của
#     auditedHead: `git merge-base --is-ancestor <base> <auditedHead>`). Đối chứng: auditedHead sau base vẫn duyệt.
#  H  push_gate.audited_head đọc trường cấu trúc verdicts.audit.auditedHead (pm_verdict ghi) trước, rồi mới tới notes.
#  P  ANTIGRAVITY_PM_STATE_HOME lạ (không phải ~/.antigravity-pm của user): lời duyệt dựa vào nó vẫn cho kết luận exit 0 (test cần),
#     nhưng lượt đó là "nới lỏng": không ghi biên nhận task, full_pass.json không phải exit 0. Đối chứng: lượt chỉ sửa code (không
#     lời duyệt nào) cùng biến đó vẫn ghi biên nhận task.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
PG_DIR="$DEVKIT_DIR/bin"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # biên bản giả dưới $TMP, không bao giờ ~/.antigravity-pm thật
export DEVKIT_PM_HOME_TEST=1                 # công tắc chỉ cho test: push_gate.approved tính biên bản pm giả trong thư mục tạm
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
pm_task() {   # pm_task <task-id> <project> <auditedHead>: audit pass, notes ghi `auditedHead: <sha>`
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"pm","notes":"audit ok\\nauditedHead: %s"}}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$3" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
approve() {   # approve <repo> <task-id>: mục duyệt chéo hợp lệ cho tests/t.sh (nội dung hiện tại)
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
root, tid = sys.argv[1:3]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": "antigravity", "author": "claude", "task_id": tid,
                          "reason": "fixture"}]}, open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
}
# repo: main C1 (test yếu: true) -> C2 (main thêm assertion); nhánh feat cắt từ C2
mk_repo() {   # mk_repo <dir>; đặt C1, C2
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt; printf '#!/bin/sh\ntrue\n' > tests/t.sh
  git add -A && git commit -qm "C1: test yếu"; C1="$(git rev-parse HEAD)"
  printf '#!/bin/sh\ntrue\ngrep -q "ok" src/Core.kt\n' > tests/t.sh && git commit -qam "C2: main thêm assertion"; C2="$(git rev-parse HEAD)"
  git checkout -q -b feat
}
run_gate() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests "${@:2}" 2>&1)"; RC=$?; }
pg() { OUT="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; r = getattr(p, sys.argv[2])(*sys.argv[3:]); print(*r) if isinstance(r, tuple) else print(r)' "$PG_DIR" "$@" 2>&1)"; }

# D1. mục approved_tests.json: task cũ pass tại C1 (trước base C2), test trên nhánh chép lùi về blob C1 -> exit 2
mk_repo "$TMP/d1"; pm_task T0701-old "$TMP/d1" "$C1"
git show "$C1:tests/t.sh" > tests/t.sh; echo 'fun ok()=2' > src/Core.kt
approve "$TMP/d1" T0701-old
run_gate "$TMP/d1"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "D1: mục duyệt, auditedHead trước base -> exit 2"
else bad "D1: mục duyệt hạ cấp: rc=$RC, $(printf '%s' "$OUT" | tail -12)"; fi
# D1c. đối chứng: cùng nội dung, auditedHead là cây làm việc (sau base) -> exit 0
pm_task T0701-new "$TMP/d1" "$(git -C "$TMP/d1" stash create)"
approve "$TMP/d1" T0701-new
run_gate "$TMP/d1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity"; then ok "D1c: mục duyệt, auditedHead sau base -> exit 0"
else bad "D1c: đối chứng mục duyệt: rc=$RC, $(printf '%s' "$OUT" | tail -12)"; fi

# D2. trailer: nhánh chép lùi cả cây về C1, commit rỗng mang trailer task cũ (auditedHead C1), rồi sửa code -> exit 2 với --diff main
mk_repo "$TMP/d2"; pm_task T0702-old "$TMP/d2" "$C1"
git read-tree -u --reset "$C1" && git commit -qm "chép lùi về C1"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0702-old"
echo 'fun ok()=2' > src/Core.kt && git commit -qam "sửa code"
run_gate "$TMP/d2" --diff main
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi antigravity"; then ok "D2: trailer task cũ, auditedHead trước base -> exit 2"
else bad "D2: trailer hạ cấp: rc=$RC, $(printf '%s' "$OUT" | tail -12)"; fi

# D3. push_gate.approved: cây đầu range = cây C1 = cây trailer, nhưng C1 không sau mốc dưới của range (main = C2) -> không duyệt
mk_repo "$TMP/d3"; pm_task T0703-old "$TMP/d3" "$C1"
git read-tree -u --reset "$C1" && git commit -qm "chép lùi về C1"; R3="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0703-old"
pg approved "$TMP/d3" "main..HEAD"
if printf '%s' "$OUT" | grep -q "^False"; then ok "D3: push_gate.approved, auditedHead trước mốc dưới -> không duyệt"
else bad "D3: push_gate.approved hạ cấp: $OUT"; fi
# D3c. đối chứng: auditedHead = commit chép lùi trên nhánh (sau C2, cùng cây) -> duyệt
pm_task T0703-old "$TMP/d3" "$R3"
pg approved "$TMP/d3" "main..HEAD"
if printf '%s' "$OUT" | grep -q "^True"; then ok "D3c: push_gate.approved, auditedHead sau mốc dưới -> duyệt"
else bad "D3c: đối chứng push_gate.approved: $OUT"; fi
# D4. cùng biên bản hợp lệ của D3c, nhưng pm home lạ KHÔNG bật công tắc test -> approved() từ chối ở mọi đường push
OUT="$(DEVKIT_PM_HOME_TEST= python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(*p.approved(sys.argv[2], "main..HEAD"))' "$PG_DIR" "$TMP/d3" 2>&1)"
if printf '%s' "$OUT" | grep -q "^False" && printf '%s' "$OUT" | grep -qF "ANTIGRAVITY_PM_STATE_HOME lạ"; then ok "D4: pm home lạ, không công tắc test -> approved() từ chối"
else bad "D4: pm home lạ không công tắc: $OUT"; fi
# D4b. công tắc bật nhưng pm home không nằm trong thư mục tạm của hệ thống -> vẫn từ chối
OUT="$(ANTIGRAVITY_PM_STATE_HOME=/nonexistent-agpm-home python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(*p.approved(sys.argv[2], "main..HEAD"))' "$PG_DIR" "$TMP/d3" 2>&1)"
if printf '%s' "$OUT" | grep -q "^False" && printf '%s' "$OUT" | grep -qF "ANTIGRAVITY_PM_STATE_HOME lạ"; then ok "D4b: công tắc bật, pm home ngoài thư mục tạm -> từ chối"
else bad "D4b: pm home ngoài thư mục tạm: $OUT"; fi

# H. audited_head đọc verdicts.audit.auditedHead (không có trong notes); giá trị sai khuôn -> lùi về notes
mk_repo "$TMP/h"; H="$(git rev-parse HEAD)"
mkdir -p "$TMP/pm/projects/p-T0704/tasks/T0704-st"
printf '{"id":"T0704-st","project":"%s","verdicts":{"audit":{"verdict":"pass","notes":"ok","auditedHead":"%s"}}}\n' "$(pwd -P)" "$H" \
  > "$TMP/pm/projects/p-T0704/tasks/T0704-st/task.json"
pg audited_head "$TMP/h" T0704-st
if [ "$OUT" = "$H" ]; then ok "H: audited_head đọc trường cấu trúc auditedHead"
else bad "H: audited_head trường cấu trúc: '$OUT' (mong $H)"; fi
printf '{"id":"T0704-st","project":"%s","verdicts":{"audit":{"verdict":"pass","notes":"auditedHead: %s","auditedHead":"HEAD"}}}\n' "$(pwd -P)" "$C1" \
  > "$TMP/pm/projects/p-T0704/tasks/T0704-st/task.json"
pg audited_head "$TMP/h" T0704-st
if [ "$OUT" = "$C1" ]; then ok "H2: trường cấu trúc sai khuôn -> lùi về notes"
else bad "H2: auditedHead sai khuôn: '$OUT' (mong $C1)"; fi
# H3 (audit T0066 vòng 3): cùng biên bản hợp lệ của H2, pm home lạ KHÔNG bật công tắc test -> audited_head None (như approved()),
# vì post-fix-gate/merge gate dựa vào audited_head cho mục duyệt chéo: HOME=/tmp/x hay ANTIGRAVITY_PM_STATE_HOME tự dựng không duyệt được.
OUT="$(DEVKIT_PM_HOME_TEST= python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.audited_head(sys.argv[2], "T0704-st"))' "$PG_DIR" "$TMP/h" 2>&1)"
if [ "$OUT" = "None" ]; then ok "H3: pm home lạ, không công tắc test -> audited_head None"
else bad "H3: audited_head với pm home lạ không công tắc: '$OUT' (mong None)"; fi

# P. ANTIGRAVITY_PM_STATE_HOME lạ: lời duyệt vẫn cho exit 0 nhưng không cấp biên nhận
ORIGIN="$TMP/origin.git"; REPO="$TMP/prepo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src tests .agents
  echo 'fun ok()=1' > src/Core.kt; printf '#!/bin/sh\ntrue\n' > tests/t.sh
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/audit-gate/\n' > .gitignore
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git -C "$REPO" remote set-head origin main >/dev/null 2>&1
task_pass() { echo "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/task_pass.json"; }
full_exit() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("exit"))
except Exception: print("none")' "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
pgate() { OUT="$(CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --run-tests --no-checklist --lang vi "${@:2}" 2>&1)"; RC=$?; }

# P0. đối chứng: chỉ sửa code (không lời duyệt) cùng biến -> exit 0 và có biên nhận task
W0="$TMP/wt-p0"; git -C "$REPO" worktree add -q --detach "$W0" origin/main || exit 1
echo 'fun ok()=2' > "$W0/src/Core.kt"
pgate "$W0"
if [ "$RC" = 0 ] && [ -f "$(task_pass "$W0")" ]; then ok "P0: chỉ sửa code, pm home lạ -> biên nhận task vẫn ghi"
else bad "P0: đối chứng biên nhận task: rc=$RC, $(printf '%s' "$OUT" | tail -8)"; fi

# P1. test sửa + duyệt chéo dựa vào pm home lạ -> exit 0, duyệt chéo, KHÔNG biên nhận task, nói rõ vì sao
W1="$TMP/wt-p1"; git -C "$REPO" worktree add -q --detach "$W1" origin/main || exit 1
printf '#!/bin/sh\nexit 0\n' > "$W1/tests/t.sh"; echo 'fun ok()=2' > "$W1/src/Core.kt"
pm_task T0705-p "$W1" "$(git -C "$W1" stash create)"; approve "$W1" T0705-p
pgate "$W1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity" && [ ! -f "$(task_pass "$W1")" ] && has "ANTIGRAVITY_PM_STATE_HOME"; then
  ok "P1: duyệt chéo qua pm home lạ -> exit 0, không biên nhận task, nêu ANTIGRAVITY_PM_STATE_HOME"
else bad "P1: pm home lạ, lượt task: rc=$RC, task_pass=$([ -f "$(task_pass "$W1")" ] && echo có || echo không), $(printf '%s' "$OUT" | tail -8)"; fi

# P2. cùng cây, --full -> exit 0 nhưng full_pass.json không phải exit 0 (push gate / proof gate không nhận)
pgate "$W1" --full
FE="$(full_exit "$W1")"
if [ "$RC" = 0 ] && [ "$FE" != 0 ]; then ok "P2: --full, pm home lạ -> exit 0, full_pass.json exit=$FE (không nhận)"
else bad "P2: pm home lạ, --full: rc=$RC, full_pass exit=$FE, $(printf '%s' "$OUT" | tail -8)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
