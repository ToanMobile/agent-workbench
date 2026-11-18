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
#   • no supported review ran AFTER the last code Edit/Write this session (or Bash
#     command that names a code file changed after it started) —
#     i.e. either none ran, or the last one ran before the latest code change
#     (the "reviewed-then-kept-coding" hole).
# Review = Agent/Task tool_use with subagent_type ∈ REVIEW_AGENTS, or a Skill
# invocation of code-review / review-pr / open-code-review, or a full OCR review.
# With `ocr` installed (REVIEW_GATE_REQUIRE_OCR=0: off) an OCR review after the last
# edit is REQUIRED (user, 13/10: OCR always runs again after principal-code-reviewer;
# the two find different defects); `ocr-review` writing its delegation spec (#1332: always,
# OCR's LLM is removed) plus an agent review after it stands in for it (in one message: the
# `ocr-review` call before the Agent call — calls are indexed in the order listed).
# A progress reply (CHƯA XONG, no status line) is reviewed at the handover: a turn that ran
# git push, `gh pr create`, `agent-kit worktree finish|integrate` or super-board-merge-gate.sh
# (also under `timeout N`; not its --dry-run / --preflight) is one unless what it handed over was reviewed.
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
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'   # a JSON-escaped cwd too (é sent escaped, \", \\): tests/gates/test_hook_payload_cwd_escaped.sh
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  case "${_PCWD}" in *\\*) _PCWD="$(python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())' "${_PCWD}" 2>/dev/null)" || _PCWD="." ;; esac
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
# QA K-4: without python3 this gate cannot run — say so instead of passing silently (#754: before W1 v6, which needs it).
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ review_gate: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
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
    echo "⚠ DevKit ${0##*/}: the session's worktree could not be resolved (hooks/session_worktree.py next to the real hook) - judging ${REPO_ROOT}" >&2
  fi
fi
LOG_DIR="${REPO_ROOT:+${REPO_ROOT}/.claude/audit-gate}"
# No project: the loop guard below has nowhere to count re-Stops, and a gate that cannot count could hold every Stop.
[ -n "${LOG_DIR}" ] || exit 0
mkdir -p "${LOG_DIR}"
for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
[ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LOG="${LOG_DIR}/review_gate.log"
MAX_ATTEMPTS="${REVIEW_GATE_MAX_ATTEMPTS:-3}"

# #528: worker của board không chấm main. Worktree liên kết vẫn chạy.
if [ "${SB_BOARD_WORKER:-}" = "1" ] && python3 -I -c 'import os,sys
_d = os.path.dirname(os.path.realpath(sys.argv[1]))
if os.path.isabs(_d): sys.path.append(_d)
import session_worktree as s
raise SystemExit(0 if s.worker_skip_main(sys.argv[2]) else 1)' "$0" "${REPO_ROOT}"; then
  echo "$(date +%Y-%m-%dT%H:%M:%S) SB_BOARD_WORKER skip main" >> "${LOG}"
  exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable python could not
# start and the gate passed (tests/gates/test_hook_large_payload.sh).
CLAIM_LOG="${LOG}" CLAIM_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
CLAIM_REPO="${REPO_ROOT}" CLAIM_LOGDIR="${LOG_DIR}" CLAIM_MAX="${MAX_ATTEMPTS}" \
CLAIM_HOOKDIR="$(cd "$(dirname "$0")" && pwd)" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, sys, json, re, shutil, subprocess, time

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

# A progress reply (status line CHƯA XONG / CHỜ DUYỆT …, no outcome claimed, no git push after the
# turn's last edit): the fresh-context review is asked at the handover turn, not on every stop (T0003).
# Audit 2026-10-25 A3: a push this turn that more edits followed is no handover (devkit_harness.push_after_last_edit), but the code it
# carried must have been reviewed: such a Stop skips only after the scan below finds no push of code edited since the last review.
wip_push_start = None
_HANDOVER_KEYS = ("push", "pr create", "agent-kit", "super-board-merge-gate")   # cheap prefilter: a line with none is no handover
_INTERP = {"python", "python3", "bash", "sh", "zsh"}


# options of .claude/bin/super-board-merge-gate.sh that take a value (its `case "$1"` loop: `shift 2`)
_MG_VALUE_OPTS = {"--config", "--pr", "--expect-head", "--subject", "--body-file", "--lock-timeout", "--stale-after", "--train-receipt"}


def _merge_gate_check_only(args):
    """#992: the merge gate words carry its own --dry-run / --preflight FLAG, read as its arg loop reads them: the word after a value
    option is that option's value (`--subject --dry-run` merges for real). ponytail: a new value option of the merge gate needs adding to
    _MG_VALUE_OPTS; until then its value is read as a flag (the old reading)."""
    i = 0
    while i < len(args):
        if args[i] in ("--dry-run", "--preflight"):
            return True
        i += 2 if args[i] in _MG_VALUE_OPTS else 1
    return False


def _handover_cmd(cmd):
    """The Bash command line hands the work over (04/11): a git push (devkit_harness.git_writes), `gh pr create`, `agent-kit worktree
    finish`, `agent-kit integrate`, super-board-merge-gate.sh — as a command word, read like git_writes (devkit_harness._shell_code: quoted
    text, comments and heredoc bodies are data). ponytail: `bash -c '…'`, eval and aliases are not seen, as in git_writes."""
    if not isinstance(cmd, str) or not any(k in cmd for k in _HANDOVER_KEYS):
        return False
    if "push" in devkit_harness.git_writes(cmd):
        return True
    for seg in devkit_harness._CMD_SPLIT.split(devkit_harness._shell_code(cmd)[0]):
        w = devkit_harness._command_words(seg)
        if w and os.path.basename(w[0]) in ("timeout", "gtimeout"):   # #992: `[g]timeout [-k N|-s SIG|--opt=…] DURATION <cmd>` (merge gate có trần giờ; gtimeout: coreutils macOS)
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[2:] if w[0] in ("-k", "-s", "--kill-after", "--signal") else w[1:]
            w = w[1:]   # DURATION
        if w and os.path.basename(w[0]) in _INTERP:   # python3 …/agent-kit, bash …/super-board-merge-gate.sh
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[1:]
        if not w:
            continue
        c, rest = os.path.basename(w[0]), [x for x in w[1:] if not x.startswith("-")]
        if c == "super-board-merge-gate.sh":
            if not _merge_gate_check_only(w[1:]):   # #992: --dry-run / --preflight chỉ kiểm, không merge: không bàn giao
                return True
        elif (c == "agent-kit" and (rest[:2] == ["worktree", "finish"] or rest[:1] == ["integrate"])) \
                or (c == "gh" and any(w[k] == "pr" and w[k + 1] == "create" for k in range(1, len(w) - 1))):
            return True
    return False


def _handover_in_turn(tp, start):
    """A tool call of the turn (after `start`, epoch) ran a _handover_cmd — devkit_harness.git_writes_in_turn's turn filter. Unreadable:
    True (fail closed: the gate then looks for the handover itself and holds when it cannot find it)."""
    import datetime
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if '"command"' not in raw or not any(k in raw for k in _HANDOVER_KEYS):
                    continue
                try:
                    e = json.loads(raw)
                    t = datetime.datetime.fromisoformat(e.get("timestamp", "").replace("Z", "+00:00")).timestamp()
                except (ValueError, AttributeError):
                    continue
                if t < start or e.get("type") != "assistant":
                    continue
                for c in (e.get("message") or {}).get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use" and _handover_cmd((c.get("input") or {}).get("command", "")):
                        return True
    except OSError:
        return True
    return False


for _hd in (os.environ.get("CLAIM_HOOKDIR", ""),
            os.path.dirname(os.path.realpath(os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "review_gate.sh"))),
            os.path.join(repo, ".agents", "devkit", "hooks")):
    if os.path.isfile(os.path.join(_hd, "devkit_harness.py")):
        try:
            sys.path.insert(0, _hd)
            sys.dont_write_bytecode = True
            import devkit_harness
            if devkit_harness.work_in_progress(d, status_optional=True, repo=repo):
                _tp0 = d.get("transcript_path")
                _st0 = devkit_harness.turn_start(_tp0)
                if _st0 is None or not _handover_in_turn(_tp0, _st0):   # no push, PR, finish, integrate or merge gate this turn
                    logline(f"[{ts}] skip: work in progress — review at the handover turn")
                    sys.exit(0)
                wip_push_start = _st0
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
    since, since_base = [], ""
    try:
        import devkit_harness as _dh
        _vh = _dh.verified_head(repo_root, write=False)[0]
        since = [f for f in _dh.files_since(repo_root, _vh) if f.endswith(tuple(CODE_EXTS)) and not os.path.islink(os.path.join(repo_root, f))]
        since_base = _vh or ""
    except Exception as e:
        logline(f"[{ts}] since-files failed: {e!r}")
    changed = sorted({l for l in (diff.stdout.splitlines() + untracked.stdout.splitlines() + since)
                      if l.strip() and not os.path.islink(os.path.join(repo_root, l))})
    dirty = {l for l in diff.stdout.splitlines() + untracked.stdout.splitlines()   # the code a workspace OCR run sees
             if l.strip() and not os.path.islink(os.path.join(repo_root, l))}
