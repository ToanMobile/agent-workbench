"""Digest of every source post-fix-gate reads to approve an edited existing test (split_user_approved, _trailer_cross_review).

hooks/regression_gate.sh keys its stored "edited test waits for review" reminder on the content AND this digest: while both
stay the same the gate would say the same, so a repeat Stop prints the reminder without running the gate (measured 03/11:
62 edited_test Stop runs a day, 36 of them the same content again, ~47 s each). Anything that can change the verdict moves
the digest: the ledger .claude/audit-gate/approved_tests.json (of the project dir the gate resolves), approved_hashes.json
(project and main checkout), the antigravity-pm audit records (verdicts + audit dispatches) of every task id the ledger, an auditedHead on the branch or a
`Test-approved-by:` trailer of the branch names, whether their auditedHead resolves here, the answers of the user
(`toolUseResult.answers` records) that name a changed file in every transcript the gate scans, the trunk tip, the env that
changes the verdict and the code that computes it. The scan is a SUPERSET of the gate's (every tracked changed file, not
only the edited tests it will find), never the transcript mtime: a transcript grows every turn. Any error raises: the caller then
runs the gate (fail closed). Rules copied from bin/post-fix-gate.py and bin/push_gate.py (not imported: post-fix-gate is a
script with module state); a change there must be mirrored here. tests/gates/test_regression_gate_reminder_approval_key.sh
"""
import glob
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

# The env the verdict depends on: the reviewer identity check, the PM home and its test-fixture switch, the folders searched,
# the refused self-approval switch, and the gate cache that decides which suites a run starts.
# Wave 2 F2: push_gate.session_agent() (the self-approval check) also reads CLAUDECODE and the GROK_* session env.
ENV_KEYS = ("DEVKIT_AGENT_ID", "ANTIGRAVITY_PM_STATE_HOME", "DEVKIT_PM_HOME_TEST", "HOME", "CLAUDE_CODE_SESSION_ID",
            "DEVKIT_TRANSCRIPTS_DIR", "DEVKIT_AUTO_APPROVE_TESTS", "DEVKIT_GATE_CACHE", "DEVKIT_GATE_CACHE_MAX_S",
            "CLAUDECODE", "GROK_SESSION_ID", "GROK_WORKSPACE_ROOT", "GROK_HOOK_EVENT")
MAX_TASK_IDS = 64                 # more ids than that: no digest (the caller runs the gate)
TASK_JSON_MAX = 8_000_000         # push_gate._task_audits skips a bigger task.json
AUDITED_HEAD = re.compile(r"(?<![0-9A-Za-z])auditedHead:[ \t\n\r\f\v]*([0-9a-f]{40})(?![0-9A-Za-z])")   # push_gate.AUDITED_HEAD
SHA40 = re.compile(r"[0-9a-f]{40}")
SESSION_ID = re.compile(r"[A-Za-z0-9-]{8,64}")


class DigestError(Exception):
    pass


