#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# comment_claim_guard.sh — PostToolUse hook: apply Rule 5 to COMMENTS/KDoc.
#
# CLAUDE.md: the no-fabrication gates apply to every text emitted, including code
# comments — and comments are where claims slip the gate most easily, because
# writing one feels like "writing code" rather than "making a statement".
# claim_check.sh only scans the final chat message, so comments had zero coverage.
# Measured 2026-07-27: three false claims reached KDoc/comments (an ungrepped
# negative claim, a wrong "covered by that other test", a runtime mechanism that
# does not exist) plus one wrong line reference.
#
# SCOPE: scans ONLY the text just written (Edit.new_string / Write.content), only
# its comment lines, in //-comment languages of the active profile (devkit_profile.py), and full-line # comments in .py / .rb
# of the active profile and in .sh / .bash / .zsh / .yaml / .yml (2026-10-09). Never re-scans the whole file, so
# pre-existing comments do not fire on every edit.
#
# THREE FAMILIES ONLY (precision > recall, same policy as claim_check):
#   1. line reference inside a comment      → C1, must come from graph/source
#   2. "đã test / covered by / verified in" → C5-outcome, needs real evidence
#   3. "không dùng / not used / never called / không ảnh hưởng" → C4, needs a search
#
# WARN (exit 2 → stderr to Claude). Never blocks the edit — it already happened.
# Comments are often legitimately descriptive; this asks for evidence or softer
# wording, it does not forbid comments.
#
# WHAT IT CANNOT DO: judge whether a claim is TRUE. A grepped, correct negative
# claim trips it exactly like an invented one — answer by citing the evidence.
#
# Escape hatch: COMMENT_CLAIM_GUARD=0 (logged). Fail-open on internal error.
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

if [ "${COMMENT_CLAIM_GUARD:-1}" = "0" ]; then
  [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] COMMENT_CLAIM_GUARD=0 — gate bypassed" >> "${LOG_DIR}/comment_claim_guard.log" 2>/dev/null
  exit 0
fi

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ comment_claim_guard: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
# Fast path (2026-10-09, decision-neutral; tests/gates/test_edit_hook_fast_path.sh): python below acts only on a
# tool_input.file_path whose extension is in devkit_profile.SLASH_COMMENT_EXTS or the # languages below (every profile
# picks from these). When no file_path value in the payload ends in one, and none holds a JSON escape that could spell one
# (A\u002ekt), python would exit 0 without a word: skip its start (~30 ms a call). Keep the list in sync (ratchet).
CC_EXT='\.(kt|kts|java|swift|m|mm|ts|tsx|js|jsx|mjs|cjs|go|rs|php|cs|dart|c|cc|cpp|h|hpp|scala|py|rb|sh|bash|zsh|yaml|yml)"'
_RX_HIT='"(file_path)"[[:space:]]*:[[:space:]]*"[^"\\]*'"${CC_EXT}"
_RX_ESC='"(file_path)"[[:space:]]*:[[:space:]]*"[^"\\]*\\'
# Under 128 KiB only: a regex over 1 MB costs ~25 ms in a UTF-8 locale, more than the python start it saves.
if [ "${#INPUT}" -lt 131072 ]; then
  [[ ${INPUT} =~ ${_RX_HIT} ]] || [[ ${INPUT} =~ ${_RX_ESC} ]] || exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable python could not
# start and a claim comment in a big file passed (tests/gates/test_hook_large_payload.sh).
CC_LOG="${LOG_DIR:+${LOG_DIR}/comment_claim_guard.log}" \
CC_TS="$(date +%Y-%m-%dT%H:%M:%S)" CCG_HOOKDIR="$(cd "$(dirname "$0")" && pwd)" CCG_REPO="${REPO_ROOT}" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, sys, json, re

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
log = os.environ.get("CC_LOG", "/dev/null")
ts  = os.environ.get("CC_TS", "?")
repo = os.environ.get("CCG_REPO", ".")

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

inp = d.get("tool_input") or {}
if not isinstance(inp, dict):
    sys.exit(0)
