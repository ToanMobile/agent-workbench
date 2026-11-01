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
#   • uncommitted code changes (or code committed since the verified head) exist that THIS session
#     edited (Edit/Write, or a Bash command that names a code file changed after it started), AND
#   • THE review of exactly that code state has not PASSED.
# THE review (user, 31/10/2026: "3 agent review ... phải cùng thống nhất kết quả thì mới gọi là pass") is
# bin/review-fanout.sh: Claude Code pinned to Opus + Antigravity (antigravity-pm audit) + Grok (grok CLI) +
# Alibaba OpenCodeReview (full mode, its own LLM), in parallel, verdict by bin/review-merge.py — PASS only when all 4 ran (Claude
# on Opus, Grok on its pinned model) and all 4
# say pass, no unrefuted P0/P1, no recurring known bug, accepted findings fixed with a test.
# A sub-agent review, a skill, or OCR alone no longer counts. No review yet → the gate starts it in the
# background and blocks; running → blocks; FAIL → blocks with the reasons and findings.
#
# Fail-CLOSED (31/10/2026): no python3, an unreadable payload, a git error or a crash of this gate BLOCK the
# Stop with the reason — there is no anti-loop release after N blocks and no fail-open path. Out of scope
# (pass): no project, nothing this session edited, a board worker on main (#528), a progress reply that
# pushed nothing (the handover turn is gated).
#
# Stop hook protocol: stdin JSON; exit 2 blocks (stderr→Claude); exit 0 allows.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

INPUT="$(cat)"

# A reviewer started by bin/review-fanout.sh (review_runner sets REVIEW_FANOUT_CHILD=1) is itself the review: gating its own
# Stop would start a nested 4-way review per reviewer (tests/gates/test_review_gate_4way.sh). The variable lives in the
# environment Claude Code was started with; nothing a session runs through Bash can set it for its own hooks.
[ "${REVIEW_FANOUT_CHILD:-}" = 1 ] && exit 0

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
# No project: the loop guard below has nowhere to count re-Stops, and a gate that cannot count could hold every Stop.
[ -n "${REPO_ROOT}" ] || exit 0
# QA K-4: without python3 this gate cannot run — say so instead of passing silently. Before any other command
# (r14b, 31/10): with a stripped PATH `mkdir` failed first and its error hid this message; before the W1 v6 block too (#754):
# a worktree session's first line was its warning or "basename: command not found".
if ! command -v python3 >/dev/null 2>&1; then   # fail closed (31/10): a gate that cannot run cannot say the code was reviewed
  echo "⛔ REVIEW-GATE: python3 không có — không kiểm được review 4 bên, chặn Stop. Cài python3." >&2
  exit 2
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
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}"
for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
[ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LOG="${LOG_DIR}/review_gate.log"

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
CLAIM_REPO="${REPO_ROOT}" CLAIM_LOGDIR="${LOG_DIR}" \
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
except Exception as e:   # fail closed (31/10)
    logline(f"[{ts}] stdin parse fail: {e!r} — BLOCK (fail-closed)")
    sys.stderr.write(f"⛔ REVIEW-GATE: không đọc được payload của Stop hook ({e!r}) — chặn (fail-closed).\n")
    sys.exit(2)

# A progress reply (status line CHƯA XONG / CHỜ DUYỆT …, no outcome claimed, no git push after the
# turn's last edit): the fresh-context review is asked at the handover turn, not on every stop (T0003).
# Audit 2026-10-25 A3: a push this turn that more edits followed is no handover (devkit_harness.push_after_last_edit), but the code it
# carried must have been reviewed: such a Stop skips only after the scan below finds no push of code edited since the last review.
wip_push_start = None
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
                if _st0 is None or "push" not in devkit_harness.git_writes_in_turn(_tp0, _st0):
                    logline(f"[{ts}] skip: work in progress — review at the handover turn")
                    sys.exit(0)
                wip_push_start = _st0
        except SystemExit:
            raise
        except Exception as e:
            logline(f"[{ts}] work_in_progress failed: {e!r}")
        break

# the project the bash part resolved (CLAUDE_PROJECT_DIR, or the session's worktree through session_worktree.project) wins
# when it is a git tree; the payload cwd is the fallback for a project dir outside git (critical scan 31/10: cwd first sent
# a worktree session back to main; hooks/tests/or_ported_contract_test.sh: a non-git CLAUDE_PROJECT_DIR keeps the cwd's repo)
repo_root, in_git = repo, False
for cwd in (repo, d.get("cwd")):
    if not cwd or not isinstance(cwd, str):
        continue
    try:
        repo_root = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10, check=True).stdout.strip() or repo
        in_git = True
        break
    except Exception:
        continue
