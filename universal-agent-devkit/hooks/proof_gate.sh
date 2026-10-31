#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# proof_gate.sh — Stop hook: a reply that opens with XONG must carry the turn's
# acceptance image (rules/essentials.md "Every prompt", step 4/5).
#
# Only the status line decides (devkit_harness.reply_status): first non-empty line of the
# reply, markdown, leading emoji and a `Status:`/`Trạng thái:` label stripped, any case.
# "XONG" → checked; "CHƯA XONG", "CHỜ DUYỆT", anything else → allowed.
# Checked = both halves of step 5, from this turn:
#   - .git/postfix-gate/full_pass.json, written by `post-fix-gate --run-tests --full` on
#     exit 0, newer than the turn's user message, whose fingerprint (bin/tree_fp.py) still
#     matches the code — an edit after the gate run voids it (25/10, audit A item 4: a receipt of an EARLIER turn holds too when
#     every suite in it is PASS and its fingerprint equals the current one exactly; tests/gates/test_proof_gate.sh grp_earlier) (trunk mode, 17/10: a receipt `worktree finish` carried into main for
#     main's HEAD, of a clean tree, still holds when the only differing files are dirty in main and named by no editing tool call of
#     this session: other sessions' / the board runner's files, foreign_dirty_only); trunk mode, 18/10: without such a receipt the turn
#     still passes on (a) a --full exit 0 receipt a worktree of the repo wrote this turn, still matching that worktree, for the same tree
#     as the judged HEAD, or (b) the output of a super-board-merge-gate.sh call this turn ("verified green" + "merged <H>") when git
#     attests it: the real origin (ls-remote) holds a squash of H committed this turn and the judged tree stands at H or holds it with
#     nothing origin lacks (merged_evidence; tests/gates/test_proof_gate_merged_trunk.sh); #105, 19/10: or (c) a --full exit 0 receipt of
#     this turn that post-fix-gate mirrored by tree into <git common dir>/postfix-gate/tree_receipts (it outlives the worktree), for the
#     judged tree, or in main for HEAD's commit when only other sessions' uncommitted files differ (tree_store_evidence;
#     tests/gates/test_proof_gate_tree_receipt.sh); 27/10: or (d) a merge receipt super-board-merge-gate.sh wrote this turn for this
#     session (<git common dir>/postfix-gate/merge_receipts) whose squash git finds on the real origin with the receipt's base as parent
#     and its verified tree, the judged tree at it or after it through receipted squashes only (merge_receipt_evidence;
#     tests/gates/test_proof_gate_merge_receipt.sh); #644: full_pass.json không đạt thì scoped_pass.json (biên nhận exit 0 của lượt gate
#     scoped, `scope` "scoped") được xét theo cùng luật, và (c) đọc thêm kho scoped_receipts/ (tests/gates/test_scoped_receipt_doors.sh);
#     #722: ở main trunk mode, file thường của main có ctime + mtime trước lúc phiên bắt đầu không thành "của phiên" chỉ vì một lệnh shell
#     nhắc tên (predates_session; tests/gates/test_proof_gate_main_predates_session.sh), dòng `api-request-blob` không timestamp không còn
#     đóng cửa (d) (tests/gates/test_proof_gate_api_request_blob.sh), và lời khuyên ở main trunk mode là `--tree HEAD` trong worktree tạm;
#   - the reply names at least one reports/proof-<yyyyMMdd-HHmmss>.png that
#   - exists under the project,
#   - starts with the PNG signature,
#   - is larger than 8 KB (PROOF_MIN_BYTES),
#   - was modified after the turn's user message (transcript timestamp).
# The image is waived only when bin/tree_fp.py image_required() says the change cannot show
# on a screen: the backend profile, or every changed file (working tree, untracked, commits
# of the turn) is surely off-screen (tests, docs, Markdown, top-level tooling dirs). A cited
# PNG is checked even then. The full gate is never waived.
# Handover report (core-rules §1.3): an XONG, and any turn that ran `git push` (transcript Bash
# call after the last user prompt), must carry the 4 items — Đã fix · bug cũ · bug mới · An
# toàn mã nguồn (English labels accepted). A push turn is checked for the report only. A push turn
# that does not open with XONG may carry the report in an earlier message instead of the final reply:
# one assistant text message (not a subagent line, thinking block or tool result) written after the
# LAST successful push of the turn, with all 4 items, is enough (PROOF_REPORT_AFTER_PUSH=0 turns this
# off). An XONG reply always carries the report itself.
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

INPUT="$(cat)"

# The project (2026-10-09): CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (of the process cwd when the payload has
# none). Outside a git tree there is no project and nothing is written (tests/gates/test_hook_log_dir.sh): a run at /
# created /.claude/audit-gate/.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "${REPO_ROOT}" ]; then
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'   # a JSON-escaped cwd too (é sent escaped, \", \\): tests/gates/test_hook_payload_cwd_escaped.sh
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  case "${_PCWD}" in *\\*) _PCWD="$(python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())' "${_PCWD}" 2>/dev/null)" || _PCWD="." ;; esac
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
BASE_ROOT="${REPO_ROOT}"   # the hooks that write turn_class_<sid>.json (prompt_context) write under it, whatever tree is judged below
# W1 v6 (hooks/session_worktree.py): a session that ENTERED a worktree (EnterWorktree: CLAUDE_PROJECT_DIR still names main) or a subagent
# the harness started in one is judged in that worktree, not in a clean main. Python only when the payload or a session record can need it.
_SW_SID='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9][A-Za-z0-9._-]*)"'
_SW_CWD='"cwd"[[:space:]]*:[[:space:]]*"[^"]*/\.claude/worktrees/'   # the cwd FIELD, not any text of the payload (a file read, a subagent)
if [ -n "${REPO_ROOT}" ] && { [[ ${INPUT} =~ ${_SW_CWD} ]] \
     || { [[ ${INPUT} =~ ${_SW_SID} ]] && [ -f "${REPO_ROOT}/.claude/audit-gate/session_worktree/${BASH_REMATCH[1]}" ]; }; }; then
  if _SW_ROOT="$(python3 -I -c 'import json,os,sys
_d = os.path.dirname(os.path.realpath(sys.argv[1]))
if os.path.isabs(_d): sys.path.append(_d)
import session_worktree as s; print(s.project(json.loads(sys.stdin.read() or "{}")) or "")' "$0" <<<"${INPUT}" 2>/dev/null)"; then
    [ -n "${_SW_ROOT}" ] && REPO_ROOT="${_SW_ROOT}"
  else   # never silent: this gate then judges what CLAUDE_PROJECT_DIR names, possibly a clean main (OCR 14/10)
    echo "⚠ DevKit $(basename "$0"): the session's worktree could not be resolved (hooks/session_worktree.py next to the real hook) - judging ${REPO_ROOT}" >&2
  fi
fi
[ -n "${REPO_ROOT}" ] || exit 0
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}" 2>/dev/null
# -e, not -f: a FIFO planted there is not a file, and the redirect into it blocked the hook until its timeout (= the Stop passes)
for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
[ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

if [ "${PROOF_GATE:-1}" = "0" ]; then
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] skipped: PROOF_GATE=0" >> "${LOG_DIR}/proof_gate.log"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ proof_gate: python3 không có — gate này KHÔNG chạy, ảnh nghiệm thu không được kiểm." >&2
  exit 0
fi

# #528: worker của board không chấm main. Worktree liên kết vẫn chạy.
if [ "${SB_BOARD_WORKER:-}" = "1" ] && python3 -I -c 'import os,sys
_d = os.path.dirname(os.path.realpath(sys.argv[1]))
if os.path.isabs(_d): sys.path.append(_d)
import session_worktree as s
raise SystemExit(0 if s.worker_skip_main(sys.argv[2]) else 1)' "$0" "${REPO_ROOT}"; then
  echo "$(date +%Y-%m-%dT%H:%M:%S) SB_BOARD_WORKER skip main" >> "${LOG_DIR}/proof_gate.log"
  exit 0
fi

