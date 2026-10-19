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
#     matches the code — an edit after the gate run voids it (trunk mode, 17/10: a receipt `worktree finish` carried into main for
#     main's HEAD, of a clean tree, still holds when the only differing files are dirty in main and named by no editing tool call of
#     this session: other sessions' / the board runner's files, foreign_dirty_only); trunk mode, 18/10: without such a receipt the turn
#     still passes on (a) a --full exit 0 receipt a worktree of the repo wrote this turn, still matching that worktree, for the same tree
#     as the judged HEAD, or (b) the output of a super-board-merge-gate.sh call this turn ("verified green" + "merged <H>") when git
#     attests it: the real origin (ls-remote) holds a squash of H committed this turn and the judged tree stands at H or holds it with
#     nothing origin lacks (merged_evidence; tests/gates/test_proof_gate_merged_trunk.sh); #105, 19/10: or (c) a --full exit 0 receipt of
#     this turn that post-fix-gate mirrored by tree into <git common dir>/postfix-gate/tree_receipts (it outlives the worktree), for the
#     judged tree, or in main for HEAD's commit when only other sessions' uncommitted files differ (tree_store_evidence;
#     tests/gates/test_proof_gate_tree_receipt.sh);
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
    """None when this turn has a full-gate exit 0 on the current code, else the reason."""
    _pb = os.environ.get("PROOF_BIN") or ""
    if os.path.isabs(_pb):   # "" (copy-mode install: no ../bin) would put the cwd first on sys.path again and undo -I
        sys.path.insert(0, _pb)
    try:
        import tree_fp
    except ImportError:
        return "không tìm thấy bin/tree_fp.py của DevKit"
    rp = tree_fp.receipt_path(repo)
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
        return "receipt hỏng (full_pass.json không phải object JSON)"
    if rec.get("exit") != 0:
        return "chưa có exit 0 trên code hiện tại"
    rtime = rec.get("time", 0)
    # A wrong-shaped receipt used to crash this function: python exit 1, the wrapper turns it into exit 0, XONG passes.
    # An int is finite, but math.isfinite raises OverflowError on 10**400, and a 400-digit time is not a timestamp.
    # A real receipt time is a unix epoch (well under 10**12, year 33658). Negative is not one either.
    if (isinstance(rtime, bool) or not isinstance(rtime, (int, float))
            or (isinstance(rtime, float) and not math.isfinite(rtime))
            or rtime < 0 or rtime > 10 ** 12):
        return "receipt hỏng (full_pass.json: time không phải số)"
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
    if rtime < turn_start_time:
        return "lần exit 0 là từ trước lượt này"
    now_fp = FP["now"] = tree_fp.tree_fingerprint(repo)   # tree_store_evidence dùng lại: không tính dấu vân tay hai lần trong hạn chót
    if not now_fp or not rec.get("fingerprint"):
        why = getattr(tree_fp.tree_fingerprint, "error", "") or "?"
        return "không tính được dấu vân tay code hiện tại (%s)" % str(why)[:60]
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
    excluded = lambda p: any(p == ex or p.startswith(ex + "/") for ex in tree_fp.EXCLUDE)
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

