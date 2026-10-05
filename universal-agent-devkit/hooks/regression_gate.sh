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
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
PROBE="${REGRESSION_GATE_PROBE:-0}"
if [ "${PROBE}" != "1" ]; then  # the probe writes nothing
  mkdir -p "${LOG_DIR}" 2>/dev/null || exit 0
  [ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
fi
LOG="${LOG_DIR}/regression_gate.log"

if [ "${REGRESSION_GATE:-1}" = "0" ]; then
  [ "${PROBE}" = "1" ] && { printf '%s\n' '{"state":"disabled"}'; exit 0; }
  echo "$(date +%Y-%m-%dT%H:%M:%S) skipped: REGRESSION_GATE=0" >> "${LOG}"
  exit 0
fi
command -v python3 >/dev/null 2>&1 || exit 0
git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

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

printf '%s' "${INPUT}" | REPO_ROOT="${REPO_ROOT}" GATE="${GATE}" LOG="${LOG}" PROBE="${PROBE}" \
  MAX_ATTEMPTS="${REGRESSION_GATE_MAX_ATTEMPTS:-2}" MAX_SESSION_BLOCKS="${REGRESSION_GATE_MAX_SESSION_BLOCKS:-3}" \
  HOOK_PPID="${PPID}" HOOK_DIRS="$(dirname "${SELF}"):$(dirname "$0")" python3 -I -c '
import contextlib, fnmatch, hashlib, io, json, os, re, subprocess, sys, tempfile, time

repo, gate, log = os.environ["REPO_ROOT"], os.environ["GATE"], os.environ["LOG"]
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

# A reply that declares itself unfinished (CHƯA XONG / CHỜ DUYỆT …), claims no outcome and pushed
# nothing unverified: no test run now — the handover turn runs it (T0003, 2026-09-28).
if info is not None and not probe and not pushed:
    try:
        if devkit_harness.work_in_progress(data):
            note("skip: work in progress (status line %r) sid=%s" % (devkit_harness.status_line(
                data.get("last_assistant_message"))[:40], sid))
            sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        note("work_in_progress failed: %r" % e)

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

def save_state():
    # Atomic: sessions running side by side share this file, and a torn write read back
    # as {} reset every loop-guard counter (OfficeReader 2026-09-25: two sessions racing).
    for key, keep in (("attempts", 200), ("sessions", 50), ("shown", 50), ("repeat", 50)):
        if isinstance(state.get(key), dict) and len(state[key]) > keep:
            state[key] = dict(list(state[key].items())[-keep:])
    try:
        fd, tmp = tempfile.mkstemp(prefix=".regression_gate.", dir=os.path.dirname(state_file))
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh, ensure_ascii=False)
        os.replace(tmp, state_file)
    except OSError as e:
        note("state not saved: %r" % e)

# Degraded mode: the last result of this session, reused while the tree is unchanged, and its
# total block count (reset by a pass).
sess = state.setdefault("sessions", {}).setdefault(sid, {}) if degraded else {}
# Its tree key also hashes untracked contents (a fix in a new test file is a new tree);
# the per-fingerprint key above names untracked files only.
tree_fp = devkit_harness.tree_fingerprint(repo) if degraded else fp
# Claude session with its transcript: the last block of this session, keyed by fp (it carries the
# unverified range) and the full tree fingerprint (a fix in an untracked file is new content).
reuse_key = None
if info is not None and not degraded and (data.get("session_id") or data.get("sessionId") or sid != "nosession"):
    try:
        reuse_key = hashlib.sha256((fp + ":" + devkit_harness.tree_fingerprint(repo)).encode()).hexdigest()[:20]
    except Exception as e:
        note("reuse key failed: %r" % e)
repeat = state.get("repeat") if isinstance(state.get("repeat"), dict) else {}
REUSED = "cùng nội dung với lần chặn trước — chưa chạy lại; sửa code hoặc chạy post-fix-gate --full"