def _under_dotgit(p):
    p = os.path.abspath(p)
    while True:
        if os.path.lexists(os.path.join(p, ".git")):
            return True
        q = os.path.dirname(p)
        if q == p:
            return False
        p = q
if not in_git:
    # rev-parse failed with a .git above: a broken repo (dubious ownership, bad gitdir) — fail closed (OCR #742 5aa9335b)
    if any(isinstance(c, str) and c and _under_dotgit(c) for c in (repo, d.get("cwd"))):
        logline(f"[{ts}] git rev-parse failed inside a git tree ({repo}) — BLOCK (fail-closed)")
        sys.stderr.write(f"⛔ REVIEW-GATE: git lỗi khi tìm repo của {repo} — chặn (fail-closed).\n")
        sys.exit(2)
    # no git project at all: out of scope (the header) — never a Stop that can never pass
    logline(f"[{ts}] no git project at {repo} / {d.get('cwd')} — pass")
    sys.exit(0)
cwd = d.get("cwd") or repo   # relative paths in the transcript are relative to the session's own cwd

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
# hooks, CI, agent/tool config and the review machinery are code whatever their extension (audit 31/10: a .json/.yml
# edit to the gate itself, or a hook without a source extension, slipped past the review)
MACHINERY_SPECS = [":(glob)**/hooks/**", ":(glob).github/workflows/**", ":(glob)**/.claude/settings*.json",
                   ":(glob)**/.mcp.json", ":(glob)**/mcp_config.json", ":(glob)**/bin/review*"]
MACHINERY_RX = re.compile(r"(^|/)(hooks/|\.github/workflows/|\.claude/settings[^/]*\.json$|\.mcp\.json$|mcp_config\.json$|bin/review[^/]*$)")
PATHSPECS = ["*" + e for e in CODE_EXTS] + MACHINERY_SPECS


def is_code(path):
    return path.endswith(tuple(CODE_EXTS)) or MACHINERY_RX.search(path) is not None

# ── 1) uncommitted code changes? — modified-tracked + staged + UNTRACKED.
#       Untracked new .kt (created via Write, not yet `git add`) is the most
#       important to review, yet `git diff HEAD` omits it → union ls-files. ──
try:
    diff = subprocess.run(
        ["git", "-C", repo_root, "diff", "--name-only", "HEAD", "--", *PATHSPECS],
        capture_output=True, text=True, timeout=10)
    if diff.returncode != 0 and subprocess.run(["git", "-C", repo_root, "rev-parse", "--verify", "-q", "HEAD"],
                                               capture_output=True, text=True, timeout=10).returncode != 0:
        # unborn HEAD (no commit yet): every file is new — compare with the empty tree (asked from git: SHA-1 or SHA-256 repo)
        _empty = subprocess.run(["git", "-C", repo_root, "hash-object", "-t", "tree", "/dev/null"],
                                capture_output=True, text=True, timeout=10).stdout.strip()
        diff = subprocess.run(
            ["git", "-C", repo_root, "diff", "--name-only", _empty or "HEAD", "--", *PATHSPECS],
            capture_output=True, text=True, timeout=10)
    untracked = subprocess.run(
        ["git", "-C", repo_root, "ls-files", "--others", "--exclude-standard",
         "--", *PATHSPECS],
        capture_output=True, text=True, timeout=10)
    # git exits non-zero with empty stdout (corrupt index, dubious ownership): an empty list there is not "no code" (OCR #742)
    for _q in (diff, untracked):
        if _q.returncode != 0:
            raise RuntimeError(f"git rc={_q.returncode}: {(_q.stderr or '').strip()[:200]}")
    # A symlink's content is a path, not code to review (DevKit hook links such as
    # .claude/hooks/devkit_profile.py in a symlink install).
    # Commits past the last verified HEAD (T0003): code committed mid-work still needs its review.
    since, since_base = [], ""
    try:
        import devkit_harness as _dh
        _vh = _dh.verified_head(repo_root, write=False)[0]
        since = [f for f in _dh.files_since(repo_root, _vh) if is_code(f) and not os.path.islink(os.path.join(repo_root, f))]
        since_base = _vh or ""
    except Exception as e:
        logline(f"[{ts}] since-files failed: {e!r}")
    changed = sorted({l for l in (diff.stdout.splitlines() + untracked.stdout.splitlines() + since)
                      if l.strip() and not os.path.islink(os.path.join(repo_root, l))})
    dirty = {l for l in diff.stdout.splitlines() + untracked.stdout.splitlines()   # the code a workspace OCR run sees
             if l.strip() and not os.path.islink(os.path.join(repo_root, l))}
