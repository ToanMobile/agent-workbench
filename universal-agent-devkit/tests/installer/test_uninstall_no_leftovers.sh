#!/usr/bin/env bash
# test_uninstall_no_leftovers.sh — B6 (audit 2026-10-09): `agent-kit uninstall --apply` +
# `agent-kit restore-old --apply` on an untouched install must give back the original project
# with NOTHING left over. It left 5–6 untracked *_old files: the pre-install backups uninstall had
# just put back (settings_old.json, .mcp_old.json, CLAUDE_old.md) and its own
# `_old.uninstall-<ts>` copies of files that held only DevKit content.
# A backup that was NOT restored is never removed: the project edited after install keeps its
# pre-install backup and the uninstall backup, and a project-tier backup restore-old had to skip stays.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/uninstall-leftovers.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

make_project() { # <dir> — the project's own CLAUDE.md, AGENTS.md, MCP server, settings and a /fix command
  local p="$1"
  mkdir -p "$p/.claude/commands" "$p/src"
  (cd "$p" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false)
  printf '# My project\n\nOur own agent notes.\n' > "$p/CLAUDE.md"
  printf '# Agents\n\nTeam conventions.\n' > "$p/AGENTS.md"
  printf 'node_modules/\n' > "$p/.gitignore"
  printf '{\n  "mcpServers": {\n    "mine": {\n      "command": "my-mcp"\n    }\n  }\n}\n' > "$p/.mcp.json"
  printf '{\n  "permissions": {\n    "allow": [\n      "Bash(ls)"\n    ]\n  }\n}\n' > "$p/.claude/settings.json"
  printf 'my own fix command\n' > "$p/.claude/commands/fix.md"
  printf 'console.log(1)\n' > "$p/src/app.js"
  (cd "$p" && git add -A && git commit -qm init)
}
leftovers() { git -C "$1" status --porcelain --untracked-files=all; }
uninstall_restore() {
  bash "$DEVKIT/bin/agent-kit" uninstall "$1" --apply > "$TMP/u.out" 2>&1 || { fail "uninstall --apply failed"; tail -5 "$TMP/u.out"; }
  bash "$DEVKIT/bin/agent-kit" restore-old "$1" --apply > "$TMP/r.out" 2>&1
}

# 1. Untouched install → uninstall + restore-old → the project exactly as it was, nothing extra.
P="$TMP/clean"
make_project "$P"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a all --no-githooks > "$TMP/i.out" 2>&1 || { fail "install failed"; tail -5 "$TMP/i.out"; }
[ -n "$(leftovers "$P")" ] && ok "(the install changed the project)" || fail "the install changed nothing?"
uninstall_restore "$P"
left="$(leftovers "$P")"
if [ -z "$left" ]; then ok "uninstall + restore-old: original project back, no *_old or other file left"
else fail "uninstall + restore-old left:"; echo "$left" | head -10; fi

# 2. Edited after install → what was not restored stays.
P="$TMP/edited"
make_project "$P"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > /dev/null 2>&1
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["permissions"]["allow"].append("Bash(pwd)")
json.dump(s, open(sys.argv[1], "w"), indent=2)
PY
bash "$DEVKIT/bin/agent-kit" uninstall "$P" --apply > "$TMP/u2.out" 2>&1
[ -f "$P/.claude/settings_old.json" ] && grep -q '"Bash(ls)"' "$P/.claude/settings_old.json" \
  && ok "settings.json edited after install: its pre-install backup (not restored) is kept" || fail "pre-install backup of an edited settings.json removed"
ls "$P/.claude" | grep -q "settings_old.uninstall-" \
  && ok "settings.json edited after install: the uninstall backup is written" || fail "no uninstall backup for an edited settings.json"
grep -q '"Bash(pwd)"' "$P/.claude/settings.json" && ok "(the user's later permission is still in settings.json)" || fail "the user's later permission was lost"
mkdir -p "$P/.claude/commands" && printf 'my NEW fix command\n' > "$P/.claude/commands/fix.md"   # a new file where restore-old would put the backup
bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply > "$TMP/r2.out" 2>&1
grep -q "my own fix command" "$P/.agents/local/commands/fix.md" 2>/dev/null && grep -q "my NEW fix command" "$P/.claude/commands/fix.md" \
  && ok "a backup restore-old had to skip is kept (.agents/local/commands/fix.md)" || fail "skipped backup lost"

if [ "$FAILS" -ne 0 ]; then echo "uninstall leftovers: $FAILS FAILED"; exit 1; fi
echo "uninstall leftovers: all checks passed"