SELF="$0"
while [ -L "${SELF}" ]; do
  L="$(readlink "${SELF}")"; case "${L}" in /*) SELF="${L}" ;; *) SELF="$(dirname "${SELF}")/${L}" ;; esac
done
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable (Linux 128 KiB,
# macOS ~1 MiB for args + env) python could not start and the gate passed (tests/gates/test_hook_large_payload.sh).
PROOF_REPO="${REPO_ROOT}" PROOF_LOG_DIR="${LOG_DIR}" PROOF_BASE_LOG_DIR="${BASE_ROOT}/.claude/audit-gate" PROOF_HOOKDIR="$(dirname "${SELF}")" \
PROOF_BIN="$(cd "$(dirname "${SELF}")/../bin" 2>/dev/null && pwd)" python3 -I <<'PY' 3<<<"${INPUT}"
import datetime, glob, hashlib, json, math, os, re, stat, sys, time

repo = os.environ["PROOF_REPO"]
log_dir = os.environ["PROOF_LOG_DIR"]
log_path = os.path.join(log_dir, "proof_gate.log")
state_path = os.path.join(log_dir, "proof_gate.state")
min_bytes = int(os.environ.get("PROOF_MIN_BYTES", "8192"))
max_blocks = int(os.environ.get("PROOF_GATE_MAX_BLOCKS", "2"))
PNG_SIG = b"\x89PNG\r\n\x1a\n"
HOOK_T0 = time.monotonic()
# Hạn chót của phần kiểm tốn thời gian (mạng, git): hook có "timeout": 15 trong settings, và Claude Code giết hook quá hạn = Stop lọt.
try:   # một giá trị hỏng không được làm python chết (= wrapper exit 0 = Stop lọt); nan / inf / quá 12 s cũng không vô hiệu được hạn chót
    HOOK_BUDGET_S = float(os.environ.get("PROOF_GATE_BUDGET_S", "9"))
except ValueError:
    HOOK_BUDGET_S = 9.0
HOOK_BUDGET_S = 9.0 if not math.isfinite(HOOK_BUDGET_S) else min(max(HOOK_BUDGET_S, 0.0), 12.0)
left = lambda: HOOK_T0 + HOOK_BUDGET_S - time.monotonic()

def open_reg(path, flags=os.O_RDONLY):
    """fd of the REGULAR file at path, never waited on: a FIFO an agent planted at a state file blocked open() until the hook's
    timeout, and a Stop hook killed by its timeout lets the Stop through (issues-bugs A.4). OSError otherwise, as for a missing file."""
    fd = os.open(path, flags | getattr(os, "O_NONBLOCK", 0), 0o666)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError("not a regular file: %s" % path)
    return fd

def log(msg):
    try:
        with os.fdopen(open_reg(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND), "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), msg))
    except OSError:
        pass

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        _raw = _fh.read()
except OSError:
    _raw = ""
try:
    d = json.loads(_raw.strip() or "{}")
except ValueError:
    log("fail-open: bad stdin JSON")
    sys.exit(0)
reply = d.get("last_assistant_message") or ""
session = d.get("session_id") or "?"

# The status line is read by devkit_harness.reply_status, shared with the other Stop hooks:
# `✅ XONG`, `Xong.`, `Status: XONG`, `Trạng thái: XONG` are XONG too. Without the helper (a hook
# copied alone) the plain uppercase XONG check still runs.
xong = harness = None
for _hd in (os.environ.get("PROOF_HOOKDIR", ""), os.path.join(repo, ".agents", "devkit", "hooks")):
    if _hd and os.path.isfile(os.path.join(_hd, "devkit_harness.py")):
        try:
            sys.path.insert(0, _hd)
            sys.dont_write_bytecode = True
            import devkit_harness
            xong = devkit_harness.reply_status(reply) == "DONE"
            harness = devkit_harness
        except Exception as e:
            log("devkit_harness failed: %r" % e)
        break
if xong is None:
    status = next((s for s in (re.sub(r"^[\s>#*_`\-]+|[\s*_`]+$", "", l) for l in reply.splitlines()) if s), "")
    xong = bool(re.match(r"XONG\b", status))
# The 4-item acceptance report (core-rules §1.3) every handover carries: an XONG, or a turn
# that ran `git push` whatever its status line says (2026-09-25: a push turn left it out).
# Labels as the rule words them and as agents write them (2026-10-14 replay of 7 days of real Stops: 19 replies with all four items
# were blocked for "Nguy cơ mới", "Đã làm gì", "Đã thay đổi gì", "Chặn lỗi cũ", "Nguy cơ lỗi mới"). The words the old patterns
# already matched anywhere stay as they were (HEAD behaviour, unchanged: `bug cũ`, `bug mới`, `đã fix gì` still count anywhere in the
# reply); the NEW variants must be exactly a LABEL: at the start of a line (after a list marker, never indented: an indented sub-bullet is
# the content of the item above), nothing before the phrase but "đã" / "chặn", at most "nào" / "đã triệt tiêu" and a parenthesis after
# it, then its own colon. So "Rủi ro còn lại: không có rủi ro mới", "Rủi ro còn lại — rủi ro mới thấp:", "Không có nguy cơ mới nào:" and
# a sentence that only starts with the phrase are no item ("Rủi ro còn lại", residual risk, is another item; a bare "Lỗi cũ:" line is
# content) (OCR + principal-code-reviewer 14/10, 6 rounds).
_START = r"(?:^|\n)(?![ \t])[>*_#\-\d.()•+ \t]*"
_END = r"(?:\s+nào)?(?:\s+đã\s+triệt\s+tiêu)?[*_]*\s*(?:\([^)\n]*\))?[*_]*\s*[:：]"
REPORT_ITEMS = (("1. Đã fix gì (tên lỗi, nguyên nhân gốc, RED→GREEN)",
                 r"đã\s+(?:fix|sửa)\s*(?:gì|:)|" + _START + r"đã\s+(?:fix|sửa|làm|thay\s+đổi)(?:\s+được)?\s+gì[*_]*\s*(?:\([^)\n]*\))?[*_]*\s*[:：]"
                 + r"|what\s+was\s+fixed"),
                ("2. Chặn bug cũ (test hồi quy / immutable_guards chạy lại PASS)",
                 r"bug\s+cũ|" + _START + r"(?:đã\s+)?chặn\s+(?:đứng\s+)?(?:các\s+)?lỗi\s+cũ" + _END + r"|reopened"),
                ("3. Nguy cơ bug mới (caller, module liên đới đã rà)",
                 r"bug\s+mới|" + _START + r"(?:nguy\s+cơ|rủi\s+ro)\s+(?:(?:bug|lỗi)\s+)?mới" + _END + r"|collateral"),
                ("4. An toàn mã nguồn (secret, placeholder, OCR)", r"an\s+toàn\s+mã|code\s+safety"))
missing_report = [name for name, rx in REPORT_ITEMS if not re.search(rx, reply, re.I)]

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
                # same rule as devkit_harness.is_user_prompt (used when it loads, below)
                if isinstance(e.get("origin"), dict) and e["origin"].get("kind") in ("task-notification", "peer", "auto-continuation"):
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

# One definition of "the user's last prompt" for every hook (INSTINCT-015): devkit_harness when it loads.
start = (harness.turn_start if harness else turn_start)(d.get("transcript_path") or "")

# A push that did not go through is no handover: its result is an error (a denied permission),
# shows git refusing it, or says the command went to the background (GeelyEx2 2026-09-26, and a
# denied push in the DevKit workbench). A push with no result found still counts.
PUSH_FAILED = re.compile(r"\[(?:remote )?rejected\]|error: failed to push|^fatal:|hook declined", re.I | re.M)
# A ref that went out ("   a1b2..c3d4  main -> main", "* [new branch] x -> x") on a line that is not a rejection.
PUSH_WENT = re.compile(r"^(?!.*\[(?:remote )?rejected\]).*\S\s+->\s+\S", re.M)


def safe_digest(p):
    try:
        with os.fdopen(open_reg(p), "rb") as f: return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None

def pushed_in_turn(tp):
    """(pushed, report_after) for the turn after the last user prompt. pushed: a Bash call ran `git push`
    that did not visibly fail. A push is what devkit_harness.git_writes reads as one — the classifier
    work_in_progress (regression_gate, review_gate) uses too: a real `git push` command, not the
    words in a heredoc body, a string, `git stash push` or a --dry-run. Without the helper (a hook
    copied alone) no push is detected. report_after: an assistant text message (no subagent line, no
    thinking block, no tool result) that carries all 4 REPORT_ITEMS stands LATER IN THE FILE than the last
    successful push settled (its tool_result, else its call). File order, not timestamps: lines of one
    millisecond keep their order."""
    if harness is None:
        log("push check skipped: devkit_harness not loaded")
        return False, False
    pushes = {}   # tool_use id -> [call line, result line or None, True (went through or unknown) / False (failed)]
    report_at = -1
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for n, raw in enumerate(f):
                if "push" not in raw and not any(i in raw for i in pushes) and not (pushes and '"text"' in raw):
                    continue          # most lines: no JSON parse on every Stop
                try:
                    e = json.loads(raw)
                    t = datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp()
                except (ValueError, AttributeError):
                    continue
                if start is None or t < start:
                    continue
                msg = e.get("message")
                blocks = msg.get("content") if isinstance(msg, dict) else None
                for c in blocks if isinstance(blocks, list) else ():   # a line of another shape is skipped, never a crash (= a pass)
                    if not isinstance(c, dict):
                        continue
                    if e.get("type") == "assistant" and c.get("type") == "tool_use":
                        cmd = (c.get("input") or {}).get("command", "")
                        if "push" in harness.git_writes(cmd):
                            pushes[c.get("id") or "no-id-%d" % len(pushes)] = [n, None, True]
                    elif c.get("type") == "tool_result" and c.get("tool_use_id") in pushes:
                        body = c.get("content")
                        if isinstance(body, list):
                            body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                        body = str(body or "")
                        # went out = a ref line, even if a later ref or command failed; a background
                        # push usually completes. Only a failure with nothing sent is no handover.
                        failed = (bool(c.get("is_error")) or bool(PUSH_FAILED.search(body))) \
                            and not PUSH_WENT.search(body) and "running in background" not in body
                        pushes[c["tool_use_id"]][1:] = [n, not failed]
                    elif (pushes and e.get("type") == "assistant" and not e.get("isSidechain") and c.get("type") == "text"
                          and isinstance(c.get("text"), str) and all(re.search(rx, c["text"], re.I) for _, rx in REPORT_ITEMS)):
                        report_at = n
    except OSError:
        pass
    settled = [p[1] if p[1] is not None else p[0] for p in pushes.values() if p[2]]
    return bool(settled), bool(settled) and report_at > max(settled)

if not xong:
    if not missing_report:
        sys.exit(0)
    pushed, report_after = pushed_in_turn(d.get("transcript_path") or "")
    if not pushed:
        sys.exit(0)
    if report_after and os.environ.get("PROOF_REPORT_AFTER_PUSH", "1") != "0":
        log("pass session=%s report-after-push" % session)
        sys.exit(0)
cited = sorted(set(re.findall(r"(?:[\w./-]*/)?reports/proof-\d{8}-\d{6}\.png", reply))) if xong else []
problems, good, before_problems = [], [], []
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
    stamp = re.search(r"proof-(\d{8}-\d{6})\.png$", rel)
    try:
        taken = datetime.datetime.strptime(stamp.group(1), "%Y%m%d-%H%M%S").timestamp() if stamp else None
    except ValueError:
        taken = None
    if taken is None or taken < start - 60:
        problems.append("%s: giờ chụp trong tên file có trước lượt này (touch/đổi tên ảnh cũ không phải ảnh mới)" % rel); continue
    if taken > datetime.datetime.now().timestamp() + 60:
        problems.append("%s: giờ chụp trong tên file ở tương lai — không phải ảnh chụp trong lượt này" % rel); continue
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    twin = next((o for o in sorted(glob.glob(os.path.join(repo, "reports", "*.png")))
                 if os.path.realpath(o) != os.path.realpath(path)
                 and safe_digest(o) == digest), None)
    if twin:
        problems.append("%s: trùng byte với %s (ảnh cũ chép sang tên mới)" % (rel, os.path.relpath(twin, repo))); continue
    good.append(rel)

FP = {}   # "now": dấu vân tay cây đang xét, full_gate_problem tính một lần

def full_gate_problem():
    """None when this turn has a full-gate exit 0 on the current code, else the reason.
    #644: full_pass.json không đạt thì thử scoped_pass.json (lượt gate scoped) theo cùng luật; lý do chặn nêu cả hai khi file scoped có mặt."""
    _pb = os.environ.get("PROOF_BIN") or ""
    if os.path.isabs(_pb):   # "" (copy-mode install: no ../bin) would put the cwd first on sys.path again and undo -I
        sys.path.insert(0, _pb)
    try:
        import tree_fp
    except ImportError:
        return "không tìm thấy bin/tree_fp.py của DevKit"
    problem = receipt_gate_problem(tree_fp, tree_fp.receipt_path(repo), "full")
    srp = tree_fp.scoped_receipt_path(repo) if problem and hasattr(tree_fp, "scoped_receipt_path") else None
    if not srp or not os.path.lexists(srp):
        return problem
    sproblem = receipt_gate_problem(tree_fp, srp, "scoped")
    if sproblem is None:
        log("pass-gate session=%s scoped-receipt fp=%s (full: %s)" % (session, FP.get("now"), problem))
        return None
    return "%s; biên nhận scoped: %s" % (problem, sproblem)