def block(lines, cure, rc, reused=False, reusable=True, repeat_hit=False):
    attempts = state.setdefault("attempts", {})
    attempts[fp] = attempts.get(fp, 0) + 1
    if degraded:
        sess.update({"fp": tree_fp, "result": "block", "lines": lines, "cure": cure, "rc": rc})
    if reuse_key:
        state["repeat"] = repeat
        if reusable:
            repeat[sid] = {"key": reuse_key, "lines": lines, "cure": cure, "rc": rc}
        else:
            repeat.pop(sid, None)
    save_state()
    note("block fp=%s attempt=%d exit=%s%s%s" % (fp, attempts[fp], rc, " (reused result)" if reused else "",
                                                (" sid=%s agent=%s" % (sid, info["agent"])) if degraded else ""))
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
    # The same block again in this session (O4, 2026-09-28: 31 blocks, 32 k characters in one
    # GeelyEx2 session): every item stays (id, status, exit, log — the first block may have been
    # compacted away), only a long command is cut and the advice is not repeated.
    shown = state.setdefault("shown", {})
    # Each run writes a new evidence log (…/20260928-140109.log): compare without the stamp.
    digest = hashlib.sha256(re.sub(r"\d{8}-\d{6}", "#", "\n".join(lines)).encode()).hexdigest()[:16]
    again = shown.get(sid) == digest
    shown[sid] = digest
    save_state()
    if again:
        def cut(l):
            i = l.find("(lệnh: ")
            if i < 0 or len(l) < 200:
                return l
            j = l.rfind(", exit ")
            return l[:i + 7] + l[i + 7:i + 87] + "…" + (l[j:] if j > i else ")")
        print("\n".join([cut(l) for l in lines if not l.startswith("Checklist: ")]
                        + ["(Như lần chặn trước trong phiên: mục lỗi giữ nguyên; lệnh đầy đủ và hướng dẫn: %s)"
                           % next((l.split("báo cáo: ", 1)[-1] for l in lines if l.startswith("Checklist: ")), "-")]
                        + ([REUSED] if repeat_hit else [])),
              file=sys.stderr)
    else:
        print("\n".join(lines + cure + ([REUSED] if repeat_hit else [])), file=sys.stderr)
    sys.exit(2)

# pass_fp / untested_fp name the CONTENT too: fp hashes status + `git diff HEAD` only, so an edit
# inside an untracked file kept the key and the next Stop skipped the suites (review 2026-09-29).
# Same content hash as reuse_key (devkit_harness.tree_fingerprint). Without the helper (a hook
# copied alone) the per-fingerprint key stays as it was.
content_fp = ""
if info is not None:
    try:
        content_fp = devkit_harness.tree_fingerprint(repo)
    except Exception as e:
        note("content fingerprint failed: %r" % e)


def skip_key(f):
    return f + ":" + content_fp if content_fp else f


if state.get("pass_fp") == skip_key(fp):
    sys.exit(0)
# UNTESTED content (every suite that can run here passed; one says by its untested_exit that it
# cannot run on this machine) was already said to the user and cannot give another result here.
# 2026-09-29 (GeelyEx2: verified_head stuck, every Stop re-ran the --since range 4-5 min).
if state.get("untested_fp") == skip_key(fp):
    note(f"untested fp={fp} (reused result)")
    sys.exit(0)
# A full PASS of this exact content is reused inside the gate run below (post-fix-gate
# cached_full_pass: ~1 s, with its format/matrix/local-config/age checks and --session/--since);
# never end the Stop here on a bare full_pass.json.
if degraded and sess.get("fp") == tree_fp:
    # Same tree as the last run of this session: the result cannot have changed. Re-use it
    # instead of re-running the whole suite on every stop.
    if sess.get("result") == "block" and isinstance(sess.get("lines"), list):
        block(sess["lines"], sess.get("cure") or [], sess.get("rc", 1), reused=True)
    if sess.get("result") in ("untested", "matrix", "env"):
        note("%s fp=%s (reused result) sid=%s" % (sess["result"], fp, sid))
        sys.exit(0)
last = repeat.get(sid) if reuse_key else None
if isinstance(last, dict) and last.get("key") == reuse_key and isinstance(last.get("lines"), list):
    # This session already blocked on exactly this content: the gate would say the same (a flaky
    # suite is no reason to re-run every Stop). Same reason, no run.
    block(last["lines"], last.get("cure") or [], last.get("rc", 1), reused=True, repeat_hit=True)

