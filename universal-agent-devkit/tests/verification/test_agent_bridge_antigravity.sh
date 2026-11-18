#!/usr/bin/env bash
# Regression test: the DevKit's two destructive-command guards on Antigravity.
# Before: hooks/agent_bridge.sh only spoke Codex / Gemini CLI / Cursor, and the app repos have no Codex or Cursor and a
# Gemini CLI that cannot log in since 14/10 — Antigravity, the one other agent in use, ran with no mechanical guard
# (GeelyEx2: `git clean -f -x` despite the prompt, skills/devkit-audit/references/backlog.md).
# Antigravity hook contract (docs embedded in its language_server, 2026-11-16 build): `.agents/hooks.json`, PreToolUse with
# matcher "run_command", stdin {"toolCall":{"name":"run_command","args":{"CommandLine":…,"Cwd":…}},"cwd":…}, the hook runs
# with the directory holding hooks.json as its working directory, and answers {"decision":"deny","reason":…} on stdout.
# A safe command must get NO decision: "allow" would skip Antigravity's own permission prompt.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$DEVKIT_DIR/hooks/agent_bridge.sh"
AH="$DEVKIT_DIR/scripts/context/agent_hooks.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/.agents"; (cd "$P" && git init -q .)
ag() { # hook command-line → sets OUT, RC (run from .agents/, as Antigravity does)
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"toolCall":{"id":"t1","name":"run_command","args":{"CommandLine":sys.argv[2],"Cwd":sys.argv[1]}},"cwd":sys.argv[1],"hookEventName":"PreToolUse","stepIdx":3}))' "$P" "$2")"
  OUT="$(cd "$P/.agents" && printf '%s' "$payload" | bash "$BRIDGE" antigravity shell "$1" 2>"$TMP/err")"; RC=$?
}
decision() { printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision",""))' 2>/dev/null; }

ag block-dangerous-git.sh 'git clean -f -x'
[ "$RC" = 0 ] && [ "$(decision)" = deny ] && ok "git clean -f -x -> decision deny" || fail "git clean -f -x: rc=$RC out=$OUT err=$(head -c 200 "$TMP/err")"
printf '%s' "$OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["reason"].strip()' 2>/dev/null \
  && ok "deny carries a reason" || fail "deny has no reason: $OUT"

ag block-dangerous-git.sh 'git reset --hard HEAD~3'
[ "$(decision)" = deny ] && ok "git reset --hard -> deny" || fail "git reset --hard: rc=$RC out=$OUT"

ag hardware_safety_gate.sh 'adb remount'
[ "$(decision)" = deny ] && ok "adb remount -> deny (hardware gate)" || fail "adb remount: rc=$RC out=$OUT"

ag block-dangerous-git.sh 'git status'
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "safe command -> no decision (never auto-allow)" || fail "git status: rc=$RC out=$OUT"

# OCR review 2026-11-19: Antigravity also has send_command_input (types into a running terminal) and shell_exec
# (CORTEX_STEP_TYPE_* in its language_server). Their argument names are not documented: the bridge must find the command
# under CommandLine / Input / Command, else in any string argument but the model-written toolSummary.
agt() { # tool args-json -> sets OUT, RC
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"toolCall":{"id":"t2","name":sys.argv[2],"args":json.loads(sys.argv[3])},"cwd":sys.argv[1]}))' "$P" "$1" "$2")"
  OUT="$(cd "$P/.agents" && printf '%s' "$payload" | bash "$BRIDGE" antigravity shell block-dangerous-git.sh 2>/dev/null)"; RC=$?
}
agt send_command_input '{"CommandId":"c1","Input":"git reset --hard HEAD~2\n"}'
[ "$(decision)" = deny ] && ok "send_command_input typing git reset --hard -> deny" || fail "send_command_input: rc=$RC out=$OUT"
agt shell_exec '{"Shell":"git clean -fdx","WaitMs":100}'
[ "$(decision)" = deny ] && ok "shell_exec with an unknown arg name -> deny (any string arg)" || fail "shell_exec unknown arg: rc=$RC out=$OUT"
# Board review audit 2026-11-19 (major): a multi-line command (typed into a terminal, or several shell_exec arguments) let
# the second line slip past the guard's fast path. A newline separates commands, so the bridge hands it on as "; ".
agt send_command_input '{"CommandId":"c1","Input":"echo hi\ngit reset --hard HEAD~1\n"}'
[ "$(decision)" = deny ] && ok "multi-line Input with git reset --hard on line 2 -> deny" || fail "multi-line Input: rc=$RC out=$OUT"
agt shell_exec '{"A":"echo one","B":"git clean -fdx"}'
[ "$(decision)" = deny ] && ok "shell_exec: dangerous command in the second string argument -> deny" || fail "two shell_exec args: rc=$RC out=$OUT"
agt run_command '{"CommandLine":"ls\n\tgit reset --hard"}'
[ "$(decision)" = deny ] && ok "run_command with newline + tab before git reset --hard -> deny" || fail "run_command newline/tab: rc=$RC out=$OUT"
# principal review 2026-11-19 (P1): rewriting the command opened a bypass — bash runs `git clea\n -fdx` as `git clean -fdx`
# (an unquoted backslash-n is just n) but the guard saw `git clea; -fdx`. The original must always be checked as it runs.
agt run_command '{"CommandLine":"git clea\\n -fdx"}'
[ "$(decision)" = deny ] && ok "literal backslash inside a word (git clea\\n -fdx) -> deny on the original" || fail "git clea\\n -fdx: rc=$RC out=$OUT"
agt run_command '{"CommandLine":"git b\\ranch -D main"}'
[ "$(decision)" = deny ] && ok "git b\\ranch -D -> deny on the original" || fail "git b\\ranch -D: rc=$RC out=$OUT"
# Probe 2026-11-19: a lone CR (the Enter key typed into a terminal), VT, FF and a literal backslash-n passed the guard.
for sep in '\r' '\u000b' '\u000c' '\\n' '\\r'; do
  agt send_command_input "{\"CommandId\":\"c1\",\"Input\":\"echo hi${sep}git reset --hard HEAD~1\"}"
  [ "$(decision)" = deny ] && ok "send_command_input separator ${sep} before git reset --hard -> deny" || fail "separator ${sep}: rc=$RC out=$OUT"