except Exception as e:   # fail closed (31/10)
    logline(f"[{ts}] git query failed: {e!r} — BLOCK (fail-closed)")
    sys.stderr.write(f"⛔ REVIEW-GATE: git lỗi khi tìm code chưa review ({e!r}) — chặn (fail-closed).\n")
    sys.exit(2)

if not changed:
    reset_attempts()
    logline(f"[{ts}] no uncommitted code ({'|'.join(CODE_EXTS)}) — pass")
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
edit_marks, review_marks, push_marks = [], [], []   # every edit / review index, and this turn's pushes (wip_push_start only)
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
ocr_fallbacks = []   # (transcript index, spec, argv) of ocr-review runs that ASKED the LLM and fell back to delegation for want of an endpoint
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
                        if ("no valid LLM endpoint configured" in _txt or "LLM endpoint unusable" in _txt) and "mode: delegate" in _txt \
                                and _spec and _spec_from_run(ocmd, _spec):   # no endpoint, or one that rejects every request (bin/ocr-review)
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
                if name in ("Edit", "Write", "NotebookEdit"):
                    fp = inp.get("file_path") or inp.get("notebook_path") or ""
                    if isinstance(fp, str) and is_code(fp):
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
                elif name == "Skill":
                    sk = inp.get("skill", "") or inp.get("command", "")
                    if sk in REVIEW_SKILLS:
                        last_review_idx = idx
                        review_marks.append(idx)
                elif name == "Bash":
                    _bts = _tt
                    if wip_push_start is not None and _tt is not None and _tt >= wip_push_start \
                            and "push" in devkit_harness.git_writes(str(inp.get("command") or "")):
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
    # 31/10: a push carries code to others, so it needs THE 4-way review like a handover (no skip on an older agent review)
    logline(f"[{ts}] work in progress, but this turn pushed (#{_unreviewed_push or push_marks}) — gated by the 4-way review")

# No .kt edited by me this session (the dirty files are pre-existing /
# someone else's) → nothing of mine to gate.
if last_edit_idx == -1:
    reset_attempts()
    logline(f"[{ts}] uncommitted code exists but none edited this session "
            f"({changed}) — pass")
    sys.exit(0)

# ── 3) THE review: Claude Code + OCR + Antigravity, unanimous (bin/review-fanout.sh + bin/review-merge.py) ──
def _fanout_path():
    for cand in (os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "..", "bin", "review-fanout.sh"),
                 os.path.join(os.path.dirname(os.path.realpath(os.path.join(os.environ.get("CLAIM_HOOKDIR", ""), "review_gate.sh"))),
                              "..", "bin", "review-fanout.sh"),
                 os.path.join(repo_root, ".agents", "devkit", "bin", "review-fanout.sh"),
                 os.path.join(repo_root, "universal-agent-devkit", "bin", "review-fanout.sh")):
        if os.path.isabs(cand) and os.path.isfile(cand):
            return os.path.realpath(cand)
    return ""


def _block(lines_):
    unrev_ = sorted(session_unreviewed)
    out = list(lines_) + ["", f"{len(unrev_)} file code session này sửa, chưa có review 4 bên PASS cho đúng code hiện tại:"]
    out += [f"  • {f}" for f in unrev_[:20]] + ([f"  … +{len(unrev_) - 20} file nữa"] if len(unrev_) > 20 else [])
    sys.stderr.write("\n".join(out) + "\n")
    sys.exit(2)


fanout = _fanout_path()
review_base = "merge-base"   # bin/review-fanout.sh resolves merge-base(HEAD, origin/<base>) — the base super-board-merge-gate.sh queries: one code state, one hash
if not fanout:
    logline(f"[{ts}] BLOCK — bin/review-fanout.sh not found next to the hook")
    _block(["⛔ REVIEW-GATE: không tìm thấy bin/review-fanout.sh (review 4 bên) — chặn (fail-closed). Cài lại DevKit: agent-kit init."])
cmd_show = f"bash {fanout} --repo {repo_root} --base {review_base}"


