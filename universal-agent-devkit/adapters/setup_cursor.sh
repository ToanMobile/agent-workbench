#!/usr/bin/env bash
# setup_cursor.sh — Configure Cursor IDE (Non-Destructive Smart Merge)
set -euo pipefail

TARGET_DIR="${1:-$PWD}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"
DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODE="${2:-symlink}" # symlink or copy
LANGUAGE="${3:-en}"
DOMAIN="${4:-general}"

case "$MODE" in symlink|copy) ;; *) echo "$(basename "$0"): invalid mode '$MODE' (symlink | copy)" >&2; exit 2 ;; esac

source "$DEVKIT_ROOT/scripts/backup_conflict.sh"

echo "Configuring Cursor IDE for: $TARGET_DIR (mode: $MODE, domain: $DOMAIN, lang: $LANGUAGE)"

# 1. Non-Destructive Smart Merge for .cursorrules and AGENTS.md
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && [ -f "$TARGET_DIR/.cursorrules" ] && [ ! -f "$TARGET_DIR/.cursorrules_old" ] \
   && ! grep -q "universal-agent-devkit" "$TARGET_DIR/.cursorrules" 2>/dev/null; then
  cp "$TARGET_DIR/.cursorrules" "$TARGET_DIR/.cursorrules_old"
  echo "  - Preserved original .cursorrules as .cursorrules_old"
fi

# Cursor reads AGENTS.md as plain markdown (no @-imports): the block tells the agent to
# open each listed file itself. .cursorrules is the legacy file (gone from Cursor's docs).
CURSOR_INJECT="$DEVKIT_ROOT/templates/agents_injection_block.md"
if [ -f "$TARGET_DIR/.cursorrules" ]; then
  devkit_merge_block "$CURSOR_INJECT" "$TARGET_DIR/.cursorrules"
fi

# AGENTS.md: shared logic (devkit link/copy vs the project's own file) — see backup_conflict.sh
devkit_install_agents_md "$TARGET_DIR" "$MODE"

# 2. An always-applied project rule, .cursor/rules/universal-agent-devkit.mdc: Cursor
#    includes files named `@path` in a rule (docs: "Use @filename to include files in
#    your rule's context"), so core, profile and project-tier rules reach every request.
#    The block is built at the project root (devkit_merge_block resolves paths from the
#    file's folder); the root AGENTS.md line is left out — Cursor loads that file itself.
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  MDC="$TARGET_DIR/.cursor/rules/universal-agent-devkit.mdc"
  mkdir -p "$(dirname "$MDC")"
  if [ ! -f "$MDC" ]; then
    MDC_TMP="$(mktemp "$MDC.XXXXXX")"
    printf -- '---\ndescription: Universal Agent DevKit rules — read before any work in this project\nalwaysApply: true\n---\n' > "$MDC_TMP"
    chmod 644 "$MDC_TMP" && mv "$MDC_TMP" "$MDC"
  fi
  BLOCK_TMP="$(mktemp "$TARGET_DIR/.devkit-cursor-block.XXXXXX")"
  trap 'rm -f "$BLOCK_TMP" "$BLOCK_TMP.body"' EXIT
  rm -f "$BLOCK_TMP"   # merge_markdown.py creates it
  devkit_merge_block "$CURSOR_INJECT" "$BLOCK_TMP" >/dev/null
  # The essentials section is filled in AGENTS.md only (context_sync.py); Cursor loads that file itself.
  sed -e '/universal-agent-devkit:start/d' -e '/universal-agent-devkit:end/d' -e '/SSOT: @AGENTS\.md$/d' \
      -e '/devkit-essentials:/d' "$BLOCK_TMP" > "$BLOCK_TMP.body"
  python3 "$DEVKIT_ROOT/scripts/merge_markdown.py" "$BLOCK_TMP.body" "$MDC" "universal-agent-devkit" >/dev/null
  rm -f "$BLOCK_TMP" "$BLOCK_TMP.body"
  echo "  - .cursor/rules/universal-agent-devkit.mdc: DevKit rules, always applied"
fi

echo "✓ Cursor IDE (AGENTS.md SSOT) ready."