except Exception as e:
    logline(f"[{ts}] git query failed: {e!r} — fail-open")
    sys.exit(0)

if not changed:
    reset_attempts()
    logline(f"[{ts}] no uncommitted code ({'|'.join(CODE_EXTS)}) — pass")
    sys.exit(0)

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


def _reviewed(rep_):
    """An OCR JSON report that reviewed something: an object with a comments list (an error object, another schema or a partial write
    is no review, OCR 13/10), not `status` skipped/error and not 0 files reviewed (code committed before the run: the workspace diff
    is empty, review 13/10)."""
    if not isinstance(rep_, dict) or not isinstance(rep_.get("comments"), list) or rep_.get("status") not in (None, "complete"):
        return False
    summ = rep_.get("summary")
    return not (isinstance(summ, dict) and summ.get("files_reviewed") == 0)


def _valid_ocr_report(rp, newest):
    """rp is an OCR JSON report (an object with a comments list) written after the newest edited file (mtime `newest`)."""
    try:
        if os.path.getmtime(rp) < newest:
            return False
        with open(rp, encoding="utf-8") as fh:
            return _reviewed(json.load(fh))
    except (OSError, ValueError, RecursionError):
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
edit_marks, review_marks, push_marks = [], [], []   # every edit / review index, and this turn's handovers (wip_push_start only)
session_unreviewed = set()   # diff paths edited by me this session
idx = 0
# OpenCodeReview (2026-10-13): a FULL review that succeeded counts as the fresh review. The command must START a command segment
# (`echo ocr review` is not one), and a REPORT decides, never a word in the output (OpenCodeReview of this gate, 13/10: `--help`,
# `echo mode: review` and other wording passed): the helper's `report: <file>` (in `mode: review`; a delegation spec alone means
# nobody reviewed yet) or a plain `ocr review … -o <file>` must be an OCR JSON report (an object with a `comments` list) written
# after the newest file this session edited. `--help` / `-h` / `--version`: not a review.
OCR_CMD = re.compile(r"(?:^|[;&|(\n]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:python3?\s+)?(?:\S*/)?(ocr-review|ocr\s+(?:review|r))\b")
review_pending = {}   # #1301: tool_use id of an agent/skill review -> its transcript index
review_rounds = []    # #1301: (index, has P0/P1) per agent review whose result was read
ocr_pending = {}   # tool_use id -> (transcript index, "helper" | "plain", command)
ocr_reports = []   # (transcript index, report path) of OCR runs that named a report
ocr_fallbacks = []   # (transcript index, spec, argv) of ocr-review delegation runs (not --delegate-only) that wrote their own spec
OCR_NOT_A_RUN = re.compile(r"(?:^|\s)(?:--help|-h|--version)(?:\s|$)")
bash_runs = []   # [transcript index, start, end, command] of every Bash run with a timestamp: a code change made through it
bash_open = {}   # tool_use id -> its bash_runs entry, until its result (end time) is read
tool_times = []   # (transcript index, time) of every tool call with a timestamp: where a change made at a given time sits
BASH_SLACK_S = 2.0
BASH_OPEN_MAX_S = 300.0   # a run with no result line (background, failed, interrupted): its window; 2 h let a `git diff <file>` own another session's save (issue #2)
# the result of a run that went on in the background (its end is unknown); `run_in_background` is checked on the call too
BASH_BACKGROUND = re.compile(r"\s*Command (?:running in background|was moved to the background|did not complete within .{0,40}moved to the background)")


