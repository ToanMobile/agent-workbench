#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# regression_gate.sh — Stop hook: the living regression checklist must be green
# for everything the current change touches before the agent may finish.
#
# Runs `post-fix-gate.py --run-tests --task <session>` when there are uncommitted
# changes. The gate re-runs every regression test whose watch_files match the
# change, records real PASS/FAIL into .agents/CHECKLIST.md (via the checklist JSON), and refuses
# PASS for changed source files no test watches (UNCOVERED).
#
# BLOCK (exit 2, reason → Claude) when the gate says REJECT (exit 1) or
# UNVERIFIED (exit 2): a related test fails, a changed file has no test, …
#
# Enforced for a project that has adopted a matrix: .agents/regression_matrix.active.json
# (what `agent-kit profile` writes) or a legacy templates/ matrix, whose content differs
# from every DevKit sample (templates/ + profiles/*) or that says "adopted": true (then
# even a byte-identical copy of a sample is enforced). Sample matrices name placeholder
# tests that do not exist in a real project — enforcing them would trap every session.
# A profile matrix marked "enforce_as_is": true (web, backend: they auto-detect the
# project's own runner) is enforced as installed. Without an adopted matrix the hook
# does not block: a sample matrix (e.g. no runner detected: Unity) and a DevKit gate it
# cannot find are each reported once per session (systemMessage) and logged.
#
# An adopted matrix the gate does not trust because it is UNCOMMITTED (and shadows no
# committed matrix), with nothing else wrong: no test ran and only a commit (a human
# decision, not the agent's) can make it trusted, so the stop is allowed with a
# systemMessage once per change — the same deal as UNTESTED. An edited COMMITTED
# matrix still blocks: that is the `exit 1` -> `true` shape.
#
# REGRESSION_GATE_PROBE=1: print one JSON line with the matrix state the Stop gate would
# see ({"state": none|sample|outside|untrusted|trusted|nogate|disabled, …}) and exit 0 —
# read-only, runs no test. session_context.sh reports it at session start.
#
# Cheap when nothing changed: the result is cached per working-tree fingerprint,
# so a second Stop on the same diff does not re-run the tests. A block is re-used too: when
# this session's previous Stop blocked on the same content (tree incl. untracked contents +
# unverified range), the stored reason is returned without running the gate (GeelyEx2,
# 2026-09-28: 100 of 214 blocks re-ran the suites on unchanged content). Not re-used: a block
# with an edited existing test (cleared by the user's answer, not by the tree) or a BUSY item.
# The reminder that follows such an edit ("waiting for a person to review the test diff", never a block)
# is re-used by the SAME session on the same content AND the same approval sources (bin/approval_digest.py: the
# ledger, approved_hashes.json, the antigravity-pm audit records the ledger and trailers name, the answers of the user
# that name a changed file, the trunk tip), without running the gate (OfficeReader 2026-10-08: 58 of 71 Stop runs,
# 31-37 s each; 03/11: 36 repeats a day after the old 300 s window ran out, ~47 s each). Ceiling: REGRESSION_GATE_TOUCHED_RECHECK_S
# when set, else DEVKIT_GATE_CACHE_MAX_S (default 21600 s); 0 = run the gate on every Stop. A BUSY suite, another session,
# other content, a new commit, a moved approval source or a digest that cannot be computed never re-use it.
# REGRESSION_GATE_TOUCHED_RECHECK_S=0 runs the GATE on every Stop (the answer of the user and the verdict are judged again) but it does not start a
# suite that already passed on the same content: the gate keeps the suites a Stop run passed (budget_pass.json, bin/post-fix-gate.py) and the next
# run on identical inputs re-uses them, for DEVKIT_GATE_CACHE_MAX_S seconds (default 259200, i.e. 3 days, as the receipt). A suite that starts to fail on unchanged
# content is therefore not seen until that record ages out or the content changes; only DEVKIT_GATE_CACHE=0 (the gate's own switch, not this hook's)
# makes every run start every suite again.
# Loop-guard: MAX_ATTEMPTS blocks per fingerprint, then the stop is allowed with a
# visible warning (systemMessage) — a broken test can never trap the session.
# Non-Claude agent or no usable Claude transcript ("degraded", hooks/devkit_harness.py:
# Grok, a bridged agent, a caller that sends no transcript): the diff of such an agent
# changes every turn, so the per-fingerprint guard alone never released it (Grok,
# 2026-09-25: 11 blocks in one morning). There the guard is also keyed per SESSION
# (session_id / sessionId / GROK_SESSION_ID; else harness pid + transcript path or cwd):
# at most REGRESSION_GATE_MAX_SESSION_BLOCKS (default 3) blocks per session — a pass
# resets it — then every stop is allowed with a systemMessage that says the gate is still
# not green; and the suite runs once per unchanged tree per session (its last result is
# re-used). Grok's observe-only session-end Stop (reason ≠ end_turn) runs nothing. A
# Claude session with its transcript keeps the per-fingerprint guard only. State is
# written atomically (sessions share regression_gate.state.json).
# Escape hatch: REGRESSION_GATE=0 (logged). Fail-open on internal error.
#
# Stop hook protocol: stdin JSON; exit 2 blocks (stderr→Claude); exit 0 allows.
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
BASE_ROOT="${REPO_ROOT}"   # bash_write_ledger.sh writes bash_write_ledger.tsv under it, whatever tree is judged below
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
[ -n "${REPO_ROOT}" ] || { [ "${REGRESSION_GATE_PROBE:-0}" = "1" ] && printf '%s\n' '{"state":"disabled"}'; exit 0; }
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
PROBE="${REGRESSION_GATE_PROBE:-0}"
if [ "${PROBE}" != "1" ]; then  # the probe writes nothing
  mkdir -p "${LOG_DIR}" 2>/dev/null || exit 0
  for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
  [ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
fi
LOG="${LOG_DIR}/regression_gate.log"

if [ "${REGRESSION_GATE:-1}" = "0" ]; then
  [ "${PROBE}" = "1" ] && { printf '%s\n' '{"state":"disabled"}'; exit 0; }
  echo "$(date +%Y-%m-%dT%H:%M:%S) skipped: REGRESSION_GATE=0" >> "${LOG}"
  exit 0
fi
command -v python3 >/dev/null 2>&1 || exit 0
git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# #528: worker của board không chấm main. Worktree liên kết vẫn chạy. Probe vẫn in trạng thái.
if [ "${SB_BOARD_WORKER:-}" = "1" ] && [ "${PROBE}" != "1" ] && python3 -I -c 'import os,sys
_d = os.path.dirname(os.path.realpath(sys.argv[1]))
if os.path.isabs(_d): sys.path.append(_d)
import session_worktree as s
raise SystemExit(0 if s.worker_skip_main(sys.argv[2]) else 1)' "$0" "${REPO_ROOT}"; then
  echo "$(date +%Y-%m-%dT%H:%M:%S) SB_BOARD_WORKER skip main" >> "${LOG}"
  exit 0
fi

# Locate the DevKit: this script's real path (symlink install), else `postfix-gate` on PATH.
SELF="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null)"
GATE="$(dirname "$(dirname "${SELF}")")/bin/post-fix-gate.py"
if [ ! -f "${GATE}" ]; then
  PG="$(command -v postfix-gate 2>/dev/null || true)"
  [ -n "${PG}" ] && GATE="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${PG}")"