def receipt_gate_problem(tree_fp, rp, kind):
    """None khi biên nhận ở rp (kind "full": full_pass.json; "scoped": scoped_pass.json, #644) cho lượt này exit 0 trên code hiện tại."""
    name = os.path.basename(rp or "") or "full_pass.json"
    rec = None
    try:
        if rp:
            with os.fdopen(open_reg(rp), encoding="utf-8") as fh:
                rec = json.load(fh)
    except (OSError, ValueError, RecursionError):   # RecursionError: a deeply nested file; no receipt, never a crash (python exit 1 became wrapper exit 0)
        rec = None
    if not rec:
        return "chưa có exit 0 trên code hiện tại"
    if not isinstance(rec, dict):
        return "receipt hỏng (%s không phải object JSON)" % name
    if kind == "scoped":
        if rec.get("scope") != "scoped":   # #644: thiếu scope hay "task" đều không phải biên nhận scoped
            return "%s không mang scope scoped" % name
    elif rec.get("scope", "full") != "full":   # T0061: biên nhận task chỉ được nhận qua task_evidence (đúng lượt), không thay biên nhận --full
        return "full_pass.json là biên nhận task, không phải --full"
    if rec.get("exit") != 0:
        return "chưa có exit 0 trên code hiện tại"
    rtime = rec.get("time", 0)
    # A wrong-shaped receipt used to crash this function: python exit 1, the wrapper turns it into exit 0, XONG passes.
    # An int is finite, but math.isfinite raises OverflowError on 10**400, and a 400-digit time is not a timestamp.
    # A real receipt time is a unix epoch (well under 10**12, year 33658). Negative is not one either.
    if (isinstance(rtime, bool) or not isinstance(rtime, (int, float))
            or (isinstance(rtime, float) and not math.isfinite(rtime))
            or rtime < 0 or rtime > 10 ** 12):
        return "receipt hỏng (%s: time không phải số)" % name
    turn_start_time = start
    if turn_start_time is None:
        # No human prompt in the transcript. The code that stood here read `tp` and `time`, two names that do not exist in
        # this script: NameError, exit 1, wrapper exit 0 = the XONG went through unchecked. Its intent (the transcript's
        # mtime) could never hold anyway: Claude Code writes the gate's tool_result and the reply AFTER the receipt.
        # ponytail: a session fed only by peer messages accepts a receipt younger than 1 h whose fingerprint still matches
        # the code, and blocks twice per hour (key below). Upgrade when a real per-turn scope is needed: the mark must come
        # from the transcript and must skip isMeta entries of Stop-hook feedback, [Image: ...] and skills, task-notification
        # and auto-continuation (rv5/rv7 reviews, 2026-10-04: marking by "the last user entry" blocked 22 of 95 valid XONG).
        turn_start_time = time.time() - 3600
    earlier = rtime < turn_start_time
    if earlier:
        # Audit 25/10 A item 4 (303 blocks in 14 days: the agent re-ran a long gate on code that had not changed): a receipt of an
        # EARLIER turn still holds when it is a real --full exit 0 (post-fix-gate writes exit 0 only for a full run, never for an
        # impacted / deferred / budget / BUSY one) whose every suite is PASS, and the tree fingerprint below equals the current one
        # exactly (no foreign-dirty relief). A suite that is not PASS (UNTESTED: KEYED, STALE, KNOWN-RED, untested_exit; BUSY) was
        # proven in no run of its own: its own turn only. Checked before the fingerprint (cheap; 29 of 44 real exit-0 receipts carry
        # UNTESTED, 25/10). ponytail: no age cap and no gate_sha / matrix_sha check: a DevKit linked from outside the tree that changes
        # between turns does not void the receipt; add the receipt's gate_sha check when such a stale pass is seen in proof_gate.log.
        tests = rec.get("tests")
        if isinstance(rec.get("exit"), bool) or not isinstance(tests, list) or not tests:
            return "lần exit 0 là từ trước lượt này (biên nhận không ghi suite nào: chỉ dùng được trong lượt của nó)"
        not_pass = ["%s=%s" % (str(t.get("id"))[:40], str(t.get("status"))[:16]) if isinstance(t, dict) else "?"
                    for t in tests if not isinstance(t, dict) or t.get("status") != "PASS"]
        if not_pass:
            return "lần exit 0 là từ trước lượt này, có suite không PASS (%s): chỉ dùng được trong lượt của nó" % ", ".join(not_pass[:4])
    now_fp = FP["now"] = FP.get("now") or tree_fp.tree_fingerprint(repo)   # tree_store_evidence (và lần xét scoped) dùng lại: không tính hai lần trong hạn chót
    if not now_fp or not rec.get("fingerprint"):
        why = getattr(tree_fp.tree_fingerprint, "error", "") or "?"
        return "không tính được dấu vân tay code hiện tại (%s)" % str(why)[:60]
    if earlier:
        if rec.get("fingerprint") != now_fp:
            return "lần exit 0 là từ trước lượt này và code đã đổi sau đó"
        log("pass-gate session=%s earlier-turn receipt fp=%s suites=%d" % (session, now_fp, len(rec["tests"])))
        return None
    if rec.get("fingerprint") != now_fp:
        try:
            foreign = foreign_dirty_only(rec, tree_fp)
        except Exception as e:   # RecursionError, ValueError (NUL trong đường dẫn), TypeError…: python chết = wrapper exit 0 = XONG lọt; chặn như cũ
            log("foreign-dirty check crashed: %r" % e)
            foreign = None
        if not foreign:
            return "code đã đổi sau lần exit 0"
        log("pass session=%s foreign-dirty head=%s: %s" % (session, rec["head"][:12], ", ".join(foreign[:8])))
    return None

def foreign_dirty_only(rec, tree_fp):
    """Trunk mode (17/10): main chỉ nhận merge, `worktree finish` chép biên nhận của worktree sang main (`carried_from`), nhưng main giữ
    file chưa commit của phiên khác / runner của board, nên dấu vân tay không bao giờ khớp và XONG bị chặn ở mọi phiên. Danh sách các
    đường dẫn bẩn (khác rỗng) khi biên nhận vẫn phủ code của phiên này: lượt này có lượt bắt đầu thật (không phải mốc dự phòng 1 h), biên
    nhận chép từ worktree, `head` = HEAD của repo, `dirty` rỗng (đã gate đúng HEAD), và mọi file repo khác HEAD (ngoài EXCLUDE) đều chưa
    từng xuất hiện trong một tool_use không chỉ đọc của phiên (kể cả subagent). Không thì None = chặn như cũ."""
    if start is None or not isinstance(rec.get("carried_from"), str) or not rec["carried_from"]:
        return None
    import session_worktree   # hooks/ (đã vào sys.path cùng devkit_harness); thiếu thì ImportError -> chặn như cũ
    if not session_worktree.trunk_mode(repo):   # chỉ trunk mode: session_lock chặn mọi lần ghi vào main, luật này dựa vào đó
        return None
    head, dirty = rec.get("head"), rec.get("dirty")
    if not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{40}", head) or not isinstance(dirty, dict):
        return None
    excluded = lambda p: any(p == ex or p.startswith(ex + "/") for ex in tree_fp.EXCLUDE)
    if any(not excluded(p) for p in dirty):
        return None
    state = dirty_state(repo, tree_fp)
    if state is None or state[0] != head or not state[1] or not untouched_by_session(state[1]):
        return None
    return state[1]

def dirty_state(root, tree_fp, t=10):
    """(HEAD, các đường dẫn khác HEAD hoặc chưa track, ngoài tree_fp.EXCLUDE, đã sắp xếp) của cây git ở root; None khi git lỗi."""
    import subprocess
    # #691: path ghim (settings.json do bản cài kit sửa) không phải việc của phiên nào: tree_fingerprint() đã lấy bản HEAD của nó
    excluded = lambda p: any(p == ex or p.startswith(ex + "/") for ex in tree_fp.EXCLUDE) or tree_fp.head_pinned(p)
    git = lambda *a: subprocess.run(["git", "-C", root, *a], capture_output=True, timeout=t)
    try:
        now_head = git("rev-parse", "HEAD")
        changed = git("diff", "--name-only", "--relative", "--no-renames", "-z", "HEAD")   # một rename: cả đường dẫn cũ lẫn mới
        untracked = git("ls-files", "-o", "--exclude-standard", "-z")
    except (OSError, subprocess.SubprocessError) as e:
        log("dirty check failed in %s: %r" % (root, e))
        return None
    if any(r.returncode for r in (now_head, changed, untracked)):
        return None
    return now_head.stdout.decode().strip(), sorted({p for p in (changed.stdout + untracked.stdout).decode("utf-8", "surrogateescape").split("\0")
                                                     if p and not excluded(p)})

SESSION_SKEW_S = 2   # #722: ctime / mtime phải trước lúc phiên bắt đầu ít nhất chừng này (độ phân giải đồng hồ, giờ transcript)
_T0, _PREDATES = {}, {}

def session_t0():
    """#722: lúc phiên bắt đầu = timestamp hợp lệ đầu tiên trong 200 dòng đầu của transcript chính, chỉ khi 0 < t0 <= bây giờ + 60 (dòng
    đầu mang giờ tương lai: không biết), rồi kẹp về `start` (phiên không bắt đầu sau lời nhắc của lượt này). None khi không biết."""
    if "t0" not in _T0:
        t0 = None
        try:
            with os.fdopen(open_reg(d.get("transcript_path") or ""), encoding="utf-8", errors="replace") as f:
                for n, raw in enumerate(f):
                    if n >= 200:
                        break
                    try:
                        t0 = datetime.datetime.fromisoformat(json.loads(raw)["timestamp"].replace("Z", "+00:00")).timestamp()
                    except (ValueError, KeyError, TypeError, AttributeError, IndexError, RecursionError, OverflowError):
                        continue
                    break
        except OSError:
            t0 = None
        _T0["t0"] = min(t0, start) if (t0 is not None and start is not None and 0 < t0 <= time.time() + 60) else None
    return _T0["t0"]

def predates_session(paths):
    """#722 (30/10, phiên điều phối giữ Stop oan ở main): tập con của `paths` (tương đối repo) mà một lần NHẮC TÊN trong lệnh shell không làm
    thành của phiên. Chỉ ở main checkout trunk mode (session_lock cấm ghi vào main; foreign_dirty_only dựa vào cùng điều đó); chỉ file THƯỜNG
    (lstat: thư mục submodule / nested repo, symlink, FIFO thì không), của chính main (session_worktree.tree_of của file là main: không qua
    checkout con, như _lands_in_main của session_lock), cùng thiết bị với file probe trong log_dir, và ctime lẫn mtime đều trước lúc phiên
    bắt đầu − SESSION_SKEW_S. ctime do kernel đặt mỗi lần ghi / đổi tên / link / chmod / touch -t (đo trên APFS 31/10); agent không lùi được
    nếu không có root: nội dung lẫn metadata có từ trước phiên. Probe: ctime của một file tạm phải nhảy về bây giờ sau os.utime (FS không có
    ctime thật thì tắt). Mọi lỗi (kể cả thiếu session_worktree ở bản cài copy-mode): tập rỗng = luật cũ."""
    key = tuple(paths)
    if key in _PREDATES:
        return _PREDATES[key]
    out = set()
    try:
        t0 = session_t0()
        if t0 is not None and paths:
            import session_worktree   # hooks/ (đã vào sys.path cùng devkit_harness); thiếu thì except -> luật cũ
            root = os.path.realpath(repo)
            tree = session_worktree.tree_of(repo)
            if tree and not tree[1] and session_worktree.trunk_mode(repo):
                cands = []
                for p in paths:
                    full = os.path.join(root, p)
                    try:
                        st = os.lstat(full)
                    except (OSError, ValueError):   # file đã xoá, NUL: không chứng minh được gì
                        continue
                    if stat.S_ISREG(st.st_mode) and max(st.st_ctime, st.st_mtime) < t0 - SESSION_SKEW_S:
                        cands.append((p, full, st.st_dev))
                if cands:
                    import tempfile
                    fd, probe = tempfile.mkstemp(prefix=".ctime_probe.", dir=log_dir)
                    try:
                        os.close(fd)
                        os.utime(probe, (1e9, 1e9))
                        pst = os.lstat(probe)
                    finally:
                        os.remove(probe)
                    if pst.st_ctime < time.time() - 5:
                        log("predates-session: ctime in %s did not move with utime: exemption off" % log_dir)
                    else:
                        for p, full, dev in cands:
                            owner = session_worktree.tree_of(full)
                            if dev == pst.st_dev and owner and os.path.realpath(owner[0]) == root:
                                out.add(p)
            if out:
                log("predates-session: %d path(s) older than the session (t0=%d), a shell mention does not count: %s"
                    % (len(out), t0, ",".join(sorted(out)[:8])))
    except Exception as e:   # python chết = wrapper exit 0 = XONG lọt; lỗi ở đây = luật cũ
        log("predates-session check crashed: %r" % e)
        out = set()
    _PREDATES[key] = out
    return out