def _rec_time(rec_):
    """The record's timestamp ("2026-10-13T23:59:14.548Z") in epoch seconds, or None."""
    import datetime
    try:
        return datetime.datetime.fromisoformat(str(rec_.get("timestamp")).replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError):
        return None


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

def _helper_argv(cmd):
    """The words of the OCR command itself (from `ocr-review` / `ocr review` up to the next ;, &&, ||, |): a `-c` of `bash -c` or
    `git -c` elsewhere in the line is not its flag, and `--from=X` is not one either (the helper reads separate words only)."""
    import shlex
    om = OCR_CMD.search(cmd)
    if not om:
        return []
    try:
        lex = shlex.shlex(cmd[om.start(1):], posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        words = []
        for w in lex:
            if w and set(w) <= set(";&|()<>"):
                break
            words.append(w)
        return words
    except ValueError:   # an unbalanced quote (the command sits inside `bash -c '…'`): not a plain run of the helper
        return []


def _rev(ref):
    try:
        r = subprocess.run(["git", "-C", repo_root, "rev-parse", "-q", "--verify", ref + "^{commit}"], capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _covers_since(argv):
    """A ranged OCR run covers the code committed since the verified head: `--from` at or before it (to HEAD), or `--commit` of
    the one commit since it. A later base or another commit reviews only part of it (OCR, 14/10)."""
    if not since_base:
        return False
    val = {w: argv[i + 1] for i, w in enumerate(argv[:-1]) if w in ("--from", "--to", "--commit", "-c")}
    head = _rev("HEAD")
    if "--from" in val:
        if val.get("--to", "HEAD") != "HEAD" and _rev(val["--to"]) != head:
            return False
        frm = _rev(val["--from"])
        try:
            return bool(frm) and subprocess.run(["git", "-C", repo_root, "merge-base", "--is-ancestor", frm, since_base],
                                                capture_output=True, timeout=5).returncode == 0
        except Exception:
            return False
    c = _rev(val.get("--commit") or val.get("-c") or "")
    return bool(c) and c == head and _rev(c + "^") == _rev(since_base)


def _short_circuited(cmd):
    """`… || ocr-review`: the helper only runs when what comes before fails — its output may be anyone's (review 13/10)."""
    om = OCR_CMD.search(cmd)
    return bool(om) and om.start() > 0 and cmd[om.start()] == "|" and cmd[om.start() - 1] == "|"


def _spec_from_run(cmd, spec):
    """The spec sits where THIS run writes: its --out folder, else the helper's own mkdtemp folder (ocr-review.*) — not a file
    made by hand somewhere and named in echoed output (review 13/10)."""
    words = _helper_argv(cmd)
    out = next((words[i + 1] for i, w in enumerate(words[:-1]) if w == "--out"), "")
    folder = os.path.realpath(os.path.dirname(spec))
    try:   # the helper makes its folder private (mkdtemp, or chmod 0700 of --out): a folder made by hand is not
        st = os.stat(folder)
        if st.st_uid != os.getuid() or (st.st_mode & 0o777) != 0o700:
            return False
    except OSError:
        return False
    if out:
        return folder == os.path.realpath(out if os.path.isabs(out) else os.path.join(cwd, out))
    return os.path.basename(folder).startswith("ocr-review.")


def _result_text(blk):
    c = blk.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""


# #1301: a review result "has P0/P1" when a line names one without a negation ("Không có P0/P1", "no P0", "0 P1"); words like "không"/"no"/"clean" elsewhere in the line are a description, not a negation.
_SEVERE = re.compile(r"\bP[01]\b", re.I)
_SEP = r"(?:\s*(?:/|or|and|,|v\u00e0)\s*)"
_NEG = r"(?:kh\u00f4ng(?:\s+c\u00f3)?|no|none|zero|without|0)"
_NEG_BEFORE = re.compile(r"\b" + _NEG + r"\s+(?:P[01]" + _SEP + r")*$", re.I)   # "no P0", "Kh\u00f4ng c\u00f3 P0/" before the label
_NEG_AFTER = re.compile(r"^(?:" + _SEP + r"P[01])*\s*[:=-]?\s*" + _NEG + r"\s*[.;]?$", re.I)   # "P1: none" closing the line


# ponytail: R10 only P0/P1 labels count as severe; unlabelled "Critical:"/"High:" results read as clean, upgrade when reviewers emit other severity words.
def _severe(txt):
    # each label is judged on its own: a negation of one label never hides another label in the same line
    for l in txt.splitlines():
        for m in _SEVERE.finditer(l):
            if not (_NEG_BEFORE.search(l[:m.start()]) or _NEG_AFTER.search(l[m.end():].strip())):
                return True
    return False


# #1301: files in these areas are never capped (auth, secrets, payment, migrations).
_SENSITIVE_SUBSTR = re.compile(r"secret|credential|token|password|payment|billing|migrat", re.I)


def _sensitive(path):
    # R6: auth is matched on filename tokens (snake/kebab/dot/slash and camelCase boundaries): `author`/`authority` are not auth;
    # `authorization`, `userAuth`, `JwtAuth`, `reauth`, `oauth*`, `OAuth2` (-> o|auth2), `auth0` are (R9: digit suffix).
    if _SENSITIVE_SUBSTR.search(path):
        return True
    spaced = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", path)
    for t in re.split(r"[^A-Za-z0-9]+", spaced.lower()):
        if re.fullmatch(r"(?:re)?auth[nz]?\d*", t) or t.startswith(("oauth", "authoriz", "authentic")):
            return True
    return False


# ponytail: R11 the cap does not check that required OCR ran on the final code (ocr_missing is judged elsewhere), upgrade if a capped Stop must also prove OCR.
CLEAN_ROUNDS_CAP = 2
_REVIEW_NOT_READ = re.compile(r"async agent launched|agent (?:is )?running in (?:the )?background", re.I)
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
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in bash_open:
                    _run = bash_open.pop(blk.get("tool_use_id"))   # a run moved to the background ends when it ends: no end time
                    if not BASH_BACKGROUND.match(_result_text(blk)):   # a result with no readable time: the run ended within seconds
                        _run[2] = _rec_time(rec) or _run[1] + BASH_SLACK_S
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in review_pending:
                    _ridx = review_pending.pop(blk.get("tool_use_id"))
                    _rtxt = _result_text(blk).strip()
                    # R3: a failed, empty or backgrounded review read nothing: not a clean round, and it resets nothing
                    if not blk.get("is_error") and _rtxt and not _REVIEW_NOT_READ.match(_rtxt):
                        review_rounds.append((_ridx, _severe(_rtxt)))
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in ocr_pending:
                    at, kind, ocmd = ocr_pending.pop(blk.get("tool_use_id"))
                    _rp = "" if blk.get("is_error") or _short_circuited(ocmd) else _ocr_report_path(kind, ocmd, _result_text(blk))
                    if _rp:   # a run over a commit range (--from / --commit) or over the workspace: each covers its own code
                        ocr_reports.append((at, _rp, _helper_argv(ocmd)))
                    elif kind == "helper" and not blk.get("is_error") and "--delegate-only" not in ocmd and not OCR_NOT_A_RUN.search(ocmd) \
                            and not _short_circuited(ocmd):
                        _txt = _result_text(blk)
                        _spec = next((l[6:].strip() for l in _txt.splitlines() if l.startswith("spec: ")), "")
                        _spec = os.path.join(cwd, _spec) if _spec and not os.path.isabs(_spec) else _spec   # a relative --out
                        # #1332: ocr-review luôn chạy delegation (LLM của OCR đã gỡ): ghi nhận `mode: delegate` + spec của chính lượt
                        # chạy, không còn đòi dòng báo lỗi endpoint của LLM
                        if "mode: delegate" in _txt and _spec and _spec_from_run(ocmd, _spec):
                            ocr_fallbacks.append((at, _spec, _helper_argv(ocmd)))
                    continue
                if not isinstance(blk, dict) or blk.get("type") != "tool_use":
                    continue
                idx += 1
                name = blk.get("name", "")
                inp = blk.get("input") or {}
                _tt = _rec_time(rec)
                if _tt is not None:
                    tool_times.append((idx, _tt))
                if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):   # MultiEdit: its path is file_path too (2026-11-15)
                    fp = inp.get("file_path") or inp.get("notebook_path") or ""
                    if isinstance(fp, str) and fp.endswith(CODE_EXTS):
                        hit = in_diff(fp)
                        if hit:
                            last_edit_idx = idx
                            edit_marks.append(idx)
                            session_unreviewed.add(hit)
                elif name in ("Agent", "Task"):
                    st = inp.get("subagent_type", "")
                    if st in REVIEW_AGENTS:
                        last_review_idx = idx
                        review_marks.append(idx)
                        if blk.get("id"):
                            review_pending[blk.get("id")] = idx
                elif name == "Skill":
                    sk = inp.get("skill", "") or inp.get("command", "")
                    if sk in REVIEW_SKILLS:
                        last_review_idx = idx
                        review_marks.append(idx)
                elif name == "Bash":
                    _bts = _tt
                    if wip_push_start is not None and _tt is not None and _tt >= wip_push_start \
                            and _handover_cmd(str(inp.get("command") or "")):
                        push_marks.append(idx)
                    if _bts is not None:
                        bash_runs.append([idx, _bts, None, str(inp.get("command") or "")])
                        if blk.get("id") and not inp.get("run_in_background"):   # in the background: no end time
                            bash_open[blk.get("id")] = bash_runs[-1]
                    om = OCR_CMD.search(str(inp.get("command") or ""))
                    if om and blk.get("id"):
                        ocr_pending[blk.get("id")] = (idx, "helper" if om.group(1) == "ocr-review" else "plain",
                                                      str(inp.get("command") or ""))
                elif name == "Workflow":
                    wf = inp.get("name", "") or ""
                    scr = inp.get("script", "") or ""
                    if wf in REVIEW_WORKFLOWS or "multi-lens-audit" in scr:
                        last_review_idx = idx
                        review_marks.append(idx)

# Code changed through Bash (a script, `sed -i`, a heredoc) never passes through Edit/Write (issue #13, 13/10: worktree.py rewritten
# by Python only, no BLOCK). A diff file counts as edited at the latest Bash command that names it and was RUNNING when the file last
# changed: its start to its result, 2 s of clock slack; a run in the background, up to 2 h. A deleted file has no time: it counts at the
# latest command that names it as a write target (bin/session_authorship.py, the gate's own authorship rule); a `grep` naming it does
# not. Not this session's edit: a command that ran before or after the change (a `cat`, then an IDE save or another session's edit).
# ponytail: a command that changes code without naming the file (a glob, `xargs sed -i`, a fix script kept in a file, a formatter over
# a folder) is still not seen; .claude/audit-gate/bash_write_ledger.tsv windows could tell those if they keep escaping review.
_PATH_SPLIT = re.compile(r"[\s\"'`=:(<>|;&,]+")


def _names(cmd, rel, base):
    """`cmd` names the repo file `rel`: a word whose path is rel relative from some folder (`scripts/app.py`, `../scripts/app.py`,
    the bare name), absolute into this repo, or behind a prefix that cannot be resolved ($VAR, {ROOT} of an f-string, ~), which may
    also sit above the repo root. other/app.py, myapp.py, app.py.bak, ../other/scripts/app.py and /elsewhere/scripts/app.py do not
    name scripts/app.py. One linear split (review 14/10: a backtracking regex took 120 s on a 72 KB heredoc, past the hook's budget)."""
    full = os.path.realpath(os.path.join(repo_root, rel))
    for tok in _PATH_SPLIT.split(cmd):
        if not tok.endswith(base) or (len(tok) > len(base) and tok[-len(base) - 1] != "/"):
            continue
        parts = tok.split("/")
        var = max([i for i, x in enumerate(parts) if "$" in x or "{" in x or x == "~"] or [-1])
        if var >= 0:   # unresolvable prefix: rel, a part of it, or rel under some folder
            tail = "/".join(parts[var + 1:])
            if tail == rel or rel.endswith("/" + tail) or tail.endswith("/" + rel):
                return True
        elif tok.startswith("/"):
            if os.path.realpath(tok) == full:
                return True
        else:          # relative from a folder this hook does not know: what follows the last `.` / `..` must be a part of rel
            dots = max([i for i, x in enumerate(parts) if x in (".", "..")] or [-1])
            tail = "/".join(parts[dots + 1:])
            if tail == rel or rel.endswith("/" + tail):
                return True
    return False


_SA = []


def _authorship():
    """bin/session_authorship.py of this kit (the hook's real folder's sibling), or None; tried once."""
    if not _SA:
        hookdir = os.environ.get("CLAIM_HOOKDIR", "")
        try:
            if not os.path.isabs(hookdir):   # "" would resolve from the cwd: the project's own files
                raise ImportError("CLAIM_HOOKDIR is not an absolute path")
            sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(
                os.path.join(hookdir, "review_gate.sh")))), "bin"))   # after the stdlib
            import session_authorship
            _SA.append(session_authorship)
        except Exception as e:
            logline(f"[{ts}] session_authorship unavailable ({e!r}): a file deleted through Bash is not counted")
            _SA.append(None)
    return _SA[0]


