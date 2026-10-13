#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# review_gate.sh — Stop hook: enforce a FRESH-CONTEXT review of uncommitted
# code changes before Claude can finish (kills "self-audit misses bugs"). "Code" =
# the active profile's source_extensions (hooks/devkit_profile.py): .ts/.tsx on web,
# .swift on iOS, .py/.go/.rs on backend, .kt/.java on Android; every language when
# no profile is active. $DEVKIT_SOURCE_EXTS overrides.
#
# Rationale: when Claude audits its own code it is anchored on the mental model
# it used to write it → blind spots survive all 7 self-lenses. The fix is an
# independent reviewer with fresh context. This gate makes that non-optional.
#
# BLOCK (exit 2) when BOTH hold:
#   • uncommitted code changes exist, AND
#   • no supported review ran AFTER the last code Edit/Write this session —
#     i.e. either none ran, or the last one ran before the latest code change
#     (the "reviewed-then-kept-coding" hole).
# Review = Agent/Task tool_use with subagent_type ∈ REVIEW_AGENTS, or a Skill
# invocation of code-review / review-pr / open-code-review.
#
# Loop-guard: per-session attempts file, MAX_ATTEMPTS — release with a logged
# warning if the environment genuinely can't run reviews (avoid infinite block).
# The release covers ONE stuck episode: writing more unreviewed code afterwards
# (a later edit, a file the release did not cover, or a file touched after the
# release time) re-arms the gate and it blocks again.
# Fail-open on any internal error (never block Claude because of a gate bug).
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
if [ -z "${REPO_ROOT}" ]; then   # the regex costs ~10 ms on a 1 MB payload: only when it is needed
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
LOG_DIR="${REPO_ROOT:+${REPO_ROOT}/.claude/audit-gate}"
# No project: the loop guard below has nowhere to count re-Stops, and a gate that cannot count could hold every Stop.
[ -n "${LOG_DIR}" ] || exit 0
mkdir -p "${LOG_DIR}"
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LOG="${LOG_DIR}/review_gate.log"
MAX_ATTEMPTS="${REVIEW_GATE_MAX_ATTEMPTS:-3}"

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ review_gate: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable python could not
# start and the gate passed (tests/gates/test_hook_large_payload.sh).
CLAIM_LOG="${LOG}" CLAIM_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
CLAIM_REPO="${REPO_ROOT}" CLAIM_LOGDIR="${LOG_DIR}" CLAIM_MAX="${MAX_ATTEMPTS}" \
CLAIM_HOOKDIR="$(cd "$(dirname "$0")" && pwd)" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, sys, json, re, subprocess, time

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
log     = os.environ.get("CLAIM_LOG", "/dev/null")
ts      = os.environ.get("CLAIM_TS", "?")
repo    = os.environ.get("CLAIM_REPO", ".")
logdir  = os.environ.get("CLAIM_LOGDIR", ".")
try:
    maxatt = int(os.environ.get("CLAIM_MAX", "3") or "3")
except ValueError:          # QA K-6: non-numeric env var → default, not a crash
    maxatt = 3

REVIEW_AGENTS = {
    # App project agents (AGENTS.md / CLAUDE.md)
    "principal-code-reviewer", "exampleapp-code-reviewer",
    "test-architect-seti",
    "android-principal-architect",
    # legacy / optional plugin reviewer agents
    "silent-failure-hunter", "code-reviewer", "pr-test-analyzer",
    "type-design-analyzer",
    # plugin-namespaced forms
    "pr-review-toolkit:silent-failure-hunter",
    "pr-review-toolkit:code-reviewer",
    "pr-review-toolkit:pr-test-analyzer",
    "pr-review-toolkit:type-design-analyzer",
}
REVIEW_SKILLS = {"code-review", "review-pr", "pr-review-toolkit:review-pr",
                 "review-changes", "open-code-review",
                 # multi-lens-audit is exposed as a SKILL in this harness, not as a
                 # `Workflow` tool. Accepting it only via REVIEW_WORKFLOWS below meant
                 # running the very audit CLAUDE.md prescribes still got you blocked.
                 "multi-lens-audit"}