fi
# Copy-mode installs have no link back to the DevKit: try $DEVKIT_ROOT and the
# quick-install location too.
for cand in "${DEVKIT_ROOT:-}/bin/post-fix-gate.py" "${HOME}/.universal-agent-devkit/bin/post-fix-gate.py"; do
  [ -f "${GATE}" ] && break
  [ -f "${cand}" ] && GATE="${cand}"
done
if [ ! -f "${GATE}" ]; then
  [ "${PROBE}" = "1" ] && { printf '%s\n' '{"state":"nogate"}'; exit 0; }
  echo "$(date +%Y-%m-%dT%H:%M:%S) skipped: post-fix-gate.py not found" >> "${LOG}"
  SID="$(printf '%s' "${INPUT}" | python3 -I -c 'import json,re,sys
try: print(re.sub(r"[^A-Za-z0-9_-]", "_", str(json.load(sys.stdin).get("session_id") or ""))[:40])
except Exception: print("")' 2>/dev/null)"
  FLAG="${LOG_DIR}/regression_gate.notfound.${SID:-nosession}"
  if [ ! -e "${FLAG}" ]; then
    : > "${FLAG}" 2>/dev/null
    printf '%s\n' '{"systemMessage":"⚠ regression_gate: không tìm thấy post-fix-gate.py (cài copy mode?) — test hồi quy KHÔNG được chạy khi dừng. Chạy `agent-kit install-global` hoặc đặt DEVKIT_ROOT=<thư mục DevKit>."}'
  fi
  exit 0
fi

printf '%s' "${INPUT}" | REPO_ROOT="${REPO_ROOT}" LEDGER_ROOT="${BASE_ROOT}" GATE="${GATE}" LOG="${LOG}" PROBE="${PROBE}" \
  MAX_ATTEMPTS="${REGRESSION_GATE_MAX_ATTEMPTS:-2}" MAX_SESSION_BLOCKS="${REGRESSION_GATE_MAX_SESSION_BLOCKS:-3}" \
  HOOK_PPID="${PPID}" HOOK_DIRS="$(dirname "${SELF}"):$(dirname "$0")" HOOK_SELF="${SELF}" python3 -I -c '
import contextlib, copy, errno, fcntl, fnmatch, glob, hashlib, io, json, os, re, subprocess, sys, tempfile, time

repo, gate, log = os.environ["REPO_ROOT"], os.environ["GATE"], os.environ["LOG"]
ledger_root = os.environ.get("LEDGER_ROOT") or repo   # main: where the Bash window ledger is written when repo is a worktree
max_attempts = int(os.environ.get("MAX_ATTEMPTS", "2"))
devkit = os.path.dirname(os.path.dirname(gate))
probe = os.environ.get("PROBE") == "1"

def note(msg):
    with open(log, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + " " + msg + "\n")

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
# Grok gửi lastAssistantMessage (camelCase). Hook viết cho Claude chỉ đọc last_assistant_message,
# nên nhánh bỏ qua giữa chừng không thấy lời trả lời và vẫn mở suite (log 20/10: gating, không grok mid-work).
_reply_snake = data.get("last_assistant_message")
if not isinstance(_reply_snake, str) or not _reply_snake.strip():
    _reply_camel = data.get("lastAssistantMessage")
    if isinstance(_reply_camel, str):
        data["last_assistant_message"] = _reply_camel
# Which agent runs this Stop (hooks/devkit_harness.py). Degraded = not Claude Code, or no
# Claude transcript: Grok, a bridged agent, an unknown caller. Without the helper (a hook
# copied alone) the gate keeps its per-fingerprint guard only.
info = None
for d in os.environ.get("HOOK_DIRS", "").split(":") + [os.path.join(devkit, "hooks")]:
    if d and os.path.isfile(os.path.join(d, "devkit_harness.py")):
        try:
            sys.path.insert(0, d)
            sys.dont_write_bytecode = True
            import devkit_harness
            info = devkit_harness.detect(data, ppid=os.environ.get("HOOK_PPID"))
        except Exception as e:
            note("devkit_harness failed: %r" % e)
            info = None
        break
degraded = bool(info and info["degraded"])
sid = re.sub(r"[^A-Za-z0-9_-]", "_", str((info or {}).get("session") or data.get("session_id") or "nosession"))[:40]
max_session_blocks = int(os.environ.get("MAX_SESSION_BLOCKS", "3"))
if info and info["terminal_stop"] and not probe:
    # Grok fires an observe-only Stop when the session closes (reason channel_closed /
    # shutdown): no turn is left to continue, so running the suite there is pure cost.
    note("skip: session-end Stop (agent=%s reason=%s)" % (info["agent"], data.get("reason")))
    sys.exit(0)

def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True).stdout

