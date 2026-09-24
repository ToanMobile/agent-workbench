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

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}"
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LOG="${LOG_DIR}/review_gate.log"
MAX_ATTEMPTS="${REVIEW_GATE_MAX_ATTEMPTS:-3}"

INPUT="$(cat)"

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ review_gate: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
CLAIM_INPUT="${INPUT}" CLAIM_LOG="${LOG}" CLAIM_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
CLAIM_REPO="${REPO_ROOT}" CLAIM_LOGDIR="${LOG_DIR}" CLAIM_MAX="${MAX_ATTEMPTS}" \
CLAIM_HOOKDIR="$(cd "$(dirname "$0")" && pwd)" \
python3 <<'PY'
import os, sys, json, re, subprocess, time

raw     = os.environ.get("CLAIM_INPUT", "")
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
    changed = sorted({l for l in (diff.stdout.splitlines() + untracked.stdout.splitlines())
                      if l.strip() and not os.path.islink(os.path.join(repo_root, l))})
except Exception as e:
    logline(f"[{ts}] git query failed: {e!r} — fail-open")
    sys.exit(0)

if not changed:
    reset_attempts()
    logline(f"[{ts}] no uncommitted code ({"|".join(CODE_EXTS)}) — pass")
    sys.exit(0)

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
                elif name == "Workflow":
                    wf = inp.get("name", "") or ""
                    scr = inp.get("script", "") or ""
                    if wf in REVIEW_WORKFLOWS or "multi-lens-audit" in scr:
                        last_review_idx = idx

# No .kt edited by me this session (the dirty files are pre-existing /
# someone else's) → nothing of mine to gate.
if last_edit_idx == -1:
    reset_attempts()
    logline(f"[{ts}] uncommitted code exists but none edited this session "
            f"({changed}) — pass")
    sys.exit(0)

reviewed_after_edits = last_review_idx > last_edit_idx and last_review_idx != -1

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
sys.stderr.write("\n".join(lines) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
