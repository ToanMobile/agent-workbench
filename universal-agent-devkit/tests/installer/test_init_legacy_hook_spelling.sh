#!/usr/bin/env bash
# test_init_legacy_hook_spelling.sh — #809: repo app đăng ký hook DevKit block-dangerous-git dạng cũ
# `"$CLAUDE_PROJECT_DIR"/.claude/hooks/block-dangerous-git.sh` (chạy trực tiếp, không bash, không :-$PWD). Init coi đó là cùng hook
# nên giữ nguyên, parity không báo: phiên đồng bộ phải sửa tay settings.json.
# Luật: `agent-kit parity` báo dòng hook-legacy cho dạng cũ; `agent-kit init` đổi nó thành dạng kit, không thêm mục trùng, hook riêng
# của dự án (kể cả script trùng tên ở chỗ khác) giữ nguyên từng chữ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/legacy-hook-spelling.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export DEVKIT_NO_GATE_SCHEDULE=1 DEVKIT_LAUNCH_AGENTS_DIR="$TMP/la" DEVKIT_LAUNCHCTL=/usr/bin/false
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/proj"
mkdir -p "$P/.claude/hooks" "$P/scripts" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo x > a && git add a && git commit -qm init)
printf '#!/bin/sh\nexit 0\n' > "$P/.claude/hooks/project-own.sh"
printf '#!/bin/sh\nexit 0\n' > "$P/scripts/block-dangerous-git.sh"
LEGACY='"$CLAUDE_PROJECT_DIR"/.claude/hooks/block-dangerous-git.sh'
OWN='"$CLAUDE_PROJECT_DIR"/.claude/hooks/project-own.sh'
OWN_SAME_NAME='"$CLAUDE_PROJECT_DIR"/scripts/block-dangerous-git.sh'
KIT='bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/block-dangerous-git.sh"'
python3 - "$P/.claude/settings.json" "$LEGACY" "$OWN" "$OWN_SAME_NAME" <<'PY'
import json, sys
path, legacy, own, same = sys.argv[1:5]
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [{"type": "command", "command": legacy}, {"type": "command", "command": own}]},
    {"matcher": "Edit", "hooks": [{"type": "command", "command": same}]}]}}, open(path, "w"), indent=2)
PY

# 1) parity trước init báo dòng lệch cho dạng cũ
python3 "$DEVKIT/bin/parity_check.py" "$P" > "$TMP/p1.out" 2>&1
grep -F -q "hook-legacy: .claude/settings.json — PreToolUse Bash: $LEGACY" "$TMP/p1.out" \
  && ok "parity báo hook-legacy cho dạng cũ" || fail "parity không báo dạng cũ: $(grep -F block-dangerous-git "$TMP/p1.out" | head -3)"
grep -F "hook-legacy:" "$TMP/p1.out" | grep -q -v -F "$LEGACY" && fail "parity báo hook-legacy cho hook khác: $(grep -F hook-legacy: "$TMP/p1.out")" \
  || ok "parity chỉ báo hook DevKit dạng cũ"

# 2) init đổi sang dạng kit, không trùng, hook riêng giữ nguyên
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal --agents=claude --no-githooks -m symlink > "$TMP/i.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "init exit 0" || { fail "init exit $rc"; tail -5 "$TMP/i.out"; }
python3 - "$P/.claude/settings.json" "$KIT" "$OWN" "$OWN_SAME_NAME" <<'PY' > "$TMP/chk.out" 2>&1
import json, sys
path, kit, own, same = sys.argv[1:5]
d = json.load(open(path))
cmds = [(ev, g.get("matcher"), h.get("command")) for ev, gs in d["hooks"].items() for g in gs for h in g.get("hooks", [])]
git = [c for c in cmds if c[2] and ".claude/hooks/block-dangerous-git.sh" in c[2]]
assert git == [("PreToolUse", "Bash", kit)], f"block-dangerous-git wiring: {git}"
assert ("PreToolUse", "Bash", own) in cmds, f"project hook lost: {[c for c in cmds if 'project-own' in (c[2] or '')]}"
assert ("PreToolUse", "Edit", same) in cmds, f"same-name project hook lost: {[c for c in cmds if 'scripts/' in (c[2] or '')]}"
PY
[ $? -eq 0 ] && ok "init: block-dangerous-git một mục dạng kit, hook riêng giữ nguyên" || fail "settings sau init: $(cat "$TMP/chk.out")"

# 3) parity sau init hết dòng hook-legacy
python3 "$DEVKIT/bin/parity_check.py" "$P" > "$TMP/p2.out" 2>&1
grep -q "^hook-legacy:" "$TMP/p2.out" && fail "parity sau init vẫn báo: $(grep hook-legacy: "$TMP/p2.out")" || ok "parity sau init hết hook-legacy"

[ "$FAILS" -eq 0 ] && { echo "PASS test_init_legacy_hook_spelling"; exit 0; }
echo "FAIL test_init_legacy_hook_spelling ($FAILS)"; exit 1