done
agt run_command '{"CommandLine":"git status","toolSummary":"explain why git reset --hard is dangerous"}'
[ -z "$OUT" ] && ok "toolSummary text is not read as the command" || fail "toolSummary read as command: out=$OUT"

# Broken payload: fail open (a broken bridge must not stop the agent), never print allow.
OUT="$(cd "$P/.agents" && printf 'not json' | bash "$BRIDGE" antigravity shell block-dangerous-git.sh 2>/dev/null)"; RC=$?
[ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q allow && ok "garbage payload -> fail open, no allow" || fail "garbage payload: rc=$RC out=$OUT"

# --- agent_hooks.py: .agents/hooks.json, own hooks kept, idempotent, uninstall --------------
Q="$TMP/q"; mkdir -p "$Q/.agents"
echo '{"my-lint":{"PostToolUse":[{"matcher":"run_command","hooks":[{"command":"./lint.sh"}]}]}}' > "$Q/.agents/hooks.json"
python3 "$AH" install antigravity "$Q" >/dev/null && python3 "$AH" install antigravity "$Q" >/dev/null
python3 - "$Q" <<'PY' && ok "install twice: one DevKit PreToolUse(run_command) group, own hook kept" || fail "antigravity install: $(cat "$Q/.agents/hooks.json")"
import json, sys, os
cfg = json.load(open(os.path.join(sys.argv[1], ".agents/hooks.json")))
assert cfg["my-lint"]["PostToolUse"][0]["hooks"][0]["command"] == "./lint.sh", cfg
ours = [k for k, v in cfg.items() if "agent_bridge.sh" in json.dumps(v)]
assert len(ours) == 1, ours
groups = cfg[ours[0]]["PreToolUse"]
assert len(groups) == 1 and groups[0]["matcher"] == "run_command|send_command_input|shell_exec", groups
cmds = [h["command"] for h in groups[0]["hooks"]]
assert len(cmds) == 2 and any("block-dangerous-git.sh" in c for c in cmds) and any("hardware_safety_gate.sh" in c for c in cmds), cmds
# runs from .agents/ (Antigravity's hook cwd): the bridge path is relative to it
assert all(c.startswith("bash hooks/agent_bridge.sh antigravity shell ") for c in cmds), cmds
PY
python3 "$AH" uninstall antigravity "$Q" >/dev/null
python3 - "$Q" <<'PY' && ok "uninstall: only the DevKit hook removed" || fail "antigravity uninstall: $(cat "$Q/.agents/hooks.json")"
import json, sys, os
cfg = json.load(open(os.path.join(sys.argv[1], ".agents/hooks.json")))
assert cfg == {"my-lint": {"PostToolUse": [{"matcher": "run_command", "hooks": [{"command": "./lint.sh"}]}]}}, cfg
PY

# --- install.sh: the app repos are set up with "gemini" (Antigravity replaced Gemini CLI) ------
R="$TMP/r"; mkdir -p "$R"; (cd "$R" && git init -q)
bash "$DEVKIT_DIR/bin/install.sh" -t "$R" -a claude,gemini -p none -y >"$TMP/out" 2>&1 || { fail "install failed"; tail -20 "$TMP/out"; }
grep -q "agent_bridge.sh antigravity" "$R/.agents/hooks.json" 2>/dev/null \
  && ok "install -a claude,gemini registers the Antigravity guards" || fail "no .agents/hooks.json after install -a claude,gemini"
# Antigravity audit 2026-11-19: a plain re-init (-y, no -a) keeps the guards; a broken .agents/hooks.json is never overwritten.
bash "$DEVKIT_DIR/bin/install.sh" -t "$R" -p none -y >"$TMP/out2" 2>&1
grep -q "agent_bridge.sh antigravity" "$R/.agents/hooks.json" 2>/dev/null && ok "re-init -y keeps the Antigravity guards" \
  || fail "re-init dropped .agents/hooks.json: $(grep -i 'keeping\|agents' "$TMP/out2" | head -3)"
grep -q "bash hooks/agent_bridge.sh antigravity" "$R/.agents/hooks.json" && [ "$(grep -c universal-agent-devkit "$R/.agents/hooks.json")" = 1 ] \
  && ok "re-init does not duplicate the DevKit hook" || fail "re-init duplicated: $(cat "$R/.agents/hooks.json")"
bash "$DEVKIT_DIR/bin/agent-kit" uninstall "$R" --apply >/dev/null 2>&1
[ ! -e "$R/.agents/hooks.json" ] && ok "uninstall removes .agents/hooks.json" || fail "uninstall left .agents/hooks.json"
B="$TMP/broken"; mkdir -p "$B/.agents"; (cd "$B" && git init -q)
printf '{ "mine": { // jsonc comment\n } }\n' > "$B/.agents/hooks.json"; cp "$B/.agents/hooks.json" "$TMP/broken.json"
python3 "$AH" install antigravity "$B" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && cmp -s "$B/.agents/hooks.json" "$TMP/broken.json" && ok "broken .agents/hooks.json: refused (exit 1), file untouched" \
  || fail "broken hooks.json: rc=$rc, file $(cmp -s "$B/.agents/hooks.json" "$TMP/broken.json" && echo same || echo CHANGED)"
grep -q 'antigravity' <(bash "$DEVKIT_DIR/bin/install.sh" --help 2>&1) && ok "install.sh --help names antigravity" || fail "install.sh --help omits antigravity"

[ "$FAILS" -eq 0 ] && { echo "antigravity bridge: all checks passed"; exit 0; }
echo "antigravity bridge: $FAILS FAILED"; exit 1