# A session that wrote none of the changed files is not the author of this change: a diff another agent made
# (301 files) re-ran the whole matrix (~11 min a run, 27 min seen) at the end of every read-only
# session (agent-workbench, 2026-10-02). Evidence of writing is session_authorship.wrote_any: Edit/Write
# paths, write verbs naming a changed file, a changed file inside its own Bash windows. A tool
# that may write unseen, no usable transcript, a push or unverified commits, and a reply that claims
# an outcome (or says nothing) keep the gate.
# REGRESSION_GATE_ALL_SESSIONS=1 turns the shortcut off.
def wrote_nothing_here():
    sid_raw, tp = str(data.get("session_id") or ""), data.get("transcript_path")
    if info is None or degraded or pushed or unverified or not sid_raw or not tp \
            or os.environ.get("REGRESSION_GATE_ALL_SESSIONS") == "1" or os.environ.get("DEVKIT_GATE_EVERY_STOP") == "1":
        return False
    reply = data.get("last_assistant_message")
    try:
        # Same fail-closed contract as the progress-reply skip: a reply that claims an outcome, says
        # nothing, or follows a commit/push this turn is the handover and is verified.
        start = devkit_harness.turn_start(tp)
        if not isinstance(reply, str) or not reply.strip() or devkit_harness.reply_status(reply) == "DONE" \
                or devkit_harness.OUTCOME.search(re.sub(r"(?i)chưa\s+xong", "", reply)) \
                or start is None or devkit_harness.git_writes_in_turn(tp, start):
            return False
        sys.dont_write_bytecode = True
        sys.path.insert(0, os.path.join(devkit, "bin"))
        import session_authorship
        recs, paths, i = status.decode("utf-8", "replace").split("\0"), [], 0
        while i < len(recs):
            rec = recs[i]
            i += 1
            if len(rec) <= 3:
                continue
            paths.append(rec[3:])
            if ("R" in rec[:2] or "C" in rec[:2]) and i < len(recs):   # rename/copy: the next record is its source
                paths.append(recs[i])
                i += 1
        paths = [p for p in paths if p and not p.startswith(own)]
        return bool(paths) and session_authorship.wrote_any(tp, sid_raw, repo, paths, root=toplevel) is False
    except Exception as e:
        note("wrote_nothing_here failed: %r" % e)
        return False

if wrote_nothing_here():
    note("skip: session wrote none of the changed files sid=%s" % sid)
    flag = os.path.join(os.path.dirname(log), "regression_gate.readonly." + sid)
    if not os.path.exists(flag):
        try:
            open(flag, "w").close()
        except OSError:
            pass
        print(json.dumps({"systemMessage": "ℹ regression_gate: phiên này không ghi file nào trong các thay đổi đang có "
                          "(của agent/người khác) nên KHÔNG chạy lại test hồi quy ở lượt dừng — KHÔNG phải PASS. Test chạy ở "
                          "phiên có sửa file, khi commit/push, hoặc chạy tay `postfix-gate --run-tests --full`. (regression gate "
                          "skipped: this session wrote none of the changed files — not a PASS; REGRESSION_GATE_ALL_SESSIONS=1 "
                          "runs it anyway)"}, ensure_ascii=False))
    sys.exit(0)

# --session/--transcript: an existing test edited by ANOTHER session (or a person) is a warning,
# only the test edits of THIS session block (post-fix-gate split_tests_by_author).
# TEST_RUN_LOCK_WAIT_S: a short wait for the test_run.lock another run holds (the CLI default 900 plus
# the suites could pass the 1800 s timeout of this hook); past it the gate reports "busy" (UNTESTED, never a PASS,
# nothing cached: the next stop runs the suites). Default 45 s, env overrides. Measured 2026-09-26..10-04 on 4 repos:
# 73 BUSY outcomes in the hook logs, each a full 120 s wait that ran nothing (the holder is a full matrix run, minutes
# long); in workbench about 5 waits ended in a run (12-90 s, 33.8 and 41.4 s among them) against about 33 BUSY, so 120 s
# buys few runs. Trade-off: a stop that would have run after a 45-120 s wait now ends BUSY and runs at the next stop.
# Total time for the suites of one Stop run: 45 s lock wait + this budget stay well inside the 1800 s hook timeout, so the
# hook is never cut silently (2026-10-02: 27 min). REGRESSION_GATE_BUDGET_S=0 turns it off.
budget_s = os.environ.get("REGRESSION_GATE_BUDGET_S", "900")
res = subprocess.run([sys.executable, gate, "--run-tests", "--json", "--task", "session-" + sid[:12],
                      "--timeout", os.environ.get("REGRESSION_GATE_TEST_TIMEOUT", "600"),
                      "--session", str(data.get("session_id") or ""), "--transcript", str(data.get("transcript_path") or "")]
                     + (["--since", commit_base] if commit_base else []),
                     cwd=repo, capture_output=True, text=True, errors="replace",
                     env={**os.environ, "CLAUDE_PROJECT_DIR": repo,
                          "TEST_RUN_LOCK_WAIT_S": os.environ.get("TEST_RUN_LOCK_WAIT_S", "45"),
                          "GATE_TOTAL_BUDGET_S": budget_s})
