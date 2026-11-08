#!/usr/bin/env bash
# Test hồi quy #992 (P3 review PR #993, khối "Chạy lại riêng các chỗ đỏ" của post-fix-gate.py REJECT):
#  T1. hơn 20 lệnh chạy lại: danh sách cắt [:20] phải báo "… +N" (trước: cắt im lặng, người đọc tưởng chỉ 20 chỗ đỏ).
#  T2. shard run_impacted.sh TIMEOUT: dòng ✖ chỉ có test đỏ, test treo không có dòng ✖ ⇒ phải in lệnh cả shard. Rào giữ: hôm nay
#      suite TIMEOUT không mang fail_lines (post-fix-gate chỉ tính chúng cho lượt không quá giờ) nên khối đã in lệnh shard; code nay cộng
#      lệnh shard cho mọi TIMEOUT để một fail_lines có ✖ (đường khác, sau này) không làm mất test treo.
#  T3. vế "(không chạy lại cả gate local)" chỉ in ở repo đi PR (.claude/super-board/configs/*.json); repo push thẳng trunk vẫn cần
#      gate exit 0 trước push nên tiêu đề không được bảo bỏ gate local (trước: in ở mọi repo).
#  T4. đối chứng: repo đi PR có vế đó; shard FAIL (không TIMEOUT) vẫn không in lệnh cả shard.
# Không sửa tests/gates/test_gate_reject_rerun_cmds.sh (ca cũ). bash 3.2 compatible.
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

# mkrepo <dir> <matrix tests JSON> <shard body>: repo + origin, src/core.py sửa sau commit để suite chạy
mkrepo() {
  local repo="$1" tests="$2" shard="$3"
  git init -q --bare -b main "$repo.git" && git clone -q "$repo.git" "$repo" 2>/dev/null || exit 1
  ( cd "$repo" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
    mkdir -p src templates .agents kit/tests/gates
    echo "def ok(): return 1" > src/core.py
    echo '{"profile":"backend"}' > .agents/active-profile.json
    printf '.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
    printf '%b' "$shard" > kit/tests/run_impacted.sh
    printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],"mandatory_regression_tests":[%s]}]}\n' "$tests" \
      > templates/regression_matrix.json
    git add -A && git commit -qm init && git push -q origin main ) || exit 1
  echo "def ok(): return 2" > "$repo/src/core.py"
}
block() { awk '/Chạy lại riêng|Re-run only/ { f = 1 } f' "$1"; }   # awk: sed BSD không có \| trong BRE
HDR_PR='không chạy lại cả gate local'

# ── T1 + T3: repo push thẳng trunk, shard FAIL với 25 test đỏ ──
SH1='i=1; while [ $i -le 25 ]; do echo "✖ tests/gates/test_r$i.sh"; i=$((i+1)); done\nexit 1\n'
mkrepo "$TMP/r1" '{"id":"REG-B","name":"shard red","command":"bash kit/tests/run_impacted.sh"}' "$SH1"
CLAUDE_PROJECT_DIR="$TMP/r1" python3 "$GATE" --no-checklist --run-tests --no-cache --scoped --brief >"$TMP/g1" 2>&1; rc=$?
block "$TMP/g1" > "$TMP/b1"
[ "$rc" = 1 ] && [ -s "$TMP/b1" ] && ok "T0. gate đỏ (exit 1) có khối chạy lại" || fail "T0. rc $rc / không có khối: $(tail -c 600 "$TMP/g1" | tr '\n' ' ')"
n="$(grep -c '`bash kit/tests/gates/test_r[0-9]*\.sh`' "$TMP/b1")"
[ "$n" = 20 ] && ok "T1. in đúng 20 lệnh đầu" || fail "T1. in $n lệnh (want 20)"
grep -q '… +5' "$TMP/b1" && ok "T1. báo phần bị cắt: … +5" || fail "T1. cắt [:20] im lặng (không có '… +5'): $(tr '\n' ' ' < "$TMP/b1")"
grep -q "$HDR_PR" "$TMP/b1" && fail "T3. repo push thẳng trunk mà tiêu đề vẫn bảo không chạy lại cả gate local" \
  || ok "T3. repo push thẳng trunk: tiêu đề không có vế '(không chạy lại cả gate local)'"
grep -q 'run_impacted.sh`' "$TMP/b1" && fail "T4. shard FAIL (không TIMEOUT) mà in lệnh cả shard" || ok "T4. shard FAIL: không in lệnh cả shard"

# ── T2 + T4: repo đi PR, shard in 1 test đỏ rồi treo (TIMEOUT) ──
SH2='echo "✖ tests/gates/test_red.sh"\nsleep 30\n'
mkrepo "$TMP/r2" '{"id":"REG-H","name":"shard hang","command":"bash kit/tests/run_impacted.sh"}' "$SH2"
mkdir -p "$TMP/r2/.claude/super-board/configs" && echo '{"base_branch":"main"}' > "$TMP/r2/.claude/super-board/configs/t.json"
CLAUDE_PROJECT_DIR="$TMP/r2" DEVKIT_CAPACITY_LOAD=9999 python3 "$GATE" --no-checklist --run-tests --no-cache --scoped --brief --timeout 3 \
  >"$TMP/g2" 2>&1; rc=$?
block "$TMP/g2" > "$TMP/b2"
grep -qE 'TIMEOUT.*REG-H|REG-H.*TIMEOUT' "$TMP/g2" && ok "T2. suite REG-H TIMEOUT (rc $rc)" || fail "T2. REG-H không TIMEOUT (rc $rc): $(grep REG-H "$TMP/g2" | head -3 | tr '\n' ' ')"
grep -q '`bash kit/tests/run_impacted.sh`' "$TMP/b2" && ok "T2. shard TIMEOUT: cộng lệnh cả shard (test treo không có dòng ✖)" \
  || fail "T2. shard TIMEOUT mà không in lệnh cả shard: $(tr '\n' ' ' < "$TMP/b2")"
grep -q "$HDR_PR" "$TMP/b2" && ok "T4. repo đi PR: tiêu đề có vế '(không chạy lại cả gate local)'" \
  || fail "T4. repo đi PR mất vế '(không chạy lại cả gate local)': $(tr '\n' ' ' < "$TMP/b2")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_reject_rerun_trunc_timeout: PASS"; exit 0; }
echo "test_gate_reject_rerun_trunc_timeout: FAIL ($FAILS)"
exit 1
