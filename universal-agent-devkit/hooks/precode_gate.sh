#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# precode_gate.sh — PreToolUse hook: the only gate that runs BEFORE code is written.
#
# Everything else in this repo fires after the edit (PostToolUse) or at the end
# of the turn (Stop), so W0 — the pre-code gate — had zero enforcement: all five
# of its boxes were prose only.
#
# BLOCK (exit 2) when: about to Edit/Write a source file (.kt/.java/.swift/.ts/
# .tsx/.js/.jsx/.py/.go/.rs/.dart/.cs/.c/.cc/.cpp/.h/.m/.mm) that this session has
# never looked at — no Read of it, no Edit of it, and its name never appeared in
# any tool output (Grep hit, graph result, gradle/logcat line). That is editing
# blind, the crudest form of skipping W0 box 2.
#
# "Has this session looked at it?" is answered from TWO sources, in this order:
#   1. the read ledger written by read_ledger.sh (PostToolUse on Read) — the only
#      source that can see the turn currently running;
#   2. the session transcript — covers earlier turns, and also counts a name that
#      merely surfaced in tool output.
# Source 1 exists because the transcript is flushed in batches: without it, every
# file first Read inside a long turn was blocked on its very first Edit. See the
# header of read_ledger.sh for the measurement.
#
# WHAT IT CANNOT DO: judge whether you UNDERSTAND the failure mechanism (W0 box
# 4). No machine can. It only blocks touching a file you have not once looked at.
#
# ALLOWED without any prior look:
#   • creating a genuinely new file (nothing on disk to read)
#   • a file already edited earlier this session (you have engaged with it)
#   • anything that is not a source file (see SRC_EXT)
#
# Paths are compared as resolved absolute paths (QA K-9, 2026-09-23): reading
# a/Util.kt no longer unlocks b/Util.kt. A tool_result only counts when it shows
# the file's absolute or repo-relative path, not just its basename.
#
# Escape hatch: PRECODE_GATE=0 (logged to precode_gate.log). Fail-open on any
# internal error — a bug in this gate must never stop work. Missing python3 is
# NOT an internal error: it fails closed (exit 2), see below.
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

if [ "${PRECODE_GATE:-1}" = "0" ]; then
  [ -n "${LOG_DIR}" ] && echo "[$(date +%Y-%m-%dT%H:%M:%S)] PRECODE_GATE=0 — gate bypassed" >> "${LOG_DIR}/precode_gate.log" 2>/dev/null
  exit 0
fi

# QA K-4: without python3 this gate cannot judge anything. Fail CLOSED (it guards
# an attack surface / blind edits) — except on the Stop loop-guard pass, so a box
# without python3 is never wedged. Disable with PRECODE_GATE=0.
if ! command -v python3 >/dev/null 2>&1; then
  case "${INPUT}" in
    *'"stop_hook_active":true'*|*'"stop_hook_active": true'*)
      echo "⚠ precode_gate: python3 không có — gate KHÔNG chạy (lần Stop thứ 2, thả để tránh treo)." >&2; exit 0 ;;
  esac
  echo "🛑 precode_gate: cần python3 để kiểm tra — chặn để an toàn. Cài python3 hoặc đặt PRECODE_GATE=0 để tắt gate." >&2
  exit 2
