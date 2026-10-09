#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# read_ledger.sh — PostToolUse hook on Read. Records "this session looked at
# <file>" the instant it happens.
#
# WHY THIS EXISTS. precode_gate.sh answers "has this session looked at the file
# I am about to edit?" by scanning the session transcript. That answer is only
# as fresh as the transcript on disk, and the transcript is flushed in batches:
# tool calls made during the CURRENTLY RUNNING turn are still buffered and
# appear nowhere on disk. Measured 2026-08-04: the string
# "CrossScreenExtendedTest.kt" appeared 0 times across all 18 transcript files
# in this project directory while an Edit of that very file was being blocked,
# moments after it had been Read. The failure mode is systematic, not a race —
# every .kt/.java file first touched inside a long turn is unreachable, which is
# exactly the Read-then-Edit sequence W0 box 2 asks for. A gate that fires
# hardest on correct behaviour teaches people to reach for PRECODE_GATE=0.
#
# The fix is to stop depending on flush timing: this hook writes the fact down
# synchronously, and precode_gate consults the ledger alongside the transcript.
# It does NOT relax the gate — a file that was genuinely never read appears in
# neither source and is still blocked.
#
# ONLY Read is recorded. Recording Edit/Write here would re-introduce the
# self-disarming bug documented in precode_gate.sh: a blind edit ATTEMPT would
# mark the file as seen and clear the way for its own retry.
#
# Always exits 0. A PostToolUse hook runs after the edit has already happened,
# so it can only ever report — never block — and a bug in bookkeeping must not
# interrupt work.
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
  [ -d "${LOG_DIR}" ] || mkdir -p "${LOG_DIR}" 2>/dev/null || true
  [ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
fi

if [ "${READ_LEDGER:-1}" = "0" ]; then
  [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] READ_LEDGER=0 — gate bypassed" >> "${LOG_DIR}/read_ledger.log" 2>/dev/null
  exit 0
fi
[ -n "${LOG_DIR}" ] || exit 0   # no project: no ledger to write (precode_gate then reads the transcript only)

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ read_ledger: python3 không có — không ghi được sổ Read (precode_gate sẽ chặn nhiều hơn)." >&2
  exit 0
fi

# Fast path (2026-10-09, decision-neutral; tests/gates/test_edit_hook_fast_path.sh): python below acts only on a read
# path (file_path / notebook_path / target_file) whose extension is in SRC_EXT. When no such value in the payload ends in
# one, and none holds a JSON escape that could spell one (A\u002ekt), python would exit 0 without a word: skip its start
# (~30 ms a call). Keep the list in sync (ratchet).
RL_SRC='\.(kt|kts|java|swift|ts|tsx|js|jsx|mjs|py|go|rs|dart|cs|c|cc|cpp|h|hpp|m|mm)"'
_RX_HIT='"(file_path|notebook_path|target_file)"[[:space:]]*:[[:space:]]*"[^"\\]*'"${RL_SRC}"
_RX_ESC='"(file_path|notebook_path|target_file)"[[:space:]]*:[[:space:]]*"[^"\\]*\\'
# Under 128 KiB only: a regex over 1 MB costs ~25 ms in a UTF-8 locale, more than the python start it saves.
if [ "${#INPUT}" -lt 131072 ]; then
  [[ ${INPUT} =~ ${_RX_HIT} ]] || [[ ${INPUT} =~ ${_RX_ESC} ]] || exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): a Read of a big file (> 128 KiB on Linux, ~1 MiB on
# macOS) could not start python, the read never reached the ledger and precode_gate blocked the edit of the file just read.
RL_LEDGER="${LOG_DIR}/read_ledger.tsv" RL_REPO="${REPO_ROOT}" python3 -I <<'PY' 3<<<"${INPUT}" 2>/dev/null || true
import os, sys, json

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
ledger = os.environ.get("RL_LEDGER", "")

try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)
if not isinstance(d, dict) or not ledger:
    sys.exit(0)

inp = d.get("tool_input") or d.get("toolInput")   # toolInput: the camelCase envelope (Grok), as precode_gate reads it
if not isinstance(inp, dict):
    sys.exit(0)

# file_path is Claude Code's Read/Edit key. target_file is Grok's read_file key.
# Same read event; without this fallback a read never reaches the ledger and
# precode_gate blocks the edit of a file that was just opened.
path = inp.get("file_path") or inp.get("notebook_path") or inp.get("target_file") or ""
if not isinstance(path, str) or not path:
    sys.exit(0)

# Only source files matter here; precode_gate ignores everything else anyway.
# Keep in sync with SRC_EXT in precode_gate.sh.
SRC_EXT = (".kt", ".kts", ".java", ".swift", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py",
           ".go", ".rs", ".dart", ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm")
if not path.endswith(SRC_EXT):
    sys.exit(0)

session = d.get("session_id") or ""
if not isinstance(session, str):
    session = ""

# Resolved absolute path (QA K-9): a basename cannot tell a/Util.kt from b/Util.kt.
repo = os.environ.get("RL_REPO", "") or os.getcwd()
full = os.path.realpath(path if os.path.isabs(path) else os.path.join(repo, path))
if "\t" in full or "\n" in full:
    sys.exit(0)

try:
    with open(ledger, "a") as fh:
        fh.write(f"{session}\t{full}\n")
except Exception:
    sys.exit(0)

# Bound the file so a long-lived project cannot grow it without limit. The tail
# is what matters: entries are only ever consulted for the CURRENT session. The
# size is checked first, so a Read does not re-read the whole ledger every time
# (512 KB ≈ 4000–6000 entries of a session id and an absolute path).
try:
    if os.path.getsize(ledger) > 512 * 1024:
        with open(ledger) as fh:
            lines = fh.readlines()
        with open(ledger, "w") as fh:
            fh.writelines(lines[-2500:])
except Exception:
    pass
PY

exit 0
