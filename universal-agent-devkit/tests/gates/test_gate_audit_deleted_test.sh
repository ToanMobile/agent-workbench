#!/usr/bin/env bash
# #1323: audit pass duyệt được test cũ đã XOÁ. Trước đây audit_covers `git hash-object` file hiện tại: file đã xoá -> rc≠0 -> "nội dung khác
# cây đã audit", và split_user_approved bỏ qua file không stat được -> gate exit 2 mãi dù có audit pass trên head (GeelyEx2#289, PR #1335).
#  A1: PR xoá tests/old.sh + sửa tests/t.sh, biên bản PM Antigravity (phạm vi có cả hai) tại head -> nhận cả hai, exit 0.
#  A1b: `agent-kit approve-tests` ghi mục cho t.sh, báo old.sh đã xoá được audit phủ (không ghi mục), gate exit 0.
#  A2: PR chỉ xoá tests/old.sh, trailer `Test-approved-by: antigravity <task>` -> nhận.
#  B1: xoá test, không audit -> vẫn chặn (exit 2, tên file trong danh sách cần duyệt).
#  B2: audit ở head khi test còn, xoá SAU audit, có trailer -> chặn (file còn ở cây đã audit).
#  B3: test đã xoá nằm ngoài danh sách edited của lượt audit -> chặn; B3b: approve-tests không báo "phủ" ca đó.
#  B4: audit mới hơn còn file -> chặn (luật 4). B5: main sửa test sau audit -> chặn (luật 5). B6: phiên reviewer không tự duyệt.
#  C1: xoá test + sửa test đã audit, rồi sửa tiếp tests/t.sh sau audit -> t.sh vẫn chặn (blob phải khớp auditedHead).
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
pm_ag() {   # pm_ag <task-id> <project> <auditedHead> [skip] [extra]: audit pass Antigravity kèm phạm vi như PM ghi (auditBase = merge-base(main,
  # head), edited = file đã có bị sửa/xoá trong auditBase..head); skip: bỏ <skip> khỏi edited (audit phạm vi hẹp); extra: thêm <extra> vào edited
  local d="p-$1"
  mkdir -p "$TMP/pm/projects/$d/tasks/$1"
  python3 - "$TMP/pm/projects/$d/tasks/$1/task.json" "$1" "$(cd "$2" && pwd -P)" "$3" "${4:-}" "${5:-}" <<'PY2'
import json, subprocess, sys
dest, tid, proj, head, skip, extra = sys.argv[1:7]
g = lambda *a: subprocess.run(["git", "-C", proj, *a], capture_output=True, text=True).stdout.strip()
mb = g("merge-base", "main", head)
ns = g("diff", "--name-status", "--no-renames", mb, head).splitlines()
edited = [l.split("\t", 1)[1] for l in ns if l[:1] in "MDT" and l.split("\t", 1)[1] != skip] + ([extra] if extra else [])
disp = {"kind": "audit", "agent": "antigravity", "at": "2026-11-19T00:00:00Z", "auditedHead": head, "verdict": "pass",
        "auditBase": mb, "edited": edited}
json.dump({"id": tid, "project": proj, "dispatches": [disp], "verdicts": {
    "audit": {"verdict": "pass", "round": 1, "reviewer": "antigravity", "notes": "ok", "auditedHead": head},
    "auditHistory": [{"auditedHead": head, "reviewer": "antigravity", "at": "2026-11-19T00:00:01Z"}]}}, open(dest, "w"))
PY2
}
V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V2='#!/bin/sh\ngrep -q "ok()" src/Core.kt\n'
mk() {   # mk <dir>: main M0 (tests/t.sh V0 chạy trong ma trận, tests/old.sh test cũ sẽ bị xoá), nhánh feat
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt; printf "$V0" > tests/t.sh; printf '#!/bin/sh\ngrep -q "fun" src/Core.kt\n' > tests/old.sh
  git add -A && git commit -qm "M0"
  git checkout -q -b feat
}
del_old() { git rm -q tests/old.sh; echo "fun ok()=$RANDOM" > src/Core.kt; git commit -qam "${1:-PR xoá test cũ}"; git rev-parse HEAD; }
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
blocked() { printf '%s' "$OUT" | grep -E "Test đã có bị sửa|cần duyệt|CHƯA XÁC MINH" | grep -qF -- "$1"; }
tailout() { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|CHƯA XÁC MINH|old.sh|t.sh|exit" | tail -6 | cut -c1-240; }

# A1. xoá tests/old.sh + sửa tests/t.sh; biên bản PM tại head (edited có cả hai) -> nhận, exit 0
mk "$TMP/a1"; printf "$V1" > tests/t.sh; X="$(del_old "PR sửa t.sh, xoá old.sh")"; pm_ag T2001-a1 "$TMP/a1" "$X"
run_gate "$TMP/a1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T2001-a1)" && ! has "CHƯA XÁC MINH"; then ok "A1: test đã xoá + test sửa, audit PM tại head -> nhận"
else bad "A1: test đã xoá có audit pass: rc=$RC, $(tailout)"; fi

# A1b. `agent-kit approve-tests` (ca PR #1335): ghi mục cho t.sh, báo old.sh đã xoá được audit phủ (không ghi mục); gate sau đó exit 0
OUT="$(cd "$TMP/a1" && DEVKIT_AGENT_ID=claude CLAUDE_PROJECT_DIR="$TMP/a1" bash "$DEVKIT_DIR/bin/agent-kit" approve-tests T2001-a1 2>&1)"; RC=$?
AK="$OUT"; run_gate "$TMP/a1"
if printf '%s' "$AK" | grep -qF "tests/old.sh đã xoá — cây đã audit cũng không có file, nằm trong phạm vi audit T2001-a1" && printf '%s' "$AK" | grep -qF "tests/t.sh sha256=" && [ "$RC" = 0 ] \
   && ! grep -qF '"tests/old.sh"' "$TMP/a1/.claude/audit-gate/approved_tests.json"; then ok "A1b: approve-tests báo test đã xoá được audit phủ, gate exit 0"
else bad "A1b: approve-tests + test đã xoá: rc=$RC, $(printf '%s' "$AK" | tail -3)"; fi

# A2. chỉ xoá test; trailer Test-approved-by trỏ biên bản PM tại head -> nhận
mk "$TMP/a2"; X="$(del_old)"; pm_ag T2002-a2 "$TMP/a2" "$X"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T2002-a2"
run_gate "$TMP/a2"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T2002-a2)"; then ok "A2: test đã xoá, trailer audit -> nhận"
else bad "A2: trailer cho test đã xoá: rc=$RC, $(tailout)"; fi

