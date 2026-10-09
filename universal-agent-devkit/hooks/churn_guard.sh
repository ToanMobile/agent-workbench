#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# churn_guard.sh — PostToolUse hook: enforce CLAUDE.md 6.4b (churn guard).
#
# Rule 6.4b: editing the same file a third time in one task with NO new evidence
# in between means you are coding on guesswork — go back to W0 box 4 (failure
# mechanism) instead of patching again.
#
# Prose alone cannot enforce it: 6.4/6.4b ask the agent to count its own failed
# attempts, and nothing persists that count. This hook counts instead.
#
# WHAT COUNTS AS "NO NEW EVIDENCE": no evidence-producing tool call between the
# edits — Bash, gradle-build/test, adb-logcat, Grep, or any codebase-memory-mcp
# query. Reading/writing files is NOT evidence: re-reading the file you are
# editing is exactly the guesswork loop this guard targets.
#
# WARN (exit 2 → stderr goes to Claude) when: the Nth consecutive edit of one
# file lands with no evidence call since the first of that run. The edit has
# ALREADY happened (PostToolUse) — this is a stop-and-think signal, not a block.
# It fires once per threshold crossing per file, not on every subsequent edit.
#
# Escape hatch: CHURN_GUARD=0 (logged). Fail-open on any internal error.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

# Drain stdin before any early exit, otherwise the caller gets EPIPE.
INPUT="$(cat)"

# The project (2026-10-09): CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (of the process cwd when the payload has
# none). Outside a git tree there is no project and nothing is written (tests/gates/test_hook_log_dir.sh): a run at /
# created /.claude/audit-gate/.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "${REPO_ROOT}" ]; then   # the regex costs ~10 ms on a 1 MB payload: only when it is needed
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
LOG_DIR="${REPO_ROOT:+${REPO_ROOT}/.claude/audit-gate}"
if [ -n "${LOG_DIR}" ]; then
  [ -d "${LOG_DIR}" ] || mkdir -p "${LOG_DIR}"
  [ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
fi

if [ "${CHURN_GUARD:-1}" = "0" ]; then
  [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] CHURN_GUARD=0 — gate bypassed" >> "${LOG_DIR}/churn_guard.log" 2>/dev/null
  exit 0
fi

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ churn_guard: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
# Fast path (2026-10-09, decision-neutral; tests/gates/test_churn_guard_fast_path.sh): python warns only when the transcript holds
# exactly N landed edits of this file NAME since the last evidence call (N = CHURN_GUARD_MAX, 3 by default). Every landed edit is a
# tool_use line that names the file, so fewer than N lines naming it cannot warn: count them with grep (~8 ms on a 27 MB transcript)
# and skip python (~30 ms a call). Anything unusual (a JSON escape in the name, a non-numeric N, no transcript, a payload over
# 128 KiB) goes to python as before.
if [ "${#INPUT}" -lt 131072 ]; then
  _CG_N="${CHURN_GUARD_MAX:-3}"
  case "${_CG_N}" in ''|*[!0-9]*) _CG_N="" ;; *) [ "${_CG_N}" -ge 2 ] || _CG_N=2 ;; esac
  _CG_RX_F='"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  _CG_RX_T='"transcript_path"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  _CG_RX_B='^[A-Za-z0-9._+@=, -]+$'   # a name JSON writes as it is: no escape to miss in the transcript
  if [ -n "${_CG_N}" ] && [[ ${INPUT} =~ ${_CG_RX_F} ]]; then
    _CG_B="${BASH_REMATCH[2]##*/}"
    if [ -n "${_CG_B}" ] && [[ ${_CG_B} =~ ${_CG_RX_B} ]] && [[ ${INPUT} =~ ${_CG_RX_T} ]] && [ -f "${BASH_REMATCH[1]}" ]; then
      _CG_C="$(grep -c -F -- "${_CG_B}" "${BASH_REMATCH[1]}" 2>/dev/null)"
      case "${_CG_C}" in ''|*[!0-9]*) ;; *)
        if [ "${_CG_C}" -lt "${_CG_N}" ]; then
          [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] ${_CG_B}: ${_CG_C}/${_CG_N} lines naming it — pass (fast path)" >> "${LOG_DIR}/churn_guard.log" 2>/dev/null
          exit 0
        fi ;; esac
    fi
  fi
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable python could not
# start and the guard stayed quiet (tests/gates/test_hook_large_payload.sh).
CHURN_LOG="${LOG_DIR:+${LOG_DIR}/churn_guard.log}" \
CHURN_TS="$(date +%Y-%m-%dT%H:%M:%S)" CHURN_MAX="${CHURN_GUARD_MAX:-3}" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, sys, json, re

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
log    = os.environ.get("CHURN_LOG", "/dev/null")
ts     = os.environ.get("CHURN_TS", "?")
try:
    THRESHOLD = max(2, int(os.environ.get("CHURN_MAX", "3")))
except Exception:
    THRESHOLD = 3

def logline(s):
    try:
        with open(log, "a") as fh:
            fh.write(s + "\n")
    except Exception:
        pass

try:
    d = json.loads(raw)