def untouched_by_session(paths):
    """True khi không tool_use không chỉ đọc nào của phiên (kể cả subagent) nhắc tới một trong `paths` (tương đối với repo đang xét);
    False khi có, hoặc khi một transcript không đọc được (không chứng minh được gì). #722: công cụ sửa file so với MỌI đường dẫn; lệnh shell
    và công cụ khác bỏ qua đường dẫn của predates_session (file thường của main có từ trước phiên: nhắc tên không phải là sửa)."""
    from session_authorship import read_only_tool   # bin/ (PROOF_BIN, đã vào sys.path): cùng danh sách công cụ chỉ đọc với các hook khác
    root = os.path.realpath(repo)
    targets = {os.path.join(root, p) for p in paths} | {os.path.realpath(os.path.join(root, p)) for p in paths}   # cả hai phía qua realpath: file bẩn là symlink
    old = predates_session(paths)
    named = [p for p in paths if p not in old]
    tp = d.get("transcript_path") or ""
    # ponytail: lệnh shell chỉ bị bắt khi nhắc đúng đường dẫn tương đối (glob `docs/*.md` hay `cd docs && …` lọt), không parse shell
    # (INSTINCT-045); lớp chặn chính là session_lock (trunk mode từ chối mọi lần ghi vào main), đây là lớp thứ hai. Nâng cấp khi một
    # phiên sửa được file bẩn của main mà không nêu tên nó. #722: một lệnh chỉ đọc (grep của subagent) nhắc tên file người khác để ở main
    # từ trước phiên từng khoá mọi cửa của cả phiên; predates_session (ctime do kernel giữ) gỡ đúng ca đó, không parse shell.
    for t in [tp] + sorted(glob.glob(os.path.join(os.path.splitext(tp)[0], "subagents", "*.jsonl"))):
        try:
            with os.fdopen(open_reg(t), encoding="utf-8", errors="replace") as f:   # open_reg: một FIFO đặt ở subagents/ không treo hook
                for raw in f:
                    if '"tool_use"' not in raw:
                        continue
                    try:
                        e = json.loads(raw)
                    except (ValueError, RecursionError):   # dòng có tool_use mà không đọc được: có thể là một lần sửa, chặn
                        log("session-touch check: unreadable tool_use line in %s" % t)
                        return False
                    msg = e.get("message") if isinstance(e, dict) else None
                    for c in (msg.get("content") if isinstance(msg, dict) else None) or []:
                        if not isinstance(c, dict) or c.get("type") != "tool_use" or read_only_tool(c.get("name")):
                            continue
                        args = c.get("input") if isinstance(c.get("input"), dict) else {}
                        files = [args[k] for k in ("file_path", "notebook_path", "TargetFile") if isinstance(args.get(k), str)]
                        if files:   # công cụ sửa file: so đường dẫn thật, file cùng tên trong worktree riêng không tính
                            if any(os.path.realpath(x if os.path.isabs(x) else os.path.join(root, x)) in targets for x in files):
                                return False
                        else:       # lệnh shell và mọi công cụ khác: nhắc tên file là coi như đã đụng (thừa thì chặn, như cũ)
                            text = json.dumps(args, ensure_ascii=False)
                            if any(p in text or json.dumps(p, ensure_ascii=False)[1:-1] in text for p in named):   # cả dạng JSON escape (", \)
                                return False
        except OSError as e:   # transcript nào (chính hay subagent) không đọc được: không chứng minh được gì, chặn như cũ
            log("session-touch check: transcript unreadable %s: %r" % (t, e))
            return False
    return True

MERGE_GATE_SKEW_S = 120   # đồng hồ GitHub (giờ commit squash) lệch máy này
# Lệnh Bash LÀ lệnh gọi merge gate: tuỳ chọn `cd <dir> &&` và `bash`, đường dẫn tới script, các đối số trơn, tuỳ chọn `2>&1` và `| tail -N`
# (tail chỉ cắt bớt, không viết được dòng nào). Không `;`, `&`, `|` khác, `#`, `$`, backtick, ngoặc, quote: một `echo …; # super-board-…`
# không còn là lệnh merge gate (OCR + principal review 18/10). Nhóm: 1 thư mục của `cd`, 2 đường dẫn script, 3 các đối số.
_W = r"""[^\s;&|<>$`#()'"\\]"""
MERGE_GATE_CALL = re.compile(r"\s*(?:cd\s+(%s+)\s*&&\s*)?(?:bash\s+)?(%s*/super-board-merge-gate\.sh)((?:\s+%s+)*)\s*(?:2>&1\s*)?"
                             r"(?:\|\s*tail(?:\s+-n)?\s+-?\d+\s*)?" % (_W, _W, _W))
GATE_SCRIPT = ".claude/bin/super-board-merge-gate.sh"
# Một `git push` chỉ được coi là đẩy nhánh PR khi đích chắc chắn là một nhánh tên khác main / master / trunk / HEAD; mọi push khác (trần,
# `HEAD`, biến, `<sha>:main`, `git stash push` cũng vậy: thừa thì chặn, fail-closed) coi như có thể đã đẩy thẳng lên trunk.
SAFE_PUSH = re.compile(r"\s*(?:cd\s+\S+\s*)?(?:git\s+(?:-C\s+\S+\s+)?push\s+(?:(?:-u|--set-upstream|-q|--quiet)\s+)*origin\s+"
                       r"(?!(?:HEAD:)?(?:refs/heads/)?(?:main|master|trunk|HEAD)\s*$)(?:HEAD:)?[\w./-]+)?\s*")
# origin của super-board là GitHub (merge gate gộp bằng `gh pr merge`): https / ssh / scp tới github.com, không gì khác (một sshd ở localhost
# hay host lạ phục vụ repo giả cũng là "mạng").
GITHUB_URL = re.compile(r"(?:https://(?:[^@/\s]+@)?github\.com/|ssh://(?:[^@/\s]+@)?github\.com(?::\d+)?/|[\w.-]+@github\.com:)[\w./-]+")

