#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# prompt_context.sh — UserPromptSubmit hook: the context-enricher step, done by the
# harness instead of hoping the model runs it.
#
# For each prompt, scripts/enrich_context.py --compact prints a few lines that are
# added to the model's context: the kind of work detected (bug fix, UI, network…),
# the paired RED→GREEN requirement for bug fixes, intent-specific non-functional
# requirements, and the project's own recorded traps (.agents/instincts.md) that
# match the request — with the `sed -n` line range to read each one.
#
# Silent (adds nothing) for slash commands, very short prompts, and requests that
# match no intent and no trap — questions and chit-chat pay no context cost.
#
# Never blocks: always exit 0. Escape hatch: PROMPT_CONTEXT=0.
# Protocol: stdin JSON {"prompt": …}; stdout is added to the context.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

[ "${PROMPT_CONTEXT:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Locate the DevKit: this script's real path (symlink install), $DEVKIT_ROOT, or the
# quick-install location (copy-mode installs have no link back). Links are followed
# in bash (no readlink -f on bash 3.2 / macOS) so python starts only once, below.
SELF="$0"
while [ -L "${SELF}" ]; do
  LINK="$(readlink "${SELF}")"
  case "${LINK}" in /*) SELF="${LINK}" ;; *) SELF="$(dirname "${SELF}")/${LINK}" ;; esac
done
ENRICH=""
for cand in "$(cd -P "$(dirname "${SELF}")/.." 2>/dev/null && pwd)/scripts/enrich_context.py" \
            "${DEVKIT_ROOT:-}/scripts/enrich_context.py" \
            "${HOME}/.universal-agent-devkit/scripts/enrich_context.py"; do
  [ -f "${cand}" ] && { ENRICH="${cand}"; break; }
done
[ -n "${ENRICH}" ] || exit 0

# enrich_context.py --hook reads the payload itself and stays silent for slash
# commands and prompts under 8 characters.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CLAUDE_PROJECT_DIR="${REPO_ROOT}" python3 "${ENRICH}" --hook 2>/dev/null
exit 0