# B1. xoá test, không audit -> vẫn chặn
mk "$TMP/b1"; del_old >/dev/null
run_gate "$TMP/b1"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi" && has "tests/old.sh"; then ok "B1: xoá test không audit -> chặn"
else bad "B1: xoá test không audit: rc=$RC, $(tailout)"; fi

# B2. audit ở head khi tests/old.sh còn (chỉ sửa code), xoá test SAU audit; trailer trỏ audit đó (trailer không lọc phạm vi, nên chỉ luật
#     "cây đã audit còn file" của audit_covers chặn) -> chặn. B2p: biên bản PM có edited ghi cả tests/old.sh (phạm vi khai rộng) -> vẫn chặn
#     nhờ cùng luật đó (ca duy nhất tới được nhánh này của audit_covers).
mk "$TMP/b2"; echo 'fun ok()=2' > src/Core.kt; git commit -qam "PR code"; X="$(git rev-parse HEAD)"; pm_ag T2012-b2 "$TMP/b2" "$X" "" tests/old.sh
git rm -q tests/old.sh && git commit -qm "xoá sau audit"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T2012-b2"
run_gate "$TMP/b2"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "B2: xoá test sau audit -> chặn"
else bad "B2: xoá sau audit: rc=$RC, $(tailout)"; fi

# B3. test đã xoá nằm ngoài danh sách edited của lượt audit (phạm vi hẹp) -> chặn
mk "$TMP/b3"; X="$(del_old)"; pm_ag T2013-b3 "$TMP/b3" "$X" tests/old.sh
run_gate "$TMP/b3"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "B3: test xoá ngoài phạm vi audit -> chặn"
else bad "B3: ngoài phạm vi: rc=$RC, $(tailout)"; fi
OUT="$(cd "$TMP/b3" && DEVKIT_AGENT_ID=claude CLAUDE_PROJECT_DIR="$TMP/b3" bash "$DEVKIT_DIR/bin/agent-kit" approve-tests T2013-b3 2>&1)"; RC=$?
if [ "$RC" = 1 ] && has "không ghi phạm vi chứa file" && has "test đã xoá không cần mục"; then ok "B3b: approve-tests không báo 'phủ' khi phạm vi audit thiếu file"
else bad "B3b: approve-tests phạm vi hẹp: rc=$RC, $(printf '%s' "$OUT" | tail -3)"; fi

# B4. luật 4 (chỉ audit mới nhất): audit T1 ở X1 (đã xoá), khôi phục test ở X2 và audit T2 ở X2, rồi xoá lại; trailer trỏ T1 -> chặn
mk "$TMP/b4"; X1="$(del_old)"; pm_ag T2041-b4 "$TMP/b4" "$X1"
git show main:tests/old.sh > tests/old.sh && git add tests/old.sh && git commit -qm "khôi phục old.sh"; X2="$(git rev-parse HEAD)"; pm_ag T2042-b4 "$TMP/b4" "$X2"
git rm -q tests/old.sh && git commit -qm "xoá lại"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T2041-b4"
run_gate "$TMP/b4"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "B4: audit mới hơn còn file -> audit cũ (đã xoá) không dùng được"
else bad "B4: luật audit mới nhất: rc=$RC, $(tailout)"; fi