REVIEW_WORKFLOWS = {"multi-lens-audit"}

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

# A progress reply (status line CHƯA XONG / CHỜ DUYỆT …, no outcome claimed, no git commit/push
# this turn): the fresh-context review is asked at the handover turn, not on every stop (T0003).
for _hd in (os.environ.get("CLAIM_HOOKDIR", ""),
            os.path.dirname(os.path.realpath(os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "review_gate.sh"))),
            os.path.join(repo, ".agents", "devkit", "hooks")):
    if os.path.isfile(os.path.join(_hd, "devkit_harness.py")):
        try:
            sys.path.insert(0, _hd)
            sys.dont_write_bytecode = True
            import devkit_harness
            if devkit_harness.work_in_progress(d):
                logline(f"[{ts}] skip: work in progress — review at the handover turn")
                sys.exit(0)
        except SystemExit:
            raise
        except Exception as e:
            logline(f"[{ts}] work_in_progress failed: {e!r}")
        break

cwd = d.get("cwd") or repo
try:
    repo_root = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=10, check=True).stdout.strip()
except Exception:
    repo_root = repo

# Per-session attempts file + reset helper (hoisted so PASS paths can clear it).
# Reset on every clean exit so MAX bounds each *stuck episode*, not the whole
# session — otherwise the counter grows monotonically and the gate silently
# self-disables after a few unrelated blocks.
sid = re.sub(r"[^A-Za-z0-9_-]", "_", str(d.get("session_id", "default")))[:64] or "default"
attempt_file = os.path.join(logdir, f"review_attempts_{sid}.txt")
def reset_attempts():
    try:
        if os.path.exists(attempt_file):
            os.remove(attempt_file)
    except Exception:
        pass

try:
    sys.dont_write_bytecode = True  # no __pycache__ inside the project's .claude/hooks
    sys.path.insert(0, os.environ.get("CLAIM_HOOKDIR", ""))
    from devkit_profile import source_exts
    CODE_EXTS = source_exts(repo_root)
except Exception:
    CODE_EXTS = (".kt", ".java")
PATHSPECS = ["*" + e for e in CODE_EXTS]

# ── 1) uncommitted code changes? — modified-tracked + staged + UNTRACKED.
#       Untracked new .kt (created via Write, not yet `git add`) is the most
#       important to review, yet `git diff HEAD` omits it → union ls-files. ──
try:
    diff = subprocess.run(
        ["git", "-C", repo_root, "diff", "--name-only", "HEAD", "--", *PATHSPECS],
        capture_output=True, text=True, timeout=10)
    untracked = subprocess.run(
        ["git", "-C", repo_root, "ls-files", "--others", "--exclude-standard",
         "--", *PATHSPECS],
        capture_output=True, text=True, timeout=10)
    # A symlink's content is a path, not code to review (DevKit hook links such as
    # .claude/hooks/devkit_profile.py in a symlink install).
    # Commits past the last verified HEAD (T0003): code committed mid-work still needs its review.
    since = []
    try:
        import devkit_harness as _dh
        _vh = _dh.verified_head(repo_root, write=False)[0]
        since = [f for f in _dh.files_since(repo_root, _vh) if f.endswith(tuple(CODE_EXTS))]
    except Exception as e:
        logline(f"[{ts}] since-files failed: {e!r}")
    changed = sorted({l for l in (diff.stdout.splitlines() + untracked.stdout.splitlines() + since)
                      if l.strip() and not os.path.islink(os.path.join(repo_root, l))})
except Exception as e:
    logline(f"[{ts}] git query failed: {e!r} — fail-open")
    sys.exit(0)

if not changed:
    reset_attempts()
    logline(f"[{ts}] no uncommitted code ({'|'.join(CODE_EXTS)}) — pass")
    sys.exit(0)

# OpenCodeReview, full mode (REVIEW_GATE_OCR=full, 2026-10-13): one full LLM review per state of the unreviewed code, run in the
# background (the hook has 20 s, a review ~80 s), kept in <repo>/.git/ocr-review/full-<hash>/ and shared by sessions.
OCR_MODE = os.environ.get("REVIEW_GATE_OCR", "1")