# verified_head (T0003, Antigravity review): HEAD at the last PASS (devkit_harness, shared with
# testsourceset/review gates). Commits past it — made by any path, in any earlier turn — are
# unverified: the run covers verified_head..HEAD (--since) plus what is uncommitted. A local commit
# mid-work is fine; a push of unverified commits is a handover.
vh = head = ""
unverified = pushed = False
if info is not None:
    try:
        vh, head, reset_why = devkit_harness.verified_head(repo, write=not probe)
        unverified = bool(head and vh and head != vh)
        pushed = unverified and devkit_harness.pushed_unverified(repo, vh)
        if reset_why and not probe:
            note("verified_head reset (%s): now %s" % (reset_why, vh[:12]))
            print(json.dumps({"systemMessage": "ℹ regression_gate: lịch sử git bị viết lại (%s) — mốc đã kiểm lùi về "
                              "điểm chung cuối của hai lịch sử; mọi commit viết lại sau đó được kiểm ở lượt bàn giao."
                              % reset_why}, ensure_ascii=False))
    except Exception as e:
        note("verified_head failed: %r" % e)

# Held by ANOTHER live, active session (2026-10-13): this session is read-only in the checkout (session_lock refuses its writes
# and pushes), so it has nothing to hand over, and verified_head is shared: the holder next handover gates the same range.
# Gating here ran the holder in-progress diff and blocked a session that had changed nothing (five Stops, 08:45 to 09:20).
# No lock, its own lock, a stale lock, an idle holder or a dead holder process: gated as before. Any error: gated as before.
# The same three cases session_lock lets write are gated too (OpenCodeReview, 13/10): no session_id in the payload (Grok, bridged
# agents; session_lock never makes them read-only), DEVKIT_ALLOW_SHARED_CHECKOUT=1 and an active allow-shared grant.
if not probe:
    try:
        sys.path.insert(0, os.path.join(devkit, "bin"))
        import session_lock as _sl
        _gdir, _top = _sl.git_dir(repo)
        _lock = _sl.read_checkout_lock(_gdir) if _gdir else None
        _now = time.time()
        _lsid = str(data.get("session_id") or "")   # the id session_lock itself compares, not the harness one
        if (_gdir and _lsid and os.environ.get("DEVKIT_ALLOW_SHARED_CHECKOUT") != "1"
                and not _sl.is_free_for(_lock, _lsid, _now) and _sl.allow_shared_until(_gdir) <= _now):
            note("skip: checkout held by another live session (%s) sid=%s" % (str((_lock or {}).get("session_id"))[:12], sid))
            sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        note("held-by-other check failed: %r" % e)
    try:
        # K12 (18/10): trunk mode, phiên dừng ở chính MAIN checkout. session_lock từ chối mọi lần ghi vào main (cả chạy gate ở đó), nên
        # đòi "chạy post-fix-gate" ở main là vòng lặp không lối ra; thứ bẩn ở main không phải của phiên này (runner board, file sổ
        # sách của phiên khác) và mọi thứ vào main đã qua gate gộp của `worktree finish`; push trunk chỉ qua `agent-kit integrate`
        # (push_gate, #472 mục A), XONG vẫn cần biên nhận gate (proof_gate). Chỉ phiên Claude Code có transcript (hook PreToolUse của session_lock chạy ở đó); không có
        # session_id hay transcript (Grok, agent bắc cầu, lời gọi không rõ): không ai chặn họ ghi vào main, nên vẫn gate như cũ.
        # Phiên vừa push dải chưa kiểm (pushed): vẫn gate như cũ (review 18/10).
        # ponytail: session_lock.trunk_write không coi build / interpreter chạy ở main là ghi, nên `python3 fix.py` sửa file ở main lọt
        # qua bước này (proof_gate vẫn đòi biên nhận gate trước XONG, push_gate chỉ cho push trunk qua integrate); nâng cấp: chỉ bỏ qua khi main không có file bẩn
        # nào mới hơn lúc phiên bắt đầu, khi thấy một phiên sửa main theo đường đó.
        _tmain = _sl.trunk_main(_top)[0] if (_top and _lsid and info is not None and not degraded and not pushed) else None
        if _tmain and _sl._same_dir(_top, _tmain):
            note("skip: trunk mode, Stop at the merge-only main checkout (nothing of this session to gate there) sid=%s" % sid)
            sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:   # (session_lock không nạp được ở khối trên: NameError ở đây, vẫn gate như cũ)
        note("trunk-main check failed: %r" % e)

# A reply that declares itself unfinished (CHƯA XONG / CHỜ DUYỆT …) or carries no status line at all, claims
# no outcome and pushed nothing (unverified): nothing is checked now — the handover turn is, over verified_head..HEAD (T0003,
# 2026-09-28; user 2026-10-09: 15 h of Stop-hook test runs in 3 days, "chỉ test khi bàn giao"). proof_gate
# (XONG needs a gate receipt of this turn for the current code: task, scoped or --full) and push_gate (a receipt that covers what is
# pushed) still hold every handover; pre-commit runs static checks only unless DEVKIT_PRECOMMIT_TESTS sets a mode (v26 mục 2).
# DEVKIT_GATE_EVERY_STOP=1: every Stop is judged as a handover.
# Claude, Gemini, Grok: lời giữa chừng không xét biên nhận (Gemini/Grok không có transcript Claude: không đọc được push của lượt).
# XONG hoặc câu nhận đã xong: Stop đòi biên nhận gate của cây hiện tại (v26: Stop không chạy suite). Commit đã đẩy mà chưa kiểm vẫn nợ tới lượt bàn giao.
# Claude: một `git push` ngay trong lượt này vẫn là bàn giao, dù lời không nhận đã xong — khi không có lần sửa nào sau nó
# (devkit_harness.push_after_last_edit, audit 25/10 A3; push_gate đã đòi biên nhận gate cho nội dung được push).
# Một định nghĩa duy nhất: devkit_harness.mid_work (audit 25/10 A5: testsourceset_gate dùng chung, không chép lại).
if info is not None and not probe:
    try:
        why = devkit_harness.mid_work(data, info, pushed, repo=repo)   # repo: an edit outside it after a push is no work of the turn
        if why == "wip":
            note("skip: work in progress (status line %r) sid=%s" % (devkit_harness.status_line(
                data.get("last_assistant_message"))[:40], sid))
            sys.exit(0)
        if why:
            note("skip: mid-work (no handover) agent=%s sid=%s" % (info.get("agent") or "?", sid))
            sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        note("mid-work check failed: %r" % e)

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