# B5. luật 5: audit ở head đã xoá, sau đó main sửa tests/old.sh -> chặn (main đổi file kể từ audit)
mk "$TMP/b5"; X="$(del_old)"; pm_ag T2051-b5 "$TMP/b5" "$X"
git checkout -q main && printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\n' > tests/old.sh && git commit -qam "main sửa old.sh" && git checkout -q feat
run_gate "$TMP/b5"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "B5: main sửa test sau audit -> chặn"
else bad "B5: luật nhánh đích: rc=$RC, $(tailout)"; fi

# B6. phiên là reviewer (DEVKIT_AGENT_ID=antigravity) -> không tự duyệt việc xoá
mk "$TMP/b6"; X="$(del_old)"; pm_ag T2061-b6 "$TMP/b6" "$X"
run_gate "$TMP/b6" DEVKIT_AGENT_ID=antigravity
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi" && blocked "tests/old.sh"; then ok "B6: phiên antigravity không tự duyệt test đã xoá"
else bad "B6: tự duyệt: rc=$RC, $(tailout)"; fi

# C1. xoá old.sh + sửa t.sh (V1) đã audit, rồi sửa t.sh (V2) sau audit -> t.sh chặn (blob phải khớp auditedHead), old.sh vẫn nhận
mk "$TMP/c1"; printf "$V1" > tests/t.sh; X="$(del_old "PR sửa t.sh, xoá old.sh")"; pm_ag T2021-c1 "$TMP/c1" "$X"
printf "$V2" > tests/t.sh; git commit -qam "nới t.sh sau audit"
run_gate "$TMP/c1"
if [ "$RC" = 2 ] && has "duyệt chéo bởi antigravity (task T2021-c1)" && blocked "tests/t.sh"; then ok "C1: sửa test sau audit vẫn chặn, test xoá vẫn nhận"
else bad "C1: sửa test sau audit: rc=$RC, $(tailout)"; fi

# D. approved_tests.json (comment duyệt tay edited-tests, cài bởi super-board-install-edited-test-approval.sh): mục `"sha256": "deleted"`.
#    Audit phạm vi hẹp (không ghi old.sh / t.sh) để chỉ mục json quyết định.
jentry() {   # jentry <dir> <path> <sha256> <task>
  python3 -c '
import json, sys
d, path, digest, task = sys.argv[1:5]
json.dump({"approvals": [{"path": path, "sha256": digest, "reviewer": "antigravity", "author": "claude", "task_id": task,
                          "reason": "duyệt tay"}]}, open(d + "/.claude/audit-gate/approved_tests.json", "w"))
' "$1" "$2" "$3" "$4"
}
# D1. test đã xoá + mục deleted, biên bản PM tại head -> nhận
mk "$TMP/d1"; X="$(del_old)"; pm_ag T2071-d1 "$TMP/d1" "$X" tests/old.sh
mkdir -p .claude/audit-gate && jentry "$TMP/d1" tests/old.sh deleted T2071-d1
run_gate "$TMP/d1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T2071-d1)"; then ok "D1: mục json deleted cho test đã xoá -> nhận"
else bad "D1: mục json deleted: rc=$RC, $(tailout)"; fi
# D2. tests/t.sh sửa (còn file) + mục deleted cho t.sh -> không duyệt (mục deleted không nới ca sửa test)
mk "$TMP/d2"; printf "$V1" > tests/t.sh; git commit -qam "sửa t.sh"; X="$(git rev-parse HEAD)"; pm_ag T2072-d2 "$TMP/d2" "$X" tests/t.sh
mkdir -p .claude/audit-gate && jentry "$TMP/d2" tests/t.sh deleted T2072-d2
run_gate "$TMP/d2"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi" && blocked "tests/t.sh"; then ok "D2: mục deleted cho file còn ở cây -> không duyệt"
else bad "D2: mục deleted cho file còn: rc=$RC, $(tailout)"; fi
# D3. mục deleted nhưng task không có biên bản audit -> chặn
mk "$TMP/d3"; del_old >/dev/null
mkdir -p .claude/audit-gate && jentry "$TMP/d3" tests/old.sh deleted T2073-d3
run_gate "$TMP/d3"
if [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; then ok "D3: mục deleted không biên bản audit -> chặn"
else bad "D3: mục deleted không audit: rc=$RC, $(tailout)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
