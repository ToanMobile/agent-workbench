#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# proof_gate.sh — Stop hook: a reply that opens with XONG must carry the turn's
# acceptance image (rules/essentials.md "Every prompt", step 4/5).
#
# Only the status line decides: first non-empty line of the reply, markdown
# stripped. "XONG" → checked; "CHƯA XONG", "CHỜ DUYỆT", anything else → allowed.
# Checked = both halves of step 5, from this turn:
#   - .git/postfix-gate/full_pass.json, written by `post-fix-gate --run-tests --full` on
#     exit 0, newer than the turn's user message, whose fingerprint (bin/tree_fp.py) still
#     matches the code — an edit after the gate run voids it;
#   - the reply names at least one reports/proof-<yyyyMMdd-HHmmss>.png that
#   - exists under the project,
#   - starts with the PNG signature,
#   - is larger than 8 KB (PROOF_MIN_BYTES),
#   - was modified after the turn's user message (transcript timestamp).
# The hook never takes the screenshot; it only refuses an XONG without one.
#
# Loop guard: PROOF_GATE_MAX_BLOCKS (default 2) blocks per session, then the stop
# goes through with a user-visible systemMessage. Escape hatch: PROOF_GATE=0
# (logged). Fail-open on internal error. Claude Code only (reads the transcript).
#
# Stop hook protocol: stdin JSON; exit 2 blocks (stderr → Claude); exit 0 allows.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}" 2>/dev/null
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

INPUT="$(cat)"
if [ "${PROOF_GATE:-1}" = "0" ]; then
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] skipped: PROOF_GATE=0" >> "${LOG_DIR}/proof_gate.log"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ proof_gate: python3 không có — gate này KHÔNG chạy, ảnh nghiệm thu không được kiểm." >&2
  exit 0
fi

SELF="$0"
while [ -L "${SELF}" ]; do
  L="$(readlink "${SELF}")"; case "${L}" in /*) SELF="${L}" ;; *) SELF="$(dirname "${SELF}")/${L}" ;; esac
done
PROOF_INPUT="${INPUT}" PROOF_REPO="${REPO_ROOT}" PROOF_LOG_DIR="${LOG_DIR}" \
PROOF_BIN="$(cd "$(dirname "${SELF}")/../bin" 2>/dev/null && pwd)" python3 <<'PY'
import datetime, json, os, re, sys

repo = os.environ["PROOF_REPO"]
log_dir = os.environ["PROOF_LOG_DIR"]
log_path = os.path.join(log_dir, "proof_gate.log")
state_path = os.path.join(log_dir, "proof_gate.state")
min_bytes = int(os.environ.get("PROOF_MIN_BYTES", "8192"))
max_blocks = int(os.environ.get("PROOF_GATE_MAX_BLOCKS", "2"))
PNG_SIG = b"\x89PNG\r\n\x1a\n"

def log(msg):
    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), msg))
    except OSError:
        pass

try:
    d = json.loads(os.environ.get("PROOF_INPUT") or "{}")
except ValueError:
    log("fail-open: bad stdin JSON")
    sys.exit(0)
reply = d.get("last_assistant_message") or ""
session = d.get("session_id") or "?"

status = ""
for line in reply.splitlines():
    s = re.sub(r"^[\s>#*_`\-]+|[\s*_`]+$", "", line)
    if s:
        status = s
        break
if not re.match(r"XONG\b", status):
    sys.exit(0)

def turn_start(tp):
    """Timestamp of the last real user prompt (not a tool result) in the transcript."""
    last = None
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                try:
                    e = json.loads(raw)
                except ValueError:
                    continue
                if e.get("type") != "user" or e.get("isMeta"):
                    continue
                c = (e.get("message") or {}).get("content")
                human = isinstance(c, str) or (isinstance(c, list) and any(
                    isinstance(x, dict) and x.get("type") == "text" for x in c))
                if human and e.get("timestamp"):
                    last = e["timestamp"]
    except OSError:
        return None
    if not last:
        return None
    try:
        return datetime.datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

start = turn_start(d.get("transcript_path") or "")
cited = sorted(set(re.findall(r"(?:[\w./-]*/)?reports/proof-\d{8}-\d{6}\.png", reply)))
problems, good = [], []
for rel in cited:
    path = rel if os.path.isabs(rel) else os.path.join(repo, rel)
    if not os.path.isfile(path):
        problems.append("%s: không có file này" % rel); continue
    try:
        with open(path, "rb") as f:
            head = f.read(8)
        st = os.stat(path)
    except OSError as e:
        problems.append("%s: không đọc được (%s)" % (rel, e)); continue
    if head != PNG_SIG:
        problems.append("%s: không phải PNG thật (sai chữ ký file)" % rel); continue
    if st.st_size <= min_bytes:
        problems.append("%s: %d byte, cần lớn hơn 8 KB" % (rel, st.st_size)); continue
    if start is None:
        problems.append("%s: không xác định được lúc bắt đầu lượt để so thời gian" % rel); continue
    if st.st_mtime < start:
        problems.append("%s: ảnh cũ, sửa lúc trước lượt này bắt đầu" % rel); continue
    good.append(rel)