status = git("status", "--porcelain=v1", "-z", "-uall")
# Only our own bookkeeping changed (audit-gate state, the checklist itself) => nothing to gate.
own = (".claude/audit-gate/", ".agents/regression_status.json", ".agents/regression_checklist.md",
       ".agents/CHECKLIST.md", ".agents/INBOX.md", ".agents/evidence/", ".agents/archive/")
entries = [e for e in status.decode("utf-8", "replace").split("\0") if len(e) > 3 and not e[3:].startswith(own)]
commit_base = vh if unverified else None
if not entries and not probe and not unverified:
    sys.exit(0)
if commit_base:
    note("unverified commits %s..%s: gating --since" % (vh[:12], head[:12]))

# Adopted matrix? (committed in the repo, not a byte-for-byte DevKit sample)
def norm(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.dumps(json.load(f), sort_keys=True)
    except Exception:
        return None
def enforce_as_is(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f).get("enforce_as_is") is True
    except Exception:
        return False
def adopted(p):
    # Explicit adoption: enforced even when byte-identical to a sample — a sample that
    # later gains the project’s only difference (e.g. untested_exit) must not switch it off.
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f).get("adopted") is True
    except Exception:
        return False
samples = set()
for root, _, files in os.walk(os.path.join(devkit, "profiles")):
    if "regression_matrix.json" in files and not enforce_as_is(os.path.join(root, "regression_matrix.json")):
        samples.add(norm(os.path.join(root, "regression_matrix.json")))
samples.add(norm(os.path.join(devkit, "templates", "regression_matrix.json")))
candidates = [os.path.join(repo, ".agents", "regression_matrix.active.json"),
              os.path.join(repo, "templates", "regression_matrix.active.json"),
              os.path.join(repo, ".agents", "active-profile", "regression_matrix.json"),
              os.path.join(repo, "templates", "regression_matrix.json")]
matrix = next((c for c in candidates if os.path.exists(c)), None)
# The committed matrix deleted in the working tree is not "no matrix": removing the
# test oracle is itself a change the gate must not wave through by switching off.
committed_rel = ".agents/regression_matrix.active.json"
if not os.path.exists(os.path.join(repo, committed_rel)) and subprocess.run(
        ["git", "-C", repo, "cat-file", "-e", "HEAD:./" + committed_rel], capture_output=True).returncode == 0:
    if probe:
        emit({"state": "deleted", "problem": committed_rel + " is deleted in the working tree"})
        sys.exit(0)
    msg = ("Regression gate: " + committed_rel + " (committed) đã bị XOÁ trong working tree — gate không được tắt kiểu này. "
           "Khôi phục nó (`git show HEAD:./" + committed_rel + " > " + committed_rel + "`), hoặc để người dùng tự commit việc xoá.")
    flag = os.path.join(os.path.dirname(log), "regression_gate.deleted." + sid)
    if os.path.exists(flag):            # said once this session: warn, never trap the session
        print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
        sys.exit(0)
    open(flag, "w").close()
    print(msg, file=sys.stderr)
    note("block: committed matrix deleted")
    sys.exit(2)
if not matrix:
    if probe:
        emit({"state": "none"})
    sys.exit(0)
real = os.path.realpath(matrix)
toplevel = os.path.realpath(git("rev-parse", "--show-toplevel").decode().strip() or repo)
rel = os.path.relpath(matrix, repo)
is_sample = norm(real) in samples and not adopted(real)
if probe and (not real.startswith(toplevel + os.sep) or is_sample):
    emit({"state": "sample" if is_sample else "outside", "matrix": rel})
    sys.exit(0)
if probe:
    # The gate’s own trust rule (committed, or byte-identical to a DevKit profile matrix /
    # to what `agent-kit matrix` generates), not a copy of it.
    try:
        import importlib.util
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("post_fix_gate", gate)
        pfg = importlib.util.module_from_spec(spec)
        os.environ["CLAUDE_PROJECT_DIR"] = repo
        with contextlib.redirect_stdout(io.StringIO()):
            spec.loader.exec_module(pfg)
            pfg.set_lang(pfg.resolve_lang(None, repo))
            _, problem = pfg.load_active_matrix(None, "HEAD")
    except Exception as e:
        emit({"state": "unknown", "matrix": rel, "problem": str(e)[:200]})
        sys.exit(0)
    emit({"state": "untrusted" if problem else "trusted", "matrix": rel, "problem": problem})
    sys.exit(0)
if not real.startswith(toplevel + os.sep) or is_sample:
    note(f"skipped: matrix {matrix} is a DevKit sample / outside the repo (not adopted)")
    # Not silent: a project whose runner the DevKit cannot detect (Unity, …) keeps the
    # profile sample and so has NO Stop-time regression check. Say it once per session.
    flag = os.path.join(os.path.dirname(log), "regression_gate.sample." + sid)
    if not os.path.exists(flag):
        try:
            open(flag, "w").close()
        except OSError:
            pass
        why = "là ma trận MẪU của DevKit (test minh họa)" if is_sample else "nằm ngoài repo (link vào DevKit)"
        print(json.dumps({"systemMessage":
            "⚠ regression_gate TẮT: không dò được test runner và `" + rel + "` " + why +
            " — test hồi quy KHÔNG chạy khi dừng. Chạy `agent-kit matrix --write`, hoặc sửa ma trận thành test thật "
            "của dự án (hay thêm \"adopted\": true) rồi commit. (regression gate off: no test runner detected and the "
            "matrix is a sample — run `agent-kit matrix --write` or adopt the matrix (\"adopted\": true) and commit it.)"},
            ensure_ascii=False))
    sys.exit(0)

# Fingerprint of the USER change only — the gate rewrites the checklist on every run,
# which must not make the same change look new (that would defeat the loop guard).
excl = [":(exclude).claude/audit-gate", ":(exclude).agents/regression_status.json",
        ":(exclude).agents/regression_checklist.md", ":(exclude).agents/CHECKLIST.md",
        ":(exclude).agents/INBOX.md", ":(exclude).agents/evidence", ":(exclude).agents/archive"]