OCR_REVIEW_TIMEOUT_S = 900   # bin/ocr-review stops `ocr review` there: a pid file older than this (+ margin) is not a running review
OCR_KEEP_RUNS = 10
_OCR_ROOT = []


def _ocr_root():
    """<git dir>/ocr-review of the repo the gate checks (a worktree: its own git dir; never the working tree), else a per-repo
    folder under the system temp dir (bin/ocr-review refuses it when it is a symlink or another user's)."""
    if not _OCR_ROOT:
        import hashlib, tempfile
        try:
            gd = subprocess.run(["git", "-C", repo_root, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True,
                                timeout=5, check=True).stdout.strip()
        except Exception as e:
            logline(f"[{ts}] git dir for OCR failed: {e!r} — temp dir")
            gd = ""
        _OCR_ROOT.append(os.path.join(gd, "ocr-review") if gd and os.path.isdir(gd) else os.path.join(
            tempfile.gettempdir(), "ocr-review-" + hashlib.sha256(os.path.realpath(repo_root).encode()).hexdigest()[:12]))
    return _OCR_ROOT[0]


def _code_hash():
    import hashlib
    h = hashlib.sha256()
    for rel in changed:
        h.update(rel.encode("utf-8", "surrogateescape") + b"\0")
        try:
            with open(os.path.join(repo_root, rel), "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
        except OSError:
            h.update(b"-")
    return h.hexdigest()[:16]


def _full_dir():
    return os.path.join(_ocr_root(), "full-" + _code_hash())


def _full_report(fdir):
    """The comments of a finished full review in fdir, or None (none yet, or not a full review)."""
    try:
        with open(os.path.join(fdir, "ocr-review.json"), encoding="utf-8") as fh:
            rep_ = json.load(fh)
        # an error object, another schema or a partial write is no review (OCR, 13/10): only a real comments list counts
        return rep_["comments"] if isinstance(rep_, dict) and isinstance(rep_.get("comments"), list) else None
    except (OSError, ValueError):
        return None


def _valid_ocr_report(rp, newest):
    """rp is an OCR JSON report (an object with a comments list) written after the newest edited file (mtime `newest`)."""
    try:
        if os.path.getmtime(rp) < newest:
            return False
        with open(rp, encoding="utf-8") as fh:
            rep_ = json.load(fh)
        return isinstance(rep_, dict) and isinstance(rep_.get("comments"), list)
    except (OSError, ValueError):
        return False


def _prune_full_runs(keep_dir):
    """Keep the newest OCR_KEEP_RUNS full-* runs (each new code state makes one; nothing else removes them)."""
    import shutil
    root = _ocr_root()
    try:
        runs = sorted((os.path.join(root, n) for n in os.listdir(root) if n.startswith("full-")),
                      key=os.path.getmtime, reverse=True)
    except OSError as e:
        logline(f"[{ts}] OCR prune: {e!r}")
        return
    for old in runs[OCR_KEEP_RUNS:]:
        if os.path.realpath(old) != os.path.realpath(keep_dir):
            try:
                shutil.rmtree(old)
            except OSError as e:
                logline(f"[{ts}] OCR prune {os.path.basename(old)}: {e!r}")


def _shown_to(fdir):
    try:
        with open(os.path.join(fdir, "shown"), encoding="utf-8") as fh:
            return sid in fh.read().split()
    except OSError:
        return False


def in_diff(fp):
    """Does an absolute edit path correspond to an uncommitted diff entry?"""
    absolute = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(cwd, fp))
    rel = os.path.relpath(absolute, repo_root).replace(os.sep, "/")
    return rel if rel in changed else None

# ── 2) scan transcript: only .kt files edited THIS SESSION *and* uncommitted
#       count — unrelated pre-existing dirty files must not trap the gate. ──
tp = d.get("transcript_path")
last_edit_idx = -1
last_review_idx = -1
session_unreviewed = set()   # diff paths edited by me this session
idx = 0
# OpenCodeReview (2026-10-13): a FULL review that succeeded counts as the fresh review. The command must START a command segment
# (`echo ocr review` is not one), and a REPORT decides, never a word in the output (OpenCodeReview of this gate, 13/10: `--help`,
# `echo mode: review` and other wording passed): the helper's `report: <file>` (in `mode: review`; a delegation spec alone means
# nobody reviewed yet) or a plain `ocr review … -o <file>` must be an OCR JSON report (an object with a `comments` list) written
# after the newest file this session edited. `--help` / `-h` / `--version`: not a review.
OCR_CMD = re.compile(r"(?:^|[;&|(\n]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:python3?\s+)?(?:\S*/)?(ocr-review|ocr\s+(?:review|r))\b")
ocr_pending = {}   # tool_use id -> (transcript index, "helper" | "plain", command)
ocr_reports = []   # (transcript index, report path) of OCR runs that named a report
OCR_NOT_A_RUN = re.compile(r"(?:^|\s)(?:--help|-h|--version)(?:\s|$)")


def _ocr_report_path(kind, cmd, txt):
    import shlex
    if OCR_NOT_A_RUN.search(cmd):
        return ""
    if kind == "helper":
        if "mode: review" not in txt:
            return ""
        rp = next((l[8:].strip() for l in txt.splitlines() if l.startswith("report: ")), "")
    else:
        try:
            words = shlex.split(cmd)
        except ValueError:
            return ""
        rp = next((words[i + 1] for i, w in enumerate(words[:-1]) if w in ("-o", "--output")), "")
    return os.path.join(cwd, rp) if rp and not os.path.isabs(rp) else rp

def _result_text(blk):
    c = blk.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""
if tp and os.path.exists(tp):
    with open(tp) as fh:
        for rawline in fh:
            rawline = rawline.strip()
            if not rawline:
                continue
            try:
                rec = json.loads(rawline)
            except Exception:
                continue
            m = rec.get("message") or {}
            content = m.get("content")
            if not isinstance(content, list):
                continue
            for blk in content:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in ocr_pending:
                    at, kind, ocmd = ocr_pending.pop(blk.get("tool_use_id"))
                    _rp = "" if blk.get("is_error") else _ocr_report_path(kind, ocmd, _result_text(blk))
                    if _rp:
                        ocr_reports.append((at, _rp))
                    continue
                if not isinstance(blk, dict) or blk.get("type") != "tool_use":
                    continue
                idx += 1
                name = blk.get("name", "")
                inp = blk.get("input") or {}
                if name in ("Edit", "Write", "NotebookEdit"):
                    fp = inp.get("file_path") or inp.get("notebook_path") or ""
                    if isinstance(fp, str) and fp.endswith(CODE_EXTS):
                        hit = in_diff(fp)
                        if hit:
                            last_edit_idx = idx
                            session_unreviewed.add(hit)
                elif name in ("Agent", "Task"):
                    st = inp.get("subagent_type", "")
                    if st in REVIEW_AGENTS:
                        last_review_idx = idx
                elif name == "Skill":
                    sk = inp.get("skill", "") or inp.get("command", "")
                    if sk in REVIEW_SKILLS:
                        last_review_idx = idx
                elif name == "Bash":
                    om = OCR_CMD.search(str(inp.get("command") or ""))
                    if om and blk.get("id"):
                        ocr_pending[blk.get("id")] = (idx, "helper" if om.group(1) == "ocr-review" else "plain",
                                                      str(inp.get("command") or ""))
                elif name == "Workflow":
                    wf = inp.get("name", "") or ""
                    scr = inp.get("script", "") or ""
                    if wf in REVIEW_WORKFLOWS or "multi-lens-audit" in scr:
                        last_review_idx = idx

# An OCR report counts only when it is newer than every file this session edited (a report from before the last edit is stale).
if ocr_reports:
    _newest = 0.0
    for _f in session_unreviewed:
        try:
            _newest = max(_newest, os.path.getmtime(os.path.join(repo_root, _f)))
        except OSError:
            pass   # deleted since the edit: nothing newer to compare
    for _at, _rp in ocr_reports:
        if _valid_ocr_report(_rp, _newest):
            last_review_idx = max(last_review_idx, _at)
        else:
            logline(f"[{ts}] OCR run at #{_at} named {_rp}: not a fresh OCR report — not counted")

# No .kt edited by me this session (the dirty files are pre-existing /
# someone else's) → nothing of mine to gate.
if last_edit_idx == -1:
    reset_attempts()
    logline(f"[{ts}] uncommitted code exists but none edited this session "
            f"({changed}) — pass")
    sys.exit(0)

reviewed_after_edits = last_review_idx > last_edit_idx and last_review_idx != -1

# A full review diffs the workspace: code committed past verified_head (`since`) is not in it, so it never passes that (OCR, 13/10).
if not reviewed_after_edits and OCR_MODE == "full" and not since:
    try:
        _fd = _full_dir()
        if _full_report(_fd) is not None and _shown_to(_fd):
            reset_attempts()
            logline(f"[{ts}] OCR full review of this code shown to this session ({os.path.basename(_fd)}) — pass")
            sys.exit(0)
    except SystemExit:
        raise
    except Exception as _e:
        logline(f"[{ts}] OCR full check failed: {_e!r}")

if reviewed_after_edits:
    reset_attempts()
    logline(f"[{ts}] review ran after last .kt edit "
            f"(edit#{last_edit_idx} < review#{last_review_idx}) — pass")
    sys.exit(0)

# ── 3) would block — apply loop-guard (attempt_file hoisted above) ──
# The release covers ONE stuck episode, not the rest of the session. While an
# episode is live the file holds the bare attempt count; on release it holds JSON
# {"n", "released_at", "released_time", "files"} — the transcript index, wall-clock
# time and file set that release covered. The older shapes ("3", "4:97") are still
# read, so a file written by a previous version never crashes the gate.
#
# Measured on OfficeReader (2026-09-08), with a bare counter that only a PASS reset:
# three real blocks followed by 34 consecutive "BLOCK suppressed" lines to the end
# of the session — every code file written after the release went unreviewed with
# nothing left to notice. Writing MORE unreviewed code now starts a new episode.
# Three re-arm signals, because each one alone has a hole:
#   • a later edit index      — misses a transcript COMPACTED shorter mid-session;
#   • an unreviewed file the release did not cover — misses the same file again;
#   • a file mtime after the release time — survives compaction of the same file.
n = 0
released_at = None
released_files = set()
released_time = None
try:
    if os.path.exists(attempt_file):
        raw_att = open(attempt_file).read().strip()
        if raw_att.startswith("{"):
            rec_att = json.loads(raw_att)
            n = int(rec_att.get("n", 0))
            released_at = rec_att.get("released_at")
            released_files = set(rec_att.get("files") or [])
            released_time = rec_att.get("released_time")
        elif ":" in raw_att:
            n_str, rel_str = raw_att.split(":", 1)
            n = int(n_str or "0")
            released_at = int(rel_str)
        else:
            n = int(raw_att or "0")
except Exception:
    n, released_at, released_files, released_time = 0, None, set(), None

def _wrote_since_release():
    if not isinstance(released_time, (int, float)):
        return False
    for rel in session_unreviewed:
        try:
            if os.path.getmtime(os.path.join(repo_root, rel)) > released_time:
                return True
        except Exception:
            continue
    return False

if released_at is not None:
    try:
        newer_edit = last_edit_idx > int(released_at)
    except Exception:
        newer_edit = True
    if newer_edit or (session_unreviewed - released_files) or _wrote_since_release():
        n, released_at = 0, None      # new unreviewed code → new episode, re-arm
    else:
        logline(f"[{ts}] BLOCK suppressed — same stuck episode "
                f"(edit#{last_edit_idx} <= released#{released_at}), "
                f"manual review still required for {changed}")
        sys.stderr.write(
            f"⚠️ REVIEW-GATE: vẫn là episode đã thả — {len(changed)} file code CHƯA "
            f"được review context-sạch, tự chịu trách nhiệm review thủ công.\n")
        sys.exit(0)

n += 1
if n > maxatt:
    try:
        with open(attempt_file, "w") as fh:
            json.dump({"n": n, "released_at": last_edit_idx,
                       "released_time": time.time(),
                       "files": sorted(session_unreviewed)}, fh)
    except Exception:
        pass
    logline(f"[{ts}] BLOCK suppressed after {maxatt} attempts (anti-loop) — "
            f"manual review still required for {changed}")
    sys.stderr.write(
        f"⚠️ REVIEW-GATE: đã nhắc {maxatt} lần, thả Stop để tránh kẹt loop.\n"
        f"   Nhưng {len(changed)} file code vẫn CHƯA được review context-sạch — "
        f"tự chịu trách nhiệm review thủ công.\n"
        f"   Viết THÊM code chưa review sẽ kích hoạt lại gate.\n")
    sys.exit(0)

try:
    with open(attempt_file, "w") as fh:
        fh.write(str(n))
except Exception:
    pass

unrev = sorted(session_unreviewed)
logline(f"[{ts}] BLOCK (attempt {n}/{maxatt}) — unreviewed code: {unrev}")
lines = [
    "⛔ REVIEW-GATE: thay đổi code chưa được review bằng CONTEXT SẠCH.",
    "",
    f"{len(unrev)} file code tôi sửa session này (chưa commit), chưa có",
    "fresh-context review chạy SAU lần edit cuối (self-audit không tính — điểm mù):",
    "",
]
for f in unrev[:20]:
    lines.append(f"  • {f}")
if len(unrev) > 20:
    lines.append(f"  … +{len(unrev)-20} file nữa")
lines += [
    "",
    "Bắt buộc trước khi xong — chạy review CONTEXT SẠCH (chọn 1):",
    "  A) Agent principal-code-reviewer (DevKit cài sẵn ở .claude/agents) trên diff.",
    "  B) Hoặc Skill code-review / open-code-review trên diff.",
    "  C) Nếu đổi test/CI: thêm test-architect-seti; Android đổi kiến trúc/API: android-principal-architect.",
    "  D) Hoặc Workflow 'multi-lens-audit' nếu môi trường hỗ trợ workflow.",
    "Gom finding → fix theo CLASS (không chỉ instance) → rồi mới stop.",
]
# OpenCodeReview, run by the gate itself on this block path only (2026-10-13, user: run ocr review in every repo): the delegation
# mode needs no LLM and no key (~1 s); its spec goes to the reviewer. REVIEW_GATE_OCR=0: off.
_full_lines = []
if OCR_MODE == "full":
    _helper = os.path.realpath(os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "..", "bin", "ocr-review"))
    try:
        _fd = _full_dir()
        _comments = _full_report(_fd)
        if _comments is not None:
            _sev = {"critical": 0, "high": 1, "medium": 2, "low": 3}
            _top = sorted(_comments, key=lambda c: _sev.get(str(c.get("severity", "")).lower(), 4))[:8]
            _full_lines = ["", f"OCR review đầy đủ cho đúng code này đã xong: {len(_comments)} phát hiện "
                               f"(report {os.path.join(_fd, 'ocr-review.json')}). Xử lý từng cái (sửa, hoặc nói vì sao không):"]
            for c in _top:
                _txt = " ".join(str(c.get("content") or c.get("message") or "").split())[:240]
                _full_lines.append(f"  • [{c.get('severity', '?')}] {c.get('path', '?')}:{c.get('start_line', '?')} — {_txt}")
            if len(_comments) > len(_top):
                _full_lines.append(f"  … +{len(_comments) - len(_top)} phát hiện nữa trong report")
            _full_lines.append("  Code không đổi thêm thì Stop sau được tính là đã review; sửa code thì OCR review lại."
                               if not since else
                               f"  {len(since)} file code đã commit sau lần xác minh cuối không nằm trong review này (OCR chỉ diff "
                               "workspace): phần đó vẫn cần review context sạch (A–D).")
            with open(os.path.join(_fd, "shown"), "a", encoding="utf-8") as fh:
                fh.write(sid + "\n")
            logline(f"[{ts}] OCR full review shown: {len(_comments)} finding(s) ({os.path.basename(_fd)})")
        elif os.path.isfile(_helper):
            _pidf = os.path.join(_fd, "pid")
            _running = False
            try:   # older than the helper's own bound: a recycled pid, not a running review
                _age = time.time() - os.path.getmtime(_pidf)
                with open(_pidf) as fh:
                    _ptxt = fh.read().strip()
                if _age < OCR_REVIEW_TIMEOUT_S + 120:
                    if _ptxt:
                        os.kill(int(_ptxt), 0)
                        _running = True
                    else:
                        _running = _age < 30   # claimed by another Stop a moment ago, its pid not written yet
            except (OSError, ValueError):
                _running = False
            _running_line = ["", "OCR review đầy đủ (LLM) đang chạy ở nền cho code này; Stop sau sẽ có kết quả."]
            if _running:
                _full_lines = _running_line
            elif not os.path.isfile(_pidf):
                os.makedirs(_fd, mode=0o700, exist_ok=True)
                try:   # claim the run first: two Stops at once start one review, not two writing the same report
                    _pfd = os.open(_pidf, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                except FileExistsError:
                    _pfd = None
                if _pfd is None:
                    _full_lines = _running_line
                else:
                    with open(os.path.join(_fd, "run.log"), "w") as _lg:
                        _pr = subprocess.Popen([sys.executable, "-I", _helper, "--out", _fd], cwd=repo_root,
                                               stdin=subprocess.DEVNULL, stdout=_lg, stderr=subprocess.STDOUT, start_new_session=True)
                    with os.fdopen(_pfd, "w") as fh:
                        fh.write(str(_pr.pid))
                    _full_lines = ["", "OCR review đầy đủ (LLM, ~1–2 phút) đã khởi động ở nền cho code này; Stop sau sẽ có kết quả."]
                    logline(f"[{ts}] OCR full review started in the background pid={_pr.pid} ({os.path.basename(_fd)})")
                    _prune_full_runs(_fd)
            else:   # ended without a report (no endpoint, error): the delegation spec below is the way
                logline(f"[{ts}] OCR full review ended without a report ({os.path.basename(_fd)}) — delegation only")
    except Exception as _e:   # OCR is an aid here, never a reason to fail the gate
        logline(f"[{ts}] OCR full review failed: {_e!r}")
lines += _full_lines
if os.environ.get("REVIEW_GATE_OCR", "1") != "0" and not any("đã xong" in l for l in _full_lines):
    _helper = os.path.realpath(os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "..", "bin", "ocr-review"))
    try:
        if os.path.isfile(_helper):
            # one folder per repo, in its git dir (never in the working tree; the message names the repo path, so it reads the same
            # on every run), of the repo the gate checks (repo_root, the cwd's toplevel; not CLAUDE_PROJECT_DIR: OCR, 13/10);
            # -I like every hook python: a module planted in the repo or PYTHONPATH must not run here
            # (tests/gates/test_hook_python_isolation.sh)
            _out = _ocr_root()
            # 14 s: past the helper's own bound (2 x 6 s per ocr call) and inside the hook's 20 s, which Claude Code enforces by
            # killing the hook, and a killed Stop hook lets the Stop through unreviewed (tests/gates/test_review_gate_ocr.sh)
            _r = subprocess.run([sys.executable, "-I", _helper, "--delegate-only", "--out", _out], cwd=repo_root,
                                capture_output=True, text=True, timeout=14)
            _spec = next((l[6:].strip() for l in _r.stdout.splitlines() if l.startswith("spec: ")), "")
            if _r.returncode == 0 and _spec:
                lines += ["", "OCR (OpenCodeReview) đã tự chạy chế độ delegation: spec " + _spec,
                          "  → giao spec này cho reviewer ở mục A; có khoá LLM thì chạy .agents/devkit/bin/ocr-review để OCR tự review "
                          "(một lượt OCR review thành công sau lần sửa cuối được tính)."]
            logline(f"[{ts}] ocr-review --delegate-only rc={_r.returncode} spec={_spec or '-'}")
    except Exception as _e:   # OCR is an aid here, never a reason to fail the gate
        logline(f"[{ts}] ocr-review failed: {_e!r}")
sys.stderr.write("\n".join(lines) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