summary = {}
for line in reversed(res.stdout.splitlines()):
    if line.startswith("{"):
        try:
            summary = json.loads(line)
            break
        except ValueError:
            pass
def range_verified():
    # HEAD is verified: the next stop computes fp_plain (no --since range) for the same content.
    state["verified_head"] = head or state.get("verified_head")
    if isinstance(state.get("attempts"), dict):
        state["attempts"].pop(fp, None)
    if isinstance(state.get("repeat"), dict):
        state["repeat"].pop(sid, None)

if res.returncode in (0, 3):
    state["pass_fp"] = skip_key(fp_plain)
    range_verified()
    if degraded:
        sess.update({"fp": tree_fp, "result": "pass", "blocks": 0, "lines": None, "cure": None})
    save_state()
    note(f"pass fp={fp} exit={res.returncode}")
    other = summary.get("tests_touched_other") or []
    if other:   # once per change (pass_fp): not an edit of this session, still someone must review it
        emit({"systemMessage": "⚠ Test đã có bị phiên khác / người khác sửa (không chặn phiên này): " + ", ".join(other[:10])
              + " — cần người review diff test (`git diff HEAD -- " + " ".join(other[:3]) + "`) trước khi commit."})
    sys.exit(0)
if res.returncode == 4 and summary.get("busy"):
    # BUSY: another test run held the project lock, no test ran. Transient, not this machine
    # lacking a tool: say the real cause every time and cache nothing (the next stop runs it).
    note(f"busy fp={fp}")
    print(json.dumps({"systemMessage": "Regression gate UNTESTED — một lượt chạy test khác đang giữ khoá dự án — chạy lại sau "
                      "(.claude/audit-gate/test_run.lock); test hồi quy CHƯA chạy, KHÔNG phải PASS."}, ensure_ascii=False))
    sys.exit(0)
if res.returncode == 4 and summary.get("budget_exhausted"):
    # Time budget spent: some suites did not start. Nothing to fix in the change and no verdict to remember: say it every
    # time, cache nothing (the next stop runs again), do not advance verified_head.
    left = [str(t.get("id") or "?") for t in summary.get("regression_tests", []) if t.get("label") == "BUDGET"]
    note("budget fp=%s left=%s" % (fp, ",".join(left)))
    print(json.dumps({"systemMessage": "Regression gate UNTESTED — hết ngân sách thời gian (%ss): %s chưa chạy — KHÔNG phải PASS; "
                      "chạy `postfix-gate --run-tests --full` trước khi bàn giao. (REGRESSION_GATE_BUDGET_S)"
                      % (budget_s, ", ".join(left))}, ensure_ascii=False))
    sys.exit(0)
if res.returncode == 4 and summary:
    # UNTESTED: every test that could run passed, but one cannot run on this machine
    # (its matrix untested_exit, e.g. unity-batch.sh without a Unity Editor). Blocking
    # would stop every session on that machine; passing would claim a PASS nobody saw.
    # Say it once per change and let the stop through. The range counts as verified for what
    # can run here (never pass_fp): 2026-09-29 (GeelyEx2: verified_head stuck, every Stop
    # re-ran the --since range 4-5 min); untested_fp = fp_plain ends the next stop of this content.
    if degraded:
        sess.update({"fp": tree_fp, "result": "untested"})
    first = state.get("untested_fp") != skip_key(fp)
    state["untested_fp"] = skip_key(fp_plain)
    range_verified()
    save_state()
    if first:
        names = ["%s (%s)" % (t.get("id"), t.get("command")) for t in summary.get("regression_tests", [])
                 if t.get("status") == "UNTESTED"]
        print(json.dumps({"systemMessage": "Regression gate UNTESTED — không chạy được trên máy này, KHÔNG phải PASS: "
                          + "; ".join(names or ["?"]) + ". Chạy lại trên máy có công cụ đó trước khi báo xong."},
                         ensure_ascii=False))
    note(f"untested fp={fp}")
    sys.exit(0)