fi
# Fast path (2026-10-09, decision-neutral; tests/gates/test_edit_hook_fast_path.sh): python below acts only on a
# tool_input.file_path whose extension is in SRC_EXT. When no file_path value in the payload ends in one, and none holds a
# JSON escape that could spell one (A\u002ekt), python would exit 0 without a word: skip its start (~30 ms a call). Keep
# the list in sync (ratchet).
PG_SRC='\.(kt|kts|java|swift|ts|tsx|js|jsx|mjs|py|go|rs|dart|cs|c|cc|cpp|h|hpp|m|mm)"'
_RX_HIT='"(file_path)"[[:space:]]*:[[:space:]]*"[^"\\]*'"${PG_SRC}"
_RX_ESC='"(file_path)"[[:space:]]*:[[:space:]]*"[^"\\]*\\'
# Under 128 KiB only: a regex over 1 MB costs ~25 ms in a UTF-8 locale, more than the python start it saves.
if [ "${#INPUT}" -lt 131072 ]; then
  [[ ${INPUT} =~ ${_RX_HIT} ]] || [[ ${INPUT} =~ ${_RX_ESC} ]] || exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable (Linux 128 KiB,
# macOS ~1 MiB for args + env) python could not start and a blind Write of a big file passed (tests/gates/test_hook_large_payload.sh).
PG_LOG="${LOG_DIR:+${LOG_DIR}/precode_gate.log}" \
PG_LEDGER="${LOG_DIR:+${LOG_DIR}/read_ledger.tsv}" PG_REPO="${REPO_ROOT}" \
PG_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, subprocess, sys, json

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
log = os.environ.get("PG_LOG", "/dev/null")
ts  = os.environ.get("PG_TS", "?")

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

inp = d.get("tool_input") or d.get("toolInput") or {}   # toolInput: the camelCase envelope (Grok), 2026-10-09
if not isinstance(inp, dict):
    sys.exit(0)
SRC_EXT = (".kt", ".kts", ".java", ".swift", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py",
           ".go", ".rs", ".dart", ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm")
path = inp.get("file_path") or ""
if not isinstance(path, str) or not path.endswith(SRC_EXT):
    sys.exit(0)

base = os.path.basename(path)
repo = os.environ.get("PG_REPO", "") or os.getcwd()

def norm(p):
    if not os.path.isabs(p):
        p = os.path.join(repo, p)
    return os.path.realpath(p)

target = norm(path)
try:
    rel = os.path.relpath(target, os.path.realpath(repo))
except ValueError:
    rel = target
if rel.startswith(".."):
    rel = target

# Creating a genuinely new file: nothing exists to have read.
if not os.path.exists(path):
    logline(f"[{ts}] {base}: file mới — pass")
    # The session writes the whole file, so its later edits are not blind: note it in the read
    # ledger (OfficeReader 2026-09-28: Grok created a .kt, and its next edit of it was blocked
    # because only a Read reached the ledger). A path that already exists never gets here.
    _led, _sid = os.environ.get("PG_LEDGER", ""), d.get("session_id") or ""
    if _led and isinstance(_sid, str) and _sid and "\t" not in target and "\n" not in target:
        try:
            with open(_led, "a") as fh:
                fh.write(f"{_sid}\t{target}\n")
        except OSError as e:
            logline(f"[{ts}] ledger write fail: {e!r}")
    sys.exit(0)

looked = False

# ── Source 1: the read ledger (read_ledger.sh, PostToolUse on Read) ──────────
# Checked BEFORE the transcript because it is the only source that can see the
# turn currently running. The transcript is flushed in batches, so a Read made
# moments ago during this same turn is still buffered and invisible on disk —
# measured 2026-08-04, when an Edit was blocked while the file's name appeared
# 0 times across every transcript file in the project. Consulting the ledger
# does not widen what counts as "looked at": it is written only by Read, and a
# file that was never read appears in neither source and is still blocked.
ledger = os.environ.get("PG_LEDGER", "")
session = d.get("session_id") or ""
if ledger and os.path.exists(ledger):
    try:
        with open(ledger) as fh:
            for entry in fh:
                sid, _, fp = entry.rstrip("\n").partition("\t")
                # Legacy basename-only entries are ignored: they cannot tell
                # a/Util.kt from b/Util.kt.
                if sid == session and os.path.isabs(fp) and os.path.realpath(fp) == target:
                    looked = True
                    break
    except Exception as e:
        logline(f"[{ts}] ledger scan fail: {e!r} — falling through to transcript")

if looked:
    logline(f"[{ts}] {base}: đã Read trong phiên (ledger) — pass")
    sys.exit(0)

tp = d.get("transcript_path")
if not tp or not os.path.exists(tp):
    logline(f"[{ts}] transcript unreadable — fail-open")
    sys.exit(0)
# A line can match only if it holds a Read call (whose path may be a symlink
# alias) or the file's name (every path/rel/target below ends in one of these
# two basenames), so any other line is skipped before json.loads — the parse
# was most of this hook's cost on a long session.
needles = {'"Read"'}
for b in (base, os.path.basename(target)):
    needles.update((b, json.dumps(b)[1:-1]))
try:
    with open(tp) as fh:
        for rawline in fh:
            if not any(n in rawline for n in needles):
                continue
            rawline = rawline.strip()
            if not rawline:
                continue
            try:
                rec = json.loads(rawline)
            except Exception:
                continue
            content = (rec.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for blk in content:
                if not isinstance(blk, dict):
                    continue
                t = blk.get("type")
                if t == "tool_use":
                    # ONLY a Read counts as "looked at". Counting Edit/Write here
                    # was a self-disarming bug (measured 2026-07-27): a blind Edit
                    # ATTEMPT — even one that errored with "string not found" —
                    # marked the file as seen, so the gate could never block the
                    # retry. The action the gate exists to stop was disarming it.
                    # A legitimate prior edit needs no special case: the harness
                    # requires a Read before Edit, so that Read is in the transcript.
                    if blk.get("name") != "Read":
                        continue
                    binp = blk.get("input") or {}
                    fp = binp.get("file_path") or binp.get("notebook_path") or ""
                    if isinstance(fp, str) and fp and norm(fp) == target:
                        looked = True
                elif t == "tool_result":
                    c = blk.get("content")
                    text = c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)
                    if target in text or path in text or (rel != target and rel in text):
                        looked = True          # surfaced in grep/graph/gradle/logcat output
            if looked:
                break
except Exception as e:
    logline(f"[{ts}] transcript scan fail: {e!r} — fail-open")
    sys.exit(0)

if looked:
    logline(f"[{ts}] {base}: đã xem trong phiên — pass")
    sys.exit(0)

# Born inside one of THIS session's Bash windows (bash_write_ledger.tsv; the narrowest window
# holding the birth wins, as hooks/bash_write_ledger.sh prescribes): the session created the file
# with a shell command whose path no ledger resolves — `cat > "$FR/X.kt" <<EOF` (OfficeReader
# 2026-09-26). A file born in another session's window, or in none, is still blind.
def born_in_my_window():
    sid = str(d.get("session_id") or "")
    try:
        st = os.stat(path)
        t = getattr(st, "st_birthtime", None) or st.st_mtime
        rows = open(os.path.join(os.environ.get("PG_REPO", "."), ".claude", "audit-gate", "bash_write_ledger.tsv"),
                    encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return False
    win = {}
    for r in rows:
        f = r.split("\t")
        if len(f) == 4 and f[1] in ("start", "end"):
            try:
                win.setdefault((f[0], f[3]), {})[f[1]] = float(f[2])
            except ValueError:
                pass
    best = None
    for (s_id, _tid), w in win.items():
        a, b = w.get("start"), w.get("end")
        if a is None or b is None:
            continue   # a window still open (a backgrounded command) proves nothing about who wrote
        if a - 0.005 <= t <= b + 0.005 and (best is None or b - a < best[0]):   # ledger: 3 decimals
            best = (b - a, s_id)
    if not (sid and best is not None and best[1] == sid):
        return False
    # A tracked file was (re)written by git (pull, checkout, stash pop), not typed by the session.
    tracked = subprocess.run(["git", "-C", os.path.dirname(path) or ".", "ls-files", "--error-unmatch", "--", path],
                             capture_output=True)
    return tracked.returncode != 0

if born_in_my_window():
    logline(f"[{ts}] {base}: phiên này tạo file bằng lệnh shell — pass")
    sys.exit(0)

logline(f"[{ts}] BLOCK — {base}: sửa file chưa từng xem trong phiên")
sys.stderr.write(
    f"⛔ PRE-CODE GATE (CLAUDE.md W0 ô 2): sắp sửa {base} mà phiên này CHƯA HỀ xem nó.\n"
    f"   Không có Read, không có Edit, tên file cũng chưa xuất hiện trong bất kỳ tool output nào\n"
    f"   (grep / graph / gradle / logcat). Đây là sửa mù.\n"
    f"\n"
    f"   Trước khi sửa, điền W0:\n"
    f"     ô 2 — Read đúng vùng sẽ sửa (file dirty thì Read, đừng tin graph)\n"
    f"     ô 3 — nếu đụng signature/base member/public API: liệt kê consumer, GỒM src/test\n"
    f"     ô 4 — failure mechanism + cách chứng minh fix đổi observable behavior\n"
    f"\n"
    f"   Gate này chỉ chặn được 'chưa từng xem'; nó KHÔNG kiểm được bạn có hiểu bug hay không.\n"
    f"   Tạo file mới thì không bị chặn. Escape hatch có chủ đích: PRECODE_GATE=0.\n"
)
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