def origin_ls_remote(args, tag):
    """`git ls-remote <origin THẬT> <args…>` trong hạn chót của hook: (stdout, stderr, returncode) hoặc None (đã ghi log lý do).
    origin THẬT: URL sau insteadOf (`--get-url`) phải là GitHub (GITHUB_URL), không phải đường dẫn hay file: / ext:: / fd:: (`git config
    remote.origin.url .` biến ls-remote thành đọc chính repo này, principal review 18/10). ls-remote chạy NGOÀI repo, không đọc config
    nào agent ghi được (repo / global / system: core.sshCommand, http.proxy, sslVerify, insteadOf đều có thể dựng một origin giả, OCR
    18/10), ssh ép BatchMode, git chỉ được dùng https / ssh. PROOF_GATE_ALLOW_LOCAL_ORIGIN=1 (môi trường của hook, như PROOF_GATE=0;
    test dùng origin cục bộ) nhận cả đường dẫn. Dùng chung cho merged_evidence (b) và task_push_evidence (T0061)."""
    import subprocess
    local_ok = os.environ.get("PROOF_GATE_ALLOW_LOCAL_ORIGIN") == "1"
    genv = dict(os.environ, GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull)
    r = subprocess.run(["git", "-C", repo, "ls-remote", "--get-url", "origin"], capture_output=True, env=genv, timeout=max(0.5, min(10, left())))
    url = r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else ""
    if local_ok and url and not GITHUB_URL.fullmatch(url) and "://" not in url and "::" not in url:
        url = os.path.normpath(os.path.join(repo, url))
    elif not GITHUB_URL.fullmatch(url):
        log("%s: origin is not a GitHub remote (%r)" % (tag, re.sub(r"//[^@/\s]*@", "//***@", url)[:80]))   # token trong URL
        return None
    budget = min(5.0, left() - 1)   # mạng chậm / ssh chờ: quá hạn chót của hook = Claude Code giết hook = Stop lọt
    if budget < 1:
        log("%s: no time left for ls-remote" % tag)
        return None
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_TERMINAL_PROMPT="0", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=4")
    proto = ["-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "protocol.ssh.allow=always"] \
        + (["-c", "protocol.file.allow=always"] if local_ok else [])
    flags = [a for a in args if a.startswith("-")]
    p = subprocess.Popen(["git", *proto, "ls-remote", *flags, url, *[a for a in args if not a.startswith("-")]], cwd="/",
                         stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, start_new_session=True)
    try:
        so, se = p.communicate(timeout=budget)
    except subprocess.TimeoutExpired:   # cả nhóm tiến trình (ssh con giữ ống thì communicate chờ mãi)
        os.killpg(p.pid, 9)
        p.communicate()
        log("%s: ls-remote timed out after %.1fs" % (tag, budget))
        return None
    return so, se, p.returncode

def merged_evidence():
    """Trunk mode (18/10, 5 phiên: GeelyEx2 #63, OfficeReader #149, Goods #40, NFH #49, kit #67): việc gộp qua super-board-merge-gate.sh
    (gate --full xanh trong scratch của nó) bị chặn mãi, vì cây được xét (main sau khi worktree bị dọn) không có biên nhận --full của lượt
    và trunk mode cấm chạy gate ở main. Mô tả bằng chứng khi lượt này có một trong hai, None thì chặn như cũ:
      (a) biên nhận --full exit 0 của một worktree của repo, ghi trong lượt, vẫn khớp dấu vân tay của worktree đó, worktree sạch và cây HEAD
          của nó = cây HEAD của repo xét;
      (b) kết quả của một lệnh merge gate trong lượt ("[merge-gate #N] verified green …" và "[merge-gate #N] merged <H>"), mà git chứng
          thực: origin THẬT (`ls-remote`, không phải refs/remotes agent ghi được, INSTINCT-027) có trên nhánh mặc định một commit S ghi
          trong lượt là squash của H (cây S = merge-tree S^1 H), và repo xét đứng ở H hoặc chứa S mà không có gì ngoài origin.
    Cả hai: repo xét sạch, hoặc (chỉ main) chỉ bẩn file mà phiên này không đụng (untouched_by_session)."""
    import subprocess
    import tempfile
    import session_worktree   # hooks/ (đã vào sys.path cùng devkit_harness); thiếu thì ImportError -> chặn như cũ
    import tree_fp
    if start is None or not session_worktree.trunk_mode(repo):
        return None
    if left() <= 1:
        log("merged-evidence check: no time left")
        return None
    tree = session_worktree.tree_of(repo)
    state = dirty_state(repo, tree_fp, t=max(0.5, min(10, left() / 3)))   # ba lệnh git, mỗi lệnh một phần ba
    if not tree or state is None:
        return None
    head, paths = state
    if paths and (tree[1] or not untouched_by_session(paths)):   # worktree bẩn = việc của chính phiên, chưa gộp
        return None
    # mỗi lệnh git chỉ được phần còn lại của hạn chót (TimeoutExpired -> except ở chỗ gọi -> chặn như cũ)
    # refs/replace và info/grafts (agent ghi được, INSTINCT-027) thay được commit mà log / rev-parse / merge-base đọc: tắt cả hai
    genv = dict(os.environ, GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull)
    git = lambda *a, cwd=repo, t=None: subprocess.run(["git", "-C", cwd, *a], capture_output=True, env=genv,
                                                      timeout=t or max(0.5, min(10, left())))
    out = lambda r: r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else None
    main = session_worktree.main_of(repo) or repo

    def gate_script_ok(cwd, cd, path):
        """Lệnh gọi đúng script merge gate của repo: đường dẫn (tính từ thư mục `cd`, không có thì từ cwd THẬT của lệnh ghi trong transcript:
        cwd của shell giữ qua các lệnh, một `cd /tmp/x` ở lệnh trước đổi script được chạy) trỏ tới .claude/bin/super-board-merge-gate.sh
        của repo xét hay của main, file đó được track và không đổi so với HEAD của cây đó."""
        base = cd if cd and os.path.isabs(cd) else (os.path.join(cwd, cd) if cd and isinstance(cwd, str) else cwd)
        if not os.path.isabs(path) and not (isinstance(base, str) and os.path.isabs(base)):
            return False
        for c in [path if os.path.isabs(path) else os.path.join(base, path)]:
            for top in {repo, main}:
                if (os.path.realpath(c) == os.path.realpath(os.path.join(top, GATE_SCRIPT))
                        and git("ls-files", "--error-unmatch", "--", GATE_SCRIPT, cwd=top).returncode == 0
                        and git("diff", "--quiet", "HEAD", "--", GATE_SCRIPT, cwd=top).returncode == 0):
                    return True
        return False
    want = out(git("rev-parse", head + "^{tree}"))
    if not want:
        return None
    # (a) biên nhận của worktree anh em (cùng .git, như bin/post-fix-gate.py cached_full_pass mượn); #644: cả scoped_pass.json (scope "scoped")
    for rp in sorted(glob.glob(os.path.join(tree[2], "worktrees", "*", "postfix-gate", "full_pass.json"))
                     + glob.glob(os.path.join(tree[2], "worktrees", "*", "postfix-gate", "scoped_pass.json"))):
        scoped = os.path.basename(rp) == "scoped_pass.json"
        if left() <= 3:   # mỗi biên nhận một lần tính dấu vân tay (không cắt giữa chừng được): repo lớn, nhiều worktree
            log("worktree-receipt check: out of time")
            return None
        try:
            with os.fdopen(open_reg(rp), encoding="utf-8") as fh:
                rec = json.loads(fh.read(1 << 20))
        except (OSError, ValueError, RecursionError):
            continue
        if (not isinstance(rec, dict) or rec.get("exit") != 0 or rec.get("carried_from") or not isinstance(rec.get("project"), str)
                or (rec.get("scope") != "scoped" if scoped else rec.get("scope", "full") != "full")):   # T0061: biên nhận task không phải --full
            continue
        rtime, tested = rec.get("time"), rec.get("tested_at")
        if isinstance(rtime, bool) or not isinstance(rtime, (int, float)) or not (start <= rtime <= time.time() + 60):
            continue
        # suite chạy thật trong lần đó (lần dùng lại giữ tested_at cũ: không mượn lại một PASS đã mượn, như cached_full_pass)
        if isinstance(tested, bool) or not isinstance(tested, (int, float)) or not (-1 <= rtime - tested < 5):
            continue
        proj = rec["project"]
        gd = out(git("rev-parse", "--absolute-git-dir", cwd=proj))
        if not gd or os.path.realpath(gd) != os.path.realpath(os.path.dirname(os.path.dirname(rp))):   # biên nhận đúng của worktree đó
            continue
        wst = dirty_state(proj, tree_fp, t=max(0.5, min(10, left() / 3)))
        if (not wst or wst[1] or rec.get("head") != wst[0] or not rec.get("fingerprint") or rec.get("fingerprint") != tree_fp.tree_fingerprint(proj)
                or out(git("rev-parse", wst[0] + "^{tree}")) != want):
            continue
        return "worktree-receipt%s %s head=%s" % (" scoped" if scoped else "", proj, wst[0][:12])
    # (b) bản ghi merge gate của lượt: chỉ kết quả (không lỗi) của một lệnh Bash LÀ lệnh gọi super-board-merge-gate.sh (MERGE_GATE_CALL),
    # `--pr N` / `--expect-head` khớp "#N" / "merged <H>", script là bản track không đổi của repo (gate_script_ok), ghi sau lời nhắc người dùng.
    # ponytail: bản ghi trong transcript gắn với phiên chỉ qua lệnh của nó; một phiên chép dòng "merged
    # <H>" của PR phiên KHÁC gộp trong cùng lượt vẫn qua (git chỉ chứng thực H đã gộp qua origin trong lượt, không phải ai gộp, không phải
    # gate đã chạy). Nâng cấp khi merge gate ghi biên nhận theo session id vào git common dir.
    # ponytail: origin là URL trong .git/config (agent ghi được): một fork GitHub của chính agent có commit squash dựng sẵn, hay ~/.ssh/config
    # trỏ github.com về máy khác, vẫn qua. Cả hai cần dựng repo / máy chủ riêng, không phải một lệnh echo. Nâng cấp: ghim owner/repo từ một
    # nguồn đã track (config board) và host key GitHub đi kèm DevKit.
    # ponytail: script sửa tạm cho in hai dòng rồi hoàn lại trước Stop, hay một PR sửa chính script rồi gộp (HEAD mới chứa bản sửa), vẫn qua
    # (gate_script_ok chỉ thấy bản lúc Stop); ghi thẳng lên trunk bằng lệnh không có chữ merge / push (gh api …/contents, MCP
    # create_or_update_file) không bị other_merge bắt. Origin https riêng tư: ls-remote không có credential helper -> chặn (fail-closed;
    # các repo board dùng ssh). Merge gate kết thúc ở nhánh "merge response was lost" / "already merged" không in "merged <H>" -> chặn.
    # Nâng cấp cùng biên nhận theo session id ở trên.
    calls, merged, other_merge, pushes = {}, [], False, []
    tp = d.get("transcript_path") or ""
    for t in [tp] + sorted(glob.glob(os.path.join(os.path.splitext(tp)[0], "subagents", "*.jsonl"))):   # subagent của phiên cũng gộp được
        try:
            with os.fdopen(open_reg(t), encoding="utf-8", errors="replace") as f:
                for raw in f:
                    if "merge" not in raw and "push" not in raw:   # lệnh merge gate, kết quả của nó, gh … merge, git push … main
                        continue
                    if left() <= 0:
                        log("merge-gate check: out of time reading the transcript")
                        return None
                    try:
                        e = json.loads(raw)
                        if datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp() < start:
                            continue
                    except (ValueError, AttributeError, TypeError, RecursionError):
                        continue
                    msg = e.get("message") if isinstance(e, dict) else None
                    for c in (msg.get("content") if isinstance(msg, dict) else None) or []:
                        if not isinstance(c, dict):
                            continue
                        if e.get("type") == "assistant" and c.get("type") == "tool_use" and c.get("name") == "Bash":
                            cmd = (c.get("input") or {}).get("command", "")
                            m = MERGE_GATE_CALL.fullmatch(cmd) if isinstance(cmd, str) and not re.search(r"[\r\n]", cmd) else None
                            args = m.group(3).split() if m else []
                            pr = args[args.index("--pr") + 1] if "--pr" in args[:-1] else ""
                            want_head = args[args.index("--expect-head") + 1] if "--expect-head" in args[:-1] else ""
                            if m and pr.isdigit() and re.fullmatch(r"[0-9a-f]{7,40}", want_head) and gate_script_ok(e.get("cwd"), m.group(1), m.group(2)):
                                calls[c.get("id")] = (pr, want_head)
                            else:
                                segs = [seg for seg in re.split(r"[;&|\n]+", str(cmd)) if re.search(r"\bpush\b", seg)]
                                pushes += segs
                                if re.search(r"\bgh\b[^\n]*\bmerge\b|/pulls/\d+/merge\b", str(cmd)) or any(   # gộp thẳng (gh), không qua merge gate
                                        not SAFE_PUSH.fullmatch(seg) for seg in segs):
                                    other_merge = True
                        elif (e.get("type") == "assistant" and c.get("type") == "tool_use"
                              and re.search(r"merge|push", str(c.get("name") or ""), re.I)):   # công cụ khác (MCP GitHub: merge_pull_request, push_files)
                            other_merge = True
                        elif c.get("type") == "tool_result" and c.get("tool_use_id") in calls and not c.get("is_error"):
                            pr, want_head = calls[c["tool_use_id"]]
                            body = c.get("content")
                            if isinstance(body, list):
                                body = "\n".join(x.get("text", "") for x in body if isinstance(x, dict))
                            body = str(body or "")
                            for sha in re.findall(r"^\[merge-gate #%s\] merged ([0-9a-f]{40})\s*$" % pr, body, re.M):
                                if sha.startswith(want_head) and re.search(r"^\[merge-gate #%s\] verified green against " % pr, body, re.M):
                                    merged.append((pr, sha))
        except OSError as e:   # transcript nào (chính hay subagent) không đọc được: không chứng minh được gì
            log("merge-gate check: transcript unreadable %s: %r" % (t, e))
            return None
    if other_merge:   # lượt gộp / đẩy thẳng ngoài merge gate: bản ghi merge gate không phủ được việc đó (OCR 18/10)
        log("merge-gate check: this turn also merged or pushed outside the merge gate")
        return None
    if not merged:
        return None
    lr = origin_ls_remote(["--symref", "HEAD"], "merge-gate check")   # origin THẬT, trong hạn chót (xem origin_ls_remote)
    if lr is None:
        return None
    so, se, lrc = lr
    tip = re.search(r"^([0-9a-f]{40})\tHEAD$", so.decode("utf-8", "replace"), re.M) if lrc == 0 else None
    if not tip or git("cat-file", "-e", tip.group(1) + "^{commit}").returncode:
        log("merge-gate check: origin HEAD unreadable (%s)" % (re.sub(r"//[^@/\s]*@", "//***@", se.decode("utf-8", "replace").strip())[:120]
                                                               or "no HEAD line"))
        return None
    tip = tip.group(1)
    trunk = re.search(r"^ref: refs/heads/(\S+)\tHEAD$", so.decode("utf-8", "replace"), re.M)
    if trunk and any(re.search(r"[\s:/]%s\s*$" % re.escape(trunk.group(1)), seg) for seg in pushes):   # nhánh mặc định tên khác main/master/trunk
        log("merge-gate check: this turn pushed to origin's default branch %s" % trunk.group(1))
        return None
    hist = out(git("log", "--first-parent", "-n", "200", "--format=%H %ct %P", tip)) or ""
    landed = [(c[0], c[2]) for c in (l.split() for l in hist.splitlines())
              if len(c) == 3 and c[1].isdigit() and int(c[1]) >= start - MERGE_GATE_SKEW_S]   # một cha (squash), ghi trong lượt
    trees = {}
    gdir = out(git("rev-parse", "--path-format=absolute", "--git-common-dir"))   # #309: merge-tree runs with a scratch cwd (a killed merge driver leaves its temp files there)
    if not gdir:
        return None
    for pr, h in reversed(merged):
        if git("cat-file", "-e", h + "^{commit}").returncode:   # head của PR chưa từng fetch về đây: thử bản ghi kế tiếp
            continue
        for s, parent in landed:
            if left() <= 0:
                log("merge-gate check: out of time")
                return None
            with tempfile.TemporaryDirectory(prefix="devkit-merge-tree-") as scratch:
                r = subprocess.run(["git", "--git-dir=" + gdir, "--attr-source=" + parent, "merge-tree", "--write-tree", parent, h],
                                   capture_output=True, env=genv, cwd=scratch, timeout=max(0.5, min(10, left())))
            if r.returncode not in (0, 1):   # 1 = xung đột (không phải squash này); khác = git cũ (< 2.38) hay lỗi: nói ra, không im lặng
                log("merge-gate check: merge-tree failed (%s)" % r.stderr.decode("utf-8", "replace").strip()[:120])
                return None
            if s not in trees:
                trees[s] = out(git("rev-parse", s + "^{tree}"))
            if r.returncode or not r.stdout.split() or r.stdout.split()[0].decode() != trees[s]:
                continue
            # đứng ở H / S; hoặc main đã đi tiếp theo origin (PR phiên khác gộp sau S; lượt này không tự gộp thẳng PR nào, xem other_merge)
            if head in (h, s) or (git("merge-base", "--is-ancestor", s, head).returncode == 0
                                  and git("merge-base", "--is-ancestor", head, tip).returncode == 0):
                return "merge-gate pr=%s head=%s squash=%s" % (pr, h[:12], s[:12])
    return None

def tree_store_evidence(task=False):
    """#105 (trunk mode, 19/10: NFH, GeelyEx2, kit #104): gate --full exit 0 chạy trong worktree, giao bằng `worktree finish` hay PR squash
    rồi worktree bị gỡ: biên nhận của worktree mất theo git dir của nó, full_pass.json duy nhất của main thì cũ hoặc là của finish phiên
    khác. post-fix-gate ghi thêm biên nhận exit 0 theo cây vào <git common dir>/postfix-gate/tree_receipts (sống qua việc gỡ worktree).
    Mô tả bằng chứng khi một biên nhận ở đó ghi TRONG LƯỢT (exit 0, chưa quá TREE_RECEIPT_MAX_AGE_S) là của đúng cây phiên giao:
      (1) dấu vân tay cây đang xét = biên nhận (finish fast-forward, hay main đồng bộ origin sau squash);
      (2) chỉ main: dấu vân tay của commit HEAD (tree_fp.commit_fingerprint) = biên nhận, và file main khác HEAD phiên này không đụng
          (luật PR #50: file chưa commit của phiên khác / runner của board).
    Không nhận commit nào main có SAU cây đã gate, kể cả của phiên khác: "phiên này không đụng file" chỉ đọc được từ tool_use, mà sửa
    bằng shell / git apply / formatter sau lần gate thì không nêu tên file (principal review #105). ponytail: hai finish nối nhau (main
    nhận merge của worktree thứ hai) hay main kéo về squash của PR khác trước Stop là bị chặn (fail closed): gate lại trong worktree mới
    ở HEAD của main; nâng cấp khi đếm được ca này trong proof_gate.log.
    task=True (T0061 Pha 1, nhánh (c) trunk-finish): cùng hai luật trên kho biên nhận task <git common dir>/postfix-gate/task_receipts
    (`scope` "task", `fp` = tên file, `tested_at` trong lượt); không bao giờ có earlier-turn cho biên nhận task.
    #644: task=False đọc thêm kho scoped_receipts/ (biên nhận exit 0 của lượt gate scoped, `scope` "scoped") trong CÙNG vòng quét và cùng
    hai luật trên (một lần dirty_state / commit_fingerprint cho cả hai kho: hạn chót của hook).
    None thì chặn như cũ."""
    import session_worktree   # hooks/ (đã vào sys.path cùng devkit_harness); thiếu thì ImportError -> chặn như cũ
    import tree_fp
    tree = session_worktree.tree_of(repo)
    if start is None or not tree or not session_worktree.trunk_mode(repo) or left() <= 2:
        return None
    reserve = left() / 2   # nửa hạn chót còn lại để dành cho merged_evidence (chạy sau, cần ls-remote): không để ca merge gate hết giờ
    room = lambda: left() - reserve
    key = "fp" if task else "fingerprint"
    # (thư mục kho, nhãn log, scope mục phải mang) = tree_fp.tree_receipt_dir và anh em của nó, không chạy git
    kinds = ([("task_receipts", "task-receipt", "task")] if task else
             [("tree_receipts", "tree-receipt", "full"), (getattr(tree_fp, "SCOPED_STORE_DIR", "scoped_receipts"), "scoped-receipt", "scoped")])
    now, recs = time.time(), []
    for sub, lab, want in kinds:
        store = os.path.join(tree[2], "postfix-gate", sub)
        try:
            names = sorted(os.listdir(store))
        except OSError:
            continue
        for n in names:
            m = re.fullmatch(r"([0-9a-f]{24})\.json", n)
            if not m or room() <= 1:
                continue
            try:
                with os.fdopen(open_reg(os.path.join(store, n)), encoding="utf-8") as fh:
                    r = json.loads(fh.read(1 << 20))
            except (OSError, ValueError, RecursionError):
                continue
            t = r.get("tested_at" if task else "time") if isinstance(r, dict) else None
            if task:
                kind_ok = isinstance(r, dict) and r.get("scope") == "task" and r.get("fp") == m.group(1)
            else:   # T0061: mục scope task không phải --full; #644: mục kho scoped phải mang đúng scope "scoped"
                kind_ok = (isinstance(r, dict) and (r.get("scope", "full") == "full" if want == "full" else r.get("scope") == want)
                           and r.get("exit") == 0 and not isinstance(r.get("exit"), bool) and r.get("fingerprint") == m.group(1))
            # khoảng trước hiệu: một time 400 chữ số trừ float là OverflowError; nan / inf rơi ở so sánh
            if (kind_ok and isinstance(t, (int, float)) and not isinstance(t, bool) and start <= t <= now + 60
                    and now - t <= tree_fp.TREE_RECEIPT_MAX_AGE_S):
                recs.append((lab, r))
    if not recs:
        return None
    now_fp = FP.get("now")   # never a fresh tree_fingerprint here: it has no deadline (main clean = commit_fingerprint below, which has one)
    hit = next((lab for lab, r in recs if now_fp and r[key] == now_fp), None)
    if hit:
        return "%s fp=%s" % (hit, now_fp)
    if tree[1] or room() <= 2:
        return None
    state = dirty_state(repo, tree_fp, t=max(0.5, min(10, room() / 3)))
    if state is None or (state[1] and not untouched_by_session(state[1])) or room() <= 1:
        return None
    head_fp = tree_fp.commit_fingerprint(repo, state[0], timeout=max(0.5, min(10, room())))
    hit = next((lab for lab, r in recs if head_fp and r[key] == head_fp), None)
    if hit:
        return "%s head=%s fp=%s foreign=%s" % (hit, state[0][:12], head_fp, ",".join(state[1][:8]) or "-")
    return None

def task_receipt_ok(path, fp=None):
    """Biên nhận task ở path khi nó hợp lệ cho lượt này (scope "task", fp 24 hex (= fp nếu có), tested_at trong lượt và chưa quá
    TREE_RECEIPT_MAX_AGE_S), None nếu không. Biên nhận của lượt trước không bao giờ được nhận (khác biên nhận --full: không earlier-turn)."""
    import tree_fp
    try:
        with os.fdopen(open_reg(path), encoding="utf-8") as fh:
            r = json.loads(fh.read(1 << 16))
    except (OSError, ValueError, RecursionError):
        return None
    t, now = (r.get("tested_at") if isinstance(r, dict) else None), time.time()
    if (start is None or not isinstance(r, dict) or r.get("scope") != "task" or not isinstance(r.get("fp"), str)
            or not re.fullmatch(r"[0-9a-f]{24}", r["fp"]) or (fp is not None and r["fp"] != fp)
            or isinstance(t, bool) or not isinstance(t, (int, float)) or not (start <= t <= now + 60) or now - t > tree_fp.TREE_RECEIPT_MAX_AGE_S):
        return None
    return r

def worktree_task_evidence():
    """T0061 Pha 1, nhánh (a): worktree còn sống (linked) có task_pass.json của chính nó trong lượt, mục task_receipts/<fp>.json cùng fp
    (một lượt exit 1 trên cây đó bỏ mục này), và fp = dấu vân tay cây đang xét. None thì chặn như cũ."""
    import session_worktree
    import tree_fp
    tree = session_worktree.tree_of(repo)
    if start is None or not tree or not tree[1] or left() <= 3:
        return None
    rp = tree_fp.receipt_path(repo)
    rec = task_receipt_ok(os.path.join(os.path.dirname(rp), "task_pass.json")) if rp else None
    if not rec or not task_receipt_ok(os.path.join(tree[2], "postfix-gate", "task_receipts", rec["fp"] + ".json"), rec["fp"]):
        return None
    now_fp = FP.get("now") or tree_fp.tree_fingerprint(repo)   # full_gate_problem dừng sớm khi worktree chưa có full_pass.json
    FP["now"] = now_fp
    return "task-receipt worktree fp=%s" % now_fp if now_fp and now_fp == rec["fp"] else None

# Một đoạn lệnh `git push` đẩy nhánh PR: nhóm 1 = tên nhánh đích (đã bỏ HEAD: và refs/heads/). Chỉ tính khi SAFE_PUSH cũng nhận (đích không
# phải main / master / trunk / HEAD).
TASK_PUSH = re.compile(r"\s*(?:cd\s+\S+\s*)?git\s+(?:-C\s+\S+\s+)?push\s+(?:(?:-u|--set-upstream|-q|--quiet)\s+)*origin\s+"
                       r"(?:HEAD:)?(?:refs/heads/)?([\w./-]+)\s*")

def task_push_evidence():
    """T0061 Pha 1, nhánh (b): lượt này `git push` nhánh PR (mọi đoạn lệnh push của lượt, kể cả subagent, đều là TASK_PUSH + SAFE_PUSH, không
    công cụ merge / push nào khác: không thì fail closed), SHA nhánh đọc từ origin THẬT (origin_ls_remote; không tin refs/remotes/*,
    INSTINCT-027), commit đó có ở đây và task_receipts/<commit_fingerprint(SHA)>.json hợp lệ trong lượt; cây đang xét chỉ bẩn file phiên
    này không đụng. None thì chặn như cũ."""
    import subprocess
    import session_worktree
    import tree_fp
    tree = session_worktree.tree_of(repo)
    if start is None or not tree or left() <= 3:
        return None
    branches, bad = [], False
    tp = d.get("transcript_path") or ""
    for t in [tp] + sorted(glob.glob(os.path.join(os.path.splitext(tp)[0], "subagents", "*.jsonl"))):
        try:
            with os.fdopen(open_reg(t), encoding="utf-8", errors="replace") as f:
                for raw in f:
                    if "push" not in raw and "merge" not in raw:
                        continue
                    try:
                        e = json.loads(raw)
                        if datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp() < start:
                            continue
                    except (ValueError, AttributeError, TypeError, RecursionError):
                        continue
                    msg = e.get("message") if isinstance(e, dict) else None
                    for c in (msg.get("content") if isinstance(msg, dict) else None) or []:
                        if not isinstance(c, dict) or e.get("type") != "assistant" or c.get("type") != "tool_use":
                            continue
                        if c.get("name") != "Bash":
                            bad = bad or bool(re.search(r"merge|push", str(c.get("name") or ""), re.I))
                            continue
                        cmd = str((c.get("input") or {}).get("command", ""))
                        for seg in (s for s in re.split(r"[;&|\n]+", cmd) if re.search(r"\bpush\b", s)):
                            m = TASK_PUSH.fullmatch(seg)
                            if m and SAFE_PUSH.fullmatch(seg):
                                branches.append(m.group(1))
                            else:
                                bad = True
        except OSError as e:
            log("task-push check: transcript unreadable %s: %r" % (t, e))
            return None
    if bad or not branches:
        if bad:
            log("task-push check: this turn pushed outside a PR branch push")
        return None
    state = dirty_state(repo, tree_fp, t=max(0.5, min(10, left() / 4)))
    if state is None or (state[1] and not untouched_by_session(state[1])):
        return None
    uniq = list(dict.fromkeys(reversed(branches)))   # nhánh push sau cùng trước
    lr = origin_ls_remote(["refs/heads/" + b for b in uniq], "task-push check")
    if lr is None or lr[2] != 0:
        return None
    tips = dict((ref[len("refs/heads/"):], sha) for sha, ref in re.findall(r"^([0-9a-f]{40})\t(refs/heads/\S+)$", lr[0].decode("utf-8", "replace"), re.M))
    genv = dict(os.environ, GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull)
    store = os.path.join(tree[2], "postfix-gate", "task_receipts")
    for b in uniq:
        sha = tips.get(b)
        if not sha or left() <= 1:
            continue
        if subprocess.run(["git", "-C", repo, "cat-file", "-e", sha + "^{commit}"], capture_output=True, env=genv,
                          timeout=max(0.5, min(10, left()))).returncode:
            continue
        fp = tree_fp.commit_fingerprint(repo, sha, timeout=max(0.5, min(10, left() - 0.5)))
        if fp and task_receipt_ok(os.path.join(store, fp + ".json"), fp):
            return "task-receipt push branch=%s head=%s fp=%s" % (b, sha[:12], fp)
    return None

MERGE_RECEIPT_NAME = re.compile(r"(\d{1,9})-([0-9a-f]{40})\.json")
_HEX40 = lambda v: isinstance(v, str) and re.fullmatch(r"[0-9a-f]{40}", v) is not None

def merge_receipt_evidence():
    """27/10 (proof_gate.log của main: "task-push check: this turn pushed outside a PR branch push" rồi block): lượt gộp PR qua
    super-board-merge-gate.sh chạy NỀN (output vào file, không có dòng "merged <H>" trong tool_result: merged_evidence không thấy) và push nhánh
    PR qua pipe (`git push -u origin X 2>&1 | tail -4`: task_push_evidence tách thành "… 2>", lượt bị đánh "bad"). Không nới hai regex đó
    (INSTINCT-028); merge gate ghi biên nhận <git common dir>/postfix-gate/merge_receipts/<PR>-<head>.json (pr, head, base, verified_tree,
    squash, time, session) và đường này đọc nó. Mô tả bằng chứng khi, theo thứ tự rẻ trước:
      (1) trunk mode; một biên nhận đúng dạng ghi trong lượt có `session` khác rỗng = session_id của Stop (biên nhận của phiên);
      (2) transcript (cả subagent) không gộp thẳng trong lượt (đoạn lệnh `gh … merge`, `gh api …/pulls/N/merge`, công cụ không phải Bash
          tên có merge / push), và cả phiên không có lần ghi nào có thể vào kho (đích ghi của lệnh shell theo shell_writes.targets, đường dẫn
          đích của công cụ sửa file; nội dung sửa và `git commit -m "… merge_receipts …"` không tính: plan review T0062);
      (3) cây xét: worktree sạch, hay main chỉ bẩn file phiên này không đụng (untouched_by_session);
      (4) origin THẬT (origin_ls_remote) có trên chuỗi first-parent của nhánh mặc định một squash S của biên nhận: S đúng một cha = `base`,
          cây S = `verified_tree` (= `squash` nếu biên nhận có), và cây xét đứng ở `head` / S (hay ở commit đã review khi `head` là merge
          commit [nó, base] gate đẩy lên nhánh PR), hoặc ở một commit sau S trên chuỗi đó mà mọi
          commit từ nó lùi tới sau S cũng là squash như vậy của một biên nhận trong lượt (phiên bất kỳ). Xét theo tổ tiên, không theo giờ
          commit (GIT_COMMITTER_DATE giả được): commit đẩy thẳng lên trunk trước verify nằm trong cây gate kiểm, sau S thì không có biên nhận.
    None thì chặn như cũ.
    ponytail: biên nhận là file agent ghi được; lớp chặn ở (2) chỉ bắt lệnh nêu tên kho (một script / `bash -c '…'` / python ghi tới đường dẫn
    tính ra, hay `gh pr merge` trong `bash -c '…'`, lọt lớp này). Biên nhận giả vẫn cần một squash thật trên origin
    thật có cha = base và cây = cây khai: trần như merged_evidence (b). Nâng cấp khi biên nhận được ký hay ghi bởi tiến trình ngoài agent.
    ponytail: PR phiên khác vào trunk sau S không qua merge gate (`agent-kit integrate`, GitHub UI) thì chặn (fail-closed); nâng cấp khi
    đếm được ca này trong proof_gate.log."""
    import subprocess
    import session_worktree
    import tree_fp
    from session_authorship import read_only_tool
    if start is None or session in ("", "?") or not session_worktree.trunk_mode(repo) or left() <= 3:
        return None
    tree = session_worktree.tree_of(repo)
    if not tree:
        return None
    store, now, recs = os.path.join(tree[2], "postfix-gate", "merge_receipts"), time.time(), []
    try:
        names = sorted(os.listdir(store))
    except OSError:
        return None
    for n in names:
        m = MERGE_RECEIPT_NAME.fullmatch(n)
        if not m:
            continue
        p = os.path.join(store, n)
        try:   # chỉ file thường, không theo symlink (một link tới mount chậm treo os.open quá hạn chót của hook)
            st = os.lstat(p)
            if not stat.S_ISREG(st.st_mode) or st.st_mtime < start - 60:
                continue
            with os.fdopen(open_reg(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)), encoding="utf-8") as fh:
                r = json.loads(fh.read(1 << 16))
        except (OSError, ValueError, RecursionError):
            continue
        t = r.get("time") if isinstance(r, dict) else None
        if (isinstance(r, dict) and isinstance(r.get("pr"), int) and not isinstance(r.get("pr"), bool) and r["pr"] == int(m.group(1))
                and r.get("head") == m.group(2) and _HEX40(r.get("base")) and _HEX40(r.get("verified_tree"))
                and (r.get("squash") is None or _HEX40(r.get("squash"))) and isinstance(r.get("session"), str)
                and isinstance(t, (int, float)) and not isinstance(t, bool) and start <= t <= now + 60):
            recs.append(r)
    own = [r for r in recs if r["session"] and r["session"] == session]
    if not own or harness is None:   # devkit_harness (_shell_code) cần cho phép đọc lệnh shell dưới đây
        return None
    import shell_writes   # hooks/: cùng bộ đọc đích ghi của lệnh shell với worktree_guard / session_lock
    pg_real = os.path.realpath(os.path.dirname(store))

    def in_store(path, wd):
        """Đường dẫn (tương đối với wd) là thư mục postfix-gate chứa kho biên nhận, hay nằm trong nó."""
        if "$" in path or "`" in path:   # chưa biết nó trỏ đâu: coi như có thể vào kho
            return True
        path = os.path.expanduser(path)
        full = os.path.realpath(path if os.path.isabs(path) else os.path.join(wd, path))
        return full == pg_real or full.startswith(pg_real + os.sep)

    def bad_call(name, args, cwd, this_turn):
        """Lý do khi tool_use này gộp thẳng ngoài merge gate (chỉ xét trong lượt) hay ghi được vào kho biên nhận (cả phiên), None nếu không."""
        wd = cwd if isinstance(cwd, str) and os.path.isabs(cwd) else repo
        if name == "Bash" or name.endswith("pm_run"):   # pm_run: lệnh test của PM chạy qua shell, xét như Bash
            cmd = str(args.get("command", ""))
            if this_turn:   # đoạn lệnh (chuỗi trích dẫn, comment, heredoc bỏ đi) bắt đầu bằng gh và có từ merge; gh api …/pulls/N/merge
                code = re.sub(r"\S*super-board-merge-gate\.sh", " ", harness._shell_code(cmd)[0])
                for seg in re.split(r"[;&|\n()]+", code):
                    w = [x for x in seg.split() if not re.fullmatch(r"[A-Za-z_]\w*=\S*", x)]
                    if w and w[0] == "gh" and ("merge" in w or re.search(r"/pulls/\d+/merge\b", cmd)):
                        return "gh … merge"
            if "merge_receipts" in cmd or "postfix-gate" in cmd:   # chỉ đích GHI của lệnh (grep / cat / git commit -m "…" thì không)
                tg = shell_writes.targets(cmd, wd, run_bodies=True)   # run_bodies: thân heredoc nạp cho shell / interpreter cũng được đọc
                if tg is None:
                    return "a shell line that could not be read, naming the merge receipt store"
                for k, p, dd in tg:
                    if k in ("unparsed", "cdvar") or (k in ("redirect", "file", "interp") and in_store(str(p), dd or wd)):
                        return "a shell write that may reach the merge receipt store"
            return None
        if read_only_tool(name):
            return None
        if this_turn and re.search(r"merge|push", name, re.I) and "antigravity-pm" not in name:   # công cụ khác (MCP GitHub: merge_pull_request, push_files)
            return name
        files = [args[k] for k in ("file_path", "notebook_path", "TargetFile") if isinstance(args.get(k), str)]
        # công cụ sửa file: chỉ đường dẫn đích, không nội dung sửa (sửa chính proof_gate.sh nhắc tên kho là việc thường); công cụ khác
        # (pm_task_create, pm_plan, tạo PR / issue…) chỉ ghi chữ vào hồ sơ của chúng, không phải ghi vào kho
        return name if any(in_store(x, wd) for x in files) else None

    tp = d.get("transcript_path") or ""
    # #722: dòng `api-request-blob` (bản sao request API của Claude Code, không timestamp, không cwd; đo 30/10: 6712 dòng trên 30 transcript,
    # mọi id tool_use đều có ở một dòng `assistant` thường) từng làm cửa này đóng ở mọi phiên có nhắc tới gate. Tool_use của blob xét SAU
    # vòng đọc, theo id: id có ở một dòng assistant có giờ hợp lệ (seen) thì dòng đó đã được xét; không có mà không chỉ đọc thì chặn.
    names_store = lambda s: "merge_receipts" in s or "postfix-gate" in s
    seen, blob_uses = set(), []
    for t in [tp] + sorted(glob.glob(os.path.join(os.path.splitext(tp)[0], "subagents", "*.jsonl"))):
        try:
            with os.fdopen(open_reg(t), encoding="utf-8", errors="replace") as f:
                for raw in f:
                    if '"tool_use"' not in raw:
                        continue
                    if left() <= 0:
                        log("merge-receipt check: out of time reading the transcript")
                        return None
                    try:
                        e = json.loads(raw)
                    except (ValueError, RecursionError):
                        e = None
                    msg = e.get("message") if isinstance(e, dict) else None
                    content = msg.get("content") if isinstance(msg, dict) else None
                    uses = [c for c in content if isinstance(c, dict) and c.get("type") == "tool_use"] if isinstance(content, list) else []
                    if isinstance(e, dict) and e.get("type") == "api-request-blob":
                        if not uses and names_store(raw):   # nhắc kho mà không có tool_use đọc được: như dòng không đọc được
                            log("merge-receipt check: api-request-blob naming the store without a tool_use in %s" % t)
                            return None
                        blob_uses += [(c.get("id"), str(c.get("name") or "")) for c in uses]
                        continue
                    try:
                        ts = datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp()
                    except (ValueError, AttributeError, TypeError, RecursionError, OverflowError):
                        if names_store(raw) or not isinstance(e, dict) or (e.get("type") == "assistant" and uses):   # #722: dòng hỏng JSON / không phải object, nhắc kho, hoặc assistant có tool_use thiếu giờ: chặn
                            log("merge-receipt check: unreadable tool_use line in %s" % t)
                            return None
                        continue
                    if e.get("type") == "assistant":   # #722: chỉ dòng assistant có giờ hợp lệ đóng dấu id (chuỗi khác rỗng), kể cả lượt trước
                        seen.update(c["id"] for c in uses if isinstance(c.get("id"), str) and c["id"])
                    if ts < start and not names_store(raw):   # lượt trước: chỉ xét ghi vào kho
                        continue
                    for c in uses:
                        if e.get("type") != "assistant":
                            continue
                        why = bad_call(str(c.get("name") or ""), c.get("input") if isinstance(c.get("input"), dict) else {}, e.get("cwd"), ts >= start)
                        if why:   # gộp thẳng trong lượt, hay một lần ghi có thể vào kho biên nhận
                            log("merge-receipt check: refused by a tool call of the session (%s)" % why)
                            return None
        except OSError as e:
            log("merge-receipt check: transcript unreadable %s: %r" % (t, e))
            return None
    for cid, name in blob_uses:   # #722: fail-closed: tool_use chỉ có trong blob (không giờ, không cwd) mà không chỉ đọc
        if not (isinstance(cid, str) and cid and cid in seen) and not read_only_tool(name):
            log("merge-receipt check: api-request-blob tool_use %s (id %r) with no logged twin" % (name[:60], str(cid)[:40]))
            return None
    state = dirty_state(repo, tree_fp, t=max(0.5, min(10, left() / 4)))
    if state is None:
        return None
    head, paths = state
    if paths and (tree[1] or not untouched_by_session(paths)):
        return None
    genv = dict(os.environ, GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull)   # refs/replace, info/grafts: agent ghi được (INSTINCT-027)
    git = lambda *a: subprocess.run(["git", "-C", repo, *a], capture_output=True, env=genv, timeout=max(0.5, min(10, left())))
    lr = origin_ls_remote(["--symref", "HEAD"], "merge-receipt check")
    if lr is None:
        return None
    tip = re.search(r"^([0-9a-f]{40})\tHEAD$", lr[0].decode("utf-8", "replace"), re.M) if lr[2] == 0 else None
    if not tip or git("cat-file", "-e", tip.group(1) + "^{commit}").returncode:
        log("merge-receipt check: origin HEAD unreadable or not fetched here")
        return None
    r = git("log", "--first-parent", "-n", "200", "--format=%H %T %P", tip.group(1))
    if r.returncode:
        return None
    chain = [(c[0], c[1], c[2:]) for c in (l.split() for l in r.stdout.decode("utf-8", "replace").splitlines()) if len(c) >= 2]   # 0 = tip
    hpos = next((i for i, c in enumerate(chain) if c[0] == head), None)
    squash_of = lambda i, rec: chain[i][2] == [rec["base"]] and chain[i][1] == rec["verified_tree"]

    def at_head(rec):
        """Cây xét đứng ở head của biên nhận, hay ở commit đã review khi gate đẩy merge commit của base lên nhánh PR (head biên nhận = merge
        commit hai cha [cây xét, base], cây = cây gate kiểm): worktree của phiên vẫn ở commit cũ."""
        if head == rec["head"]:
            return True
        r = git("log", "-n", "1", "--format=%P %T", rec["head"])
        return r.returncode == 0 and r.stdout.decode("utf-8", "replace").split() == [head, rec["base"], rec["verified_tree"]]
    for rec in own:
        for i in (i for i in range(len(chain)) if squash_of(i, rec) and rec["squash"] in (None, chain[i][0])):
            s = chain[i][0]
            # mọi commit trên origin từ đỉnh tới ngay sau S phải là squash có biên nhận: một commit đẩy thẳng sau S (không qua gate) chặn
            # cả ba đường, kể cả khi cây xét còn ở H / S (plan review T0062)
            if not all(any(squash_of(j, x) for x in recs) for j in range(i)):
                log("merge-receipt check: origin has a commit without a merge receipt after squash %s" % s[:12])
                continue
            if head == s or at_head(rec) or (hpos is not None and hpos < i):
                return "merge-receipt pr=%s head=%s squash=%s" % (rec["pr"], rec["head"][:12], s[:12])
            log("merge-receipt check: HEAD %s is not at/after squash %s" % (head[:12], s[:12]))
    return None