def _git(top, *args, ok_codes=(0,)):
    try:
        res = subprocess.run(["git", "-C", str(top), *args], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        raise DigestError("git %s: %r" % (args[0], e)) from e
    if res.returncode not in ok_codes:
        raise DigestError("git %s: exit %d" % (args[0], res.returncode))
    return res.returncode, res.stdout.decode("utf-8", "surrogateescape")


def _open_regular(path):
    """Binary file object of the REGULAR file at path, opened without waiting (post-fix-gate _state_fd): a FIFO planted in a
    transcript folder must not hang the Stop hook. Anything else raises OSError."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError("not a regular file: %s" % path)
    return os.fdopen(fd, "rb")


def _file_token(path):
    """sha256 of the bytes of a state file, "absent" when it is not there; unreadable raises (fail closed)."""
    try:
        with _open_regular(path) as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except FileNotFoundError:
        return "absent"
    except OSError as e:
        if not os.path.lexists(path):
            return "absent"
        raise DigestError("unreadable %s: %r" % (path, e)) from e


def _trunk(top):
    """(ref, sha) of the target branch, in the order of post-fix-gate task_trunk; (None, None) when there is none."""
    rc, out = _git(top, "symbolic-ref", "-q", "refs/remotes/origin/HEAD", ok_codes=(0, 1))
    refs = [out.strip()] if rc == 0 and out.strip().startswith("refs/remotes/origin/") else []
    refs += [p + n for p in ("refs/remotes/origin/", "refs/heads/") for n in ("main", "master", "trunk")]
    for ref in refs:
        rc, sha = _git(top, "rev-parse", "--verify", "-q", ref + "^{commit}", ok_codes=(0, 1))
        if rc == 0 and sha.strip():
            return ref, sha.strip()
    return None, None


def _trailer_ids(top, ranges):
    """Every token of every `Test-approved-by:` trailer value in the ranges (a superset of the task ids push_gate accepts)."""
    ids = set()
    for rng in ranges:
        _rc, out = _git(top, "log", "--format=%(trailers:key=Test-approved-by,valueonly,unfold)%x00", rng)
        for rec in out.split("\0"):
            for value in rec.splitlines():
                ids.update(value.split())
    return ids


def _pm_tokens(top, task_ids):
    """Canonical verdicts + audit dispatches of every task.json named task_id under the PM home (push_gate._task_pattern), and
    whether each auditedHead resolves to a commit here. Other task.json fields (PM bookkeeping) do not move the digest."""
    home = os.path.expanduser(os.environ.get("ANTIGRAVITY_PM_STATE_HOME") or os.path.join("~", ".antigravity-pm"))
    out = []
    for tid in sorted(task_ids):
        paths = sorted(glob.glob(os.path.join(glob.escape(home), "projects", "*", "tasks", tid, "task.json")))
        if not paths:
            out.append([tid, "absent"])
            continue
        for path in paths:
            try:
                st = os.stat(path)
                if not stat.S_ISREG(st.st_mode) or st.st_size > TASK_JSON_MAX:
                    out.append([tid, path, "skipped", st.st_size])
                    continue
                with _open_regular(path) as fh:
                    task = json.loads(fh.read().decode("utf-8"))
            except FileNotFoundError:
                out.append([tid, path, "absent"])
                continue
            except (OSError, ValueError, RecursionError):
                out.append([tid, path, "unreadable"])   # the gate skips it too; a later good write moves the digest
                continue
            if not isinstance(task, dict):
                out.append([tid, path, "not-object"])
                continue
            verdicts = task.get("verdicts") if isinstance(task.get("verdicts"), dict) else None
            audit = verdicts.get("audit") if verdicts else None
            dispatches = [d for d in task.get("dispatches") or [] if isinstance(d, dict) and d.get("kind") == "audit"] \
                if isinstance(task.get("dispatches"), list) else []
            heads = []
            if isinstance(audit, dict):
                cands = [audit.get("auditedHead")] if isinstance(audit.get("auditedHead"), str) and SHA40.fullmatch(audit["auditedHead"]) else []
                m = AUDITED_HEAD.search(audit["notes"]) if isinstance(audit.get("notes"), str) else None
                cands += [m.group(1)] if m else []
                for sha in cands:
                    rc, got = _git(top, "rev-parse", "--verify", "-q", sha + "^{commit}", ok_codes=(0, 1))
                    heads.append([sha, rc == 0 and got.strip() == sha])
            out.append([tid, path, task.get("id"), task.get("project"), verdicts, dispatches, heads])
    return out


def _answer_tokens(folders, session_files, cutoff, basenames):
    """sha256 of every `toolUseResult` record with answers whose questions name a changed file (by basename: a superset of the
    gate's path-or-basename match), in every transcript the gate scans (*.jsonl of the folders, mtime >= cutoff, plus the
    session file of the main checkout). Records do not change once written, so the set only moves on a new answer."""
    if cutoff is None or not basenames:
        return []
    cands = set()
    for fld in folders:
        try:
            cands.update(str(p) for p in Path(fld).glob("*.jsonl") if p.stat().st_mtime >= cutoff)
        except OSError:
            pass                                   # the gate skips an unreadable folder too
    for sf in session_files:
        try:
            if sf.is_file() and sf.stat().st_mtime >= cutoff:
                cands.add(str(sf))
        except OSError:
            pass
    found = set()
    for tp in sorted(cands):
        try:
            fh = _open_regular(tp)
        except OSError:
            continue                               # the gate skips it too
        with fh:
            for line in fh:
                if b'"answers"' not in line or b'"toolUseResult"' not in line:
                    continue
                try:
                    rec = json.loads(line.decode("utf-8", "replace"))
                    res = rec.get("toolUseResult")
                    if not isinstance(res, dict):
                        continue
                    qtext = json.dumps(res.get("questions"), ensure_ascii=False)
                except (ValueError, TypeError, AttributeError, RecursionError):
                    continue
                if any(b in qtext for b in basenames):
                    found.add(hashlib.sha256(json.dumps([rec.get("type"), rec.get("timestamp"), res.get("questions"),
                                                         res.get("answers")], sort_keys=True, ensure_ascii=False,
                                                        default=str).encode("utf-8", "surrogateescape")).hexdigest())
    return sorted(found)


def _all_audits(top):
    """Wave 2 F4: sorted [task_id, auditedHead] of EVERY audit pass of this repo (push_gate.audited_heads, auditHistory included):
    post-fix-gate audit_covers refuses an entry when a newer audit of ANY task on the PR chain has other content, so a task that
    neither the ledger nor a trailer names still moves the verdict. push_gate is a module (guarded by __main__): imported, not copied."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import push_gate  # noqa: PLC0415 - sibling module in bin/
        return sorted([str(t), str(h)] for t, h in push_gate.audited_heads(top))
    except Exception as e:  # noqa: BLE001 - any error: no digest, the caller runs the gate (fail closed)
        raise DigestError("audited_heads: %r" % (e,)) from e


def _grok_runs(top):
    """push_gate.grok_audit_runs(top): mọi lượt audit grok PM tự chạy (mọi project của pm home). Lỗi → DigestError (người gọi chạy gate)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import push_gate  # noqa: PLC0415 - sibling module in bin/
        return push_gate.grok_audit_runs(top)
    except Exception as e:  # noqa: BLE001 - any error: no digest, the caller runs the gate (fail closed)
        raise DigestError("grok_audit_runs: %r" % (e,)) from e


def _stat_sig(paths):
    sig = []
    for p in paths:
        try:
            st = os.stat(p)
            sig.append("%d:%d" % (st.st_mtime_ns, st.st_size))
        except OSError:
            sig.append("-")
    return sig


def tracked_changes(status_z):
    """Paths of `git status --porcelain=v1 -z` output that can be an edited EXISTING test: tracked entries only (untracked and
    ignored ones are new files, the gate never calls them touched). The source of a rename/copy is its own -z field: skipped.
    Untracked files are left out because an old scratch file would pull the transcript cutoff back by days (3.3 GB of
    transcripts in one project folder, 03/11)."""
    out, parts, i = [], status_z.split("\0"), 0
    while i < len(parts):
        e, i = parts[i], i + 1
        if len(e) < 4:
            continue
        if e[0] in "RC":
            i += 1
        if e[:2] not in ("??", "!!"):
            out.append(e[3:])
    return out


def digest(repo, transcript, status_z, commit_base=None, code_paths=()):
    """Hex digest of the approval sources for the project `repo` (the dir the gate gets as CLAUDE_PROJECT_DIR), the payload
    transcript path, status_z (`git status --porcelain=v1 -z` of the git top: its tracked entries are the dirty part of the
    change) and commit_base (the --since base the hook passes, its commits join the change). code_paths: the gate and hook
    files whose stat joins the digest. A deterministic function of the content and the sources, so the value computed before
    a run matches the one of the next Stop on the same content. Raises on error."""
    root = Path(os.path.realpath(repo))             # post-fix-gate get_project_dir + realpath
    _rc, top = _git(root, "rev-parse", "--show-toplevel")
    top = top.strip()
    _rc, common = _git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    common = common.strip()
    main_root = Path(os.path.realpath(str(Path(common).parent))) if common and Path(common).name == ".git" else root

    files = {p for p in tracked_changes(status_z) if p}
    if commit_base:
        _rc, names = _git(top, "diff", "--name-only", "-z", commit_base, "HEAD")
        files.update(n for n in names.split("\0") if n)
    mtimes = []
    for p in files:
        try:
            mtimes.append(os.stat(os.path.join(top, p)).st_mtime)
        except OSError:
            pass                                   # deleted: the gate binds no approval to it either
    cutoff = min(mtimes) if mtimes else None
    basenames = sorted({os.path.basename(p.rstrip("/")) for p in files} - {""})

    ledger = root / ".claude" / "audit-gate" / "approved_tests.json"
    ledger_tok = _file_token(ledger)
    task_ids = set()
    if ledger_tok != "absent":
        try:
            with _open_regular(ledger) as fh:
                saved = json.loads(fh.read().decode("utf-8"))
        except (OSError, ValueError, RecursionError):
            saved = None                           # the gate approves nothing from it; its bytes are in ledger_tok
        entries = saved.get("approvals") if isinstance(saved, dict) else None
        for e in entries if isinstance(entries, list) else []:
            if isinstance(e, dict) and isinstance(e.get("task_id"), str) and e["task_id"].strip():
                task_ids.add(e["task_id"].strip())

    trunk_ref, trunk_sha = _trunk(top)
    ranges = ([commit_base + "..HEAD"] if commit_base else []) + ([trunk_ref + "..HEAD"] if trunk_ref else [])
    task_ids |= _trailer_ids(top, ranges)
    audits = _all_audits(top)
    if trunk_ref:
        # 04/11: post-fix-gate _pm_audit_cross_review tra thẳng biên bản của task có auditedHead trên nhánh (không cần ledger/trailer):
        # reviewer / dispatch của chúng đổi mà head không đổi vẫn đổi kết luận. Superset: mọi commit của HEAD không thuộc trunk.
        _rc, chain = _git(top, "rev-list", "HEAD", "--not", trunk_ref)
        on_chain = set(chain.split())
        task_ids |= {t for t, h in audits if h in on_chain}
        # review vòng 9: lượt grok (cả fail, mọi project) có head trên nhánh cũng đổi kết luận (post-fix-gate latest_fails)
        task_ids |= {r[0] for r in _grok_runs(top) if r[1] in on_chain}
    if len(task_ids) > MAX_TASK_IDS:
        raise DigestError("%d task ids" % len(task_ids))

    folders = []
    if transcript:
        folders.append(Path(transcript).parent)
    if os.environ.get("DEVKIT_TRANSCRIPTS_DIR"):
        folders.append(Path(os.environ["DEVKIT_TRANSCRIPTS_DIR"]))
    folders.append(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(root)))
    session_files = []
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if SESSION_ID.fullmatch(sid) and main_root != root:   # #582: this session's own transcript in the main checkout's folder
        session_files.append(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(main_root)) / (sid + ".jsonl"))
    agy_brain = Path.home() / ".gemini" / "antigravity" / "brain"
    if agy_brain.is_dir():
        try:
            folders.extend(agy_brain.glob("*/.system_generated/logs"))
        except OSError:
            pass

    parts = {
        "root": str(root),
        "ledger": ledger_tok,
        "hashes": [_file_token(root / ".claude" / "audit-gate" / "approved_hashes.json"),
                   _file_token(main_root / ".claude" / "audit-gate" / "approved_hashes.json")],
        "pm": _pm_tokens(top, task_ids),
        "audits": audits,
        "answers": _answer_tokens(folders, session_files, cutoff, basenames),
        "trunk": [trunk_ref, trunk_sha],
        "commit_base": commit_base or "",
        "env": {k: os.environ.get(k) for k in ENV_KEYS},
        "code": _stat_sig(list(code_paths) + [os.path.abspath(__file__),
                                              os.path.join(os.path.dirname(os.path.abspath(__file__)), "push_gate.py")]),
    }
    return hashlib.sha256(json.dumps(parts, sort_keys=True, default=str).encode("utf-8", "surrogateescape")).hexdigest()[:24]
