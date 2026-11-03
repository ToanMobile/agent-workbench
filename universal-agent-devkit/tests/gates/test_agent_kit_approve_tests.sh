#!/usr/bin/env bash
# Đợt 2 gate, lane A mục 2: `agent-kit approve-tests <task-id>` ghi mục duyệt chéo từ biên bản antigravity-pm, và reviewer `grok`.
#  C1  grok hợp lệ (verdicts.audit.reviewer grok, lượt audit gần nhất agent grok): lệnh ghi mục reviewer grok, author = DEVKIT_AGENT_ID;
#      gate nhận, nhãn "duyệt chéo bởi grok (thay Antigravity)".
#  C2  DEVKIT_AGENT_ID rỗng -> lệnh từ chối, không ghi.   C3  reviewer trùng author -> lệnh từ chối; gate từ chối khi phiên là grok.
#  C4  reviewer grok nhưng lượt audit gần nhất là antigravity -> lệnh từ chối; mục viết tay -> gate từ chối.
#  C5  biên bản cũ (reviewer pm) + dispatch audit không ghi agent -> antigravity.   C6  biên bản cũ không dispatch -> lệnh từ chối.
#  C7  alias grok-4.7 / Grok -> grok.   C8  trailer `Test-approved-by: grok|antigravity` phải khớp reviewer PM (push_gate.approved).
#  C9  test sửa sau audit không được ghi.   C10  .claude/audit-gate trỏ ra ngoài checkout -> từ chối.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
DA='{"kind":"audit","agent":"antigravity","at":"2026-11-01T00:00:00Z"}'
DG='{"kind":"audit","agent":"grok","at":"2026-11-02T00:00:00Z"}'
DL='{"kind":"audit","at":"2026-11-01T00:00:00Z"}'
pm_rec() {   # pm_rec <task-id> <project> <auditedHead> <reviewer> <dispatches-json-array>
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":%s,"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"%s","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$5" "$4" "$3" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
mk() {   # mk <dir>: main M0, nhánh feat có commit X sửa tests/t.sh (không phải nối thêm); in X qua biến X
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh && sh tests/u.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt
  printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\n' > tests/t.sh; printf '#!/bin/sh\ngrep -q "fun" src/Core.kt\n' > tests/u.sh
  git add -A && git commit -qm M0 && git checkout -q -b feat
  printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\n' > tests/t.sh; echo 'fun ok()=2' > src/Core.kt
  git commit -qam "PR sửa test"; X="$(git rev-parse HEAD)"
}
kit() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$KIT" approve-tests "$2" 2>&1)"; RC=$?; }
run_gate() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
ledger() { python3 - "$1/.claude/audit-gate/approved_tests.json" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
print(" ".join(f"{e['path']}:{e['reviewer']}:{e['author']}:{e['task_id']}" for e in d["approvals"] if e["path"] == sys.argv[2] or sys.argv[2] == "*"))
PY
}
hand_entry() {   # hand_entry <repo> <task> <reviewer>: mục viết tay cho tests/t.sh
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, json, os, sys
root, tid, rv = sys.argv[1:4]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": rv, "author": "claude", "task_id": tid, "reason": "tay"}]},
          open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
}

# C1
mk "$TMP/c1"; pm_rec T0901-c1 "$TMP/c1" "$X" grok "[$DA,$DG]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c1" T0901-c1; L="$(ledger "$TMP/c1" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:grok:claude-lane:T0901-c1" ]; then ok "C1: lệnh ghi mục reviewer grok, author = DEVKIT_AGENT_ID"
else bad "C1: lệnh grok: rc=$RC ledger='$L' $(printf '%s' "$OUT" | tail -3)"; fi
run_gate "$TMP/c1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task T0901-c1)"; then ok "C1: gate nhận, nhãn grok (thay Antigravity)"
else bad "C1: gate với mục grok: rc=$RC $(printf '%s' "$OUT" | grep -E 'duyệt|Duyệt' | tail -3)"; fi
# C3 (gate): cùng mục, phiên hiện tại là grok -> từ chối
OUT="$(cd "$TMP/c1" && DEVKIT_AGENT_ID=grok CLAUDE_PROJECT_DIR="$TMP/c1" python3 "$GATE" --matrix "$TMP/c1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?
if [ "$RC" = 2 ] && has "trùng author"; then ok "C3: gate, phiên là grok, reviewer PM grok -> từ chối (tự duyệt)"
else bad "C3: gate tự duyệt grok: rc=$RC $(printf '%s' "$OUT" | grep -E 'Duyệt' | tail -2)"; fi

