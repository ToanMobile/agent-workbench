#!/usr/bin/env bash
# #678: bản ghi rerun_skip.json (#648) không được bỏ qua suite không có khoá nội dung ("cache": false, runner run_impacted.sh, mạng).
# Luật của test_gate_impacted_cache.sh ca h: suite đó chạy MỖI lượt. Lượt hai cùng cây, cùng mode, cùng danh sách suite: suite cache:false
# phải chạy lại (ran2 = 2 dòng). Đối chứng: không còn suite cache:false thì lượt hai vẫn thoát từ bản ghi skip.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE
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
  printf 'ran\nran2\n.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> ran"},
  {"id":"REG-2","name":"luon chay","command":"echo y >> ran2","cache":false}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
echo "def ok(): return 2" > "$REPO/src/core.py"
GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"
SKIP="$GD/postfix-gate/rerun_skip.json"

gate() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests "$@" >"$TMP/gate" 2>&1; }
lines() { if [ -f "$REPO/$1" ]; then wc -l < "$REPO/$1" | tr -d ' '; else echo 0; fi; }
show() { tail -c 500 "$TMP/gate" | tr '\n' ' '; }

gate; rc=$?
[ "$rc" = 0 ] && [ "$(lines ran)" = 1 ] && [ "$(lines ran2)" = 1 ] \
  && ok "lượt đầu: exit 0, REG-1 và REG-2 chạy mỗi suite một lần" \
  || fail "lượt đầu: rc $rc ran=$(lines ran) ran2=$(lines ran2) $(show)"
[ -f "$SKIP" ] && ok "bản ghi rerun_skip.json đã được ghi" || fail "thiếu rerun_skip.json"

gate; rc=$?
[ "$rc" = 0 ] && [ "$(lines ran2)" = 2 ] \
  && ok "lượt hai: REG-2 (cache:false) chạy lại dù bản ghi skip khớp (ran2 = 2)" \
  || fail "lượt hai: rc $rc ran=$(lines ran) ran2=$(lines ran2) (mong ran2 = 2) $(show)"

# Đối chứng: repo thứ hai chỉ có suite cacheable, bản ghi skip vẫn dùng được
ORIGIN="$TMP/origin2.git"; REPO="$TMP/repo2"
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
SKIP="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/rerun_skip.json"
gate; rc=$?
gate; rc2=$?
[ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$(lines ran)" = 1 ] && grep -q "$SKIP" "$TMP/gate" \
  && ok "đối chứng: chỉ suite cacheable thì lượt hai thoát từ bản ghi skip (ran = 1)" \
  || fail "đối chứng: rc $rc/$rc2 ran=$(lines ran) $(show)"

[ "$FAILS" -eq 0 ] && { echo "gate rerun_skip unkeyed: all passed"; exit 0; }
echo "gate rerun_skip unkeyed: $FAILS FAILED"; exit 1