_tree = "\0".join(entries).encode() + git("diff", "HEAD", "--binary", "--", ".", *excl)
# fp_plain: what the next stop computes once this range is verified (verified_head = HEAD then).
fp_plain = hashlib.sha256(_tree).hexdigest()[:20]
fp = hashlib.sha256(_tree + (("\0" + vh + ".." + head).encode() if unverified else b"")).hexdigest()[:20]
state_file = os.path.join(os.path.dirname(log), "regression_gate.state.json")
try:
    state = json.load(open(state_file, encoding="utf-8"))
except Exception:
    state = {}
if not isinstance(state, dict):
    state = {}

_GONE = object()
# What this process last read from, or wrote to, the state file: save_state applies only what changed SINCE.
_base = copy.deepcopy(state)

def _merge_into(disk, mine, base):
    # What this process changed since base, put onto the state another session may have written meanwhile: per entry
    # of the per-session and per-content tables, and per scalar. Without it the session that finished last erased the
    # entries of the one that finished first (the file is read at the start of a run and written minutes later).
    for k in set(mine) | set(base):
        mv, bv = mine.get(k, _GONE), base.get(k, _GONE)
        if isinstance(mv, dict) or isinstance(bv, dict):
            md = mv if isinstance(mv, dict) else {}
            bd = bv if isinstance(bv, dict) else {}
            dd = disk.get(k) if isinstance(disk.get(k), dict) else {}
            for sk in set(md) | set(bd):
                if md.get(sk, _GONE) != bd.get(sk, _GONE):
                    if sk in md:
                        dd[sk] = md[sk]
                    else:
                        dd.pop(sk, None)
            disk[k] = dd
        elif mv != bv:
            if mv is _GONE:
                disk.pop(k, None)
            else:
                disk[k] = mv

def save_state():
    # Atomic: sessions running side by side share this file, and a torn write read back
    # as {} reset every loop-guard counter (OfficeReader 2026-09-25: two sessions racing).
    # Read-merge-write under a lock file (a few ms; waits 3 s at most, then merges anyway).
    global _base
    lock = None
    try:
        lock = open(state_file + ".lock", "a")
        for _ in range(60):
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as e:
                if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EACCES):
                    note("state lock not supported here (%r): merged without it" % e)   # SMB / NFS / FUSE: waiting would not help
                    break
                time.sleep(0.05)
        else:
            note("state lock busy: merged without it")
    except OSError as e:
        note("state lock not opened: %r" % e)
    try:
        try:
            merged = json.load(open(state_file, encoding="utf-8"))
        except Exception:
            merged = None
        if not isinstance(merged, dict):
            # Removed, cut short or not an object: there is nothing to merge into, and a delta alone would drop what this process
            # read at its start (verified_head, pass_fp ...). Write the whole state, as before the merge existed.
            merged = copy.deepcopy(state)
        else:
            _merge_into(merged, state, _base)
        for key, keep in (("attempts", 200), ("sessions", 50), ("shown", 50), ("repeat", 50), ("touched", 50)):
            if isinstance(merged.get(key), dict) and len(merged[key]) > keep:
                merged[key] = dict(list(merged[key].items())[-keep:])
        try:
            fd, tmp = tempfile.mkstemp(prefix=".regression_gate.", dir=os.path.dirname(state_file))
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(merged, fh, ensure_ascii=False)
            os.replace(tmp, state_file)
            _base = copy.deepcopy(state)
        except OSError as e:
            note("state not saved: %r" % e)
    finally:
        if lock is not None:
            lock.close()

# Degraded mode: the last result of a gate run is no longer kept (v26: the Stop runs no suite); the total block count of this
# session (reset by an allow) and the session cap below stay.
sess = state.setdefault("sessions", {}).setdefault(sid, {}) if degraded else {}


def block(lines, cure, rc):
    attempts = state.setdefault("attempts", {})
    attempts[fp] = attempts.get(fp, 0) + 1
    save_state()
    note("block fp=%s attempt=%d exit=%s%s" % (fp, attempts[fp], rc, (" sid=%s agent=%s" % (sid, info["agent"])) if degraded else ""))
    if attempts[fp] > max_attempts:
        msg = "\n".join(lines + ["(Đã chặn %d lần cho cùng thay đổi — cho dừng để không kẹt phiên. Người dùng cần xem lại.)" % max_attempts])
        print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
        sys.exit(0)
    if degraded:
        n = int(sess.get("blocks") or 0)
        if n >= max_session_blocks:
            note("release: session cap sid=%s blocks=%d agent=%s" % (sid, n, info["agent"]))
            head = ("⚠ Regression gate đã chặn %d lần trong phiên %s (agent: %s, transcript: %s) — CHO DỪNG để agent "
                    "không bị kẹt; gate vẫn CHƯA ĐẠT, KHÔNG phải PASS. Người dùng cần xem lại. (regression gate released "
                    "the stop after %d blocks this session — REGRESSION_GATE_MAX_SESSION_BLOCKS; not a PASS)"
                    % (n, sid, info["agent"], info["transcript"], n))
            print(json.dumps({"systemMessage": "\n".join([head] + lines)}, ensure_ascii=False))
            sys.exit(0)
        sess["blocks"] = n + 1
        save_state()
    # The same block again in this session (O4, 2026-09-28: 31 blocks, 32 k characters in one GeelyEx2 session): the advice is not repeated.
    shown = state.setdefault("shown", {})
    digest = hashlib.sha256("\n".join(lines).encode()).hexdigest()[:16]
    again = shown.get(sid) == digest
    shown[sid] = digest
    save_state()
    print("\n".join(lines + ([] if again else cure)), file=sys.stderr)
    sys.exit(2)

# pass_fp / untested_fp name the CONTENT too: fp hashes status + `git diff HEAD` only, so an edit
# inside an untracked file kept the key and the next Stop skipped (review 2026-09-29).
# Same content hash as devkit_harness.tree_fingerprint. Without the helper (a hook copied alone) the per-fingerprint key stays.
# tree_fingerprint leaves gitignored files out; the key also hashes that ignored set (2026-10-07). None means the list failed:
# do not skip, and do not store a key (a stored None matches a missing pass_fp and would skip the next Stop).
content_fp = ""
if info is not None:
    try:
        content_fp = devkit_harness.tree_fingerprint(repo)
    except Exception as e:
        note("content fingerprint failed: %r" % e)