path = inp.get("file_path") or ""
# #-comment languages (2026-10-09, tests/gates/test_comment_claim_hash.sh): Python, the backend profile's main language,
# was never checked. .py / .rb follow the active profile like the // languages; shell and YAML are in every project.
HASH_SOURCE_EXTS = (".py", ".rb")
HASH_SCRIPT_EXTS = (".sh", ".bash", ".zsh", ".yaml", ".yml")
try:
    sys.dont_write_bytecode = True  # no __pycache__ inside the project's .claude/hooks
    sys.path.insert(0, os.environ.get("CCG_HOOKDIR", ""))
    from devkit_profile import SLASH_COMMENT_EXTS, source_exts
    _src = source_exts(repo)
    exts = tuple(e for e in _src if e in SLASH_COMMENT_EXTS)
    hash_exts = tuple(e for e in _src if e in HASH_SOURCE_EXTS) + HASH_SCRIPT_EXTS
except Exception:
    exts = (".kt", ".java", ".kts")
    hash_exts = HASH_SOURCE_EXTS + HASH_SCRIPT_EXTS
if not isinstance(path, str) or not path.endswith(exts + hash_exts):
    sys.exit(0)
hash_lang = path.endswith(hash_exts) and not path.endswith(exts)

# Only the text written by THIS call.
written = inp.get("new_string")
if not isinstance(written, str):
    written = inp.get("content")
if not isinstance(written, str) or not written.strip():
    sys.exit(0)

# Comment lines only: //, ///, /*, *, */ — plus KDoc bodies. In a #-comment language: full-line # comments, without a
# shebang, a `-*- coding` / `coding:` line and tool markers (`type:`, `noqa`, `pragma:`, `pylint:`, `shellcheck disable`).
COMMENT_RE = re.compile(r"^\s*(?://+|/\*+|\*+/?)\s?(.*)$")
HASH_RE = re.compile(r"^\s*#+\s?(.*)$")
HASH_MARKER = re.compile(r"^(?:-\*-|(?:type|pragma|pylint|mypy|pyright|fmt|isort|ruff|flake8|vim?|ex|frozen_string_literal"
                         r"|yaml-language-server|rubocop)\s*:|(?:en)?coding\s*[:=]|noqa\b|nosec\b"
                         r"|shellcheck\s+(?:disable|enable|source|shell)\b|noinspection\b)", re.I)
# Also read (2026-10-09 follow-up, tests/gates/test_comment_claim_docstring_trailing.sh): the body of a Python docstring (a string
# statement that starts a line with triple quotes; an ASSIGNED triple-quoted string is data) and a comment after code on the same
# line (a # or // outside any string literal).
DOCSTR_RE = re.compile(r"^\s*[rRuUbB]{0,2}(\"\"\"|\x27\x27\x27)(.*)$")

