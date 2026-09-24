#!/usr/bin/env bash
# setup_claude.sh — Configure Claude Code integration in target project (Non-Destructive Smart Merge)
set -euo pipefail

TARGET_DIR="${1:-$PWD}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"
DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODE="${2:-symlink}" # symlink or copy
LANGUAGE="${3:-en}"
SKIP_EXISTING="${SKIP_EXISTING:-0}"

source "$DEVKIT_ROOT/scripts/backup_conflict.sh"

echo "Configuring Claude Code for: $TARGET_DIR (mode: $MODE, lang: $LANGUAGE, skip_existing: $SKIP_EXISTING)"

mkdir -p "$TARGET_DIR/.claude/hooks" "$TARGET_DIR/.claude/commands" "$TARGET_DIR/.claude/agents"

# 1. AGENTS.md is the only instruction file: Claude Code (2.1.277+) reads it, and expands
#    its @-imports, when the project has no CLAUDE.md. A CLAUDE.md of the project's own is
#    folded into AGENTS.md (kept as CLAUDE_old.md) — see devkit_install_agents_md.
devkit_install_agents_md "$TARGET_DIR" "$MODE" CLAUDE.md

# 2. Additive Merge for .mcp.json — only the servers the profile calls for
#    (DEVKIT_MCPS_ALLOWED from install.sh; empty = all) whose command is on PATH: Claude
#    Code offers every .mcp.json server for approval (the approvals land in its own
#    settings.local.json enabledMcpjsonServers), and one that cannot start only fails.
#    An unmodified DevKit entry the profile no longer wants is removed; the user's own
#    and edited entries stay.
MCP_SRC="$(mktemp "${TMPDIR:-/tmp}/devkit-mcp.XXXXXX")"
if [ "$TARGET_DIR" = "$DEVKIT_ROOT" ]; then
  cp "$DEVKIT_ROOT/mcp/.mcp.json" "$MCP_SRC"
else
  python3 - "$DEVKIT_ROOT/mcp/.mcp.json" "$TARGET_DIR/.mcp.json" "$MCP_SRC" <<'PY'
import json, os, shutil, sys, tempfile
src, dst, out = sys.argv[1:4]
allowed = os.environ.get("DEVKIT_MCPS_ALLOWED", "").split()
servers = json.load(open(src, encoding="utf-8"))["mcpServers"]
keep = {}
for name, conf in servers.items():
    if allowed and name not in allowed:
        continue
    if not shutil.which(conf.get("command", "")):
        print(f"  - MCP {name}: `{conf.get('command')}` is not on PATH — not added (install it, then re-run `agent-kit init`)")
        continue
    keep[name] = conf
with open(out, "w", encoding="utf-8") as f:
    json.dump({"mcpServers": keep}, f, indent=2)
try:
    data = json.load(open(dst, encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)                        # no file yet / unparseable: merge_json.py reports it
mine = data.get("mcpServers") if isinstance(data, dict) else None
gone = [n for n, c in servers.items() if n not in keep and isinstance(mine, dict) and mine.get(n) == c]
if gone and not os.path.islink(dst):
    for n in gone:
        del mine[n]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(dst)), prefix=".devkit-mcp.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.chmod(tmp, os.stat(dst).st_mode & 0o7777)
    os.replace(tmp, dst)
    print(f"  - Removed DevKit MCP servers the profile does not use from {os.path.basename(dst)}: {', '.join(gone)}")
PY
fi
# merge_json.py backs up the file itself (as .mcp_old.json) only when the merge changes it.
python3 "$DEVKIT_ROOT/scripts/merge_json.py" "$MCP_SRC" "$TARGET_DIR/.mcp.json"
rm -f "$MCP_SRC"
echo "  - Merged MCP servers into .mcp.json (preserved existing custom MCPs)"

# 3. Additive Merge for .claude/settings.json
# Settings template = static base (permissions, env) from templates/claude_settings.json
# + hooks generated from hooks/hooks.json, the single source of truth also used by the
# plugin. Built in a temp file: installing must never rewrite files inside the devkit.
DEFAULT_SETTINGS="$(mktemp "${TMPDIR:-/tmp}/devkit-settings.XXXXXX")"
trap 'rm -f "$DEFAULT_SETTINGS"' EXIT
python3 - "$DEVKIT_ROOT/templates/claude_settings.json" "$DEVKIT_ROOT/hooks/hooks.json" > "$DEFAULT_SETTINGS" <<'PY'
import json, sys
base = json.load(open(sys.argv[1], encoding="utf-8"))
plugin = json.load(open(sys.argv[2], encoding="utf-8"))
hooks = json.dumps(plugin.get("hooks", plugin))
hooks = hooks.replace("${CLAUDE_PLUGIN_ROOT}/hooks/", "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/")
base["hooks"] = json.loads(hooks)
print(json.dumps(base, indent=2, ensure_ascii=False))
PY