def _local_ignored_sha():
    """Hex sha of gitignored local config and build inputs. None if they cannot be listed."""
    local_base = (".env", ".env.*", "*.env", "local.properties", "keystore.properties",
                  "secrets.properties", "google-services.json", "GoogleService-Info.plist", ".npmrc")
    build_globs = ("local.properties", "**/local.properties", "google-services.json",
                   "**/google-services.json", "**/GoogleService-Info.plist", "key.properties",
                   "**/key.properties", "**/keystore.properties", "**/*.jks", "**/*.keystore",
                   "**/libs/*.aar", "**/libs/*.jar", ".env", ".env.*", "**/.env")
    skip_walk = {".git", "build", ".gradle", "node_modules", "Library", "Temp", "Logs", "obj",
                 ".venv", "venv", "__pycache__", ".idea", ".agents", ".claude", "dist", "out",
                 ".cxx", ".kotlin"}
    extra = []
    try:
        copied = json.loads(open(os.path.join(repo, ".agents", "local", "red_proof.json"),
                                  encoding="utf-8").read()).get("copy", [])
        if isinstance(copied, list):
            extra = [p for p in copied if isinstance(p, str) and p and "\n" not in p and not p.startswith("-")]
    except (OSError, ValueError, AttributeError, TypeError):
        extra = []
    specs, seen = [], set()

    def add(pat):
        spec = (":(glob)" + pat) if any(c in pat for c in "*?[") else pat
        if spec not in seen:
            seen.add(spec)
            specs.append(spec)

    for pat in local_base:
        add(pat)
        add("**/" + pat)
    for pat in build_globs + tuple(extra):
        add(pat)
    excludes = []
    for d in sorted(skip_walk):
        excludes.append(":(exclude)" + d)
        excludes.append(":(exclude,glob)" + d + "/**")

    def listed(pathspecs):
        try:
            proc = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--others", "--ignored",
                                   "--exclude-standard", "--", *pathspecs], capture_output=True)
        except OSError:
            return None
        if proc.returncode != 0:
            return None
        return proc.stdout.split(b"\0")

    rows = listed(specs + excludes)
    if rows is None and extra:
        bare, seen_bare = [], set()

        def add_bare(pat):
            spec = (":(glob)" + pat) if any(c in pat for c in "*?[") else pat
            if spec not in seen_bare:
                seen_bare.add(spec)
                bare.append(spec)

        for pat in local_base:
            add_bare(pat)
            add_bare("**/" + pat)
        for pat in build_globs:
            add_bare(pat)
        rows = listed(bare + excludes)
    if rows is None:
        return None
    pats = build_globs + tuple(extra)
    kept = []
    for raw in rows:
        if not raw or raw.endswith(b"/"):
            continue
        rel = raw.decode("utf-8", "surrogateescape").replace("\\", "/")
        parts = rel.split("/")
        if any(part in skip_walk for part in parts):
            continue
        base = parts[-1]
        if any(fnmatch.fnmatch(base, pat) for pat in local_base) or any(
                fnmatch.fnmatch(rel, pat) or (pat.startswith("**/") and fnmatch.fnmatch(rel, pat[3:]))
                for pat in pats):
            kept.append(rel)
    h = hashlib.sha256()
    for rel in sorted(set(kept)):
        digest = ""
        try:
            fh = hashlib.sha256()
            with open(os.path.join(repo, rel), "rb") as src:
                for chunk in iter(lambda: src.read(1024 * 1024), b""):
                    fh.update(chunk)
            digest = fh.hexdigest()
        except OSError:
            digest = ""
        h.update(rel.encode("utf-8", "surrogateescape") + b"\0" + digest.encode() + b"\0")
    return h.hexdigest()


_local_sha = _local_ignored_sha()


def skip_key(f):
    if _local_sha is None:
        return None
    base = f + ":" + content_fp if content_fp else f
    return base + ":" + _local_sha


_sk_fp = skip_key(fp)


def remind(lines):
    print(json.dumps({"systemMessage": "\n".join(["⚠ Vẫn chờ người duyệt diff test (không chặn lại, KHÔNG phải PASS):"]
                                                 + [str(l) for l in lines])}, ensure_ascii=False))


if _sk_fp is not None and state.get("pass_fp") == _sk_fp:
    sys.exit(0)
# UNTESTED content (a suite cannot run on this machine) was already said to the user and cannot give another result here.
if _sk_fp is not None and state.get("untested_fp") == _sk_fp:
    note(f"untested fp={fp} (reused result)")
    sys.exit(0)

# ── Gate speed v26 mục 1: Stop KHÔNG chạy suite nào. Lượt gate của agent (post-fix-gate --run-tests --scoped, một lần trên cây cuối) ghi
# biên nhận hay kết luận; hook này chỉ đọc chúng (tree_fp.receipt_for_tree, <git dir>/postfix-gate/outcomes/<fp>.json):
#   cho dừng + ghi verified_head: biên nhận phủ cây VÀ các commit sau verified_head mà lượt đó không kiểm (vh..base) đều đã ở nhánh đích;
#       hoặc mọi file đổi từ verified_head chỉ là tài liệu / trạng thái agent mà không luật ma trận nào theo dõi;
#   cho dừng, không ghi gì: repo PR (super-board) với nhánh đã đẩy, cây sạch (merge gate của PR chạy test); hoặc biên nhận merge gate của HEAD;
#   kết luận không biên nhận (outcome): như trước theo lý do (exit 3, thiếu thiết bị, môi trường, ma trận chưa commit: nói một lần rồi cho
#       dừng; test có sẵn bị sửa: chặn một lần, sau đó nhắc);
#   còn lại: chặn (MAX_ATTEMPTS), nêu lệnh đúng loại repo.
EMPTY = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
sys.path.insert(0, os.path.dirname(gate))
sys.path.insert(1, os.path.dirname(os.path.realpath(gate)))   # a linked post-fix-gate.py (copy-mode kit): its real bin/ holds tree_fp.py
try:
    import tree_fp as _tfp
except Exception as e:
    note("tree_fp not importable: %r" % e)
    emit({"systemMessage": "Regression gate LỖI: không nạp được bin/tree_fp.py — KHÔNG phải PASS, chưa xét được biên nhận gate"})
    sys.exit(0)