gate_problem = full_gate_problem() if xong else None
if gate_problem:
    try:
        alt = tree_store_evidence()
    except Exception as e:   # TimeoutExpired, OSError…: python chết = wrapper exit 0 = XONG lọt; lỗi ở đây = sang bằng chứng kế tiếp
        log("tree-store check crashed: %r" % e)
        alt = None
    # T0061 Pha 1: biên nhận task của lượt — (a) worktree còn sống, (c) trunk-finish; (b) push nhánh PR (cần ls-remote) chạy sau merged_evidence
    for _name, _check in (("task-worktree", worktree_task_evidence), ("task-store", lambda: tree_store_evidence(task=True)),
                          ("merge-receipt", merge_receipt_evidence), ("merged-evidence", merged_evidence), ("task-push", task_push_evidence)):
        if alt:
            break
        try:
            alt = _check()
        except Exception as e:   # python chết = wrapper exit 0 = XONG lọt; lỗi ở đây = sang bằng chứng kế tiếp / chặn như cũ
            log("%s check crashed: %r" % (_name, e))
            alt = None
    if alt:
        log("pass-gate session=%s %s (receipt: %s)" % (session, alt, gate_problem))
        gate_problem = None
need_image, scope = xong, "unknown" if xong else "push turn: report only"
if xong:
    try:
        import tree_fp
        need_image, scope = tree_fp.image_required(repo, start)
    except Exception as e:  # an unreadable scope must never waive the image
        scope = "scope check failed: %s" % e