# merge_json.py backs up settings.json itself (as settings_old.json) only when the merge changes it.

python3 "$DEVKIT_ROOT/scripts/merge_json.py" "$DEFAULT_SETTINGS" "$TARGET_DIR/.claude/settings.json"
echo "  - Merged safety gates into .claude/settings.json (preserved custom settings)"

# 4. Smart Item-by-Item Link for Hooks (Preserving custom user hooks)
# Only the hook scripts: hooks/tests/ and hooks.json (the plugin registry, already
# merged into settings.json above) are not hooks, and a `*.tmp*` file is an edit in
# progress. Links an older install made for them are removed.
for stale in tests hooks.json; do
  link_is_devkit_owned "$TARGET_DIR/.claude/hooks/$stale" "$DEVKIT_ROOT" && rm -f "$TARGET_DIR/.claude/hooks/$stale"
done
for hook in "$DEVKIT_ROOT/hooks"/*.sh "$DEVKIT_ROOT/hooks"/*.py; do
  [ -f "$hook" ] || continue
  hook_name="$(basename "$hook")"
  case "$hook_name" in *.tmp*|.*) continue ;; esac
  target_hook="$TARGET_DIR/.claude/hooks/$hook_name"
  if [ "$SKIP_EXISTING" = "1" ] && [ -e "$target_hook" ] && [ ! -L "$target_hook" ]; then
    echo "  - Preserved custom hook: $hook_name (--skip-existing active)"
    continue
  fi
  devkit_place "$hook" "$target_hook" "$MODE"
done

# 5. Smart Item-by-Item Link for Commands (Preserving custom user commands)
for cmd in "$DEVKIT_ROOT/commands"/*; do
  [ -e "$cmd" ] || continue
  cmd_name="$(basename "$cmd")"
  target_cmd="$TARGET_DIR/.claude/commands/$cmd_name"
  if ! devkit_command_allowed "$cmd"; then
    devkit_remove_filtered "$target_cmd"  # skill not part of the active profile
    continue
  fi
  if [ "$SKIP_EXISTING" = "1" ] && [ -e "$target_cmd" ] && [ ! -L "$target_cmd" ]; then
    echo "  - Preserved custom command: $cmd_name (--skip-existing active)"
    continue
  fi
  devkit_place "$cmd" "$target_cmd" "$MODE"
done

# 6. Smart Item-by-Item Link for Agents (Preserving custom user subagents)
for agent in "$DEVKIT_ROOT/agents"/*; do
  [ -e "$agent" ] || continue
  agent_name="$(basename "$agent")"
  target_agent="$TARGET_DIR/.claude/agents/$agent_name"
  case " ${DEVKIT_AGENTS_EXCLUDED:-} " in *" ${agent_name%.md} "*)
    devkit_remove_filtered "$target_agent"  # the profile's exclude_agents
    continue ;;
  esac
  if [ "$SKIP_EXISTING" = "1" ] && [ -e "$target_agent" ] && [ ! -L "$target_agent" ]; then
    echo "  - Preserved custom agent: $agent_name (--skip-existing active)"
    continue
  fi
  devkit_place "$agent" "$target_agent" "$MODE"
done

# 7. Project tier: the project's own commands/agents/hooks kept in .agents/local/ are
#    linked in when no DevKit item has that name (DevKit is the core and wins).
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  devkit_link_local "$TARGET_DIR" commands .claude/commands
  devkit_link_local_skill_commands "$TARGET_DIR"
  devkit_link_local "$TARGET_DIR" agents .claude/agents
  devkit_link_local "$TARGET_DIR" hooks .claude/hooks
fi

# 8. Claude Code's auto-memory: kept in the project (.agents/local/memory/claude-auto/)
#    instead of ~/.claude/projects/<slug>/memory — see scripts/claude_memory.py.
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  python3 "$DEVKIT_ROOT/scripts/claude_memory.py" "$TARGET_DIR" || true
fi

# Clean broken symlinks if any
find "$TARGET_DIR/.claude/hooks" "$TARGET_DIR/.claude/commands" "$TARGET_DIR/.claude/agents" -type l ! -exec test -e {} \; -delete 2>/dev/null || true

echo "✓ Claude Code integration complete (Non-destructive smart merge; custom files preserved)."
