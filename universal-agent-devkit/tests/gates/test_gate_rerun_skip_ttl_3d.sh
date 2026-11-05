#!/usr/bin/env bash
# Test hồi quy #992 (P3): bản ghi rerun_skip.json (#648, lượt gate exit 0 bỏ qua suite khi cùng fp/mode/suite) dùng hạn mặc định
# DEVKIT_GATE_CACHE_MAX_S như mọi PASS dùng lại khác (3 ngày = 259200 s, 05/11 #995) — trước đó _rerun_skip_expired còn mặc định 21600 (6 h).
#  T1. biến không đặt, bản ghi 7 giờ tuổi ⇒ dùng lại (suite không chạy). Trước: hết hạn ⇒ suite chạy lại (ĐỎ).
#  T2. biến không đặt, bản ghi 4 ngày tuổi ⇒ hết hạn ⇒ suite chạy lại.
#  T3. DEVKIT_GATE_CACHE_MAX_S=3600, bản ghi 7 giờ tuổi ⇒ biến vẫn thắng mặc định ⇒ chạy lại.
#  T4. DEVKIT_GATE_CACHE_MAX_S=0 ⇒ _rerun_skip_expired trả True (max_s ≤ 0) ⇒ suite chạy lại.
# Không sửa tests/gates/test_gate_rerun_skip.sh (ca cũ). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S
export DEVKIT_SUITE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf 'ran\n.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> ran"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
echo "def ok(): return 2" > "$REPO/src/core.py"
GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"
SKIP="$GD/postfix-gate/rerun_skip.json"

gate() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests "$@" >"$TMP/gate" 2>&1; }
ran_n() { [ -f "$REPO/ran" ] && wc -l < "$REPO/ran" | tr -d ' ' || echo 0; }
show() { tail -c 400 "$TMP/gate" | tr '\n' ' '; }
age() { python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$SKIP" "$1"; }

gate; rc=$?
if [ "$rc" = 0 ] && [ "$(ran_n)" = 1 ] && [ -f "$SKIP" ]; then ok "T0. lượt đầu: exit 0, suite chạy 1 lần, có rerun_skip.json"
else fail "T0. lượt đầu: rc $rc, ran=$(ran_n), skip=$([ -f "$SKIP" ] && echo có || echo không) $(show)"; fi

age 25200   # 7 giờ
b=$(ran_n); gate; rc=$?
if [ "$rc" = 0 ] && [ "$(ran_n)" = "$b" ] && grep -q "$SKIP" "$TMP/gate"; then ok "T1. bản ghi 7 giờ, biến không đặt: dùng lại (hạn mặc định 3 ngày)"
else fail "T1. bản ghi 7 giờ: rc $rc, ran $b → $(ran_n) (mong không đổi — hạn mặc định phải là 259200, không phải 21600) $(show)"; fi

age 345600   # 4 ngày
b=$(ran_n); gate; rc=$?
if [ "$rc" = 0 ] && [ "$(ran_n)" = $((b + 1)) ]; then ok "T2. bản ghi 4 ngày, biến không đặt: hết hạn, suite chạy lại"
else fail "T2. bản ghi 4 ngày: rc $rc, ran $b → $(ran_n) (mong +1) $(show)"; fi

age 25200
b=$(ran_n); DEVKIT_GATE_CACHE_MAX_S=3600 gate; rc=$?
if [ "$rc" = 0 ] && [ "$(ran_n)" = $((b + 1)) ]; then ok "T3. DEVKIT_GATE_CACHE_MAX_S=3600, bản ghi 7 giờ: biến thắng mặc định, suite chạy lại"
else fail "T3. biến 3600: rc $rc, ran $b → $(ran_n) (mong +1) $(show)"; fi

b=$(ran_n); DEVKIT_GATE_CACHE_MAX_S=0 gate; rc=$?
if [ "$rc" = 0 ] && [ "$(ran_n)" = $((b + 1)) ]; then ok "T4. DEVKIT_GATE_CACHE_MAX_S=0: không dùng lại, suite chạy lại"
else fail "T4. biến 0: rc $rc, ran $b → $(ran_n) (mong +1) $(show)"; fi

[ "$FAILS" -eq 0 ] && { echo "✅ test_gate_rerun_skip_ttl_3d: all passed"; exit 0; }
echo "❌ test_gate_rerun_skip_ttl_3d: $FAILS failed"; exit 1