def _writes(cmd, rel):
    """The Bash command `cmd` names repo file `rel` as a write target (session_authorship's rule); False when it cannot tell."""
    sa = _authorship()
    if sa is None:
        return False
    try:
        return sa.names_path(sa.shell_named([cmd]), repo_root, rel)
    except Exception as e:
        logline(f"[{ts}] write rule failed on a command naming {rel}: {e!r} — not counted")
        return False


_READ_ONLY = frozenset(("grep", "rg", "cat", "head", "tail", "ls", "wc", "diff", "stat", "file", "less", "nl", "sed", "find"))
_GIT_READ = frozenset(("diff", "status", "log", "show", "blame", "ls-files", "grep", "rev-parse", "cat-file", "ls-tree", "shortlog"))
_GIT_NEUTRAL = _GIT_READ | {"add", "commit", "push", "fetch"}   # record or send a file, never change what it holds (the A3 push check)
_REDIRECT = re.compile(r"(?<![0-9&])>|>>")


def _read_only(cmd, git_ok=_GIT_READ):
    """Every segment of `cmd` only reads (`git diff f`, `grep f`, `cat f | head`, `dotnet test`) and nothing is redirected: naming a file
    there is no edit of it (issue #2: 43 auto-releases). A heredoc body, an interpreter or any word not listed makes it not read-only.
    git_ok: the git subcommands that count as reading (_GIT_NEUTRAL adds add / commit / push / fetch)."""
    sa = _authorship()
    if sa is None or _REDIRECT.search(re.sub(r"\d?>&\d|&>|\d?>\s*/dev/null", " ", sa.QUOTED_RE.sub(" ", cmd))):
        return False
    segs = [x for x in sa.SEGMENT_SPLIT_RE.split(cmd) if x.strip()]
    for seg in segs:
        words = seg[sa.LEAD_RE.match(seg).end():].split()
        if not words or sa._segment_writes(seg):
            return False
        c = os.path.basename(words[0])
        if c == "git":
            rest = words[1:]
            while rest and rest[0].startswith("-"):
                rest = rest[2:] if rest[0] in ("-C", "-c") else rest[1:]
            if not rest or rest[0] not in git_ok:
                return False
        elif c == "dotnet":
            if len(words) < 2 or words[1] not in ("test", "build"):
                return False
        elif c not in _READ_ONLY:
            return False
    return bool(segs)


