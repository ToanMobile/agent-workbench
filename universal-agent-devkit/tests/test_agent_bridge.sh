#!/usr/bin/env bash
# Regression test: the DevKit gates on OpenAI Codex, Gemini CLI and Cursor —
# hooks/agent_bridge.sh translates each platform's hook protocol, scripts/agent_hooks.py
# registers it without touching the project's own hooks, install/uninstall round trip.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$DEVKIT_DIR/hooks/agent_bridge.sh"
AH="$DEVKIT_DIR/scripts/agent_hooks.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/.agents"; (cd "$P" && git init -q . && git config user.email t@t && git config user.name t)
printf '### [INSTINCT-001] Chống bấm đúp nút thanh toán (double-click)\n- click nhanh gọi API hai lần\n' > "$P/.agents/instincts.md"
bridge() { # platform kind hook json → sets OUT, RC
  OUT="$(cd "$P" && printf '%s' "$4" | bash "$BRIDGE" "$1" "$2" "$3" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
}
DANGER='git reset --hard HEAD~3'

# --- shell: dangerous git is blocked on every platform ---------------------------
bridge codex shell block-dangerous-git.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$DANGER\"},\"cwd\":\"$P\"}"
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q "reset" && ok "codex: PreToolUse(Bash) git reset --hard blocked (exit 2)" || fail "codex shell block (rc=$RC)"
bridge gemini shell block-dangerous-git.sh "{\"tool_name\":\"run_shell_command\",\"tool_input\":{\"command\":\"$DANGER\"},\"cwd\":\"$P\"}"
[ "$RC" = 2 ] && ok "gemini: BeforeTool(run_shell_command) blocked (exit 2)" || fail "gemini shell block (rc=$RC)"
bridge cursor shell block-dangerous-git.sh "{\"command\":\"$DANGER\",\"cwd\":\"$P\"}"
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '"permission": "deny"' && ok "cursor: beforeShellExecution answers permission deny" \
  || fail "cursor shell deny (rc=$RC out=$OUT)"
bridge cursor shell block-dangerous-git.sh "{\"command\":\"git status\",\"cwd\":\"$P\"}"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "cursor: a safe command is allowed silently" || fail "cursor allow (rc=$RC out=$OUT)"
bridge gemini shell hardware_safety_gate.sh "{\"tool_name\":\"run_shell_command\",\"tool_input\":{\"command\":\"adb remount\"},\"cwd\":\"$P\"}"
[ "$RC" = 2 ] && ok "gemini: adb remount blocked by the hardware gate" || fail "gemini hardware gate (rc=$RC)"

# --- context: each platform gets it in its own shape -----------------------------
bridge codex session session_context.sh "{\"session_id\":\"s1\",\"cwd\":\"$P\"}"
printf '%s' "$OUT" | grep -q "INSTINCT-001" && ok "codex: SessionStart context is plain stdout" || fail "codex session context"
bridge gemini session session_context.sh "{\"session_id\":\"s1\",\"cwd\":\"$P\"}"
printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "INSTINCT-001" in d["hookSpecificOutput"]["additionalContext"]' 2>/dev/null \
  && ok "gemini: SessionStart → hookSpecificOutput.additionalContext" || fail "gemini session context: $OUT"
bridge cursor session session_context.sh "{\"session_id\":\"s1\"}"
printf '%s' "$OUT" | python3 -c 'import json,sys; assert "additional_context" in json.load(sys.stdin)' 2>/dev/null \
  && ok "cursor: sessionStart → additional_context" || fail "cursor session context: $OUT"
bridge gemini prompt prompt_context.sh "{\"prompt\":\"sửa lỗi nút thanh toán bị bấm 2 lần\",\"cwd\":\"$P\"}"
printf '%s' "$OUT" | grep -q "INSTINCT-001" && ok "gemini: BeforeAgent gets the matching trap" || fail "gemini prompt context: $OUT"

# --- stop: a failing regression test keeps the agent working ---------------------
mkdir -p "$P/src"; echo "fun ok() = 1" > "$P/src/Core.kt"; echo 'exit 1' > "$P/result.sh"
cat > "$P/.agents/regression_matrix.active.json" <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-B","name":"core","command":"sh result.sh"}]}]}
JSON
(cd "$P" && git add -A && git commit -qm init)
echo "fun ok() = 2" > "$P/src/Core.kt"
bridge codex stop regression_gate.sh "{\"session_id\":\"sb1\",\"cwd\":\"$P\"}"
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q "REG-B" && ok "codex: Stop blocked by the failing regression test" || fail "codex stop (rc=$RC)"
bridge cursor stop regression_gate.sh "{\"conversation_id\":\"sb2\",\"status\":\"completed\"}"
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "followup_message" && ok "cursor: stop → followup_message (agent continues)" || fail "cursor stop (rc=$RC out=$OUT)"
(cd "$P" && git checkout -q -- src)

