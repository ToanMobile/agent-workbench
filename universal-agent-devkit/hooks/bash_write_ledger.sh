#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bash_write_ledger.sh — PreToolUse + PostToolUse hook on Bash. Records the time
# WINDOW each Bash command occupied, so a Stop gate can ask "was this file written
# while THIS session was running a command?".
#
# WHY. A file written by a shell command (heredoc, `find | xargs sed -i`, a script,
# codegen, `git apply`) appears in no Edit/Write tool_use, and often its path never
# appears in the transcript at all. testsourceset_gate (and test_evidence_gate's
# session attribution) read these windows to attribute such writes to the session
# that made them: a dirty file whose mtime falls inside one of MY windows was written
# while I was running. Ported from the OfficeReader hook this DevKit hook was derived
# from, where it was wired on PreToolUse:Bash + PostToolUse:Bash; losing the wiring
# silently disabled that attribution.
#
# FORMAT (consumers depend on it byte for byte — do not change):
#   file  ${REPO_ROOT}/.claude/audit-gate/bash_write_ledger.tsv   (shared, all sessions)
#   row   <session_id>\t<start|end>\t<epoch seconds, 3 decimals>\t<tool_use_id>\n
#   PreToolUse → `start`; PostToolUse → `end`, EXCEPT when tool_input.run_in_background
#   is true: a backgrounded command has not finished writing when Post fires, so it
#   gets NO `end` and its window stays open until Stop. Pair rows on
#   (session_id, tool_use_id). The file is trimmed to its last 4000 rows once it is
#   past 300 KB and 8000 rows.
#
# WINDOWS ARE LONG (measured on OfficeReader: p50 1.76s, p90 16.57s, max 391.6s),
# so a consumer that finds an mtime inside windows of several sessions must pick the
# NARROWEST, and attribute an exact tie to nobody.
#
# NO COMMAND TEXT is recorded — only ids and timestamps — so no secret can leak here.
# This is a separate ledger from read_ledger.tsv on purpose: precode_gate must never
# treat a write as a read (a blind edit would clear the way for its own retry).
#
# COST. This runs in front of EVERY Bash call, so it does no JSON library load: the
# five fields are matched with bash regexes on the raw payload. That is sound for
# JSON: inside a string value every `"` is escaped (`\"`), so `"tool_name"<ws>:`
# can only match a real key, never text inside tool_input.command. The timestamp
# comes from $EPOCHREALTIME (bash ≥ 5), else one perl call, else python3, else
# `date +%s` (".000"). Measured: median 14 ms (Pre) / 12 ms (Post) on macOS bash 3.2.
#
# Always exits 0 (a bookkeeping bug must never block the user's command); every
# failure is swallowed. Escape hatch: BASH_WRITE_LEDGER=0. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

# Drain stdin before any early exit, otherwise the caller gets EPIPE.
INPUT="$(cat 2>/dev/null)" || INPUT=""

[ "${BASH_WRITE_LEDGER:-1}" = "0" ] && exit 0

# Only Bash opens a window. Every other tool records its own path in the transcript
# or writes nothing; a window for it would mark every dirty file as ours.
RX_TOOL='"tool_name"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_TOOL} ]] || exit 0
[ "${BASH_REMATCH[1]}" = "Bash" ] || exit 0

RX_EVENT='"hook_event_name"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_EVENT} ]] || exit 0
case "${BASH_REMATCH[1]}" in
  PreToolUse)  KIND="start" ;;
  PostToolUse)
    KIND="end"
    RX_BG='"run_in_background"[[:space:]]*:[[:space:]]*true'
    [[ ${INPUT} =~ ${RX_BG} ]] && exit 0 ;;
  *) exit 0 ;;
esac

SESSION=""
RX_SID='"session_id"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_SID} ]] && SESSION="${BASH_REMATCH[1]}"
TUID=""
RX_TUID='"tool_use_id"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_TUID} ]] && TUID="${BASH_REMATCH[1]}"

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
[ -d "${LOG_DIR}" ] || mkdir -p "${LOG_DIR}" 2>/dev/null || exit 0
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LEDGER="${LOG_DIR}/bash_write_ledger.tsv"

# Timestamp with 3 decimals, plus the ledger size (for the trim) when perl is used.
STAMP=""; SIZE=""
if [ -n "${EPOCHREALTIME:-}" ]; then
  _t="${EPOCHREALTIME/,/.}"                       # some locales use a comma
  _frac="${_t#*.}000"
  STAMP="${_t%%.*}.${_frac:0:3}"
elif command -v perl >/dev/null 2>&1; then
  _out="$(perl -MTime::HiRes=time -e 'printf "%.3f %d", time, (-s $ARGV[0]) || 0' "${LEDGER}" 2>/dev/null)"
  STAMP="${_out%% *}"; SIZE="${_out##* }"
fi
case "${STAMP}" in
  *[0-9].[0-9][0-9][0-9]) ;;
  *) STAMP="$(python3 -S -c 'import time; print("%.3f" % time.time())' 2>/dev/null)"
     case "${STAMP}" in *[0-9].[0-9][0-9][0-9]) ;; *) STAMP="$(date +%s).000" ;; esac ;;
esac

printf '%s\t%s\t%s\t%s\n' "${SESSION}" "${KIND}" "${STAMP}" "${TUID}" >> "${LEDGER}" 2>/dev/null || exit 0

# Bound the file: only recent windows are ever consulted, so the tail is what matters.
case "${SIZE}" in ''|*[!0-9]*) SIZE="$(wc -c < "${LEDGER}" 2>/dev/null | tr -d ' ')" ;; esac
if [ -n "${SIZE}" ] && [ "${SIZE}" -gt 300000 ] 2>/dev/null; then
  _lines="$(wc -l < "${LEDGER}" 2>/dev/null | tr -d ' ')"
  if [ -n "${_lines}" ] && [ "${_lines}" -gt 8000 ] 2>/dev/null; then
    _tmp="${LEDGER}.trim.$$"
    tail -n 4000 "${LEDGER}" > "${_tmp}" 2>/dev/null && mv -f "${_tmp}" "${LEDGER}" 2>/dev/null
    rm -f "${_tmp}" 2>/dev/null
  fi
fi
exit 0
