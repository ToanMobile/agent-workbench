#!/usr/bin/env bash
# test_prompt_hook_missing.sh — GeelyEx2 2026-10-11 11:06: Antigravity ran `git clean -f -x` in the checkout, which removed the
# git-ignored DevKit links under .claude/hooks/. settings.json (tracked) survived, so every hook command exited 127 — non-blocking:
# 25 events, 9 Stop gates and 4 PreToolUse guards silently off, and nothing told the agent. SessionStart already says so when the
# hook files are missing (test_session_start_missing_hooks.sh), but it only runs when a session starts. The UserPromptSubmit entry
# now has the same launcher: with prompt_context.sh missing it prints ONE line naming the bootstrap on every prompt (the agent
# sees it in its context) and exits 0; with the file there it runs the hook unchanged (stdin, stdout, exit code). A project wired
# with the old spelling takes the new line on a re-sync (merge_json), wired once.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prompt-hook-missing.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
PAYLOAD='{"session_id":"t-prompt","hook_event_name":"UserPromptSubmit","prompt":"hello"}'

prompt_cmds() { # <settings.json> — its UserPromptSubmit commands, one per line
  python3 - "$1" <<'PY'
import json, sys
for g in json.load(open(sys.argv[1]))["hooks"].get("UserPromptSubmit", []):
    for h in g.get("hooks", []):
        print(h["command"])
PY
}
# run_all <settings.json> <env assignment> — run every UserPromptSubmit command like Claude Code does (a shell, the payload on stdin)
run_all() {
  local f="$1" envset="$2" cmd rc=0 r out=""
  while IFS= read -r cmd; do
    out="$out$(printf '%s' "$PAYLOAD" | env "$envset" bash -c "$cmd" 2>>"$TMP/stderr")"; r=$?
    [ "$r" -gt "$rc" ] && rc="$r"
  done < <(prompt_cmds "$f")
  printf '%s' "$out"
  return "$rc"
}

# 1. What the installer writes into a project.
P="$TMP/proj"
mkdir -p "$P" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false)
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > "$TMP/i.out" 2>&1 || { fail "install failed"; tail -5 "$TMP/i.out"; }
n="$(prompt_cmds "$P/.claude/settings.json" | grep -c prompt_context.sh)"
[ "$n" = 1 ] && ok "installed settings: prompt_context.sh wired once" || fail "prompt_context.sh wired $n times"
mv "$P/.claude/hooks" "$TMP/hooks-away"                         # what git clean -x did: the ignored links are gone
out="$(run_all "$P/.claude/settings.json" "CLAUDE_PROJECT_DIR=$P")"; rc=$?
[ "$rc" = 0 ] && ok "hooks missing: UserPromptSubmit exits 0 (never blocks the prompt)" || fail "hooks missing: exit $rc"
if [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && printf '%s' "$out" | grep -q "not installed" && printf '%s' "$out" | grep -q "OFF" && printf '%s' "$out" | grep -qF "agent-kit init"; then
  ok "hooks missing: one clear line says the guards are OFF and names the bootstrap"
else
  fail "hooks missing: expected one line (not installed / OFF / agent-kit init), got: $(printf '%s' "$out" | head -3)"
fi
mkdir -p "$P/.claude/hooks"
printf '#!/usr/bin/env bash\ncat\nexit 3\n' > "$P/.claude/hooks/prompt_context.sh"
out="$(run_all "$P/.claude/settings.json" "CLAUDE_PROJECT_DIR=$P")"; rc=$?
[ "$rc" = 3 ] && [ "$out" = "$PAYLOAD" ] && ok "hook present: runs as before (stdin passed, stdout kept, exit code kept)" || fail "hook present: rc=$rc out=$out"

# 2. Re-sync of a project wired with the old plain spelling: the new line replaces it, wired once.
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for g in d["hooks"]["UserPromptSubmit"]:
    for h in g["hooks"]:
        if "prompt_context.sh" in h["command"]:
            h["command"] = 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/prompt_context.sh"'
json.dump(d, open(p, "w"), indent=2)
PY
rm -rf "$P/.claude/hooks" && mv "$TMP/hooks-away" "$P/.claude/hooks"
bash "$DEVKIT/bin/install.sh" -t "$P" -y --no-githooks > "$TMP/i2.out" 2>&1 || { fail "re-init failed"; tail -5 "$TMP/i2.out"; }
cmds="$(prompt_cmds "$P/.claude/settings.json")"
n="$(printf '%s\n' "$cmds" | grep -c "prompt_context.sh")"
[ "$n" = 1 ] && ok "re-sync: prompt_context.sh wired once" || fail "re-sync: prompt_context.sh x$n"
printf '%s\n' "$cmds" | grep "prompt_context.sh" | grep -q "not installed" \
  && ok "re-sync: the old spelling took the new line" || fail "re-sync kept the old UserPromptSubmit command: $cmds"

if [ "$FAILS" -ne 0 ]; then echo "prompt hook, hooks missing: $FAILS FAILED"; exit 1; fi
echo "prompt hook, hooks missing: all checks passed"
