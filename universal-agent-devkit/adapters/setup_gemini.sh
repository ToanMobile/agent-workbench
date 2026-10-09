#!/usr/bin/env bash
# setup_gemini.sh — Configure Antigravity & Google Gemini integration (Non-Destructive Smart Merge)
set -euo pipefail

TARGET_DIR="${1:-$PWD}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"
# Reached through a symlinked alias of the DevKit (quick-install.sh: ~/.universal-agent-devkit ->
# the checkout), links go through the alias: moving the checkout and re-pointing the alias keeps
# them working (2026-10-09: pwd -P baked the checkout path in, 97 links dangled after a move).
# The real path otherwise, and when the target is the DevKit itself (self-install).
DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -L "$DEVKIT_ROOT" ] || [ "$(cd "$DEVKIT_ROOT" && pwd -P)" = "$TARGET_DIR" ]; then
  DEVKIT_ROOT="$(cd "$DEVKIT_ROOT" && pwd -P)"
fi
MODE="${2:-symlink}" # symlink or copy
LANGUAGE="${3:-en}"
SKIP_EXISTING="${SKIP_EXISTING:-0}"

_bc="$DEVKIT_ROOT/scripts/git/backup_conflict.sh"; [ -f "$_bc" ] || _bc="$DEVKIT_ROOT/scripts/backup_conflict.sh"
source "$_bc"

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
  # The real path (not an alias): Gemini compares the REAL path of the file it reads.
  python3 - "$TARGET_DIR/.gemini/settings.json" "$([ "$MODE" = symlink ] && cd "$DEVKIT_ROOT" && pwd -P)" <<'PY_EOF'
import json, os, sys
path, devkit = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except FileNotFoundError:
    data = {}
except (OSError, ValueError) as e:
    data = e
if not isinstance(data, dict):
    # 2026-10-09: a JSONC file (comments) read as {} was rewritten with only the DevKit keys.
    sys.exit(f"setup_gemini: {path} does not parse ({data if isinstance(data, Exception) else 'not a JSON object'})"
             " — left untouched; fix it (JSON has no comments) and re-run.")
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
gone = [n for n, c in servers.items() if n not in keep and isinstance(mine, dict) and mine.get(n) == c
        and os.environ.get("DEVKIT_MCP_PRUNE", "1") == "1"]   # re-init, same profile: keep (bin/install.sh)
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
_mj="$DEVKIT_ROOT/scripts/governance/merge_json.py"; [ -f "$_mj" ] || _mj="$DEVKIT_ROOT/scripts/merge_json.py"
python3 "$_mj" "$MCP_SRC" "$TARGET_DIR/mcp_config.json"
rm -f "$MCP_SRC"
echo "  - Merged MCP servers into mcp_config.json (preserved existing custom MCPs)"

# 3. Item-by-item skills in .agents/skills (custom user skills preserved, the project tier's
#    own skills linked in, dangling DevKit links cleaned) — shared with setup_claude.sh.
devkit_place_skills "$TARGET_DIR" "$MODE"

echo "✓ Antigravity & Google Gemini (.agents/skills, AGENTS.md, mcp_config.json) ready."