def _fanout_env():
    """The environment the gate starts review-fanout with (audit 31/10): nothing inherited from settings.json or the session can
    reduce the review (REVIEW_SKIP_REVIEWERS), swap a reviewer binary (REVIEW_*_BIN, REVIEW_AGY_CLI, ANTIGRAVITY_PM_AGY) or model
    (REVIEW_*_MODEL), lower the depth (REVIEW_DEEP_LINES) or the budgets (REVIEW_MAX_*), or point the BUG-REV rows at a checklist
    outside the repo (REVIEW_REGRESSION_STATUS: only a trusted caller — the merge gate, B2 of #742 — sets it; review of #742,
    BUG-REV 2823727da8): the default gate always runs and judges the default 4-way review."""
    def stripped(k):
        return (k in ("REVIEW_SKIP_REVIEWERS", "REVIEW_AGY_CLI", "REVIEW_DEEP_LINES", "REVIEW_REGRESSION_STATUS", "ANTIGRAVITY_PM_AGY")
                or (k.startswith("REVIEW_") and k.endswith(("_BIN", "_MODEL"))) or k.startswith("REVIEW_MAX_"))
    return {k: v for k, v in os.environ.items() if not stripped(k)}

try:
    st = subprocess.run(["bash", fanout, "--repo", repo_root, "--base", review_base, "--status"],
                        capture_output=True, text=True, timeout=15, env=_fanout_env())
    state, run_dir = (st.stdout.split() + ["", ""])[:2]
except Exception as e:
    logline(f"[{ts}] review-fanout --status failed: {e!r} — BLOCK")
    _block([f"⛔ REVIEW-GATE: không đọc được trạng thái review 4 bên ({e!r}) — chặn (fail-closed).", f"Chạy tay: {cmd_show}"])
if state == "PASS":
    reset_attempts()
    logline(f"[{ts}] 4-way review PASS for this code ({os.path.basename(run_dir)}) — pass")
    sys.exit(0)
if state == "FAIL":
    try:
        with open(os.path.join(run_dir, "summary.md"), encoding="utf-8") as fh:
            summ = fh.read().splitlines()[:45]
    except OSError:
        summ = [f"(summary.md không đọc được trong {run_dir})"]
    logline(f"[{ts}] BLOCK — 4-way review FAIL ({os.path.basename(run_dir)})")
    _block(["⛔ REVIEW-GATE: review 4 bên (Claude Opus + Antigravity + Grok + OCR) KHÔNG PASS cho code này — cả 4 phải cùng pass.", ""] + summ + [
        "", "Sửa từng finding P0/P1 (fix theo CLASS, không chỉ instance) + viết test hồi quy rồi",
        "  regression_checklist.py bug-link BUG-REV-<id> <test>; bug lặp lại dạng mới: instincts.py add … --detect '<regex>'.",
        f"Code đổi → review lại tự chạy. Chạy ngay và chờ kết quả: {cmd_show}",
        f"Reviewer lỗi/timeout/thiếu thì chạy lại sau khi sửa môi trường: {cmd_show} --force"])
if state == "RUNNING":
    logline(f"[{ts}] BLOCK — 4-way review running ({os.path.basename(run_dir)})")
    _block(["⛔ REVIEW-GATE: review 4 bên đang chạy cho đúng code này. Chờ kết quả (đừng sửa code giữa chừng):",
            f"  {cmd_show}   (in kết quả khi xong; trạng thái: --status)"])
if os.environ.get("REVIEW_GATE_AUTOSTART", "1") == "0":   # tests (tests/lib/clean_git_env.sh): never start real LLM reviewers; still blocks
    started = "chưa (REVIEW_GATE_AUTOSTART=0) — tự chạy lệnh dưới"
    logline(f"[{ts}] BLOCK — no 4-way review yet (autostart off)")
else:
    try:
        bg = subprocess.run(["bash", fanout, "--repo", repo_root, "--base", review_base, "--background"],
                            capture_output=True, text=True, timeout=15, env=_fanout_env())
        logline(f"[{ts}] BLOCK — 4-way review started: {bg.stdout.strip()[:200]}")
        started = bg.stdout.strip() or bg.stderr.strip()
    except Exception as e:
        logline(f"[{ts}] review-fanout --background failed: {e!r}")
        started = f"không tự khởi động được ({e!r})"
_block(["⛔ REVIEW-GATE: code chưa có review 4 bên (Claude Code Opus + Antigravity + Grok + Alibaba OCR, cả 4 phải cùng PASS).",
        f"Khởi động ở nền: {started}",
        f"Chờ kết quả: {cmd_show}   (cùng code thì dùng lại kết quả, không chạy/tốn 2 lần)"])
PY
rc=$?
[ "${rc}" -eq 0 ] && exit 0
[ "${rc}" -eq 2 ] && exit 2
echo "⛔ REVIEW-GATE: gate lỗi (python rc=${rc}) — chặn (fail-closed). Log: ${LOG}" >&2
exit 2