def trailing_comment(ln, hash_lang):
    """The text of a comment that follows code on the same line, or None."""
    q, i, n = None, 0, len(ln)
    while i < n:
        c = ln[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"\x27`":
            q = c
        elif hash_lang and c == "#" and i > 0 and ln[i - 1] in " \t":
            return ln[i + 1:]
        elif not hash_lang and c == "/" and ln.startswith("//", i) and (i == 0 or ln[i - 1] != ":"):
            return ln[i + 2:]
        i += 1
    return None

comment_lines = []
is_py, doc, data = path.endswith(".py"), None, None   # doc: closing triple quote of the docstring being read; data: of an ASSIGNED string
for i, ln in enumerate(written.split("\n"), 1):
    if hash_lang:
        if is_py:
            if doc:
                end = ln.find(doc)
                body = (ln if end < 0 else ln[:end]).strip()
                if body:
                    comment_lines.append((i, body))
                if end >= 0:
                    doc = None
                continue
            if data:   # inside an assigned triple-quoted string: its lines are data; the rest of its closing line is code
                if data not in ln:
                    continue
                ln = ln[ln.index(data) + 3:]
                data = None
            dm = DOCSTR_RE.match(ln)
            if dm:
                rest = dm.group(2)
                end = rest.find(dm.group(1))
                body = (rest if end < 0 else rest[:end]).strip()
                if body:
                    comment_lines.append((i, body))
                if end < 0:
                    doc = dm.group(1)
                continue
        m = HASH_RE.match(ln)
        if m:
            if not ln.lstrip().startswith("#!") and not HASH_MARKER.match(m.group(1)):
                body = m.group(1).strip()
                if body:
                    comment_lines.append((i, body))
            continue
        tail = trailing_comment(ln, True)
        if tail is not None and not HASH_MARKER.match(tail.strip()):
            body = tail.strip()
            if body:
                comment_lines.append((i, body))
        if is_py:   # an odd number of triple quotes in the CODE part (not in a comment) opens an assigned string
            code = ln if tail is None else ln[:len(ln) - len(tail) - 1]
            data = next((q for q in ("\"\"\"", "\x27\x27\x27") if code.count(q) % 2 == 1), None)
        continue
    m = COMMENT_RE.match(ln)
    if m:
        body = re.sub(r"\*+/\s*$", "", m.group(1)).strip()
        if body:
            comment_lines.append((i, body))
        continue
    tail = trailing_comment(ln, False)
    if tail is not None:
        body = tail.strip()
        if body:
            comment_lines.append((i, body))
if not comment_lines:
    sys.exit(0)

FAMILIES = [
    ("C1 line-ref",
     re.compile(r"\b[A-Za-z0-9_]+\.(?:kt|java|kts|xml)\s*:\s*\d+", re.I),
     "line reference trong comment — phải cite từ graph/source, và số dòng sẽ lệch ngay khi file đổi"),
    ("C5 đã-test",
     re.compile(r"(?:đã\s+(?:được\s+)?(?:test|kiểm\s*tra|verify|verified)"
                r"|covered\s+by|tested\s+in|verified\s+in|already\s+tested)", re.I),
     "claim 'đã được test ở chỗ khác' — cần evidence thật, đây là ca đã lọt 2026-07-27"),
    ("C4 negative",
     re.compile(r"(?:kh[ôo]ng\s+(?:bao\s+giờ\s+)?(?:d[ùu]ng|g[ọo]i|đ[ưu]ợc\s+g[ọo]i|ảnh\s+hưởng)"
                r"|never\s+(?:called|used|invoked)"
                r"|not\s+used\s+(?:any\s*where|elsewhere)"
                r"|no\s+(?:other\s+)?(?:caller|consumer)s?\b"
                r"|only\s+(?:used|called)\s+(?:by|from|in))", re.I),
     "negative/scope claim — phải search TRƯỚC và nêu phạm vi đã search"),
]

hits = []
for lineno, text in comment_lines:
    for fam, pat, why in FAMILIES:
        m = pat.search(text)
        if m:
            hits.append((fam, lineno, text[:90], why))
            break

if not hits:
    logline(f"[{ts}] {os.path.basename(path)}: {len(comment_lines)} comment line, sạch — pass")
    sys.exit(0)

logline(f"[{ts}] WARN — {os.path.basename(path)}: {len(hits)} comment claim "
        f"({', '.join(sorted({h[0] for h in hits}))})")

out = [f"⚠️ COMMENT-CLAIM (CLAUDE.md Rule 5 áp cho CẢ comment/KDoc): "
       f"{os.path.basename(path)}", ""]
for fam, lineno, text, why in hits[:8]:
    out.append(f"  [{fam}] dòng +{lineno} của đoạn vừa ghi:")
    out.append(f"     \"{text}\"")
    out.append(f"     → {why}")
if len(hits) > 8:
    out.append(f"  … +{len(hits)-8} chỗ nữa")
out += [
    "",
    "  Comment sai nguy hơn reply sai: nó ở lại trong code và người sau đọc nó như fact.",
    "  Chọn 1: (a) cite evidence đã có ngay trong comment, (b) đi verify rồi giữ nguyên,",
    "  hoặc (c) viết lại thành mô tả hành vi thay vì khẳng định về phần code khác.",
]
sys.stderr.write("\n".join(out) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
