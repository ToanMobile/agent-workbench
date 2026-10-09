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
#     matches the code — an edit after the gate run voids it;
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
# toàn mã nguồn (English labels accepted). A push turn is checked for the report only.
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
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
[ -n "${REPO_ROOT}" ] || exit 0
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}" 2>/dev/null
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

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
PROOF_REPO="${REPO_ROOT}" PROOF_LOG_DIR="${LOG_DIR}" PROOF_HOOKDIR="$(dirname "${SELF}")" \
PROOF_BIN="$(cd "$(dirname "${SELF}")/../bin" 2>/dev/null && pwd)" python3 -I <<'PY' 3<<<"${INPUT}"
import datetime, glob, hashlib, json, math, os, re, sys, time

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
REPORT_ITEMS = (("1. Đã fix gì (tên lỗi, nguyên nhân gốc, RED→GREEN)", r"đã\s+(fix|sửa)\s*(gì|:)|what\s+was\s+fixed"),
                ("2. Chặn bug cũ (test hồi quy / immutable_guards chạy lại PASS)", r"bug\s+cũ|reopened"),
                ("3. Nguy cơ bug mới (caller, module liên đới đã rà)", r"bug\s+mới|collateral"),
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
        with open(p, "rb") as f: return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None

def pushed_in_turn(tp):
    """True when a Bash call of this turn (after the last user prompt) ran `git push` that did not
    visibly fail. A push is what devkit_harness.git_writes reads as one — the classifier
    work_in_progress (regression_gate, review_gate) uses too: a real `git push` command, not the
    words in a heredoc body, a string, `git stash push` or a --dry-run. Without the helper (a hook
    copied alone) no push is detected."""
    if harness is None:
        log("push check skipped: devkit_harness not loaded")
        return False
    pushes = {}   # tool_use id -> True (went through or unknown) / False (failed)
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if "push" not in raw and not any(i in raw for i in pushes):
                    continue          # most lines: no JSON parse on every Stop
                try:
                    e = json.loads(raw)
                    t = datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp()
                except (ValueError, AttributeError):
                    continue
                if start is None or t < start:
                    continue
                for c in (e.get("message") or {}).get("content") or []:
                    if not isinstance(c, dict):
                        continue
                    if e.get("type") == "assistant" and c.get("type") == "tool_use":
                        cmd = (c.get("input") or {}).get("command", "")
                        if "push" in harness.git_writes(cmd):
                            pushes[c.get("id") or "no-id-%d" % len(pushes)] = True
                    elif c.get("type") == "tool_result" and c.get("tool_use_id") in pushes:
                        body = c.get("content")
                        if isinstance(body, list):
                            body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                        body = str(body or "")
                        # went out = a ref line, even if a later ref or command failed; a background
                        # push usually completes. Only a failure with nothing sent is no handover.
                        failed = (bool(c.get("is_error")) or bool(PUSH_FAILED.search(body))) \
                            and not PUSH_WENT.search(body) and "running in background" not in body
                        pushes[c["tool_use_id"]] = not failed
    except OSError:
        pass
    return any(pushes.values())

if not xong and not (missing_report and pushed_in_turn(d.get("transcript_path") or "")):
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
    try:
        rec = json.load(open(rp, encoding="utf-8")) if rp else None
    except (OSError, ValueError):
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
    now_fp = tree_fp.tree_fingerprint(repo)
    if not now_fp or not rec.get("fingerprint"):
        why = getattr(tree_fp.tree_fingerprint, "error", "") or "?"
        return "không tính được dấu vân tay code hiện tại (%s)" % str(why)[:60]
    if rec.get("fingerprint") != now_fp:
        return "code đã đổi sau lần exit 0"
    return None

gate_problem = full_gate_problem() if xong else None
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
        tc_path = os.path.join(repo, ".claude", "audit-gate", "turn_class_%s.json" % (re.sub(r"[^A-Za-z0-9_-]", "_", session)[:64] or "default"))
        try:
            with open(tc_path, encoding="utf-8") as f:
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
        except (OSError, ValueError):
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
    with open(state_path, encoding="utf-8") as fh:
        state = json.load(fh)
except (OSError, ValueError):
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
log("block session=%s attempt=%d cited=%s gate=%s" % (session, n, ",".join(cited) or "-", gate_problem or "ok"))
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