def untouched_by_session(paths):
    """True khi không tool_use không chỉ đọc nào của phiên (kể cả subagent) nhắc tới một trong `paths` (tương đối với repo đang xét);
    False khi có, hoặc khi một transcript không đọc được (không chứng minh được gì)."""
    from session_authorship import read_only_tool   # bin/ (PROOF_BIN, đã vào sys.path): cùng danh sách công cụ chỉ đọc với các hook khác
    root = os.path.realpath(repo)
    targets = {os.path.join(root, p) for p in paths} | {os.path.realpath(os.path.join(root, p)) for p in paths}   # cả hai phía qua realpath: file bẩn là symlink
    tp = d.get("transcript_path") or ""
    # ponytail: lệnh shell chỉ bị bắt khi nhắc đúng đường dẫn tương đối (glob `docs/*.md` hay `cd docs && …` lọt), không parse shell
    # (INSTINCT-045); lớp chặn chính là session_lock (trunk mode từ chối mọi lần ghi vào main), đây là lớp thứ hai. Nâng cấp khi một
    # phiên sửa được file bẩn của main mà không nêu tên nó.
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
                            if any(p in text or json.dumps(p, ensure_ascii=False)[1:-1] in text for p in paths):   # cả dạng JSON escape (", \)
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
    # (a) biên nhận của worktree anh em (cùng .git, như bin/post-fix-gate.py cached_full_pass mượn)
    for rp in sorted(glob.glob(os.path.join(tree[2], "worktrees", "*", "postfix-gate", "full_pass.json"))):
        if left() <= 3:   # mỗi biên nhận một lần tính dấu vân tay (không cắt giữa chừng được): repo lớn, nhiều worktree
            log("worktree-receipt check: out of time")
            return None
        try:
            with os.fdopen(open_reg(rp), encoding="utf-8") as fh:
                rec = json.loads(fh.read(1 << 20))
        except (OSError, ValueError, RecursionError):
            continue
        if not isinstance(rec, dict) or rec.get("exit") != 0 or rec.get("carried_from") or not isinstance(rec.get("project"), str):
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
        return "worktree-receipt %s head=%s" % (proj, wst[0][:12])
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
    # origin THẬT: URL sau insteadOf (`--get-url`) phải là GitHub (GITHUB_URL), không phải đường dẫn hay file: / ext:: / fd:: (`git config
    # remote.origin.url .` biến ls-remote thành đọc chính repo này, principal review 18/10). ls-remote chạy NGOÀI repo, không đọc config
    # nào agent ghi được (repo / global / system: core.sshCommand, http.proxy, sslVerify, insteadOf đều có thể dựng một origin giả, OCR
    # 18/10), ssh ép BatchMode, git chỉ được dùng https / ssh. PROOF_GATE_ALLOW_LOCAL_ORIGIN=1 (môi trường của hook, như PROOF_GATE=0;
    # test dùng origin cục bộ) nhận cả đường dẫn.
    local_ok = os.environ.get("PROOF_GATE_ALLOW_LOCAL_ORIGIN") == "1"
    url = out(git("ls-remote", "--get-url", "origin")) or ""
    if local_ok and url and not GITHUB_URL.fullmatch(url) and "://" not in url and "::" not in url:
        url = os.path.normpath(os.path.join(repo, url))
    elif not GITHUB_URL.fullmatch(url):
        log("merge-gate check: origin is not a GitHub remote (%r)" % re.sub(r"//[^@/\s]*@", "//***@", url)[:80])   # token trong URL
        return None
    budget = min(5.0, left() - 1)   # mạng chậm / ssh chờ: quá hạn chót của hook = Claude Code giết hook = Stop lọt
    if budget < 1:
        log("merge-gate check: no time left for ls-remote")
        return None
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_TERMINAL_PROMPT="0", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=4")
    proto = ["-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "protocol.ssh.allow=always"] \
        + (["-c", "protocol.file.allow=always"] if local_ok else [])
    p = subprocess.Popen(["git", *proto, "ls-remote", "--symref", url, "HEAD"], cwd="/", stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, start_new_session=True)
    try:
        so, se = p.communicate(timeout=budget)
    except subprocess.TimeoutExpired:   # cả nhóm tiến trình (ssh con giữ ống thì communicate chờ mãi)
        os.killpg(p.pid, 9)
        p.communicate()
        log("merge-gate check: ls-remote timed out after %.1fs" % budget)
        return None
    tip = re.search(r"^([0-9a-f]{40})\tHEAD$", so.decode("utf-8", "replace"), re.M) if p.returncode == 0 else None
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
    for pr, h in reversed(merged):
        if git("cat-file", "-e", h + "^{commit}").returncode:   # head của PR chưa từng fetch về đây: thử bản ghi kế tiếp
            continue
        for s, parent in landed:
            if left() <= 0:
                log("merge-gate check: out of time")
                return None
            r = git("merge-tree", "--write-tree", parent, h)
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

def tree_store_evidence():
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
    None thì chặn như cũ."""
    import session_worktree   # hooks/ (đã vào sys.path cùng devkit_harness); thiếu thì ImportError -> chặn như cũ
    import tree_fp
    tree = session_worktree.tree_of(repo)
    if start is None or not tree or not session_worktree.trunk_mode(repo) or left() <= 2:
        return None
    reserve = left() / 2   # nửa hạn chót còn lại để dành cho merged_evidence (chạy sau, cần ls-remote): không để ca merge gate hết giờ
    room = lambda: left() - reserve
    store, now, recs = os.path.join(tree[2], "postfix-gate", "tree_receipts"), time.time(), []   # = tree_fp.tree_receipt_dir, không chạy git
    try:
        names = sorted(os.listdir(store))
    except OSError:
        return None
    for n in names:
        m = re.fullmatch(r"([0-9a-f]{24})\.json", n)
        if not m or room() <= 1:
            continue
        try:
            with os.fdopen(open_reg(os.path.join(store, n)), encoding="utf-8") as fh:
                r = json.loads(fh.read(1 << 20))
        except (OSError, ValueError, RecursionError):
            continue
        t = r.get("time") if isinstance(r, dict) else None
        # khoảng trước hiệu: một time 400 chữ số trừ float là OverflowError; nan / inf rơi ở so sánh
        if (isinstance(r, dict) and r.get("exit") == 0 and not isinstance(r.get("exit"), bool) and r.get("fingerprint") == m.group(1)
                and isinstance(t, (int, float)) and not isinstance(t, bool) and start <= t <= now + 60 and now - t <= tree_fp.TREE_RECEIPT_MAX_AGE_S):
            recs.append(r)
    if not recs:
        return None
    now_fp = FP.get("now")   # never a fresh tree_fingerprint here: it has no deadline (main clean = commit_fingerprint below, which has one)
    if now_fp and any(r["fingerprint"] == now_fp for r in recs):
        return "tree-receipt fp=%s" % now_fp
    if tree[1] or room() <= 2:
        return None
    state = dirty_state(repo, tree_fp, t=max(0.5, min(10, room() / 3)))
    if state is None or (state[1] and not untouched_by_session(state[1])) or room() <= 1:
        return None
    head_fp = tree_fp.commit_fingerprint(repo, state[0], timeout=max(0.5, min(10, room())))
    if head_fp and any(r["fingerprint"] == head_fp for r in recs):
        return "tree-receipt head=%s fp=%s foreign=%s" % (state[0][:12], head_fp, ",".join(state[1][:8]) or "-")
    return None

gate_problem = full_gate_problem() if xong else None
if gate_problem:
    try:
        alt = tree_store_evidence()
    except Exception as e:   # TimeoutExpired, OSError…: python chết = wrapper exit 0 = XONG lọt; lỗi ở đây = sang bằng chứng kế tiếp
        log("tree-store check crashed: %r" % e)
        alt = None
    try:
        alt = alt or merged_evidence()
    except Exception as e:   # python chết = wrapper exit 0 = XONG lọt; lỗi ở đây = chặn như cũ
        log("merged-evidence check crashed: %r" % e)
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
    lines.append("- Cổng: " + gate_problem + " → python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief (bị hoãn: --force-full)")
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