def _index_at(t):
    """The last transcript index whose tool call started at or before time t (a run in the background can change a file after
    later calls, a review among them: the change sits there, not at the run's own index)."""
    best = -1
    for i, tt in tool_times:
        if tt <= t + BASH_SLACK_S:
            best = max(best, i)
    return best


for _rel in (changed if bash_runs else ()):
    try:
        _mt = os.path.getmtime(os.path.join(repo_root, _rel))
    except OSError:
        _mt = None   # deleted (`rm`, `git rm`, the old side of a `mv`)
    _base = os.path.basename(_rel)
    for _bi, _bts, _bend, _bcmd in reversed(bash_runs):
        if _base not in _bcmd:
            continue
        if _mt is not None:
            _until = _bend if _bend is not None else _bts + BASH_OPEN_MAX_S
            if not (_bts - BASH_SLACK_S <= _mt <= _until + BASH_SLACK_S) or not _names(_bcmd, _rel, _base) or _read_only(_bcmd):
                continue
            _at = max(_bi, _index_at(_mt)) if _bend is None else _bi
        elif _writes(_bcmd, _rel):
            _at = _bi
        else:
            continue
        if _at > last_edit_idx:
            last_edit_idx = _at
        edit_marks.append(_at)
        if _rel not in session_unreviewed:
            logline(f"[{ts}] {_rel}: changed by Bash #{_bi}, which names it — edited this session (at #{_at})")
        session_unreviewed.add(_rel)
        break

# An OCR report (or a delegation spec) counts only when it is newer than every file this session edited (one from before the last
# edit is stale).
last_ocr_ws_idx = last_ocr_range_idx = -1   # newest valid OCR report over the workspace / over a commit range
_newest = 0.0
for _f in session_unreviewed:
    try:
        _newest = max(_newest, os.path.getmtime(os.path.join(repo_root, _f)))
    except OSError:
        pass   # deleted since the edit: nothing newer to compare
