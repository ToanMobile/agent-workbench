#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# agent_bridge.sh — OPT-IN HELPER: run the DevKit's Claude Code hooks from other
# agents (OpenAI Codex, Gemini CLI, Cursor). Not wired in hooks/hooks.json; the
# adapters register it in .codex/hooks.json, .gemini/settings.json and
# .cursor/hooks.json (scripts/agent_hooks.py).
#
# Usage: agent_bridge.sh <codex|gemini|cursor> <session|prompt|shell|stop> <hook.sh>
#   session  SessionStart / sessionStart        → session_context.sh
#   prompt   UserPromptSubmit / BeforeAgent     → prompt_context.sh
#   shell    PreToolUse(Bash) / BeforeTool(run_shell_command) / beforeShellExecution
#                                               → block-dangerous-git.sh, hardware_safety_gate.sh
#                                               (incl. its destructive rm guard; the session
#                                               cwd is passed on as the payload cwd)
#   stop     Stop / AfterAgent / stop           → regression_gate.sh
#
# It rewrites the platform's stdin into the Claude hook input, runs <hook.sh> (from
# this script's own directory) with CLAUDE_PROJECT_DIR set, and turns the result into
# the platform's answer:
#   shell  exit 2 + reason blocks on every platform (Cursor: permission "deny" JSON)
#   stop   exit 2 + reason → Codex continues, Gemini retries with the reason,
#          Cursor gets it as followup_message (the next user message)
#   context  Codex: plain stdout · Gemini: hookSpecificOutput.additionalContext ·
#            Cursor: additional_context
# Hooks that read Claude's transcript (review, test-evidence, claims) are not bridged:
# the other agents write different transcripts.
#
# Cursor's stop payload carries no session id: regression_gate's per-session loop
# guard is shared across Cursor chats there (the diff-keyed result cache still works),
# and Cursor's own loop_limit (default 5) bounds the follow-ups.
#
# Fail-open on bridge errors (a broken bridge must not stop the agent), except that a
# hook's own "block" is always passed on. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

PLATFORM="${1:-}"; KIND="${2:-}"; HOOK="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RAW="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "${HERE}/${HOOK}" ] || exit 0
case "${PLATFORM}:${KIND}" in codex:*|gemini:*|cursor:*) ;; *) exit 0 ;; esac

ROOT="$(printf '%s' "${RAW}" | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: d = {}
print(d.get("cwd") or "")' 2>/dev/null)"
[ -n "${ROOT}" ] && [ -d "${ROOT}" ] || ROOT="$PWD"
ROOT="$(git -C "${ROOT}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${ROOT}")"

IN="$(printf '%s' "${RAW}" | KIND="${KIND}" python3 -c 'import json,os,sys
try: d = json.load(sys.stdin)
except Exception: d = {}
kind = os.environ["KIND"]
ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
if kind == "shell":
    out = {"tool_name": "Bash", "tool_input": {"command": ti.get("command") or d.get("command") or ""}}
    if isinstance(d.get("cwd"), str) and d["cwd"]:
        out["cwd"] = d["cwd"]  # where the command runs: relative rm targets start here
elif kind == "prompt":
    out = {"prompt": d.get("prompt") or ""}
elif kind == "stop":
    out = {"session_id": d.get("session_id") or d.get("conversation_id") or "", "hook_event_name": "Stop"}
else:
    out = {"session_id": d.get("session_id") or "", "hook_event_name": "SessionStart"}
print(json.dumps(out))' 2>/dev/null)"

OUT_F="$(mktemp "${TMPDIR:-/tmp}/devkit-bridge-out.XXXXXX")"; ERR_F="$(mktemp "${TMPDIR:-/tmp}/devkit-bridge-err.XXXXXX")"
trap 'rm -f "${OUT_F}" "${ERR_F}"' EXIT
printf '%s' "${IN}" | CLAUDE_PROJECT_DIR="${ROOT}" bash "${HERE}/${HOOK}" >"${OUT_F}" 2>"${ERR_F}"
RC=$?

PLATFORM="${PLATFORM}" KIND="${KIND}" RC="${RC}" OUT_F="${OUT_F}" ERR_F="${ERR_F}" python3 - <<'PY'
import json, os, sys
platform, kind, rc = os.environ["PLATFORM"], os.environ["KIND"], int(os.environ["RC"])
out = open(os.environ["OUT_F"], encoding="utf-8", errors="replace").read().strip()
err = open(os.environ["ERR_F"], encoding="utf-8", errors="replace").read().strip()

if kind in ("session", "prompt"):
    if out:
        if platform == "gemini":
            event = "SessionStart" if kind == "session" else "BeforeAgent"
            print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": out}}, ensure_ascii=False))
        elif platform == "cursor":
            print(json.dumps({"additional_context": out}, ensure_ascii=False))
        else:
            print(out)
    sys.exit(0)

if rc != 2:
    sys.exit(0)  # allowed (a hook's own warnings stay in its log)
reason = err or "blocked by a Universal Agent DevKit gate"
if platform == "cursor":
    if kind == "shell":
        print(json.dumps({"permission": "deny", "user_message": reason.splitlines()[0][:300],
                          "agent_message": reason}, ensure_ascii=False))
    else:
        print(json.dumps({"followup_message": reason}, ensure_ascii=False))
    sys.exit(0)
sys.stderr.write(reason + "\n")
sys.exit(2)
PY