def first_app_source_edit_time(tp):
    if not start: return None
    try:
        import tree_fp
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if '"tool_use"' not in raw: continue
                try:
                    e = json.loads(raw)
                    t = datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp()
                except (ValueError, AttributeError, TypeError): continue
                if t < start: continue
                for c in (e.get("message") or {}).get("content") or []:
                    if not isinstance(c, dict) or c.get("type") != "tool_use": continue
                    args = c.get("input") or {}
                    if not isinstance(args, dict): continue
                    paths = []
                    # ponytail: sua qua shell (sed -i, >, tee) khong thay duoc nen kiem thu tu mtime bi bo qua cho lan sua do; parse tu khoa ghi cua lenh khi mot luot chi sua qua shell
                    if "TargetFile" in args and isinstance(args["TargetFile"], str):
                        paths.append(args["TargetFile"])
                    if "file_path" in args and isinstance(args["file_path"], str):
                        paths.append(args["file_path"])
                    if "notebook_path" in args and isinstance(args["notebook_path"], str):
                        paths.append(args["notebook_path"])
                    for p in paths:
                        try:
                            abs_p = os.path.realpath(p if os.path.isabs(p) else os.path.join(repo, p))
                            abs_repo = os.path.realpath(repo)
                            rel = os.path.relpath(abs_p, abs_repo)
                        except ValueError: continue
                        if rel.startswith(".."): continue
                        if not tree_fp._off_screen(rel): 
                            return t
    except Exception as e: log("first_edit lookup failed: %s" % e)
    return None
