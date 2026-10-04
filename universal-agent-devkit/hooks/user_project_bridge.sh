#!/usr/bin/env bash
# OPT-IN HELPER — not wired in hooks/hooks.json and registered by no DevKit script: a user's own
# Codex / Cursor hook config is pointed at it by hand.
# User-level Codex/Cursor hook. Runs the project's DevKit bridge when this
# checkout has .agents/hooks/agent_bridge.sh and does not already register that
# platform (so a project hooks.json is not executed twice). No-op everywhere else.
# stdin is left for the bridge. bash 3.2 compatible.
set -u
platform="${1:-}"
kind="${2:-}"
hook="${3:-}"
case "$platform" in
  codex) marker_rel=".codex/hooks.json" ;;
  cursor) marker_rel=".cursor/hooks.json" ;;
  *) exit 0 ;;
esac
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || exit 0
bridge="$root/.agents/hooks/agent_bridge.sh"
[ -f "$bridge" ] || exit 0
marker="$root/$marker_rel"
if [ -f "$marker" ] && grep -q "agent_bridge.sh" "$marker" 2>/dev/null; then
  exit 0
fi
exec bash "$bridge" "$platform" "$kind" "$hook"