except Exception as e:
    logline(f"[{ts}] stdin parse fail: {e!r} — fail-open")
    sys.exit(0)

edited = ""
inp = d.get("tool_input") or {}
if isinstance(inp, dict):
    edited = inp.get("file_path") or inp.get("notebook_path") or ""
if not isinstance(edited, str) or not edited:
    sys.exit(0)
edited_base = os.path.basename(edited)

tp = d.get("transcript_path")
if not tp or not os.path.exists(tp):
    logline(f"[{ts}] transcript unreadable — fail-open")
    sys.exit(0)

# Evidence = a tool call that can produce NEW information about the code's
# behaviour. Deliberately excludes Read/Edit/Write/Glob: re-reading the file you
# keep editing is the guesswork loop, not an escape from it.
EVIDENCE_TOOLS = ("Bash", "Grep", "Task", "Agent")
EVIDENCE_SUBSTR = ("gradle-build", "gradle-test", "adb-logcat", "adb-shell",
                   "search_graph", "trace_path", "query_graph", "get_code_snippet",
                   "detect_changes", "search_code", "get_file_problems")

edits_since_evidence = 0   # LANDED edits of THIS file since the last evidence call

try:
    # Only LANDED edits count, so tool_use ids whose result was an error are
    # skipped. An edit that was blocked (by another hook) or that failed ("String to replace not found")
    # changed nothing, so counting it inflates the churn number and makes the
    # warning state a count that never happened. Measured 2026-07-27: this hook
    # reported "2/3" when exactly one edit had landed, because a precode_gate
    # block counted as an edit. A gate that reports a wrong number is the defect
    # class W4 exists to stop.
    #
    # Walked from the END of the transcript backwards: a tool_result follows its
    # tool_use, so going backwards every error id is known before the edit it
    # belongs to, and the walk stops at the most recent evidence call instead of
    # parsing the whole session on every edit.
    error_ids = set()
    with open(tp) as fh:
        lines = fh.readlines()
    done = False
    attempts = set()   # one per assistant message: edits sent together are one attempt
    for n, rawline in enumerate(reversed(lines)):
        if '"tool_use"' not in rawline and '"tool_result"' not in rawline:
            continue                     # cheap prefilter: text/thinking records
        rawline = rawline.strip()
        try:
            rec = json.loads(rawline)
        except Exception:
            continue
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for blk in reversed(content):
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "tool_result":
                if blk.get("is_error") and blk.get("tool_use_id"):
                    error_ids.add(blk["tool_use_id"])
                continue
            if blk.get("type") != "tool_use":
                continue
            name = blk.get("name", "")
            if name in EVIDENCE_TOOLS or any(s in name for s in EVIDENCE_SUBSTR):
                done = True              # new evidence → the run starts after it
                break
            if name in ("Edit", "Write", "NotebookEdit"):
                if blk.get("id") in error_ids:
                    continue             # blocked/failed → nothing landed
                binp = blk.get("input") or {}
                fp = binp.get("file_path") or binp.get("notebook_path") or ""
                if isinstance(fp, str) and os.path.basename(fp) == edited_base:
                    # Claude Code writes each tool_use of one message as its own line sharing
                    # message.id (OfficeReader 2026-09-26: batched edits warned 8 times)
                    attempts.add((rec.get("message") or {}).get("id") or "line-%d" % n)
        edits_since_evidence = len(attempts)
        if done:
            break
except Exception as e:
    logline(f"[{ts}] transcript scan fail: {e!r} — fail-open")
    sys.exit(0)

# The transcript may not yet contain the edit that triggered this hook.
if edits_since_evidence == 0:
    edits_since_evidence = 1

if edits_since_evidence < THRESHOLD:
    logline(f"[{ts}] {edited_base}: {edits_since_evidence}/{THRESHOLD} — pass")
    sys.exit(0)

# Warn only on the exact threshold crossing, not on every later edit, so a long
# deliberate editing run does not turn into a nag loop.
if edits_since_evidence > THRESHOLD:
    logline(f"[{ts}] {edited_base}: {edits_since_evidence} (>threshold) — already warned, pass")
    sys.exit(0)

logline(f"[{ts}] WARN — {edited_base}: {edits_since_evidence} edits, no evidence call in between")
sys.stderr.write(
    f"⚠️ CHURN-GUARD (CLAUDE.md 6.4b): {edited_base} — lần sửa thứ "
    f"{edits_since_evidence} liên tiếp mà KHÔNG có tool call sinh evidence nào xen giữa "
    f"(Bash/test/logcat/grep/graph).\n"
    f"   Đây là dấu hiệu đang code theo phỏng đoán, không theo failure mechanism.\n"
    f"   Trước khi sửa tiếp, trả lời W0 ô 4: cái gì SET giá trị đang gate vào, và nó có\n"
    f"   chạy trong kịch bản bug không? Chưa trả lời được → dừng sửa, đi lấy evidence.\n"
    f"   (2 lần fix hỏng cùng root cause → 6.4: bỏ và đổi đường tấn công; tiếp tục task theo B9.)\n"
)
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