def gtext(*args):
    return git(*args).decode("utf-8", "replace").strip()


branch = gtext("symbolic-ref", "-q", "--short", "HEAD")
_oh = gtext("symbolic-ref", "-q", "refs/remotes/origin/HEAD")
trunk_name = _oh[len("refs/remotes/origin/"):] if _oh.startswith("refs/remotes/origin/") else ""
if not trunk_name:
    trunk_name = next((n for n in ("main", "master", "trunk") if gtext("rev-parse", "--verify", "-q", "refs/remotes/origin/" + n)
                       or gtext("rev-parse", "--verify", "-q", "refs/heads/" + n)), "")
# The trunk the range rule excludes: origin/<trunk> first; the LOCAL trunk branch only when this is not that branch (on it, its own
# unpushed commits are exactly what the run has to cover).
trunk = ""
if trunk_name:
    if gtext("rev-parse", "--verify", "-q", "refs/remotes/origin/" + trunk_name):
        trunk = "refs/remotes/origin/" + trunk_name
    elif branch != trunk_name and gtext("rev-parse", "--verify", "-q", "refs/heads/" + trunk_name):
        trunk = "refs/heads/" + trunk_name


def covered(base, full_ok=True):
    """True when the commits after verified_head that a run from `base` did not check (vh..base, or base itself when nothing is verified)
    are all on the trunk. base "" = a full receipt (the whole tree), only when full_ok."""
    if base == "":
        return full_ok
    if not isinstance(base, str) or not SHA.fullmatch(base):
        return False
    rng = [base] if (not vh or vh == EMPTY) else [vh + ".." + base]
    res = subprocess.run(["git", "-C", repo, "rev-list", "-n", "1"] + rng + (["--not", trunk] if trunk else []),
                         capture_output=True, text=True)
    return res.returncode == 0 and not res.stdout.strip()


def allow(why, verified=True, said=None):
    if verified:
        sk_plain = skip_key(fp_plain)
        if sk_plain is not None:
            state["pass_fp"] = sk_plain
        state["verified_head"] = head or state.get("verified_head")
        if isinstance(state.get("attempts"), dict):
            state["attempts"].pop(fp, None)
    if degraded:
        sess["blocks"] = 0
    save_state()
    note("allow fp=%s (%s) sid=%s" % (fp, why, sid))
    if said:
        emit({"systemMessage": said})
    sys.exit(0)


def watch_patterns():
    pats = []
    for c in candidates:
        try:
            with open(c, encoding="utf-8") as f:
                pats += [w for r in json.load(f).get("rules", []) for w in r.get("watch_files", [])]
        except Exception:
            pass
    return pats


def watched(f, pats):
    # = post-fix-gate match_pattern: fnmatch, and "**/x" also matches a root-level x
    f = f.replace("\\", "/")
    return any(fnmatch.fnmatch(f, p) or (p.startswith("**/") and fnmatch.fnmatch(f, p[3:])) for p in pats)


def no_test_needed(p):
    # a subset of post-fix-gate needs_no_test (documentation, agent state): a narrower list only blocks more, never lets code through
    p = p.replace("\\", "/")
    name = p.rsplit("/", 1)[-1]
    return (p.lower().endswith((".md", ".rst", ".adoc", ".log")) or name in ("LICENSE", "NOTICE", "AUTHORS", "CODEOWNERS", ".gitignore")
            or p in (".antigravity-pm.json", ".adb-denylist", ".claude/settings.json", ".claude/settings.local.json")
            or p.startswith(".agents/local/memory/") or re.fullmatch(r"reports/proof-[^/]+\.png", p) is not None)


rfp, rwhy = "", []
try:
    rfp = _tfp.tree_fingerprint(repo)
    rec = _tfp.receipt_for_tree(repo, gate=gate, fp=rfp, why=rwhy, covers=covered) if rfp else None
except Exception as e:
    note("receipt check failed: %r" % e)
    rec = None
if rec is not None:
    allow("receipt %s base=%s" % (rec["_kind"], str(rec.get("_base"))[:12]))
uncovered_range = any(": covers base " in w for w in rwhy)
if rwhy:
    note("no receipt: %s" % "; ".join(os.path.basename(w) for w in rwhy)[:400])

# What the run decided when it wrote no receipt (post-fix-gate write_gate_outcome).
out = None
if rfp:
    try:
        out = _tfp._load_receipt(os.path.join(os.path.dirname(_tfp.receipt_path(repo)), "outcomes", rfp + ".json"))
    except Exception as e:
        note("outcome read failed: %r" % e)
if out is not None:
    olines = [str(l) for l in out.get("lines") or [] if isinstance(l, str)] if isinstance(out.get("lines"), list) else []
    reason = out.get("reason")
    # exit 3 and device UNTESTED say the RANGE is fine: only when the run started at a base that covers what verified_head left
    if reason in ("nothing", "device_untested") and not covered(out.get("base"), full_ok=False):
        note("outcome %s base=%s does not cover %s..HEAD: no outcome" % (reason, str(out.get("base"))[:12], vh[:12]))
        out = None
    elif reason not in ("nothing", "device_untested", "env", "matrix", "edited_test"):
        out = None
# The gate says "matrix" for every matrix it does not trust. Only a NEW matrix that shadows no committed one is let through (a commit, a
# human decision, makes it trusted); an edited COMMITTED matrix (`exit 1` -> `true`) or an uncommitted one in front of a committed one
# would switch the committed tests off, so they block and need a person to review the matrix edit.
if out is not None and reason == "matrix":
    def in_head(p):
        return subprocess.run(["git", "-C", repo, "cat-file", "-e", "HEAD:./" + os.path.relpath(p, repo).replace(os.sep, "/")],
                              capture_output=True).returncode == 0
    shadowed = [os.path.relpath(c, repo) for c in candidates[candidates.index(matrix) + 1:] if in_head(c)]
    if in_head(matrix) or shadowed:
        block(["Regression gate CHƯA ĐẠT — " + (("ma trận chưa commit `%s` che ma trận đã commit `%s`" % (rel, "`, `".join(shadowed)))
                                                 if shadowed else ("ma trận đã commit `%s` bị sửa trong thay đổi" % rel))
               + ": gate không tin nó nên không test hồi quy nào chạy"] + olines,
              ["Cần người review thay đổi ma trận (rồi commit, hoặc hoàn lại). Không sửa ma trận / test cũ để lách."], 2)