# --- agent_hooks.py: the project's own hooks and settings are kept ----------------
Q="$TMP/q"; mkdir -p "$Q/.codex" "$Q/.gemini" "$Q/.cursor"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./my-guard.sh"}]}]}}' > "$Q/.codex/hooks.json"
echo '{"theme":"dark","hooks":{"BeforeTool":[{"matcher":"write_file","hooks":[{"type":"command","command":"./fmt.sh"}]}]}}' > "$Q/.gemini/settings.json"
for p in codex gemini cursor; do python3 "$AH" install "$p" "$Q" >/dev/null && python3 "$AH" install "$p" "$Q" >/dev/null; done
python3 - "$Q" <<'PY' && ok "install twice: DevKit entries added once, own hooks + settings kept" || fail "agent_hooks install merge"
import json, sys, os
q = sys.argv[1]
codex = json.load(open(os.path.join(q, ".codex/hooks.json")))
cmds = [h["command"] for g in codex["hooks"]["PreToolUse"] for h in g["hooks"]]
assert "./my-guard.sh" in cmds and sum("agent_bridge.sh" in c for c in cmds) == 2, cmds
assert len(codex["hooks"]["Stop"]) == 1
gem = json.load(open(os.path.join(q, ".gemini/settings.json")))
assert gem["theme"] == "dark"
assert any(h["command"] == "./fmt.sh" for g in gem["hooks"]["BeforeTool"] for h in g["hooks"])
assert gem["hooks"]["AfterAgent"][0]["hooks"][0]["timeout"] == 1800000
cur = json.load(open(os.path.join(q, ".cursor/hooks.json")))
assert cur["version"] == 1 and len(cur["hooks"]["beforeShellExecution"]) == 2
PY
for p in codex gemini cursor; do python3 "$AH" uninstall "$p" "$Q" >/dev/null; done
python3 - "$Q" <<'PY' && ok "uninstall: only DevKit entries removed; a DevKit-only file is deleted" || fail "agent_hooks uninstall"
import json, sys, os
q = sys.argv[1]
codex = json.load(open(os.path.join(q, ".codex/hooks.json")))
assert codex == {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "./my-guard.sh"}]}]}}, codex
gem = json.load(open(os.path.join(q, ".gemini/settings.json")))
assert gem["theme"] == "dark" and "AfterAgent" not in gem["hooks"]
assert not os.path.exists(os.path.join(q, ".cursor/hooks.json"))
PY
printf '{ // comment\n "hooks": {} }\n' > "$Q/.codex/hooks.json"; cp "$Q/.codex/hooks.json" "$TMP/jsonc"
python3 "$AH" install codex "$Q" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && cmp -s "$Q/.codex/hooks.json" "$TMP/jsonc" && ok "JSONC config: refused, file untouched" || fail "JSONC handling (rc=$rc)"

# --- install.sh + uninstall round trip --------------------------------------------
R="$TMP/r"; mkdir -p "$R"; (cd "$R" && git init -q)
bash "$DEVKIT_DIR/bin/install.sh" -t "$R" -a codex,gemini,cursor -p none -y >"$TMP/out" 2>&1 || { fail "install failed"; cat "$TMP/out"; }
[ -e "$R/.agents/hooks/agent_bridge.sh" ] && [ -e "$R/.agents/hooks/regression_gate.sh" ] \
  && grep -q agent_bridge.sh "$R/.codex/hooks.json" "$R/.gemini/settings.json" "$R/.cursor/hooks.json" \
  && ok "install -a codex,gemini,cursor: bridge placed and registered on all three" || fail "install did not register the bridge"
bash "$DEVKIT_DIR/bin/agent-kit" uninstall "$R" --apply >/dev/null 2>&1
[ ! -e "$R/.codex/hooks.json" ] && [ ! -e "$R/.cursor/hooks.json" ] && [ ! -e "$R/.agents/hooks" ] \
  && ok "uninstall removes the registrations and .agents/hooks" || fail "uninstall leftovers: $(ls -a "$R" "$R/.agents" 2>/dev/null | tr '\n' ' ')"

if [ "$FAILS" -ne 0 ]; then
  echo "agent bridge: $FAILS FAILED"; exit 1
fi
echo "agent bridge: all checks passed"
