#!/usr/bin/env bash
# Hồi quy (25/10): `.claude/settings.json` được miễn SUITE hồi quy (needs_no_test, Goods 29/09: commit chỉ đổi settings phải chạy cả gate
# Unity), nhưng miễn suite từng thành miễn MỌI kiểm tra: 11/11 repo app không có rule ma trận nào theo dõi file này, nên một commit
# bỏ dây nối hook Stop (hay trỏ hook tới file không có) qua gate với exit 0, và push_gate (untestable_only) cho push không cần biên nhận.
# Nay gate kiểm tĩnh nhẹ khi settings*.json nằm trong thay đổi: JSON hợp lệ, settings.json có "hooks" không rỗng, mọi script hook trỏ
# vào dự án hoặc .agents/devkit tồn tại. Hỏng thì REJECT kèm đường dẫn thiếu; đúng thì PASS mà không chạy suite nào. Đường dẫn hook do
# registered_hook_scripts() của bin/agent-health.py đọc (một bản dùng chung với `agent-kit health`, INSTINCT-015).
#  Ca phải chặn: hook trỏ file không có (cả dạng `cd "$CLAUDE_PROJECT_DIR" && python3 .claude/hooks/x.py` và .agents/devkit/), "hooks"
#  rỗng, JSON hỏng, xoá settings.json, push chỉ-settings hỏng không biên nhận.
#  Ca phải cho qua (core-rules §3, test hai chiều): settings đúng, settings.local.json chỉ có permissions, hook ghi log ra file chưa có,
#  hook của kit chưa được `agent-kit init` link vào .claude/hooks/, push chỉ-settings đúng.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

hook() {   # one Stop hook running the given command, as settings.json JSON
  python3 -c 'import json,sys; print(json.dumps({"permissions": {"allow": []}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": c} for c in sys.argv[1:]]}]}}))' "$@"
}
mk() {
  R="$TMP/$1"; mkdir -p "$R/src" "$R/.agents" "$R/.claude/hooks" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '.claude/hooks/\n' > .gitignore                               # installed hook links are git-ignored, as agent-kit init makes them
  echo 'echo stop' > .claude/hooks/stop.sh
  hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' > .claude/settings.json
  # a suite that FAILS if it runs: exit 0 below proves a settings-only change runs no suite
  printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"false"}]}]}\n' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
}
expect() {   # name, description, expected exit [, text the output must contain]
  local rc; rc="$( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$GATE" --run-tests --json > "$TMP/$1.out" 2>&1; echo $? )"
  if [ "$rc" != "$3" ]; then
    fail "$2: exit $rc, expected $3 ($(grep -o '"verdict": "[^"]*"' "$TMP/$1.out" | tail -1 | cut -c1-110))"
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "$TMP/$1.out"; then
    fail "$2: exit $rc but the output does not name '$4'"
  else
    ok "$2 → exit $rc"
  fi
}

# ── post-fix-gate: must block ──
mk a; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/gone_gate.sh"' > .claude/settings.json
expect a "settings.json hook runs a .claude/hooks file that does not exist" 1 ".claude/hooks/gone_gate.sh"
mk b; echo '{"permissions":{"allow":[]},"hooks":{}}' > .claude/settings.json
expect b 'settings.json with an empty "hooks" (every hook unwired)' 1 "hooks"
mk c; echo '{"hooks": {"Stop": [' > .claude/settings.json
expect c "settings.json that is not valid JSON" 1 "JSON"
mk d; git rm -q .claude/settings.json
expect d "settings.json deleted" 1 ".claude/settings.json"
mk e; hook 'cd "$CLAUDE_PROJECT_DIR" && python3 .claude/hooks/cleanup_gone.py --auto' > .claude/settings.json
expect e "a bare .claude/hooks/ path after cd \$CLAUDE_PROJECT_DIR that does not exist" 1 ".claude/hooks/cleanup_gone.py"
mk f; hook 'python3 "$CLAUDE_PROJECT_DIR"/.agents/devkit/hooks/not_shipped.py' > .claude/settings.json
expect f "a .agents/devkit hook script that does not exist" 1 ".agents/devkit/hooks/not_shipped.py"
mk g; echo '{"hooks": {"Stop": {"command": "x"}}}' > .claude/settings.json
expect g "a hooks block Claude Code cannot read (event is not a list)" 1 "hooks.Stop"
# settings.local.json reaches the gate only when the project tracks it (Claude Code puts it in the global gitignore): force-add a base
local_base() { echo '{"permissions":{"allow":[]}}' > .claude/settings.local.json && git add -f .claude/settings.local.json && git commit -qm local; }
mk h; local_base; echo '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/missing_local.sh"}]}]}}' > .claude/settings.local.json
expect h "settings.local.json hook that does not exist" 1 ".claude/hooks/missing_local.sh"
mk h2; hook 'bash ./.claude/hooks/dot_gone.sh' 'bash "$PWD/.claude/hooks/pwd_gone.sh"' > .claude/settings.json
expect h2 "./.claude/hooks/ and \$PWD/.claude/hooks/ paths that do not exist (the old reader caught both)" 1 ".claude/hooks/pwd_gone.sh"
grep -qF ".claude/hooks/dot_gone.sh" "$TMP/h2.out" && ok "  … and it names ./.claude/hooks/dot_gone.sh too" || fail "./.claude/hooks/dot_gone.sh is not named"

