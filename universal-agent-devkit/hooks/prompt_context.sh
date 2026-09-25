#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# prompt_context.sh — UserPromptSubmit hook: the context-enricher step, done by the
# harness instead of hoping the model runs it.
#
# For each prompt, scripts/enrich_context.py --compact prints a few lines that are
# added to the model's context: the kind of work detected (bug fix, UI, network…),
# the paired RED→GREEN requirement for bug fixes, intent-specific non-functional
# requirements, and the project's own recorded traps (.agents/instincts.md) that
# match the request — with the `sed -n` line range to read each one; then the
# project-rule sections whose title matches (scripts/rule_context.py).
#
# Silent (adds nothing) for slash commands, very short prompts, and requests that
# match no intent and no trap — questions and chit-chat pay no context cost.
#
# A bug prompt also becomes a REPORTED checklist row (BUG_CAPTURE, scripts/enrich_context.py)
# — never for agent / harness prompts ("You are …" openings, tool/JSON schemas, long
# instruction blocks) nor under a non-Claude harness (Grok, a bridged agent: hooks/devkit_harness.py).
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
# rule_context.py then names the project-rule sections (.agents/context/rules-index.md)
# whose title matches the request — the rules themselves are not loaded at startup.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PAYLOAD="$(cat)"
RULES="$(dirname "${ENRICH}")/rule_context.py"
RULES_OUT=""
if [ -f "${RULES}" ] && [ -f "${REPO_ROOT}/.agents/context/rules-index.md" ]; then
  # In parallel with enrich_context.py: the hook's wall time is one python start, not two.
  RULES_OUT="$(mktemp "${TMPDIR:-/tmp}/devkit-rules.XXXXXX")" || RULES_OUT=""
  [ -n "${RULES_OUT}" ] && { printf '%s' "${PAYLOAD}" | CLAUDE_PROJECT_DIR="${REPO_ROOT}" python3 "${RULES}" > "${RULES_OUT}" 2>/dev/null & }
fi
printf '%s' "${PAYLOAD}" | CLAUDE_PROJECT_DIR="${REPO_ROOT}" python3 "${ENRICH}" --hook 2>/dev/null
if [ -n "${RULES_OUT}" ]; then
  wait
  cat "${RULES_OUT}"
  # Recall log: the matched project-rule sections, next to the traps enrich_context.py
  # logged (.claude/audit-gate/surfaced.jsonl; prompt sha1 only). SURFACED_LOG=0 off.
  if [ -s "${RULES_OUT}" ] && [ "${SURFACED_LOG:-1}" != "0" ] && [ -d "${REPO_ROOT}/.agents" ]; then
    PAYLOAD="${PAYLOAD}" RULES_FILE="${RULES_OUT}" LOG_DIR="${REPO_ROOT}/.claude/audit-gate" python3 - <<'PY' 2>/dev/null
import hashlib, json, os, re, time
d = json.loads(os.environ.get("PAYLOAD") or "{}")
secs = [{"title": m.group(1), "cmd": m.group(2)} for m in
        (re.match(r"\s*- (.+?) — (`.+`)\s*$", l) for l in open(os.environ["RULES_FILE"], encoding="utf-8")) if m]
if secs:
    os.makedirs(os.environ["LOG_DIR"], exist_ok=True)
    with open(os.path.join(os.environ["LOG_DIR"], "surfaced.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "session": str(d.get("session_id") or ""),
                             "prompt_sha1": hashlib.sha1((d.get("prompt") or "").encode("utf-8")).hexdigest(),
                             "rule_sections": secs}, ensure_ascii=False) + "\n")
PY
  fi
  rm -f "${RULES_OUT}"
fi
exit 0