if res.returncode not in (1, 2) or not summary:
    # A crash (a Python traceback also exits 1) prints no JSON: there is nothing to fix in the
    # change, so do not block with a reasonless "exit 1" (OfficeReader 2026-09-26) — say it.
    note("fail-open: gate crashed exit=%s: %r" % (res.returncode, res.stderr[-400:]))
    tail = "\n".join((res.stderr or res.stdout or "").strip().splitlines()[-6:])
    emit({"systemMessage": "Regression gate LỖI (exit %s, không có kết quả) — KHÔNG phải PASS, test hồi quy chưa được xác nhận:\n%s"
          % (res.returncode, tail)})
    sys.exit(0)

strip = lambda s: re.sub(r"\x1b\[[0-9;]*m", "", s or "")
verdict = strip(summary.get("verdict")) or ("exit " + str(res.returncode))
problem = strip(summary.get("matrix_problem"))
touched = summary.get("tests_touched") or []
# Not run: BUSY (another run held the test lock; the gate writes status UNTESTED, label BUSY) or
# UNTESTED (cannot run on this machine). Nothing to fix in the change (2026-09-27: 6 BUSY suites
# were listed as failures, with "fix code/test").
busy = [t for t in summary.get("regression_tests", []) if t.get("status") in ("UNTESTED", "BUSY")]
failing = [t for t in summary.get("regression_tests", []) if t.get("status") != "PASS" and t not in busy]

def in_head(path):
    # candidates may not exist in the tree (deleted): map through the real repo path
    rel_top = os.path.relpath(os.path.join(os.path.realpath(repo), os.path.relpath(path, repo)), toplevel)
    return subprocess.run(["git", "-C", toplevel, "cat-file", "-e", "HEAD:" + rel_top.replace(os.sep, "/")],
                          capture_output=True).returncode == 0

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

# With an untrusted matrix the gate computed UNCOVERED against no rule at all (every
# changed source file). List only files that no matrix of the project watches.
pats = watch_patterns()
uncovered = [f for f in summary.get("uncovered", []) if not watched(f, pats)]
cure_commit = ("commit " + rel + " (the gate trusts only a committed matrix, or one byte-identical to `agent-kit matrix`)")
uncommitted = bool(problem) and not in_head(matrix)
shadowed = [os.path.relpath(c, repo) for c in candidates[candidates.index(matrix) + 1:] if in_head(c)] if uncommitted else []

if res.returncode == 2 and uncommitted and not shadowed and not touched and not failing \
        and not summary.get("findings") and not summary.get("unreadable"):
    # The matrix is the only problem and it is uncommitted: no test ran, and only a commit
    # (a human decision) makes it trusted. Blocking would stop every turn until then; say
    # it to the user once per change, like UNTESTED, and let the stop through.
    if degraded:
        sess.update({"fp": tree_fp, "result": "matrix"})
        save_state()
    if state.get("matrix_fp") != fp:
        state["matrix_fp"] = fp
        save_state()
        msg = ("⚠ Regression gate KHÔNG chạy test hồi quy: `" + rel + "` chưa commit nên gate chưa tin nó. "
               "Cần làm: " + cure_commit + ".")
        if uncovered:
            msg += (" Ngoài ra %d file code đổi mà ma trận này không theo dõi (thêm vào watch_files): %s."
                    % (len(uncovered), ", ".join(uncovered[:10])))
        print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
    note(f"matrix uncommitted fp={fp}")
    sys.exit(0)

if res.returncode == 1 and failing and all(t.get("env_blocked") for t in failing) and not touched \
        and not problem and not uncovered and not summary.get("findings") and not summary.get("unreadable"):
    # Every failing test failed because this machine cannot provision its tools (toolchain,
    # SDK, network): no test ran and no code change fixes it. Blocking again only loops the
    # session; say it once per change, like UNTESTED, and let the stop through (still REJECT).
    if degraded:
        sess.update({"fp": tree_fp, "result": "env"})
        save_state()
    if state.get("env_fp") != fp:
        state["env_fp"] = fp
        save_state()
        names = ["%s (%s)" % (t.get("id"), t.get("command")) for t in failing]
        print(json.dumps({"systemMessage": "Regression gate REJECT vì môi trường — máy này thiếu công cụ/SDK/mạng nên "
                          "test không chạy, KHÔNG phải PASS: " + "; ".join(names)
                          + ". Chạy lại trên máy có đủ công cụ trước khi báo xong."}, ensure_ascii=False))
    note(f"env-blocked fp={fp}")
    sys.exit(0)