if out is not None:
    once = state.get("outcome_said") != rfp + ":" + reason
    state["outcome_said"] = rfp + ":" + reason
    text = "\n".join(olines)[:1500]
    if reason == "nothing":
        allow("outcome nothing", said=("ℹ Regression gate: không có thay đổi nào để kiểm (exit 3). " + text) if once else None)
    if reason == "device_untested":
        sk_plain = skip_key(fp_plain)
        if sk_plain is not None:
            state["untested_fp"] = sk_plain
        allow("outcome device_untested", said=("Regression gate UNTESTED — không chạy được trên máy này, KHÔNG phải PASS: " + text
                                               + " Chạy lại trên máy có công cụ đó trước khi báo xong.") if once else None)
    if reason == "env":
        allow("outcome env", verified=False, said=("Regression gate REJECT vì môi trường — máy này thiếu công cụ/SDK/mạng, hoặc suite bị kill "
                                                   "từ ngoài, KHÔNG phải PASS: " + text + " Chạy lại trên máy có đủ công cụ trước khi báo xong.") if once else None)
    if reason == "matrix":
        # changed code the new matrix does not watch: said too, or it would stay untested after the commit
        unw = sorted(p for p in (e[3:] for e in entries) if not p.startswith((".agents/", "templates/regression_matrix"))
                     and not no_test_needed(p) and not watched(p, watch_patterns()))
        allow("outcome matrix", verified=False, said=("⚠ Regression gate KHÔNG chạy test hồi quy: ma trận chưa commit nên gate chưa tin nó. "
                                                      "Cần làm: commit " + rel + ". " + text
                                                      + ((" Ngoài ra %d file code đổi mà ma trận này không theo dõi (thêm vào watch_files): %s."
                                                          % (len(unw), ", ".join(unw[:10]))) if unw else "")) if once else None)
    # edited_test: only another agent clears it (cross-review). Block ONCE per change so the agent says it; later stops only remind.
    lines = ["Regression gate CHƯA ĐẠT — test có sẵn bị sửa/xoá, chờ duyệt chéo"] + olines
    if state.get("touched_fp") == fp:
        save_state()
        note(f"tests-touched reminder fp={fp}")
        remind(lines[1:])
        sys.exit(0)
    state["touched_fp"] = fp
    block(lines, ["Cần duyệt chéo bởi agent khác: commit, rồi antigravity-pm `pm_dispatch kind=audit agent=grok` trên head PR (PM tự ghi biên "
                  "bản, gate tra thẳng); agent sửa test KHÔNG tự duyệt, KHÔNG hỏi người dùng. Không sửa test cũ để lách."], 2)

# A PR repo (super-board): the merge gate of the PR runs the tests. HEAD of a pushed branch that is not the trunk, clean tree: nothing to do here.
pr_repo = bool(glob.glob(os.path.join(repo, ".claude", "super-board", "configs", "*.json")))
if pr_repo and branch and branch != trunk_name and not entries:
    others = [r for r in gtext("for-each-ref", "--contains", "HEAD", "--format=%(refname)", "refs/remotes").splitlines()
              if r and not r.endswith("/HEAD") and r != "refs/remotes/origin/" + trunk_name]
    if others:
        allow("PR branch pushed (%s)" % others[0], verified=False)
# The merge gate of a PR verified this HEAD (super-board-merge-gate.sh: <common>/postfix-gate/merge_receipts/<PR>-<head>.json).
if not entries and head:
    try:
        for mp in glob.glob(os.path.join(os.path.dirname(_tfp.tree_receipt_dir(repo) or ""), "merge_receipts", "*.json")):
            mr = _tfp._load_receipt(mp)
            if mr and head in (mr.get("head"), mr.get("squash")):
                allow("merge receipt %s" % os.path.basename(mp), verified=False)
    except Exception as e:
        note("merge receipt check failed: %r" % e)

# Only documentation / agent state changed since verified_head, and no matrix rule watches it: nothing a test could catch.
changed = {e[3:] for e in entries}
if vh and vh != EMPTY and unverified:
    changed |= {p for p in gtext("diff", "--name-only", "--relative", vh, "HEAD").splitlines() if p}
if (not vh or vh == EMPTY) and unverified:
    changed = set()
if changed and all(no_test_needed(p) for p in changed) and not any(watched(p, watch_patterns()) for p in changed):
    allow("needs no test: %s" % ",".join(sorted(changed)[:5]))

# No receipt for this code: block, with the command for this kind of repo.
gate_disp = os.path.relpath(gate, repo) if os.path.realpath(gate).startswith(os.path.realpath(repo) + os.sep) else gate
if pr_repo:
    cmd = ("commit việc đang dở rồi `git push`" if entries else "`git push`") + " (merge gate của PR chạy test)"
else:
    diff = (" --diff " + vh) if (branch and branch == trunk_name and vh and vh != EMPTY and SHA.fullmatch(vh)) else ""
    # --force when this tree already has a receipt from a later base: rerun_skip.json (same tree, same suites) would end the run at once and
    # write no receipt for the wider base
    cmd = "`python3 " + gate_disp + " --run-tests --scoped --brief" + diff + (" --force" if uncovered_range else "") + "`"
lines = ["Regression gate CHƯA ĐẠT — chưa có biên nhận gate cho code hiện tại (Stop không chạy test; lượt gate của agent ghi biên nhận)"]
if uncovered_range:
    lines.append("  - có biên nhận cho cây này, nhưng lượt gate bắt đầu sau verified_head %s: các commit giữa hai mốc chưa được kiểm "
                 "và chưa ở nhánh đích" % vh[:12])
lines.append("  - cần làm: " + cmd + " một lần trên cây cuối (exit 0 ghi biên nhận), rồi dừng lại")
block(lines, ["Không sửa test cũ để lách. Nếu thực sự không làm được, dừng và nói rõ cho người dùng."], 1)
' || exit $?