# Content map (wave 2 lane D, 03/11): bin/ocr-review writes `content_sha256` {path: sha256 of the bytes it reviewed, hashed before the
# review} and `content_base` into its own report. Such a report is judged by content only, never by mtime (a map edited by hand gets a
# fresh mtime): a file is OCR-reviewed when its current sha equals the sha in a report of the same scope — workspace: the working-tree
# file, base == HEAD now, the session's uncommitted files; range: the blob at HEAD, a run that covers the commits since the verified head
# (_covers_since) from a base at or before it, every file committed since. Other files are the delta: a run whose map holds their
# current sha. A report without the map keeps the mtime rule below. The agent review rule does not change: a mapped report counts as a
# review at its own transcript index only, never earlier, so a file edited back to reviewed bytes still needs a review after that edit.
# ponytail: a map forged by hand with the current sha is not detected (no more than a forged `comments` list); reusing one --out for two
# runs overwrites the first report and its coverage (use a new --out, or none); a deleted file has no sha and needs a fresh run.
def _sha_file(rel):
    import hashlib
    try:
        with open(os.path.join(repo_root, rel), "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


_HEAD_SHA = {}


def _sha_head(rel):
    if rel not in _HEAD_SHA:
        import hashlib
        try:
            r = subprocess.run(["git", "-C", repo_root, "cat-file", "blob", "HEAD:" + rel], capture_output=True, timeout=10)
            _HEAD_SHA[rel] = hashlib.sha256(r.stdout).hexdigest() if r.returncode == 0 else None
        except Exception as e:
            logline(f"[{ts}] HEAD blob of {rel}: {e!r} — not credited")
            _HEAD_SHA[rel] = None
    return _HEAD_SHA[rel]


def _at_or_before(a, b):
    try:
        return bool(a) and bool(b) and subprocess.run(["git", "-C", repo_root, "merge-base", "--is-ancestor", a, b],
                                                      capture_output=True, timeout=5).returncode == 0
    except Exception as e:
        logline(f"[{ts}] merge-base {a[:12]} {b[:12]}: {e!r} — not credited")
        return False


ws_need = sorted(session_unreviewed & dirty)   # the session's uncommitted code: what a workspace map must hold
range_need = sorted(since)                     # every file committed since the verified head, as the old range rule
ws_mapped, range_mapped = set(), set()
ws_excl, range_excl = set(), set()   # what OCR's own excludes leave out of a run (content_excluded): no map can hold them
map_ws_idx = map_range_idx = -1   # newest valid map report per scope (nothing left to hold by sha: index rule, as the old one)
_head_now = _rev("HEAD") if ocr_reports else ""
for _at, _rp, _argv in list(ocr_reports):
    try:
        with open(_rp, encoding="utf-8") as fh:
            _rep = json.load(fh)
    except (OSError, ValueError, RecursionError):
        continue   # the mtime rule below says it is no report
    if not isinstance(_rep, dict) or "content_sha256" not in _rep:
        continue
    ocr_reports.remove((_at, _rp, _argv))   # mapped: judged here only
    _m, _base = _rep.get("content_sha256"), _rep.get("content_base")
    if not _reviewed(_rep) or not isinstance(_m, dict) or not isinstance(_base, str) or not _base:
        logline(f"[{ts}] OCR run at #{_at} named {_rp}: content map malformed or nothing reviewed — not counted")
        continue
    _excl = _rep.get("content_excluded")
    _excl = {x for x in _excl if isinstance(x, str)} if isinstance(_excl, list) else set()
    # G4 (review 03/11): content_excluded is in a report the agent can write, so a listed file is never exempt by itself — it is
    # covered only under the old rule: this run came after the last edit and its report is newer than every edited file
    try:
        _old_rule = _at > last_edit_idx and os.path.getmtime(_rp) >= _newest
    except OSError:
        _old_rule = False
    if not _old_rule:
        _excl = set()
    if any(w in ("--from", "--commit", "-c") for w in _argv[:-1]):
        if not _covers_since(_argv) or not _at_or_before(_base, since_base):
            logline(f"[{ts}] OCR run at #{_at}: content map over a range that does not cover the commits since {since_base[:12]} — not counted")
            continue
        _hit = {f for f in range_need if _m.get(f) is not None and _m.get(f) == _sha_head(f)}
        range_mapped |= _hit
        _excl &= set(range_need)
        range_excl |= _excl
        map_range_idx = max(map_range_idx, _at)
    else:
        if _base != _head_now:
            logline(f"[{ts}] OCR run at #{_at}: workspace content map on base {_base[:12]}, HEAD is {_head_now[:12]} — not counted")
            continue
        map_ws_idx = max(map_ws_idx, _at)
        _hit = {f for f in ws_need if _m.get(f) is not None and _m.get(f) == _sha_file(f)}
        ws_mapped |= _hit
        _excl &= set(ws_need)
        ws_excl |= _excl
    if _hit:   # a review at its own index (an excluded file is no review mark: it never stands in for the agent review)
        last_review_idx = max(last_review_idx, _at)
        review_marks.append(_at)
    logline(f"[{ts}] OCR run at #{_at}: content map matches {sorted(_hit)}")
# a file OCR excludes by itself is asked of no map: a run of that scope that meets the old rule for it (above) stands for it; a session
# that edited nothing of that scope keeps the index rule
_ws_left, _range_left = set(ws_need) - ws_excl, set(range_need) - range_excl
ws_map_ok = _ws_left <= ws_mapped if ws_need else map_ws_idx > last_edit_idx
range_map_ok = bool(range_need) and range_mapped >= _range_left
ocr_delta = sorted(_ws_left - ws_mapped) + [f + " (đã commit)" for f in sorted(_range_left - range_mapped)]

if ocr_reports:
    for _at, _rp, _argv in ocr_reports:
        if _valid_ocr_report(_rp, _newest):
            last_review_idx = max(last_review_idx, _at)
            review_marks.append(_at)
            if any(w in ("--from", "--commit", "-c") for w in _argv[:-1]):
                if _covers_since(_argv):
                    last_ocr_range_idx = max(last_ocr_range_idx, _at)
                else:
                    logline(f"[{ts}] OCR run at #{_at} covers only part of the code committed since {since_base[:12]} — not counted for it")
            else:
                last_ocr_ws_idx = max(last_ocr_ws_idx, _at)
        else:
            logline(f"[{ts}] OCR run at #{_at} named {_rp}: not a fresh OCR report — not counted")

# A3 (audit 2026-10-25): the reply is work in progress and this turn's push came before more edits. It skips only when every push of
# the turn carried reviewed code: no edit between the last review before it and it. Edits counted: Edit / Write of a changed code file,
# a Bash run that changed one (above), and — fail closed — any Bash run before the push that names a changed code file and does more
# than read or `git add / commit / push / fetch` it (a `sed -i` whose change a later edit overwrote leaves no mtime to find it by).
if wip_push_start is not None:
    def _may_edit(cmd):
        return not _read_only(cmd, _GIT_NEUTRAL) and any(
            os.path.basename(_r) in cmd and _names(cmd, _r, os.path.basename(_r)) for _r in changed)
    _unreviewed_push = None if push_marks else "?"   # the push the harness saw is not found here: gate (fail closed)
    for _p in push_marks:
        _rv = max([r for r in review_marks if r < _p], default=-1)
        if any(_rv < e < _p for e in edit_marks) or any(_rv < _bi < _p and _may_edit(_bc) for _bi, _s, _e, _bc in bash_runs):
            _unreviewed_push = _p
            break
    if _unreviewed_push is None:
        logline(f"[{ts}] skip: work in progress — this turn's handover (push / PR / finish / integrate / merge gate) carried reviewed code; "
                "review at the handover turn")
        sys.exit(0)
    logline(f"[{ts}] work in progress, but handover #{_unreviewed_push} of this turn carried code edited after the last review — gated")

# No .kt edited by me this session (the dirty files are pre-existing /
# someone else's) → nothing of mine to gate.
if last_edit_idx == -1:
    reset_attempts()
    logline(f"[{ts}] uncommitted code exists but none edited this session "
            f"({changed}) — pass")
    sys.exit(0)

reviewed_after_edits = last_review_idx > last_edit_idx and last_review_idx != -1
def _spec_ok(sp):   # the helper's own spec file, written after every edited file (not an edited file named as one)
    try:
        return os.path.basename(sp) == "ocr-spec.md" and os.path.isfile(sp) and os.path.getmtime(sp) > _newest > 0
    except OSError:
        return False


# OCR must have covered what is unreviewed: the uncommitted code (a workspace run) and the code committed since the verified head
# (a --from run; a workspace run sees none of it). The fallback stands in only when an agent review came AFTER it (somebody read
# the spec) and its spec file is this run's, real and fresh.
need_ws = bool(dirty) or not since   # uncommitted code, or nothing committed since the verified head: a workspace run


def _fallback_for(ranged_scope):
    """A delegation fallback after the last edit, read by an agent review after it, whose spec is this run's — credited to the
    scope its run covered, like a report: a workspace run for the uncommitted code, a covering ranged run for the committed."""
    for i, sp, argv in ocr_fallbacks:
        ranged = any(w in ("--from", "--commit", "-c") for w in argv[:-1])
        if last_edit_idx < i < last_review_idx and _spec_ok(sp) and ranged == ranged_scope and (not ranged or _covers_since(argv)):
            return True
    return False


ocr_done = ((not need_ws or last_ocr_ws_idx > last_edit_idx or _fallback_for(False) or ws_map_ok)
            and (not since or last_ocr_range_idx > last_edit_idx or _fallback_for(True) or range_map_ok))
ocr_missing = (reviewed_after_edits and not ocr_done
               and os.environ.get("REVIEW_GATE_OCR", "1") != "0" and os.environ.get("REVIEW_GATE_REQUIRE_OCR", "1") != "0"
               and shutil.which("ocr") is not None)
if ocr_missing:   # an agent review alone; `ocr` is here, so OCR must review the final code too
    reviewed_after_edits = False
    logline(f"[{ts}] agent review after the last edit, but no OCR review (ocr installed) — OCR required")

if reviewed_after_edits:
    reset_attempts()
    logline(f"[{ts}] review ran after last .kt edit "
            f"(edit#{last_edit_idx} < review#{last_review_idx}) — pass")
    sys.exit(0)

# #1301 round cap: every review finds something new, so a PR head never settles (#1298: 12 rounds, 9 heads). After CLEAN_ROUNDS_CAP
# trailing agent reviews with no P0/P1, the gate lets the stop go and hands the rest to the QA lane / merge gate. The first round, any
# P0/P1 in the latest round and sensitive files (auth, secret, payment, migration) are never capped.
# ponytail: counts rounds of the whole session, not of one file set; per-file rounds when a long session mixes unrelated work.
# R5: a round is a review after an edit; reviews launched together (no edit between them) are one round, severe if any is.
_rounds = []
for _ri, _sv in sorted(review_rounds):
    if not any(_e < _ri for _e in edit_marks):   # R7: a review before the first edit reviewed nothing of this change
        continue
    if _rounds and not any(_rounds[-1][0] < _e < _ri for _e in edit_marks):
        _rounds[-1] = (_ri, _rounds[-1][1] or _sv)
    else:
        _rounds.append((_ri, _sv))
_trail = 0
for _ri, _sv in _rounds:
    _trail = 0 if _sv else _trail + 1
if _trail >= CLEAN_ROUNDS_CAP and not any(_sensitive(f) for f in session_unreviewed | set(changed)):
    reset_attempts()
    logline(f"[{ts}] round cap: {_trail} clean review rounds (no P0/P1), edits after the last one — pass")
    sys.stderr.write(f"REVIEW-GATE: {_trail} vòng review sạch (không còn P0/P1), không giữ thêm; review tiếp do lane QA / merge gate.\n")
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
        + (f"   Nhưng {len(changed)} file code vẫn CHƯA có lượt OpenCodeReview sau lần sửa cuối — tự chịu trách nhiệm.\n" if ocr_missing else
           f"   Nhưng {len(changed)} file code vẫn CHƯA được review context-sạch — "
           f"tự chịu trách nhiệm review thủ công.\n") +
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
    "Finding P0..P3: sửa ngay trong PR này (theo CLASS, không chỉ instance) rồi review lại; không hạ thành thẻ Backlog",
    "  (chủ repo 06/11). Bug thật ngoài phạm vi PR thì tạo thẻ (skill createTask) rồi ghi số thẻ vào báo cáo.",
    "`ocr-review` ra mode delegate: không cần giao spec cho agent thứ hai — gọi `ocr-review` TRƯỚC",
    "  lời gọi Agent review (cùng một tin nhắn được, lệnh OCR đứng trước); một agent review sau nó là đủ.",
]
if ocr_missing:   # the agent review is done: say exactly what is left
    lines = [
        "⛔ REVIEW-GATE: đã có review context sạch (agent hoặc skill) sau lần sửa cuối, nhưng máy có `ocr`:",
        "BẮT BUỘC thêm một lượt OpenCodeReview trên code cuối (người dùng 13/10: OCR luôn chạy lại sau principal-code-reviewer —",
        "hai bên tìm ra lỗi khác nhau). Chạy:",
        *(['  python3 .agents/devkit/bin/ocr-review -b "<chủ đề>" --out <thư mục tạm>'] if need_ws else []),
        *([f'  python3 .agents/devkit/bin/ocr-review -b "<chủ đề>" --out <thư mục tạm khác> --from {since_base[:12]}'
           "   (phần đã commit sau lần xác minh cuối: lệnh không --from chỉ xem phần chưa commit)"] if since else []),
        "rồi xử lý phát hiện: P0..P3 sửa ngay trong PR (sửa code thì review lại), không hạ thành thẻ Backlog; bug thật ngoài PR thì",
        "tạo thẻ (skill createTask) và ghi số thẻ vào báo cáo. Lệnh ra spec delegation (mode delegate): không cần",
        "giao spec cho agent thứ hai — gọi `ocr-review` đúng phạm vi trên TRƯỚC lời gọi Agent review (cùng một tin nhắn được, lệnh OCR",
        "đứng trước), một agent review sau nó là đủ. Đừng cắt output của lệnh (| tail, | head): gate đọc dòng `mode: delegate` và `spec:`.",
        "`--out` viết thẳng đường dẫn (không `$BIẾN`): gate so thư mục của dòng `spec:` với chữ sau --out trong lệnh (#992).",
        "Tắt: REVIEW_GATE_REQUIRE_OCR=0 (trước khi mở phiên).",
        *([f"OCR theo nội dung đã phủ {len(ws_mapped) + len(range_mapped)} file; còn lệch: {', '.join(ocr_delta[:10])}"]
          if (ws_mapped or range_mapped) and ocr_delta else []),
        "",
    ] + [f"  • {f}" for f in unrev[:20]] + ([f"  … +{len(unrev) - 20} file nữa"] if len(unrev) > 20 else [])
