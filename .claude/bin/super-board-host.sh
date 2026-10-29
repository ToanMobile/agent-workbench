#!/usr/bin/env bash
# super-board-host.sh — which agent host is this shell inside: `claude`, `codex` or `agy` (Antigravity).
#
# WHY. `/super-board run` launched from a Codex CLI session has no Claude Workflow tool, so the
# workflow backend cannot start. The orchestrator checks its own tool list first; this is the
# check a script can make, and the tie-breaker when the tool list is unclear.
#
# THE SIGNAL. Codex CLI sets CODEX_THREAD_ID (and CODEX_SESSION_ID, the same value) in every
# shell it runs. Observed 2026-10-04 on codex-cli 0.160.0 with `codex exec -s read-only`:
# CODEX_THREAD_ID, CODEX_SESSION_ID, CODEX_VERSION, CODEX_SANDBOX=seatbelt, CODEX_CI=1.
# Not used: CODEX_HOME (people export it in their own profile), CODEX_SANDBOX (absent when
# the sandbox is off). A Codex lane started from a Claude session also carries CLAUDECODE; the
# Codex ids still win there, because the innermost host is the one running this shell.
#
# Antigravity (agy) exports ANTIGRAVITY_* variables; any one of them marks the host. Codex ids win over it.
#
# Usage: super-board-host.sh          prints `claude`, `codex` or `agy`, exit 0
# SUPER_BOARD_HOST=claude|codex|agy forces the answer (tests, or a host the check misreads).
# Any other SUPER_BOARD_HOST value exits 64: a host the board does not know is never guessed as claude.
set -euo pipefail

case "${SUPER_BOARD_HOST:-}" in
  claude|codex|agy) echo "$SUPER_BOARD_HOST"; exit 0 ;;
  '') ;;
  *) echo "super-board-host.sh: SUPER_BOARD_HOST must be claude, codex or agy" >&2; exit 64 ;;
esac

if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SESSION_ID:-}" ]; then
  echo codex
elif env | grep -q '^ANTIGRAVITY_'; then
  echo agy
else
  echo claude
fi
