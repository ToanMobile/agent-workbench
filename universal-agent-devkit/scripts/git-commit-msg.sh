#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# git-commit-msg.sh — body of the git commit-msg hook written by
# `agent-kit githooks install`: a fix commit that changes source code needs
# `Bug: <id>` (checked against .agents/local/guards.json / the checklist when they
# exist) or `No-Guard: <reason>` (post-fix-gate.py --commit-msg).
# Fails closed without python3. Skip once: git commit --no-verify
# Disable: DEVKIT_PRECOMMIT=0 (same switch as pre-commit). bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u
[ "${DEVKIT_PRECOMMIT:-1}" = "0" ] && exit 0
DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$PWD"
command -v python3 >/dev/null 2>&1 || { echo "✖ DevKit commit-msg: python3 not found — commit blocked (git commit --no-verify to skip once)" >&2; exit 1; }
CLAUDE_PROJECT_DIR="$ROOT" python3 "$DEVKIT_ROOT/bin/post-fix-gate.py" --commit-msg "$1" || {
  echo "  Skip once: git commit --no-verify" >&2; exit 1; }
