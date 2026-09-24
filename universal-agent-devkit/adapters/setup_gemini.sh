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

# 1. AGENTS.md is the only instruction file. Gemini CLI reads it through
#    context.fileName (below); a GEMINI.md / Agent.md of the project's own is folded into
#    it (kept as GEMINI_old.md / Agent_old.md) — see devkit_install_agents_md.
devkit_install_agents_md "$TARGET_DIR" "$MODE" GEMINI.md Agent.md
# 1b. .gemini/settings.json, DevKit keys only (the rest of the file is kept):
#     context.fileName = AGENTS.md first — Gemini reads the same file as Claude Code.
#     context.includeDirectories += the DevKit folder (symlink mode): Gemini CLI imports
#     a file, and lets its read tool open one, only when the file's REAL path is inside
#     the workspace, so every .agents/devkit/… path would be refused as "path traversal".
#     Copy mode is committed for a team and gets no machine path.
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  mkdir -p "$TARGET_DIR/.gemini"
  python3 - "$TARGET_DIR/.gemini/settings.json" "$([ "$MODE" = symlink ] && echo "$DEVKIT_ROOT")" <<'PY_EOF'
import json, os, sys
path, devkit = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    data = {}
ctx = data.setdefault("context", {})
before = json.dumps(ctx, sort_keys=True)
names = ctx.get("fileName")
names = [names] if isinstance(names, str) else list(names or [])
ctx["fileName"] = ["AGENTS.md"] + [n for n in names if n not in ("AGENTS.md", "GEMINI.md", "Agent.md")]
if devkit:
    dirs = [d for d in ctx.get("includeDirectories") or [] if os.path.realpath(str(d)) != os.path.realpath(devkit)]
    ctx["includeDirectories"] = dirs + [devkit]
if json.dumps(ctx, sort_keys=True) != before or not os.path.exists(path):
    tmp = path + ".devkit-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
PY_EOF
  echo "  - .gemini/settings.json: context.fileName = AGENTS.md$([ "$MODE" = symlink ] && echo ", DevKit folder in context.includeDirectories")"
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