def full_gate_problem():
    """None when this turn has a full-gate exit 0 on the current code, else the reason."""
    sys.path.insert(0, os.environ.get("PROOF_BIN") or "")
    try:
        import tree_fp
    except ImportError:
        return "không tìm thấy bin/tree_fp.py của DevKit để kiểm lần chạy cổng --full"
    rp = tree_fp.receipt_path(repo)
    try:
        rec = json.load(open(rp, encoding="utf-8")) if rp else None
    except (OSError, ValueError):
        rec = None
    if not rec or rec.get("exit") != 0:
        return "không có lần chạy `post-fix-gate.py --run-tests --full` nào ra exit 0 trên code hiện tại"
    if start is None:
        return "không xác định được lúc bắt đầu lượt để so với lần chạy cổng --full"
    if rec.get("time", 0) < start:
        return "lần chạy cổng --full exit 0 là từ trước lượt này — chạy lại trong lượt"
    if rec.get("fingerprint") != tree_fp.tree_fingerprint(repo):
        return "code đã đổi sau lần chạy cổng --full exit 0 — chạy lại cổng trên code hiện tại"
    return None

gate_problem = full_gate_problem()
if good and not gate_problem:
    log("pass session=%s proof=%s" % (session, ",".join(good)))
    sys.exit(0)

state = {}
try:
    state = json.load(open(state_path, encoding="utf-8"))
except (OSError, ValueError):
    pass
n = state.get(session, 0) + 1
state[session] = n
try:
    json.dump(state, open(state_path, "w", encoding="utf-8"))
except OSError:
    pass

lines = ["⛔ PROOF-GATE: câu trả lời mở bằng XONG nhưng lượt này chưa đủ điều kiện (cổng --full exit 0 + ảnh nghiệm thu)."]
if gate_problem:
    lines.append("  - CỔNG: " + gate_problem + ". Chạy từ gốc repo: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full")
if not good:
    if cited:
        lines += ["  - ẢNH: " + p for p in problems]
    else:
        lines.append("  - ẢNH: câu trả lời không nêu đường dẫn reports/proof-<yyyyMMdd-HHmmss>.png nào.")
lines.append("Chụp trên đúng thiết bị: adb -s <SERIAL> exec-out screencap -p > reports/proof-<yyyyMMdd-HHmmss>.png "
             "(PNG thật, > 8 KB, chụp trong lượt này), rồi nêu đường dẫn và serial ở dòng 3. "
             "Không có thiết bị online thì mở câu trả lời bằng CHƯA XONG. Không vẽ ảnh, không dùng lại ảnh cũ.")
log("block session=%s attempt=%d cited=%s gate=%s" % (session, n, ",".join(cited) or "-", gate_problem or "ok"))
if n > max_blocks:
    msg = "\n".join(lines + ["(Đã chặn %d lần — cho dừng để không kẹt phiên. XONG này THIẾU điều kiện ở trên; người dùng cần xem lại.)" % max_blocks])
    print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
    sys.exit(0)
print("\n".join(lines), file=sys.stderr)
sys.exit(2)
PY
rc=$?
[ "$rc" = 2 ] && exit 2
exit 0