# ── post-fix-gate: must allow ──
mk i; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh" record' > .claude/settings.json
expect i "a valid settings.json change passes and runs no suite (REG-1 would fail)" 0 '"test_mode": "none"'
mk j; local_base; echo '{"permissions":{"allow":["Bash(git status)"]}}' > .claude/settings.local.json
expect j "settings.local.json with permissions only (no hooks of its own)" 0
mk k; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh" >> "$CLAUDE_PROJECT_DIR/.claude/hook-runs.log"' > .claude/settings.json
expect k "a hook that appends to a log file not created yet" 0
mk l; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/session_lock.sh"' > .claude/settings.json
expect l "a kit hook (hooks/session_lock.sh) not linked into .claude/hooks/ yet: agent-kit init links it" 0
mk m; hook 'bash "$HOME/.claude/hooks/user_level.sh"' 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' > .claude/settings.json
expect m "a user-level hook outside the project is not the project's to check" 0

# ── pre-commit (--staged): the staged blob is judged, not the working tree ──
staged() {   # name, description, expected exit
  local rc; rc="$( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$GATE" --staged > "$TMP/$1.out" 2>&1; echo $? )"
  [ "$rc" = "$3" ] && ok "$2 → exit $rc" || fail "$2: exit $rc, expected $3 ($(tail -3 "$TMP/$1.out" | tr '\n' ' ' | cut -c1-160))"
}
mk s1; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/gone_gate.sh"' > .claude/settings.json; git add .claude/settings.json
hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' > .claude/settings.json
staged s1 "--staged: a staged hook to a missing file is REJECTed though the working tree is fixed" 1
mk s2; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh" record' > .claude/settings.json
git add .claude/settings.json
staged s2 "--staged: a valid staged settings change is not REJECTed (clean pre-commit = 2)" 2

# ── push_gate: a settings-only push with no receipt (untestable_only) still needs the check ──
pg() {   # name, description, expected exit
  local out rc; out="$(python3 "$PG" "$TMP/$1" 2>&1)"; rc=$?
  [ "$rc" = "$3" ] && ok "$2 (push_gate exit $rc)" || fail "$2: push_gate exit $rc, expected $3 — $out"
}
mkpush() {
  mk "$1"; git init -q --bare "$TMP/$1.git" && git remote add origin "$TMP/$1.git" && git push -q -u origin HEAD 2>/dev/null
}
mkpush p1; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh" record' > .claude/settings.json
git commit -qam "settings: one more hook"; echo "fun ok() = 9" > src/Core.kt   # failing WIP left in the tree, not pushed
pg p1 "valid settings-only push, no receipt: allowed" 0
mkpush p2; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/gone_gate.sh"' > .claude/settings.json
git commit -qam "settings: hook to a missing file"
pg p2 "settings-only push whose hook file does not exist, no receipt: blocked" 2
mkpush p3; echo '{"hooks":{}}' > .claude/settings.json; git commit -qam "settings: hooks emptied"
pg p3 "settings-only push that empties hooks, no receipt: blocked" 2
mkpush p4; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/gone_gate.sh"' > .claude/settings.json
git commit -qam "settings: hook to a missing file"; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' > .claude/settings.json
pg p4 "the pushed blob is judged, not the fixed working tree: blocked" 2

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_settings_hooks: all passed" || { echo "❌ test_gate_settings_hooks: $FAILS failed"; exit 1; }
