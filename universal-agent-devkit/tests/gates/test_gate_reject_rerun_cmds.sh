#!/usr/bin/env bash
# Test hồi quy (chủ repo 05/11: "lỗi 1 chỗ thì chạy lại 1 chỗ thôi"): gate REJECT in đúng lệnh chạy lại RIÊNG từng chỗ đỏ — suite thường
# in lệnh của suite; shard tests/run_impacted.sh in `bash <kit>/tests/<test đỏ>` (dòng "✖ tests/x.sh"), không in lệnh cả shard — kèm câu
# "repo đi PR: không chạy lại cả gate local, merge gate verify một lần". Suite xanh không có trong danh sách. bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S \
      DEVKIT_GATE_MERGE_CHECK DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_PRIORITY POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents kit/tests/gates
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  printf 'echo "✔ tests/gates/test_ok.sh"\necho "✖ tests/gates/test_red.sh"\necho "  detail"\nexit 1\n' > kit/tests/run_impacted.sh
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[
  {"id":"REG-A","name":"plain red","command":"exit 1"},
  {"id":"REG-B","name":"shard red","command":"bash kit/tests/run_impacted.sh"},
  {"id":"REG-C","name":"green","command":"true"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
echo "def ok(): return 2" > "$REPO/src/core.py"

CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --no-cache --scoped --brief >"$TMP/gate" 2>&1; rc=$?
# khối chạy lại: từ dòng tiêu đề tới hết đầu ra
awk '/Chạy lại riêng|Re-run only/ { f = 1 } f' "$TMP/gate" > "$TMP/block"   # awk: sed BSD không có \| trong BRE
show() { tail -c 900 "$TMP/gate" | tr '\n' ' '; }
[ "$rc" = 1 ] && ok "gate đỏ exit 1" || fail "rc $rc (want 1) $(show)"
[ -s "$TMP/block" ] && ok "REJECT có khối 'Chạy lại riêng'" || fail "không có khối chạy lại $(show)"
grep -q '`exit 1`' "$TMP/block" && ok "suite thường: in lệnh của suite (REG-A)" || fail "thiếu lệnh REG-A: $(tr '\n' ' ' < "$TMP/block")"
grep -q '`bash kit/tests/gates/test_red.sh`' "$TMP/block" && ok "shard: in đúng test đỏ của run_impacted.sh" \
  || fail "thiếu bash kit/tests/gates/test_red.sh: $(tr '\n' ' ' < "$TMP/block")"
grep -q 'run_impacted.sh`' "$TMP/block" && fail "in lệnh cả shard thay vì test đỏ" || ok "không in lệnh cả shard"
grep -q 'test_ok.sh\|`true`' "$TMP/block" && fail "in cả test/suite xanh" || ok "không in test/suite xanh"
grep -q 'merge gate' "$TMP/block" && ok "nhắc repo đi PR: merge gate verify một lần" || fail "thiếu câu merge gate"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_reject_rerun_cmds: PASS"; exit 0; }
echo "test_gate_reject_rerun_cmds: FAIL ($FAILS)"
exit 1
