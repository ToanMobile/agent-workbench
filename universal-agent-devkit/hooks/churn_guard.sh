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
# ALSO (the commit-closure check below): warns once per file when the edited path is UNTRACKED (the git index does not hold it, so the edit cannot be
# committed alone). Same exit-2-means-tell-Claude channel; the edit has already happened, nothing is blocked.
#
# Escape hatch: CHURN_GUARD=0 (logged; also turns the untracked warning off). Fail-open on any internal error.
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
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'   # a JSON-escaped cwd too (é sent escaped, \", \\): tests/gates/test_hook_payload_cwd_escaped.sh
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  case "${_PCWD}" in *\\*) _PCWD="$(python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())' "${_PCWD}" 2>/dev/null)" || _PCWD="." ;; esac
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
LOG_DIR="${REPO_ROOT:+${REPO_ROOT}/.claude/audit-gate}"
if [ -n "${LOG_DIR}" ]; then
  [ -d "${LOG_DIR}" ] || mkdir -p "${LOG_DIR}"
  for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
  [ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
fi

if [ "${CHURN_GUARD:-1}" = "0" ]; then
  [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] CHURN_GUARD=0 — gate bypassed" >> "${LOG_DIR}/churn_guard.log" 2>/dev/null
  exit 0
fi

# ── Commit closure at EDIT time (tests/gates/test_untracked_edit_warning.sh) ──────────────────────────────────────────────────────
# An edit that lands in an UNTRACKED file cannot be committed alone: the index (so HEAD) does not hold the file, so a commit of the edited paths (or a
# `git archive HEAD` / CI checkout) lacks the code the edit depends on. OfficeReader 2026-10-07: the edit lived in an untracked file another
# session's refactor had made, and nothing said so until a reviewer noticed. Lives here, not in a new hook file: this hook already judges every
# file type on every Edit/Write/NotebookEdit, and a new hook would change the documented hook count and need three registries.
# WARN only (PostToolUse: the edit has happened), once per file per session (a ledger in LOG_DIR keyed by session id); a file THIS session
# created with Write is its own and stays quiet (Write answers type "create"; an answer with no type is read as create, which fails safe).
# Bash + git only (no python: tests/gates/test_churn_guard_fast_path.sh). Off: UNTRACKED_EDIT_WARN=0 (CHURN_GUARD=0 turns both off).
# The warning is printed here and turns this hook's exit into 2 (_UE_RC); the churn check below still runs, so both messages can appear.
# ponytail: warns on the fact only; the full version builds `git archive HEAD` plus an overlay of the paths to be committed and compiles that;
# upgrade when a commit made around an untracked edit still breaks a clean checkout.
#
# Cost and safety (review of lane A11; this hook runs on every Edit/Write of every repo, so it stays fast, fail-open and never blocks):
#   - the file_path, session_id and tool_name regexes read only the first 8 KiB of the payload (all three come before any content), so no
#     regex walks a 20 MB payload; a file_path past that prefix is not judged. The one exception is the Write "update" check, whose key
#     follows the content: it scans the whole payload, but only for a Write to an untracked file this session has not judged yet.
#   - the session's ledger is read BEFORE any git process: a file judged earlier costs none; a ledger path that is a directory is skipped, logged.
#   - the git calls take -c core.fsmonitor=false: `git ls-files` starts the repo's core.fsmonitor program, and the edited path may lie in any
#     repo; a leaked GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE is dropped so the repo of the edited path is the one judged.
#   - the check asks the git INDEX (ls-files), not HEAD: a file another session has `git add`ed but not committed passes silently while HEAD
#     still lacks it. ponytail: no HEAD lookup (one more git process per first edit); add `git cat-file -e HEAD:<path>` if that ever bites.
#   - ponytail: a payload with no session_id shares the ledger `untracked_edit.nosid`, so a second such session is not warned again; Claude
#     Code always sends session_id, upgrade (key by transcript_path) if another host does not.
_UE_RC=0
if [ "${UNTRACKED_EDIT_WARN:-1}" != "0" ] && [ -n "${LOG_DIR}" ] && command -v git >/dev/null 2>&1; then
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
  # The two expressions that read the whole payload run under LC_ALL=C: their patterns are ASCII, and a byte-wise slice / match never
  # decodes a 20 MB payload as UTF-8 (measured on 40 MB: the 8 KiB slice 0.43 s -> 0.08 s). The locale is put back right after each.
  _UE_LC="${LC_ALL-}"; _UE_LCS="${LC_ALL+x}"
  _ue_lc_restore() { if [ -n "${_UE_LCS}" ]; then LC_ALL="${_UE_LC}"; else unset LC_ALL; fi; }
  LC_ALL=C; _UE_HEAD="${INPUT:0:8192}"; _ue_lc_restore
  _UE_RX_F='"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"(/[^"\\]*)"'   # absolute and escape-free, else not judged
  _UE_P=""
  if [[ ${_UE_HEAD} =~ ${_UE_RX_F} ]]; then
    _UE_P="${BASH_REMATCH[2]}"
  elif [[ ${_UE_HEAD} == *'"tool_input"'* ]]; then   # content ahead of the path inside tool_input pushed it past the prefix: ONE full match, under LC_ALL=C
    LC_ALL=C; if [[ ${INPUT} =~ ${_UE_RX_F} ]]; then _UE_P="${BASH_REMATCH[2]}"; fi; _ue_lc_restore
  fi
  if [ -n "${_UE_P}" ]; then
    _UE_D="${_UE_P%/*}"; _UE_B="${_UE_P##*/}"; [ -n "${_UE_D}" ] || _UE_D="/"
    _UE_RX_S='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
    [[ ${_UE_HEAD} =~ ${_UE_RX_S} ]] && _UE_SID="${BASH_REMATCH[1]}" || _UE_SID="nosid"
    _UE_L="${LOG_DIR}/untracked_edit.${_UE_SID}"
    if [ -d "${_UE_L}" ]; then
      { echo "[$(date +%Y-%m-%dT%H:%M:%S)] ${_UE_L} is a directory, not a ledger — untracked-edit check skipped (fail-open)" >> "${LOG_DIR}/churn_guard.log"; } 2>/dev/null   # {…} 2>/dev/null: the shell's own "Permission denied" for a failed >> would escape a 2>/dev/null written after the redirect
    elif [ -s "${_UE_L}" ] && grep -qxF -- "${_UE_P}" "${_UE_L}" 2>/dev/null; then
      :   # judged earlier this session (warned, or created by this session's Write): no git process
    # tracked → nothing to say (index lookup only: the common case costs one cheap git call); untracked and not ignored → the check below
    elif [ -n "${_UE_B}" ] && [ -d "${_UE_D}" ] \
       && ! git -c core.fsmonitor=false -C "${_UE_D}" ls-files --error-unmatch -- ":(literal)${_UE_B}" >/dev/null 2>&1 \
       && [ -n "$(git -c core.fsmonitor=false -C "${_UE_D}" ls-files --others --exclude-standard -- ":(literal)${_UE_B}" 2>/dev/null)" ]; then
      [ -e "${_UE_L}" ] || find "${LOG_DIR}" -maxdepth 1 -name 'untracked_edit.*' -mtime +2 -exec rm -f {} + 2>/dev/null   # a ledger is one session's: old ones go
      { printf '%s\n' "${_UE_P}" >> "${_UE_L}"; } 2>/dev/null
      _UE_RX_N='"tool_name"[[:space:]]*:[[:space:]]*"Write"'
      # unverified assumption: Claude Code writes `type` as the FIRST key of a Write tool_response; if that order changes this regex misses
      # "update" and an overwrite of an untracked file reads as a create (silent: fails safe; tests/gates/test_untracked_edit_warning.sh pins today's shape)
      _UE_RX_U='"tool_response"[[:space:]]*:[[:space:]]*\{[[:space:]]*"type"[[:space:]]*:[[:space:]]*"update"'
      _UE_OWN=0   # a Write whose answer is not "update" created the file: this session's own
      if [[ ${_UE_HEAD} =~ ${_UE_RX_N} ]]; then
        LC_ALL=C; [[ ${INPUT} =~ ${_UE_RX_U} ]] || _UE_OWN=1; _ue_lc_restore
      fi
      if [ "${_UE_OWN}" = 1 ]; then
        { echo "[$(date +%Y-%m-%dT%H:%M:%S)] UNTRACKED ${_UE_P}: created by this session's Write — own file, no warning" >> "${LOG_DIR}/churn_guard.log"; } 2>/dev/null
      else
        { echo "[$(date +%Y-%m-%dT%H:%M:%S)] WARN — UNTRACKED ${_UE_P}: edited, but the git index does not hold it" >> "${LOG_DIR}/churn_guard.log"; } 2>/dev/null
        printf '%s\n' \
          "⚠️ COMMIT-CLOSURE: ${_UE_B} là file UNTRACKED — index git không có nó (HEAD cũng chưa), nên sửa này KHÔNG commit riêng được:" \
          "   commit các path đã sửa (hoặc \`git archive HEAD\`, CI checkout) thiếu file này và code gọi tới nó sẽ không build." \
          "   Nếu là file của bạn: \`git add\` nó vào CÙNG commit với phần sửa. Nếu không phải bạn tạo (phiên/refactor khác để lại): hỏi chủ của nó," \
          "   hoặc sửa trên bản HEAD đang có. Kiểm đủ: \`git archive HEAD\` + chồng các path sắp commit lên rồi biên dịch (bản đầy đủ, chưa tự động)." \
          "   Cảnh báo một lần cho mỗi file mỗi phiên; không chặn. Tắt: UNTRACKED_EDIT_WARN=0." >&2
        _UE_RC=2
      fi
    fi
  fi
fi

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ churn_guard: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit "${_UE_RC}"
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
          exit "${_UE_RC}"
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
exit "${_UE_RC}"
