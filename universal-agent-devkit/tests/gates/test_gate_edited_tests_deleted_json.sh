#!/usr/bin/env bash
# #1323 (sau PR #1338): mục approved_tests.json `"sha256": "deleted"` (cài từ comment edited-tests bởi
# super-board-install-edited-test-approval.sh) duyệt test đã có bị xoá; file còn ở cây thì mục deleted không duyệt nó.
#  D1: test đã xoá + mục deleted + biên bản PM tại head (phạm vi hẹp, không ghi file) -> nhận, exit 0.
#  D2: tests/t.sh sửa (còn file) + mục deleted cho t.sh -> không duyệt (exit 2).
#  D3: mục deleted nhưng task không có biên bản audit -> chặn.
#  D4: audit_covers từ chối file đã xoá không có ở merge-base (thêm rồi xoá trong PR).
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

# D4. test thêm rồi xoá ngay trong PR (không có ở merge-base): gate không coi là test đã có, nên gọi thẳng audit_covers (nguồn chung của
#     mục json, trailer, biên bản PM): phải từ chối vì file không có ở merge-base, kể cả khi audit tại head và cây đã audit không có file.
mk "$TMP/d4"; printf '#!/bin/sh\ntrue\n' > tests/ghost.sh; git add tests/ghost.sh; git commit -qm "thêm ghost"
git rm -q tests/ghost.sh; echo 'fun ok()=4' > src/Core.kt; git commit -qam "xoá ghost"; X="$(git rev-parse HEAD)"; pm_ag T2074-d4 "$TMP/d4" "$X"
OUT="$(cd "$TMP/d4" && CLAUDE_PROJECT_DIR="$TMP/d4" python3 - "$GATE" "$TMP/d4" "$X" <<'PY3' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for f in ("tests/ghost.sh", "tests/old.sh"):
    print(f, m.audit_covers(sys.argv[2], "", sys.argv[2], f, sys.argv[3]))
PY3
)"
if has "tests/ghost.sh (False" && has "không có ở merge-base"; then ok "D4: audit_covers từ chối file đã xoá không có ở merge-base"
else bad "D4: audit_covers với file thêm rồi xoá: $(printf '%s' "$OUT" | tail -3 | cut -c1-240)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