# C2
mk "$TMP/c2"; pm_rec T0902-c2 "$TMP/c2" "$X" grok "[$DG]"
kit "$TMP/c2" T0902-c2
if [ "$RC" = 2 ] && has "DEVKIT_AGENT_ID" && [ ! -f "$TMP/c2/.claude/audit-gate/approved_tests.json" ]; then ok "C2: DEVKIT_AGENT_ID rỗng -> từ chối, không ghi"
else bad "C2: id rỗng: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C3 (lệnh): author trùng reviewer qua alias
DEVKIT_AGENT_ID=grok-build kit "$TMP/c2" T0902-c2
if [ "$RC" = 2 ] && has "tự duyệt" && [ ! -f "$TMP/c2/.claude/audit-gate/approved_tests.json" ]; then ok "C3: lệnh, author grok-build = reviewer grok -> từ chối"
else bad "C3: lệnh tự duyệt: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C4: reviewer grok nhưng lượt audit gần nhất là antigravity
mk "$TMP/c4"; pm_rec T0904-c4 "$TMP/c4" "$X" grok "[$DG,{\"kind\":\"audit\",\"agent\":\"antigravity\",\"at\":\"2026-11-03T00:00:00Z\"}]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c4" T0904-c4
if [ "$RC" = 2 ] && has "reviewer"; then ok "C4: grok không phải lượt audit gần nhất -> lệnh từ chối"
else bad "C4: lệnh grok sai lượt: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi
hand_entry "$TMP/c4" T0904-c4 grok; run_gate "$TMP/c4"
if [ "$RC" = 2 ] && has "không xác định được reviewer"; then ok "C4: mục viết tay reviewer grok không có lượt grok -> gate từ chối"
else bad "C4: gate grok sai lượt: rc=$RC $(printf '%s' "$OUT" | grep -E 'duyệt|Duyệt' | tail -2)"; fi

# C5: biên bản cũ (reviewer pm) + dispatch audit không ghi agent -> antigravity
mk "$TMP/c5"; pm_rec T0905-c5 "$TMP/c5" "$X" pm "[$DL]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c5" T0905-c5; L="$(ledger "$TMP/c5" tests/t.sh)"
run_gate "$TMP/c5"
if [ "$L" = "tests/t.sh:antigravity:claude-lane:T0905-c5" ] && [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T0905-c5)"; then
  ok "C5: biên bản cũ + dispatch audit không agent -> antigravity, gate nhận"
else bad "C5: biên bản cũ: rc=$RC ledger='$L'"; fi

# C6: biên bản cũ không dispatch nào -> lệnh từ chối
mk "$TMP/c6"; pm_rec T0906-c6 "$TMP/c6" "$X" pm "[]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c6" T0906-c6
if [ "$RC" = 2 ] && [ ! -f "$TMP/c6/.claude/audit-gate/approved_tests.json" ]; then ok "C6: biên bản cũ không dispatch audit -> lệnh từ chối"
else bad "C6: biên bản cũ không dispatch: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C7: alias
mk "$TMP/c7"; pm_rec T0907-c7 "$TMP/c7" "$X" grok-4.7 '[{"kind":"audit","agent":"Grok","at":"2026-11-02T00:00:00Z"}]'
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c7" T0907-c7; L="$(ledger "$TMP/c7" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:grok:claude-lane:T0907-c7" ]; then ok "C7: alias grok-4.7 / Grok -> grok"
else bad "C7: alias: rc=$RC ledger='$L'"; fi

# C8: trailer phải khớp reviewer PM
pgok() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(*p.approved(sys.argv[2], "HEAD^!"))' "$DEVKIT_DIR/bin" "$1" 2>&1; }
mk "$TMP/c8"; pm_rec T0908-g "$TMP/c8" "$X" grok "[$DG]"; pm_rec T0908-l "$TMP/c8" "$X" pm "[$DL]"
git commit -q --allow-empty -m a -m "Test-approved-by: grok T0908-g"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in True*) ok "C8: trailer grok + biên bản grok -> approved";; *) bad "C8: trailer grok: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: antigravity T0908-g"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in False*reviewer*) ok "C8: trailer antigravity, biên bản grok -> từ chối";; *) bad "C8: trailer antigravity/biên bản grok: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: grok T0908-l"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in False*reviewer*) ok "C8: trailer grok, biên bản cũ (antigravity) -> từ chối";; *) bad "C8: trailer grok/biên bản cũ: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: antigravity T0908-l"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in True*) ok "C8: trailer antigravity + biên bản cũ -> approved (như trước)";; *) bad "C8: trailer antigravity cũ: $OUT";; esac

# C9: tests/u.sh sửa SAU audit -> không ghi; tests/t.sh vẫn ghi
mk "$TMP/c9"; pm_rec T0909-c9 "$TMP/c9" "$X" grok "[$DG]"
printf '#!/bin/sh\ngrep -q "fun ok" src/Core.kt\n' > tests/u.sh
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c9" T0909-c9; L="$(ledger "$TMP/c9" '*')"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:grok:claude-lane:T0909-c9" ] && has "bỏ qua tests/u.sh"; then ok "C9: test sửa sau audit không được ghi"
else bad "C9: test sửa sau audit: rc=$RC ledger='$L'"; fi

# C10: .claude/audit-gate là symlink ra ngoài checkout
mk "$TMP/c10"; pm_rec T0910-c10 "$TMP/c10" "$X" grok "[$DG]"
mkdir -p "$TMP/outside" && ln -s "$TMP/outside" "$TMP/c10/.claude/audit-gate"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c10" T0910-c10
if [ "$RC" = 2 ] && has "ngoài checkout" && [ ! -f "$TMP/outside/approved_tests.json" ]; then ok "C10: thư mục duyệt trỏ ra ngoài checkout -> từ chối"
else bad "C10: symlink ra ngoài: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
