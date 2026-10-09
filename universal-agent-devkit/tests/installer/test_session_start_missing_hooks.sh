#!/usr/bin/env bash
# test_session_start_missing_hooks.sh — B7 (audit 2026-10-09): in a fresh clone .claude/hooks/ is
# missing (git-ignored, machine-local links), so every hook command in .claude/settings.json exited
# 127 — non-blocking: every DevKit guard and gate was silently off and nothing said so. The
# SessionStart entries now print ONE line naming the bootstrap command and exit 0 when the hook
# file is missing, and run the hook unchanged (stdin, stdout, exit code) when it is there. Checked
# for the installed settings (templates/claude_settings.json + hooks/hooks.json, as setup_claude.sh
# builds them), the plugin registry (hooks/hooks.json) and, inside agent-workbench, its own
# .claude/settings.json; a re-sync (`agent-kit init`) of a project wired with the old spelling
# takes the new line without wiring the hook twice.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-start-missing.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
PAYLOAD='{"session_id":"t-b7","hook_event_name":"SessionStart","source":"startup"}'

session_start_cmds() { # <settings.json> — its SessionStart commands, one per line
  python3 - "$1" <<'PY'
import json, sys
for g in json.load(open(sys.argv[1]))["hooks"].get("SessionStart", []):
    for h in g.get("hooks", []):
        print(h["command"])
PY
}
# run_all <settings.json> <env assignment> — run every SessionStart command like Claude Code does
# (a shell, the payload on stdin); prints the joined stdout, returns the highest exit code.
run_all() {
  local f="$1" envset="$2" cmd rc=0 r out=""
  while IFS= read -r cmd; do
    out="$out$(printf '%s' "$PAYLOAD" | env "$envset" SESSION_FETCH=0 STALE_RERUN=0 bash -c "$cmd" 2>>"$TMP/stderr")"; r=$?
    [ "$r" -gt "$rc" ] && rc="$r"
  done < <(session_start_cmds "$f")
  printf '%s' "$out"
  return "$rc"
}
check_missing() { # <label> <settings.json> <env assignment> <bootstrap text>
  local out rc
  out="$(run_all "$2" "$3")"; rc=$?
  [ "$rc" = 0 ] && ok "$1: hooks missing → SessionStart exits 0 (never blocks)" || fail "$1: hooks missing → exit $rc"
  if [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && printf '%s' "$out" | grep -q "not installed" && printf '%s' "$out" | grep -qF -- "$4"; then
    ok "$1: one clear line names the bootstrap ($4)"
  else
    fail "$1: expected one line naming '$4', got: $(printf '%s' "$out" | head -3)"
  fi
}

# 1. What the installer writes into a project.
P="$TMP/proj"
mkdir -p "$P" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false)
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > "$TMP/i.out" 2>&1 || { fail "install failed"; tail -5 "$TMP/i.out"; }
mv "$P/.claude/hooks" "$TMP/hooks-away"                         # a fresh clone: .claude/hooks/ is git-ignored
check_missing "installed settings" "$P/.claude/settings.json" "CLAUDE_PROJECT_DIR=$P" "agent-kit init"
mkdir -p "$P/.claude/hooks"
printf '#!/usr/bin/env bash\ncat\nexit 3\n' > "$P/.claude/hooks/session_context.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$P/.claude/hooks/session_lock.sh"
out="$(run_all "$P/.claude/settings.json" "CLAUDE_PROJECT_DIR=$P")"; rc=$?
[ "$rc" = 3 ] && [ "$out" = "$PAYLOAD" ] && ok "installed settings: a present hook runs as before (stdin passed, exit code kept)" \
  || fail "installed settings: present hook: rc=$rc out=$out"

# 2. The plugin registry (hooks/hooks.json, ${CLAUDE_PLUGIN_ROOT}).
mkdir -p "$TMP/plugin-empty"
check_missing "plugin hooks.json" "$DEVKIT/hooks/hooks.json" "CLAUDE_PLUGIN_ROOT=$TMP/plugin-empty" "agent-kit init"
mkdir -p "$TMP/plugin/hooks" && cp "$P/.claude/hooks/"*.sh "$TMP/plugin/hooks/"
out="$(run_all "$DEVKIT/hooks/hooks.json" "CLAUDE_PLUGIN_ROOT=$TMP/plugin")"; rc=$?
[ "$rc" = 3 ] && [ "$out" = "$PAYLOAD" ] && ok "plugin hooks.json: a present hook runs as before" || fail "plugin hooks.json: present hook: rc=$rc out=$out"

# 3. agent-workbench's own settings (only when the kit sits in that monorepo).
WB="$(cd "$DEVKIT/.." && pwd -P)"
if [ -f "$WB/.claude/settings.json" ] && [ "$(basename "$DEVKIT")" = universal-agent-devkit ] && [ -f "$WB/README.md" ]; then
  BOOT="bash universal-agent-devkit/bin/agent-kit init . -y -a claude,gemini"
  mkdir -p "$TMP/wb-clone"
  check_missing "agent-workbench .claude/settings.json" "$WB/.claude/settings.json" "CLAUDE_PROJECT_DIR=$TMP/wb-clone" "$BOOT"
  grep -qF -- "$BOOT" "$WB/README.md" && ok "agent-workbench README documents the same bootstrap" || fail "README.md does not document '$BOOT'"
else
  echo "  (skip: not inside agent-workbench)"
fi

# 4. Re-sync of a project wired with the old spelling: the new line replaces it, wired once.
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for g in d["hooks"]["SessionStart"]:
    for h in g["hooks"]:
        name = "session_context.sh" if "session_context.sh" in h["command"] else "session_lock.sh"
        h["command"] = 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/' + name + '"'
json.dump(d, open(p, "w"), indent=2)
PY
rm -rf "$P/.claude/hooks" && mv "$TMP/hooks-away" "$P/.claude/hooks"
bash "$DEVKIT/bin/install.sh" -t "$P" -y --no-githooks > "$TMP/i2.out" 2>&1 || { fail "re-init failed"; tail -5 "$TMP/i2.out"; }
cmds="$(session_start_cmds "$P/.claude/settings.json")"
n_ctx="$(printf '%s\n' "$cmds" | grep -c "session_context.sh")"; n_lock="$(printf '%s\n' "$cmds" | grep -c "session_lock.sh")"
[ "$n_ctx" = 1 ] && [ "$n_lock" = 1 ] && ok "re-sync: each SessionStart hook wired once" || fail "re-sync: session_context x$n_ctx, session_lock x$n_lock"
printf '%s\n' "$cmds" | grep "session_context.sh" | grep -q "not installed" \
  && ok "re-sync: the old spelling took the new line" || fail "re-sync kept the old SessionStart command: $cmds"

if [ "$FAILS" -ne 0 ]; then echo "session start, hooks missing: $FAILS FAILED"; exit 1; fi
echo "session start, hooks missing: all checks passed"