lines = ["Regression gate CHƯA ĐẠT — " + verdict]
if problem and uncommitted:
    lines.append("  - MATRIX: %s — `%s` che mất ma trận đã commit %s: %s, hoặc xoá nó."
                 % (problem, rel, ", ".join(shadowed), cure_commit))
elif problem:
    lines.append("  - MATRIX: %s — cần người review sửa đổi ở `%s` rồi commit, hoặc hoàn tác nó; KHÔNG sửa ma trận "
                 "để lách test (have a human review the matrix edit and commit it, or revert it)." % (problem, rel))
for t in failing:
    # The label says what failed (VACUOUS: the command exits 0, the test caught nothing when the
    # production diff was reverted — OfficeReader 2026-09-26); the reason and the log follow.
    what = t.get("label") if t.get("label") not in (None, "", t.get("status")) else t.get("status")
    extra = "" if t.get("exit_code") in (None, "") else ", exit %s" % t.get("exit_code")
    lines.append("  - %s %s: %s (lệnh: %s%s)" % (t.get("id"), t.get("name"), what, t.get("command"), extra))
    why = [l.strip() for l in strip(t.get("output_tail") or "").splitlines() if l.strip()]
    if what != "FAIL" and why:
        lines.append("      lý do: " + why[0][:300])
    if t.get("log"):
        lines.append("      log: " + str(t.get("log")))
for t in busy:
    lines.append("  - %s %s: %s — chưa chạy (%s); KHÔNG phải PASS" % (
        t.get("id"), t.get("name"), t.get("label") or t.get("status"),
        "một lượt khác giữ khoá test, chạy lại sau" if t.get("label") == "BUSY"
        else "hết ngân sách thời gian, chạy lại sau" if t.get("label") == "BUDGET" else "không chạy được trên máy này"))
for f in summary.get("findings", [])[:10]:
    # static findings (secrets, placeholders, dependencies …) with the exact place to fix
    lines.append("  - %s %s:%s: %s" % (f.get("category"), f.get("file"), f.get("line") or "?", f.get("message")))
for f in touched[:10]:
    lines.append("  - TEST ĐÃ CÓ BỊ SỬA/XOÁ: %s — cần người review diff test (`git diff HEAD -- %s`): hỏi NGAY trong lượt "
                 "bằng AskUserQuestion (câu hỏi nêu đường dẫn file + diff, phương án đầu \"Duyệt\"; gate nhận câu trả lời, "
                 "không cần commit) hoặc commit nó; không sửa test cũ để lách" % (f, f))
for f in uncovered[:10]:
    lines.append("  - UNCOVERED:%s — file code đổi nhưng chưa test hồi quy nào theo dõi" % f)
lines.append("Checklist: %s · báo cáo: %s" % (summary.get("checklist", ".agents/CHECKLIST.md"), summary.get("report", "-")))

# The cure matches what is actually wrong: a matrix or an edited test needs a person,
# a failing test / finding needs a code fix, an uncovered file needs a test mapping.
cure = []
if failing or summary.get("findings") or summary.get("unreadable") or not (problem or touched or uncovered):
    cure.append("Sửa code/test cho các mục trên rồi dừng lại. Không sửa test cũ để lách.")
if uncovered:
    cure.append("File chưa có test: thêm test vào regression_matrix.json "
                "hoặc `python3 bin/regression_checklist.py link UNCOVERED:<file> <TEST-ID>`.")
cure.append("Nếu thực sự không làm được, dừng và nói rõ cho người dùng.")

if res.returncode == 2 and touched and not failing and not problem and not uncovered \
        and not summary.get("findings") and not summary.get("unreadable"):
    # Only a person clears an edited existing test (review the diff, or commit it). Block ONCE per
    # change so the agent tells the user; later stops of the same change go through with a
    # reminder instead of blocking every turn (2026-09-25: 6 consecutive stops blocked).
    if state.get("touched_fp") == fp:
        note(f"tests-touched reminder fp={fp}")
        print(json.dumps({"systemMessage": "\n".join(["⚠ Vẫn chờ người duyệt diff test (không chặn lại, KHÔNG phải PASS):"]
                                                     + lines[1:])}, ensure_ascii=False))
        sys.exit(0)
    state["touched_fp"] = fp
    save_state()
# An edited existing test is cleared by the answer of the user in the transcript, a BUSY item by the lock
# going free — neither by the tree: such a block is never re-used.
block(lines, cure, res.returncode, reusable=not touched and not busy)
' || exit $?