if xong and need_image and os.environ.get("PROOF_BEFORE", "1") != "0":
    try:
        tc_path = os.path.join(os.environ.get("PROOF_BASE_LOG_DIR") or log_dir, "turn_class_%s.json" % (re.sub(r"[^A-Za-z0-9_-]", "_", session)[:64] or "default"))
        try:
            with os.fdopen(open_reg(tc_path), encoding="utf-8") as f:
                tc = json.load(f)
            if not isinstance(tc, dict):
                raise ValueError("not dict")
            raw_ts = tc.get("ts", 0)
            if not isinstance(raw_ts, (int, float)) or __import__('math').isnan(raw_ts) or __import__('math').isinf(raw_ts):
                raise ValueError("ts not finite number")
            tc_ts = float(raw_ts)
            raw_intents = tc.get("intents", [])
            if not isinstance(raw_intents, list) or not all(isinstance(x, str) for x in raw_intents):
                raise ValueError("intents not string list")
            tc_intents = set(raw_intents)
        except (OSError, ValueError, RecursionError):
            tc_ts = 0
            tc_intents = set()
        
        if start and tc_ts >= start - 30 and "BUG_FIX" in tc_intents and "UI_INTERACTION" in tc_intents:
            waived_before = re.search(r"before:\s*không cần\s*—\s*(.+)", reply, re.I)
            if not waived_before:
                before_cited = sorted(set(re.findall(r"(?:[\w./-]*/)?reports/before-\d{8}-\d{6}\.(?:png|txt|xml)", reply)))
                if not before_cited:
                    before_problems.append("BEFORE EVIDENCE: thiếu báo cáo trạng thái trước khi sửa (reports/before-... hoặc `before: không cần — <lý do>`)")
                else:
                    first_edit = first_app_source_edit_time(d.get("transcript_path") or "")
                    for rel in before_cited:
                        path = rel if os.path.isabs(rel) else os.path.join(repo, rel)
                        if not os.path.isfile(path):
                            before_problems.append("BEFORE %s: không có file này" % rel)
                            continue
                        try:
                            st = os.stat(path)
                        except OSError as e:
                            before_problems.append("BEFORE %s: không đọc được (%s)" % (rel, e))
                            continue
                        if st.st_size <= 0:
                            before_problems.append("BEFORE %s: 0 byte không phải bằng chứng" % rel)
                            continue
                        if path.endswith(".png"):
                            try:
                                with open(path, "rb") as f:
                                    head = f.read(8)
                                if head != PNG_SIG:
                                    before_problems.append("BEFORE %s: không phải định dạng PNG hợp lệ (sai chữ ký)" % rel)
                                    continue
                            except OSError as e:
                                before_problems.append("BEFORE %s: không đọc được (%s)" % (rel, e))
                                continue
                        if first_edit is not None and st.st_mtime >= first_edit:
                            before_problems.append("BEFORE %s: phải chụp TRƯỚC lần sửa app source đầu tiên lúc %s, nhưng file tạo lúc %s" % (rel, datetime.datetime.fromtimestamp(first_edit).strftime("%H:%M:%S"), datetime.datetime.fromtimestamp(st.st_mtime).strftime("%H:%M:%S")))
                            continue
    except Exception as e:
        log("before check failed: %s" % e)

# A cited PNG is always checked: a waived image never excuses a bogus one.
if not gate_problem and (good or not need_image) and not problems and not missing_report and not before_problems:
    log("pass session=%s proof=%s scope=%s" % (session, ",".join(good) or "-", scope))
    sys.exit(0)

state = {}
try:
    with os.fdopen(open_reg(state_path), encoding="utf-8") as fh:
        state = json.load(fh)
except (OSError, ValueError, RecursionError):
    state = {}
# per turn: a release never switches the gate off for later turns. No turn start (peer-only session, no transcript):
# one budget per hour, not one constant key (`session@0`) spent once and then letting every later XONG through.
key = "%s@%s" % (session, "h%d" % int(time.time() // 3600) if start is None else int(start or 0))
n = state.get(key, 0) + 1
state[key] = n
try:
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix=".tmp_proof_state.", dir=os.path.dirname(state_path))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False)
    os.replace(tmp, state_path)
except OSError:
    pass

# Short and actionable (GeelyEx2 2026-09-28: 45 blocks of long prose): what is missing, one line
# each, and for a missing report the exact skeleton to paste.
SKELETON = "1. Đã fix gì: …\n2. Chặn bug cũ: …\n3. Nguy cơ bug mới: …\n4. An toàn mã nguồn: …"
short = lambda t, n: t if len(t) <= n else t[:n - 1] + "…"
def format_scope(s, max_len=55):
    if len(s) <= max_len:
        return s
    prefix = "may show on screen: "
    if s.startswith(prefix):
        parts = [os.path.basename(p.strip()) for p in s[len(prefix):].split(",") if p.strip()]
        compacted = prefix + ", ".join(parts)
        if len(compacted) <= max_len:
            return compacted
    return s[:max_len - 1] + "…"
lines = ["⛔ PROOF-GATE: " + ("XONG còn thiếu:" if xong else "lượt này đã git push (bàn giao) nhưng thiếu:")]
if missing_report:
    lines.append("- Báo cáo 4 mục (thiếu %s) — dán vào cuối:" % ",".join(n[0] for n in missing_report))
    lines.append(SKELETON)
if gate_problem:
    try:   # #722: ở main trunk mode session_lock cấm chạy gate; bản cài copy-mode thiếu session_worktree.py: lời cũ (không bao giờ crash = exit 0)
        import session_worktree
        _tr = session_worktree.tree_of(repo)
        _trunk_main = bool(_tr and not _tr[1] and session_worktree.trunk_mode(repo))
    except Exception:
        _trunk_main = False
    if _trunk_main:   # worktree sạch ở HEAD: --full / impacted là exit 3 "không có thay đổi"; --tree HEAD từ chối settings.json do kit sửa
        lines.append("- Cổng: " + gate_problem + " → main ở trunk mode: không gate ở đây (session_lock chặn). Worktree tạm ở HEAD main, sạch cả"
                     " .claude/settings.json (git checkout -- .claude/settings.json nếu kit đã sửa) → python3 .agents/devkit/bin/post-fix-gate.py"
                     " --run-tests --tree HEAD --brief (--tree HEAD = --full trên cây HEAD) → gỡ worktree, Stop lại")
    else:
        lines.append("- Cổng: " + gate_problem + " → python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief (scoped; --full chỉ ở gate-full đêm 00:00)")
for bp in before_problems:
    lines.append("- " + bp)
if problems or (not good and need_image):
    if cited:
        lines += ["- ẢNH " + short(p, 120) for p in problems]
    else:
        lines.append("- ẢNH (%s): nêu reports/proof-<yyyyMMdd-HHmmss>.png + serial ở dòng 3" % format_scope(scope, 55))
if need_image:
    lines.append("Chụp: python3 .agents/devkit/bin/proof-capture.py; lỗi → CHƯA XONG + dán lỗi.")
# why it blocked, so a block can be told from another (Office 2026-10-12: 14 blocks, one line each, no reason)
log("block session=%s attempt=%d cited=%s gate=%s report=%s before=%d image=%s" % (
    session, n, ",".join(cited) or "-", gate_problem or "ok", ",".join(m[0] for m in missing_report) or "ok",
    len(before_problems), "need" if (problems or (not good and need_image)) else "ok"))
if n > max_blocks:
    msg = "\n".join(lines + ["(Đã chặn %d lần — cho dừng để không kẹt phiên. Câu trả lời này THIẾU điều kiện ở trên; người dùng cần xem lại.)" % max_blocks])
    print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
    sys.exit(0)
print("\n".join(lines), file=sys.stderr)
sys.exit(2)
PY
rc=$?
[ "$rc" = 2 ] && exit 2
exit 0
