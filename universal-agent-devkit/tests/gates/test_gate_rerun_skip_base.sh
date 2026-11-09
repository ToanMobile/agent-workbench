#!/usr/bin/env bash
# Gate speed v26 (lane D2): rerun_skip.json phải tính base đã phân giải của --diff. Lượt --scoped trên CÙNG cây, cùng suite nhưng base RỘNG
# hơn trước đây trả 0 ngay theo bản ghi skip và không ghi biên nhận scoped mới, nên Stop hook phải bảo agent thêm --force.
#   b1. --scoped --diff C1 (hẹp): suite chạy, biên nhận scoped base = C1.
#   b2. --scoped --diff C0 (rộng hơn, cùng cây): suite CHẠY, biên nhận scoped base = C0 (trước bản sửa: skip, base vẫn C1).
#   b3. lặp lại b2: bản ghi skip vẫn dùng được (không chạy lại).
#   b4. như b1, b2 với sổ suite theo khoá nội dung bật (mặc định): biên nhận scoped base C0.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SCOPED_TESTS DEVKIT_GATE_MERGE_CHECK POSTFIX_GATE_FULL \
      POSTFIX_GATE_FORCE_FULL CI DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_LEDGER_ROOT
export DEVKIT_SUITE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$TMP/repo"
mkdir -p "$REPO" && git -C "$REPO" init -q -b main . || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 0" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf 'ran\n.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> ran"}]}]}
JSON
  git add -A && git commit -qm c0
  echo "def ok(): return 1" > src/core.py && git commit -qam c1
  echo "def ok(): return 2" > src/core.py && git commit -qam c2 ) || exit 1
C0="$(git -C "$REPO" rev-parse HEAD~2)"; C1="$(git -C "$REPO" rev-parse HEAD~1)"
GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"

gate() { ( cd "$REPO" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --scoped "$@" \
  >"$TMP/gate" 2>&1 ); RC=$?; }
ran_n() { [ -f "$REPO/ran" ] && wc -l < "$REPO/ran" | tr -d ' ' || echo 0; }
rbase() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1], encoding="utf-8")).get("base") or "-")
except Exception: print("-")' "$GD/postfix-gate/scoped_pass.json"; }
show() { tail -c 400 "$TMP/gate" | tr '\n' ' '; }

gate --diff "$C1"
if ! grep -q -- "--scoped:" "$TMP/gate"; then fail "b1. tiền đề: lượt không phải --scoped ($(show))"
elif [ "$RC" = 0 ] && [ "$(ran_n)" = 1 ] && [ "$(rbase)" = "$C1" ] && [ -f "$GD/postfix-gate/rerun_skip.json" ]; then
  ok "b1. --diff C1: suite chạy, biên nhận scoped base C1, có rerun_skip.json"
else fail "b1. rc=$RC ran=$(ran_n) base=$(rbase) (mong 0 1 C1) $(show)"; fi

gate --diff "$C0"
if [ "$RC" = 0 ] && [ "$(ran_n)" = 2 ] && [ "$(rbase)" = "$C0" ]; then
  ok "b2. --diff C0 (rộng hơn, cùng cây): suite chạy lại, biên nhận scoped base C0"
else fail "b2. rc=$RC ran=$(ran_n) base=$(rbase | cut -c1-12) (mong 0 2 ${C0:0:12}) $(show)"; fi

gate --diff "$C0"
if [ "$RC" = 0 ] && [ "$(ran_n)" = 2 ] && grep -q "rerun_skip.json" "$TMP/gate" && [ "$(rbase)" = "$C0" ]; then
  ok "b3. lặp --diff C0: bản ghi skip dùng lại, không chạy lại"
else fail "b3. rc=$RC ran=$(ran_n) base=$(rbase | cut -c1-12) (mong 0 2, skip) $(show)"; fi

# b4. sổ suite theo khoá nội dung BẬT (mặc định): suite có thể được dùng lại, nhưng lượt base rộng hơn vẫn phải ghi biên nhận base C0.
git clone -q "$REPO" "$TMP/repo2" || exit 1
git -C "$TMP/repo2" config user.email t@t && git -C "$TMP/repo2" config user.name t
REPO="$TMP/repo2"; GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"
unset DEVKIT_SUITE_CACHE
gate --diff "$C1"; r1=$RC; b1="$(rbase)"
gate --diff "$C0"
if [ "$r1" = 0 ] && [ "$b1" = "$C1" ] && [ "$RC" = 0 ] && [ "$(rbase)" = "$C0" ]; then
  ok "b4. sổ suite bật: --diff C1 rồi --diff C0 ⇒ biên nhận scoped base C0"
else fail "b4. rc=$r1/$RC base=${b1:0:12}/$(rbase | cut -c1-12) (mong 0/0 ${C1:0:12}/${C0:0:12}) $(show)"; fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_rerun_skip_base: PASS"; exit 0; }
echo "test_gate_rerun_skip_base: FAIL ($FAILS)"
exit 1