# OpenCodeReview, run by the gate itself on this block path only (2026-10-13, user: run ocr review in every repo): the delegation
# mode needs no LLM and no key (~1 s); its spec goes to the reviewer. REVIEW_GATE_OCR=0: off.
# #1332: chế độ REVIEW_GATE_OCR=full (OCR review đầy đủ bằng LLM chạy nền) đã gỡ cùng LLM của OCR.
if os.environ.get("REVIEW_GATE_OCR", "1") != "0" and not ocr_missing:
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
                          "  → giao spec này cho reviewer ở mục A (lượt --delegate-only này của gate không được tính: tự chạy "
                          ".agents/devkit/bin/ocr-review rồi agent review sau nó)."]
            logline(f"[{ts}] ocr-review --delegate-only rc={_r.returncode} spec={_spec or '-'}")
    except Exception as _e:   # OCR is an aid here, never a reason to fail the gate
        logline(f"[{ts}] ocr-review failed: {_e!r}")
# Cùng thông điệp lần nữa trong phiên (chủ repo 08/11: "spam lắm và dài"): giữ dòng ⛔ (yêu cầu), lệnh cần chạy và danh sách
# file, bỏ phần giải thích — như test_evidence_gate.sh O4. So không tính số đếm lần chặn.
# Mọi lỗi ở bước rút gọn (file trạng thái hỏng, surrogate lẻ trong thông điệp…) rơi về in nguyên thông điệp và vẫn chặn:
# một ngoại lệ ở đây làm python thoát 1 và wrapper bên dưới thoát 0 = cho Stop qua (fail-open, Antigravity audit PR #1059).
def _shorten(full):
    import hashlib
    shown = os.path.join(logdir, f"review_gate_shown_{sid}")
    digest = hashlib.sha256("\n".join(full).encode("utf-8", "surrogateescape")).hexdigest()[:16]
    try:
        with open(shown, encoding="utf-8", errors="replace") as fh:
            again = fh.read().strip() == digest
    except Exception:
        again = False
    try:
        with open(shown, "w", encoding="utf-8") as fh:
            fh.write(digest)
    except OSError:
        pass
    if not again:
        return full
    # Giữ cả các lựa chọn A–D của đường chặn thường: đó là lệnh cần chạy (review PR #1059).
    short = [l for l in full if l.startswith(("⛔", "OCR")) or l.lstrip().startswith(("•", "… +", "python3 ", "→"))
             or re.match(r"\s+[A-D]\) ", l)]
    # Ràng buộc cách chạy OCR (không phải giải thích): chỉ thông điệp "thiếu OCR" mang chúng; thiếu thì lượt OCR không được tính.
    if ocr_missing:
        short.append("Nhắc: OCR trước Agent review; --out viết thẳng đường dẫn (không $BIẾN); không cắt output (| tail, | head).")
    short.append("(Như lần chặn trước trong phiên — phần giải thích không lặp lại.)")
    return short
try:
    lines = _shorten(lines)
except Exception as _e:
    logline(f"[{ts}] review_gate shorten failed, full message kept: {_e!r}")
sys.stderr.write("\n".join(lines) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
