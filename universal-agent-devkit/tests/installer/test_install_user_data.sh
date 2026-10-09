#!/usr/bin/env bash
# test_install_user_data.sh — the installer never destroys the user's files (audit 2026-10-09).
#   B1  an unparseable .claude/settings.local.json (permission allowlist, MCP approvals) is left
#       byte for byte as it was, with a warning — it used to be replaced by {"autoMemoryDirectory": …}
#   B2  the user's own DANGLING links in .claude/{commands,hooks,agents} and .agents/skills survive
#       an install (a docs file not generated yet); only dangling links into the DevKit are cleaned
#   B5  an install that cannot merge a JSON file of the project (malformed .claude/settings.json,
#       .gemini/settings.json) stops BEFORE its first write: no AGENTS.md, no .mcp.json edit, no
#       .agents/devkit link, no .git/info/exclude change
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-user-data.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"   # claude_memory.py moves ~/.claude/projects/<slug>/memory
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

newproj() { # <name> — a git project with one commit
  local p="$TMP/$1"
  mkdir -p "$p" && (cd "$p" && git init -q && git config user.email t@t && git config user.name t \
    && git config commit.gpgsign false && echo "# $1" > README.md && git add README.md && git commit -qm init)
  printf '%s' "$p"
}
# Type, path, link target / content hash of everything in the project, .git/info and .git/hooks included.
snapshot() {
  (cd "$1" && find . \( -path ./.git/objects -o -path ./.git/logs -o -path ./.git/refs \) -prune -o -print | LC_ALL=C sort \
    | while IFS= read -r f; do
        if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
        elif [ -d "$f" ]; then echo "D $f"
        else echo "F $f $(cksum < "$f")"; fi
      done)
}

# ── B1: unparseable settings.local.json ─────────────────────────────────────────────────
P="$(newproj b1)"
mkdir -p "$P/.claude"
printf '{\n  "permissions": {"allow": ["Bash(npm test)", "mcp__mine__run"]},\n  "enabledMcpjsonServers": ["mine"],\n}\n' > "$P/.claude/settings.local.json"
cp "$P/.claude/settings.local.json" "$TMP/b1.orig"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > "$TMP/b1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "B1: install with an unparseable settings.local.json still succeeds" || { fail "B1: install exit $rc"; tail -5 "$TMP/b1.out"; }
cmp -s "$TMP/b1.orig" "$P/.claude/settings.local.json" \
  && ok "B1: unparseable .claude/settings.local.json left byte for byte (allowlist, MCP approvals kept)" \
  || { fail "B1: .claude/settings.local.json was rewritten:"; cat "$P/.claude/settings.local.json"; }
grep -q "settings.local.json" "$TMP/b1.out" && grep -qi "untouched\|not parse\|does not parse" "$TMP/b1.out" \
  && ok "B1: the install says why autoMemoryDirectory was not set" || fail "B1: no warning about settings.local.json"
# A parseable one still gets the setting, and keeps the user's keys.
P="$(newproj b1ok)"
mkdir -p "$P/.claude"
printf '{"permissions": {"allow": ["Bash(npm test)"]}}\n' > "$P/.claude/settings.local.json"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > /dev/null 2>&1
python3 - "$P/.claude/settings.local.json" <<'PY' && ok "B1: a valid settings.local.json gets autoMemoryDirectory, user keys kept" || fail "B1: valid settings.local.json not merged"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("permissions") == {"allow": ["Bash(npm test)"]} and d.get("autoMemoryDirectory", "").endswith("claude-auto") else 1)
PY

# ── B2: the user's dangling links ───────────────────────────────────────────────────────
P="$(newproj b2)"
mkdir -p "$P/.claude/commands" "$P/.claude/hooks" "$P/.claude/agents" "$P/.agents/skills" "$P/docs"
ln -s ../../docs/not-yet-generated.md "$P/.claude/commands/gen-notes.md"
ln -s ../../scripts/not-yet-hook.sh "$P/.claude/hooks/my-later-hook.sh"
ln -s ../../docs/agents/not-yet.md "$P/.claude/agents/my-later-agent.md"
ln -s ../../docs/skills/not-yet "$P/.agents/skills/my-later-skill"
# Dangling links INTO the DevKit (an item the DevKit no longer ships) are still cleaned up.
ln -s "$DEVKIT/commands/zz-removed-command.md" "$P/.claude/commands/zz-removed-command.md"
ln -s "$DEVKIT/skills/zz-removed-skill" "$P/.agents/skills/zz-removed-skill"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a all --no-githooks > "$TMP/b2.out" 2>&1 || { fail "B2: install failed"; tail -5 "$TMP/b2.out"; }
for l in .claude/commands/gen-notes.md .claude/hooks/my-later-hook.sh .claude/agents/my-later-agent.md .agents/skills/my-later-skill; do
  [ -L "$P/$l" ] && ok "B2: the user's dangling link $l survives the install" || fail "B2: the user's dangling link $l was deleted"
done
[ "$(readlink "$P/.claude/commands/gen-notes.md" 2>/dev/null)" = "../../docs/not-yet-generated.md" ] \
  && ok "B2: its target is unchanged" || fail "B2: gen-notes.md re-pointed"
[ ! -L "$P/.claude/commands/zz-removed-command.md" ] && [ ! -L "$P/.agents/skills/zz-removed-skill" ] \
  && ok "B2: dangling links into the DevKit are still removed" || fail "B2: stale DevKit links left"

# ── B5: validate every JSON input before the first write ────────────────────────────────
P="$(newproj b5)"
mkdir -p "$P/.claude"
printf '{\n  "permissions": {"allow": ["Bash(ls)"],}\n}\n' > "$P/.claude/settings.json"
printf '{"mcpServers": {"mine": {"command": "my-mcp"}}}\n' > "$P/.mcp.json"
before="$(snapshot "$P")"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a all > "$TMP/b5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && ok "B5: malformed .claude/settings.json fails the install (exit $rc)" || fail "B5: install succeeded on a malformed settings.json"
grep -q ".claude/settings.json" "$TMP/b5.out" && ok "B5: the message names the file" || { fail "B5: file not named"; tail -5 "$TMP/b5.out"; }
after="$(snapshot "$P")"
if [ "$before" = "$after" ]; then ok "B5: nothing was written (no AGENTS.md, .mcp.json, .agents/devkit, .git/info/exclude change)"
else fail "B5: the failed install left partial state:"; diff <(echo "$before") <(echo "$after") | head -15; fi

P="$(newproj b5g)"
mkdir -p "$P/.gemini"
printf '{\n  // my comment\n  "theme": "dark"\n}\n' > "$P/.gemini/settings.json"
before="$(snapshot "$P")"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a gemini --no-githooks > "$TMP/b5g.out" 2>&1; rc=$?
after="$(snapshot "$P")"
[ "$rc" != 0 ] && [ "$before" = "$after" ] && grep -q ".gemini/settings.json" "$TMP/b5g.out" \
  && ok "B5: JSONC .gemini/settings.json: install refused before writing anything, file named" \
  || { fail "B5: .gemini/settings.json (rc=$rc)"; diff <(echo "$before") <(echo "$after") | head -10; }
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude --no-githooks > "$TMP/b5c.out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "my comment" "$P/.gemini/settings.json" \
  && ok "B5: a Claude-only install does not need .gemini/settings.json to parse (and leaves it)" || fail "B5: claude-only install blocked by .gemini/settings.json (rc=$rc)"

if [ "$FAILS" -ne 0 ]; then echo "install user data: $FAILS FAILED"; exit 1; fi
echo "install user data: all checks passed"
