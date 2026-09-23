#!/usr/bin/env bash
# setup_gemini.sh — Configure Antigravity & Google Gemini integration (Non-Destructive Smart Merge)
set -euo pipefail

TARGET_DIR="${1:-$PWD}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"
DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODE="${2:-symlink}" # symlink or copy
LANGUAGE="${3:-en}"
SKIP_EXISTING="${SKIP_EXISTING:-0}"

source "$DEVKIT_ROOT/scripts/backup_conflict.sh"

echo "Configuring Antigravity / Google Gemini for: $TARGET_DIR (mode: $MODE, lang: $LANGUAGE, skip_existing: $SKIP_EXISTING)"

mkdir -p "$TARGET_DIR/.agents/skills"

# 1. Non-Destructive Smart Merge for AGENTS.md, GEMINI.md, and Agent.md
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  if [ -f "$TARGET_DIR/GEMINI.md" ] && [ ! -f "$TARGET_DIR/GEMINI_old.md" ] && ! grep -q "universal-agent-devkit" "$TARGET_DIR/GEMINI.md" 2>/dev/null; then
    cp "$TARGET_DIR/GEMINI.md" "$TARGET_DIR/GEMINI_old.md"
  fi
  if [ -f "$TARGET_DIR/Agent.md" ] && [ ! -f "$TARGET_DIR/Agent_old.md" ] && ! grep -q "universal-agent-devkit" "$TARGET_DIR/Agent.md" 2>/dev/null; then
    cp "$TARGET_DIR/Agent.md" "$TARGET_DIR/Agent_old.md"
  fi
fi

# Gemini CLI loads GEMINI.md (not AGENTS.md) and expands its `@path` imports, so a
# project without one gets a GEMINI.md holding the DevKit block alone.
GEMINI_TARGET="${TARGET_DIR}/GEMINI.md"
[ -f "$TARGET_DIR/Agent.md" ] && GEMINI_TARGET="${TARGET_DIR}/Agent.md"
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] || [ -f "$GEMINI_TARGET" ]; then
  GEMINI_INJECT="$DEVKIT_ROOT/templates/agents_injection_block.md"
  devkit_merge_block "$GEMINI_INJECT" "$GEMINI_TARGET"
fi

# AGENTS.md: shared logic (devkit link/copy vs the project's own file) — see backup_conflict.sh
devkit_install_agents_md "$TARGET_DIR" "$MODE"

# 1b. Gemini CLI imports a file, and lets its read tool open one, only when the file's
#     REAL path is inside the workspace: every DevKit link (symlink mode; and
#     .agents/active-profile in both modes) is refused as "path traversal". Symlink mode
#     already ties the project to this DevKit folder, so it joins the workspace
#     (context.includeDirectories) and the block's "open each path" works; copy mode is
#     committed for a team and gets no machine path.
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && [ "$MODE" = "symlink" ]; then
  GEMINI_CTX="$(mktemp "${TMPDIR:-/tmp}/devkit-gemini.XXXXXX")"
  python3 -c 'import json,sys; print(json.dumps({"context": {"includeDirectories": [sys.argv[1]]}}))' "$DEVKIT_ROOT" > "$GEMINI_CTX"
  mkdir -p "$TARGET_DIR/.gemini"
  python3 "$DEVKIT_ROOT/scripts/merge_json.py" "$GEMINI_CTX" "$TARGET_DIR/.gemini/settings.json" >/dev/null
  rm -f "$GEMINI_CTX"
  echo "  - .gemini/settings.json: DevKit folder added to context.includeDirectories (its links are readable)"
fi

# 2. Additive Merge for mcp_config.json — the same filter as .mcp.json in setup_claude.sh:
#    the profile's servers (DEVKIT_MCPS_ALLOWED) whose command is on PATH; unmodified
#    DevKit entries the profile does not use are removed.
MCP_SRC="$(mktemp "${TMPDIR:-/tmp}/devkit-mcp.XXXXXX")"
if [ "$TARGET_DIR" = "$DEVKIT_ROOT" ]; then
  cp "$DEVKIT_ROOT/mcp/mcp_config.json" "$MCP_SRC"
else
  python3 - "$DEVKIT_ROOT/mcp/mcp_config.json" "$TARGET_DIR/mcp_config.json" "$MCP_SRC" <<'PY'
import json, os, shutil, sys, tempfile
src, dst, out = sys.argv[1:4]
allowed = os.environ.get("DEVKIT_MCPS_ALLOWED", "").split()
servers = json.load(open(src, encoding="utf-8"))["mcpServers"]
keep = {n: c for n, c in servers.items()
        if (not allowed or n in allowed) and shutil.which(c.get("command", ""))}
with open(out, "w", encoding="utf-8") as f:
    json.dump({"mcpServers": keep}, f, indent=2)
try:
    data = json.load(open(dst, encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)
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
# merge_json.py backs up mcp_config.json itself (as mcp_config_old.json) only when the merge changes it.
python3 "$DEVKIT_ROOT/scripts/merge_json.py" "$MCP_SRC" "$TARGET_DIR/mcp_config.json"
rm -f "$MCP_SRC"
echo "  - Merged MCP servers into mcp_config.json (preserved existing custom MCPs)"

# 3. Smart Item-by-Item Link for Skills (Preserving custom user skills)
for skill in "$DEVKIT_ROOT/skills"/*; do
  [ -e "$skill" ] || continue
  skill_name="$(basename "$skill")"
  target_skill_path="$TARGET_DIR/.agents/skills/$skill_name"
  if ! devkit_skill_allowed "$skill_name"; then
    devkit_remove_filtered "$target_skill_path"  # not part of the active profile
    continue
  fi
  if [ "$SKIP_EXISTING" = "1" ] && [ -e "$target_skill_path" ] && [ ! -L "$target_skill_path" ]; then
    echo "  - Preserved custom skill: $skill_name (--skip-existing active)"
    continue
  fi
  devkit_place "$skill" "$target_skill_path" "$MODE"
done

# 4. Project tier: the project's own skills kept in .agents/local/skills are linked in
#    when no DevKit skill has that name (DevKit is the core and wins).
[ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && devkit_link_local "$TARGET_DIR" skills .agents/skills

# Clean broken symlinks if any
find "$TARGET_DIR/.agents/skills" -type l ! -exec test -e {} \; -delete 2>/dev/null || true

echo "✓ Antigravity & Google Gemini (.agents/skills, AGENTS.md, mcp_config.json) ready."
