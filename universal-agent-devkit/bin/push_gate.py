#!/usr/bin/env python3
"""Does the full-gate PASS cover what a `git push` sends? Called by hooks/block-dangerous-git.sh.

Rule (rules/essentials.md, Git): every push needs the latest `post-fix-gate --run-tests --full`
at exit 0 on the content pushed, or an edited test an Antigravity audit passed: a pushed commit
whose trailer is `Test-approved-by: antigravity <task-id>` AND an antigravity-pm record of that
task of this repository with an audit pass (approved(); audit 2026-10-09: any line holding
"Test-approved-by:" used to pass). Audit 2026-09-28: nothing enforced it.

The receipt (.git/postfix-gate/full_pass.json, written by post-fix-gate on a full PASS) holds
`head` (HEAD when the gate ran) and `dirty` ({path: blob sha, or null when deleted} for every
file that differed from HEAD). The push passes when `head` is an ancestor of (or is) the pushed
commit and every file changed between them has, in the pushed commit, the blob the gate tested.
A commit that only rewords the gated one (`git commit --amend`, same tree) is covered too (2026-10-09).
The receipt must be what the gate writes, for this repository (receipt_problem(); 2026-10-09: a
hand-written {"exit": 0, "head": "<HEAD>"} passed): anything else counts as no receipt.

Only repos with an active regression matrix are checked: without one no receipt can exist.
Files the gate itself writes after the run (tree_fp.EXCLUDE) are not compared.
ponytail: a file dirty at gate time and left uncommitted (another session's work in a shared
checkout) was in the tested tree but is not pushed — accepted; checking it blocks every push
from a shared checkout. Upgrade when pushes from shared trees are rare.

A plain tag push (the guard passes --tag-remote <name> only for one) of commits the remote already has
uploads nothing new, so it needs no receipt: an old release tag can never contain the commit the last
gate passed (GeelyEx2 / OfficeReader, 2026-10-04). Any doubt falls back to the normal rule.

`git push --tags` / `--all` / `--branches` used to skip the guard altogether (measured 2026-10-04: exit 0 with an
ungated commit). --all-tags <remote>: every tag must point at a commit the remote already advertises, so it never
uploads one. --all-branches <remote>: every local branch has nothing new to send (its tip is in the remote branch of
the same name) or is covered exactly like `git push <remote> <branch>`.

CLI: push_gate.py <dir> [<rev>] [--tag-remote <name>] | --all-tags <name> | --all-branches <name>
→ exit 0 covered · 2 not covered (reason on stdout).
100% standard library.
"""
import glob
import json
import os
import pathlib
import re
import shlex
import stat
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tree_fp  # noqa: E402

MATRIX = os.path.join(".agents", "regression_matrix.active.json")
GATE = "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"
APPROVED = "Test-approved-by:"
APPROVED_VALUE = re.compile(r"antigravity\s+(T\d{4,}-[a-z0-9-]{1,48})")   # antigravity-pm TASK_ID_RE (src/tasks.js)
HEX_SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")


def git(cwd, *args):
    # surrogateescape: a path git prints that is not valid UTF-8 (cfg_<0xE9>.py) crashed the gate with a traceback (2026-10-09);
    # it now round-trips to the same bytes in argv and stdin, as bin/post-fix-gate.py decodes them
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, errors="surrogateescape", timeout=5)
    return r.returncode, r.stdout


def remote_refs(top, remote):
    """{refname: sha} the remote ITSELF advertises now (git ls-remote), not refs/remotes/* — a ref this repo's agent
    can write (update-ref, fetch . HEAD:refs/remotes/…) or one gone stale (review 2026-10-04). None when <remote>
    is not a configured remote name (a URL), there is no network, git fails or times out."""
    rc, names = git(top, "remote")
    if rc != 0 or remote not in names.split():
        return None
    # ls-remote asks the fetch url; `git push` goes to the push url (remote.<n>.pushurl, pushInsteadOf): when they
    # differ the answer is about another server (review 2026-10-04).
    rc1, fetch_url = git(top, "remote", "get-url", remote)
    rc2, push_url = git(top, "remote", "get-url", "--push", remote)
    if rc1 != 0 or rc2 != 0 or fetch_url.strip() != push_url.strip():
        return None
    try:
        r = subprocess.run(["git", "-C", top, "ls-remote", "--refs", remote], capture_output=True, text=True,
                           errors="surrogateescape", timeout=10, stdin=subprocess.DEVNULL, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    refs = {}
    for ln in r.stdout.splitlines():
        sha, _, name = ln.partition("\t")
        if name:
            refs[name] = sha
    return refs


def unpushed(top, commits, remote):
    """The set of commits reachable from <commits> that the remote does not have, or None when the remote cannot be
    asked (see remote_refs). A commit c of <commits> is on the remote exactly when c is not in the returned set."""
    refs = remote_refs(top, remote)
    if not refs:
        return None
    try:
        chk = subprocess.run(["git", "-C", top, "cat-file", "--batch-check"], input="\n".join(refs.values()) + "\n",
                             capture_output=True, text=True, timeout=5)
        have = [ln.split()[0] for ln in chk.stdout.splitlines() if ln.strip() and not ln.rstrip().endswith("missing")]
        out = subprocess.run(["git", "-C", top, "rev-list", "--stdin"],
                             input="\n".join(commits) + "\n--not\n" + "\n".join(have) + "\n",
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return set(out.stdout.split()) if out.returncode == 0 else None


def toplevel(cwd):
    """(top, why). Inside a .git directory `rev-parse --show-toplevel` fails although `git push` works there
    (review 2026-10-04: cwd=.git made every check fail open as "not a git repo"): the work tree is then the parent of
    a .git dir; a bare repository or any other layout → (None, "no work tree"), never fail-open. (None, None) = not a
    git repo at all."""
    rc, top = git(cwd, "rev-parse", "--show-toplevel")
    if rc == 0 and top.strip():
        return top.strip(), None
    rc, gd = git(cwd, "rev-parse", "--absolute-git-dir")
    if rc != 0:
        return None, None
    gd = gd.strip()
    return (os.path.dirname(gd), None) if os.path.basename(gd) == ".git" else (None, "no work tree")


def on_remote_only(top, rev, remote):
    """True when every commit of rev is on the remote (as the remote itself says). Any doubt → False, and the
    normal receipt rule applies."""
    rc, sha = git(top, "rev-parse", "--verify", "-q", rev + "^{commit}")
    if rc != 0:
        return False
    missing = unpushed(top, [sha.strip()], remote)
    return missing is not None and not missing


def check_all_tags(cwd, remote):
    """(ok, reason) for `git push --tags <remote>`: no new commit may ride along."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        return True, "not a git repo"
    rc, out = git(top, "for-each-ref", "--format=%(refname)", "refs/tags")
    if rc != 0:
        return False, "cannot list the tags"
    refs = out.split()
    try:     # one process for every tag (a subprocess per tag took 15 s for 2000 tags and timed out near 6000)
        chk = subprocess.run(["git", "-C", top, "cat-file", "--batch-check"],
                             input="".join(f"{r}^{{commit}}\n" for r in refs), capture_output=True, text=True,
                             errors="surrogateescape", timeout=15)
    except (OSError, subprocess.SubprocessError):
        return False, "cannot read the tags"
    lines = chk.stdout.splitlines()
    if chk.returncode != 0 or len(lines) != len(refs):
        return False, "cannot read the tags"
    pairs, odd = [], []
    for ref, ln in zip(refs, lines):
        (odd if ln.endswith(" missing") else pairs).append((ref[len("refs/tags/"):], ln.split()[0]))
    if odd:
        return False, "--tags would send tag(s) that do not point at a commit: " + ", ".join(n for n, _ in odd[:5])
    if not pairs:
        return True, "no tags"
    missing = unpushed(top, [c for _, c in pairs], remote)
    if missing is None:
        return False, f"cannot ask the remote \"{remote}\" (not a configured remote name, or no network): nothing says the tags' commits are already there"
    off = [n for n, c in pairs if c in missing]
    if off:
        return False, (f"--tags would send {len(off)} tag(s) of commits the remote does not have ({', '.join(off[:5])}): "
                       "push the branch first, through the gate, then the tags")
    return True, "every tag points at a commit the remote already has"


def check_all_branches(cwd, remote):
    """(ok, reason) for `git push --all|--branches <remote>`: each local branch has nothing new to send or is covered."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        return True, "not a git repo"
    rc, out = git(top, "for-each-ref", "--format=%(refname)", "refs/heads")
    if rc != 0:
        return False, "cannot list the branches"
    refs_raw = remote_refs(top, remote)
    refs = refs_raw or {}
    bad = []
    for ref in out.split():
        rc, tip = git(top, "rev-parse", "--verify", "-q", ref + "^{commit}")
        r_tip = refs.get(ref)
        if refs_raw and ref not in refs_raw:      # (an empty remote is a first push: the receipt rule decides)
            bad.append(f"{ref[len('refs/heads/'):]}: the remote has no such branch, --all would create it (1 dev, 1 branch): "
                       "push it by name or delete it locally")
            continue
        if rc == 0 and r_tip and git(top, "cat-file", "-e", r_tip + "^{commit}")[0] == 0 \
                and subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", tip.strip(), r_tip],
                                   capture_output=True, timeout=5).returncode == 0:
            continue                      # the remote branch of that name already has everything
        ok, reason = check(top, ref)
        if not ok:
            bad.append(f"{ref[len('refs/heads/'):]}: {reason}")
    return (not bad), "; ".join(bad[:3])


def entries(top, rev, paths):
    """{path: (mode, object sha)} of paths in rev (absent → not in the map), one git call."""
    if not paths:
        return {}
    rc, out = git(top, "ls-tree", "-r", "-z", rev, "--", *paths)
    if rc != 0:
        raise RuntimeError(f"git ls-tree {rev} failed")
    res = {}
    for rec in out.split("\0"):
        if "\t" in rec:
            meta, path = rec.split("\t", 1)
            res[path] = (meta.split()[0], meta.split()[2])
    return res


def blobs(top, rev, paths):
    """{path: blob sha} of paths in rev (absent → not in the map), one git call."""
    return {p: e[1] for p, e in entries(top, rev, paths).items()}


def untestable_only(top, project, paths):
    """True when every path (repo-relative) is a file post-fix-gate's needs_no_test() says needs no
    test (docs, agent state, the agents' harness config) AND no rule of the project's active matrix
    watches it. The gate's own classifier and matcher are used — never a second rule (INSTINCT-015).
    2026-09-29 (Goods): a commit of .claude/settings.json alone could not be pushed without a full
    gate, which REJECTed unrelated WIP in the working tree. Any doubt → False (a receipt is needed)."""
    import importlib.util  # noqa: PLC0415
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    prefix = "" if prefix == "." else prefix + "/"
    rel = [p[len(prefix):] if p.startswith(prefix) else None for p in paths
           if not any(p == prefix + e or p.startswith(prefix + e + "/") for e in tree_fp.EXCLUDE)]
    if not rel or None in rel:
        return False
    try:
        spec = importlib.util.spec_from_file_location(
            "post_fix_gate", os.path.join(os.path.dirname(os.path.abspath(__file__)), "post-fix-gate.py"))
        pfg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pfg)
        with open(os.path.join(project, MATRIX), encoding="utf-8") as f:
            rules = json.load(f).get("rules") or []
        # the gate's own "watched" rule: watch_files + files linked to a rule's tests (INSTINCT-015)
        pfg.get_project_dir = lambda: pathlib.Path(project)
        covers = pfg.checklist_covers()
        pats = [w for r in rules if isinstance(r, dict) for w in pfg.rule_watch(r, covers)]
        return all(pfg.needs_no_test(p) and not any(pfg.match_pattern(p, w) for w in pats) for p in rel)
    except Exception as e:  # noqa: BLE001 — cannot classify: fall back to requiring a receipt
        print(f"push_gate: không phân loại được file sắp push ({e}) — cần biên nhận gate", file=sys.stderr)
        return False


def recovery_hint(top, rev, head):
    """Second line of the "gated commit is not in the history of <rev>" refusal (OfficeReader 2026-10-08: a clone on a detached
    HEAD passed the gate, then `git push origin main` said only that, and nobody could tell the LOCAL main was stale): where the
    repository is, where HEAD is, and - when the branch <rev> is an ancestor of HEAD and the gated commit is in HEAD's history -
    the one command that fast-forwards it. Never raises: a hint must not turn a refusal into a crash."""
    gate_advice = f"`{GATE}` (exit 0) trên đúng code sẽ push, commit, rồi push lại"
    try:
        def is_ancestor(a, b):
            return subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", a, b],
                                  capture_output=True, timeout=5).returncode == 0
        rc, cur = git(top, "symbolic-ref", "-q", "--short", "HEAD")
        branch = cur.strip() if rc == 0 else ""
        rc, tip = git(top, "rev-parse", "HEAD")
        tip = tip.strip() if rc == 0 else ""
        where = f"repo {top}, " + (f"HEAD ở nhánh {branch}" if branch else "HEAD đang detached") + (f" tại {tip[:10]}" if tip else "")
        rc, _ = git(top, "rev-parse", "--verify", "-q", f"refs/heads/{rev}")
        if rev != "HEAD" and rc == 0 and tip and is_ancestor(rev, tip) and is_ancestor(head, tip):
            fix = f"cd {shlex.quote(top)} && git switch {shlex.quote(rev)} && git merge --ff-only {tip}"
            covered, _why = check(top, tip)   # would the push of HEAD itself pass? (a commit added after the gate would not)
            then = "rồi push lại (không cần chạy lại gate)" if covered else f"rồi chạy lại {gate_advice} (HEAD có code mới hơn lần gate)"
            return (f"{where}. Nhánh local {rev} cũ hơn commit đã qua gate (clone detached hoặc đang ở nhánh khác): "
                    f"chạy `{fix}` {then}")
        return f"{where}. Nếu đã pull/rebase/squash sau lần gate: chạy {gate_advice}"
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError):   # (check() below may raise RuntimeError: a hint never turns a refusal into a crash)
        return f"repo {top}. Chạy {gate_advice}"


def _inside(path, root):
    """True when `path` is `root` or lies under it, compared by inode (APFS case, symlinks, /private/tmp spellings)."""
    if not isinstance(path, str) or not path or not root:
        return False
    try:
        want = os.stat(root)
    except OSError:
        return False
    p = os.path.abspath(path)
    while True:
        try:
            if os.path.samestat(os.stat(p), want):
                return True
        except OSError:
            pass
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent


def audit_record(top, task_id):
    """(True, None) when antigravity-pm recorded an audit pass for task `task_id` of this repository; (False, why) otherwise.
    antigravity-pm keeps its task state OUTSIDE the repository (an agent cannot edit it from the work tree):
    ${ANTIGRAVITY_PM_STATE_HOME:-~/.antigravity-pm}/projects/<name>-<hash>/tasks/<id>/task.json, verdicts.audit.verdict
    (mcp-servers/antigravity-pm-mcp src/config.js, src/tasks.js recordVerdict). The task's `project` must be this repository
    (or a directory in it): task ids restart at T0001 in every project."""
    home = os.path.expanduser(os.environ.get("ANTIGRAVITY_PM_STATE_HOME") or os.path.join("~", ".antigravity-pm"))
    pattern = os.path.join(glob.escape(home), "projects", "*", "tasks", task_id, "task.json")
    verdicts = []
    for path in sorted(glob.glob(pattern)):
        try:
            if not stat.S_ISREG(os.stat(path).st_mode) or os.path.getsize(path) > 8_000_000:
                continue
            with open(path, encoding="utf-8") as f:
                task = json.load(f)
        except (OSError, ValueError, RecursionError):
            continue
        if not isinstance(task, dict) or task.get("id") != task_id or not _inside(task.get("project"), top):
            continue
        audit = (task.get("verdicts") or {}).get("audit") if isinstance(task.get("verdicts"), dict) else None
        verdict = audit.get("verdict") if isinstance(audit, dict) else None
        if verdict == "pass":
            return True, None
        verdicts.append(str(verdict or "chưa có"))
    if verdicts:
        return False, f"antigravity-pm: audit của {task_id} chưa pass ({', '.join(verdicts)})"
    return False, f"không có biên bản audit pass của antigravity-pm cho {task_id} trong repo này ({pattern})"


def approved(top, rng):
    """(True, note) when a commit of rng ends with the trailer `Test-approved-by: antigravity <task-id>` (git's own trailer
    parsing: the last paragraph, line-anchored) and antigravity-pm recorded an audit pass for that task (audit_record);
    (False, why) when a Test-approved-by line is there but does not count; (False, None) when there is none.
    Audit 2026-10-09: the old check was `"Test-approved-by:" in git log`, so "fix; Test-approved-by: whatever" passed.
    ponytail: the task record lives in a directory of the same user — an agent that writes ~/.antigravity-pm by hand still
    passes; upgrade to a record signed by the PM server if that is ever seen."""
    rc, out = git(top, "log", "--format=%(trailers:key=Test-approved-by,valueonly,unfold)%x00", rng)
    if rc != 0:
        return False, None
    values = [v.strip() for v in out.replace("\0", "\n").splitlines() if v.strip()]
    whys = []
    for value in values:   # newest commit first
        m = APPROVED_VALUE.fullmatch(value)
        if not m:
            whys.append(f"`{APPROVED} {value[:60]}` sai dạng (cần `{APPROVED} antigravity T0001-ten-task`)")
            continue
        ok, why = audit_record(top, m.group(1))
        if ok:
            return True, f"{APPROVED} antigravity {m.group(1)} (antigravity-pm audit pass)"
        whys.append(why)
    if not whys:
        rc, body = git(top, "log", "--format=%B", rng)
        if rc == 0 and APPROVED in body:
            whys.append(f"`{APPROVED}` chỉ tính khi là trailer cuối commit (`{APPROVED} antigravity <task-id>`)")
    return False, "; ".join(dict.fromkeys(whys[:3])) or None


def tested_fingerprint(top, project, head, dirty, rev):
    """The tree fingerprint (bin/tree_fp.py) of what the gate tested - commit `head` with the receipt's `dirty` applied,
    tree_fp.EXCLUDE left out - rebuilt from git objects in a throw-away index and object store (the real ones never change).
    None when it cannot be rebuilt exactly - a submodule or a symlink among the dirty paths (the gate's `hash-object --stdin-paths`
    hashes a symlink's TARGET, `git add` its text), or a file whose mode the gate saw cannot be told (the receipt has no modes: the
    pushed commit's mode when it holds that blob, the file's on disk, else HEAD's, else 100644; two of them disagreeing is a
    chmod or core.fileMode doubt) - and the caller then skips the comparison."""
    import hashlib  # noqa: PLC0415
    import tempfile  # noqa: PLC0415
    paths = list(dirty)
    at_head, at_rev = entries(top, head, paths), entries(top, rev, paths)
    if any(m in ("160000", "120000") for m, _ in list(at_head.values()) + list(at_rev.values())):
        return None
    lines = []
    for p, sha in dirty.items():
        if sha is None:
            lines.append(f"0 {'0' * len(head)}\t{p}")
            continue
        modes = {at_rev[p][0]} if p in at_rev and at_rev[p][1] == sha else set()
        try:
            st = os.lstat(os.path.join(top, p))
            if stat.S_ISLNK(st.st_mode):
                return None
            if stat.S_ISREG(st.st_mode):
                modes.add("100755" if st.st_mode & 0o100 else "100644")   # git's rule: the owner's x bit
        except OSError:
            pass
        if len(modes) > 1:
            return None
        lines.append(f"{modes.pop() if modes else (at_head[p][0] if p in at_head else '100644')} {sha}\t{p}")
    rc, objects = git(top, "rev-parse", "--path-format=absolute", "--git-path", "objects")
    if rc != 0:
        raise RuntimeError("git rev-parse --git-path objects failed")
    prefix = os.path.relpath(os.path.realpath(project), os.path.realpath(top)).replace(os.sep, "/")
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "objects", "info"))
        os.makedirs(os.path.join(tmp, "objects", "pack"))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"), GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects.strip())

        def run(cwd, *args, stdin=None):
            r = subprocess.run(["git", "-C", cwd, *args], input=stdin, capture_output=True, text=True, errors="surrogateescape",
                               timeout=60, env=env)
            if r.returncode != 0:
                raise RuntimeError(f"git {args[0]} failed: {r.stderr.strip()[:200]}")
            return r.stdout.strip()
        run(top, "read-tree", head)
        if lines:
            run(top, "update-index", "-z", "--index-info", stdin="\0".join(lines) + "\0")
        run(project, "rm", "-r", "-f", "--cached", "-q", "--ignore-unmatch", "--", *tree_fp.EXCLUDE)   # -f: a throw-away index
        tree = run(top, "write-tree", "--missing-ok")
        if prefix != ".":
            tree = run(top, "rev-parse", f"{tree}:{prefix}")
    return hashlib.sha256(tree.encode()).hexdigest()[:24]


def run_log_has(rp, receipt):
    """True when <git common dir>/postfix-gate/runs.jsonl (bin/post-fix-gate.py _log_gate_run, written right after the receipt) holds
    the line of this full PASS: mode full, exit 0, verdict PASS or REUSED, same project name, logged 0-900 s after the receipt."""
    gdir = os.path.dirname(os.path.dirname(rp))
    parent = os.path.dirname(gdir)
    base = os.path.dirname(parent) if os.path.basename(parent) == "worktrees" else gdir   # as post-fix-gate _run_log_dir
    try:
        fd = os.open(os.path.join(base, "postfix-gate", "runs.jsonl"), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return False
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return False
        n = min(st.st_size, 4 << 20)
        raw = os.pread(fd, n, st.st_size - n)
    except OSError:
        return False
    finally:
        os.close(fd)
    t, name = float(receipt["time"]), os.path.basename(str(receipt["project"]))[:64]
    for line in reversed(raw.splitlines()):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        epoch = rec.get("epoch") if isinstance(rec, dict) else None
        if not isinstance(epoch, int) or isinstance(epoch, bool):
            continue
        if epoch < t - 60:
            return False   # older than the receipt: lines are appended in time order
        if (epoch <= t + 900 and rec.get("mode") == "full" and rec.get("exit") == 0 and not isinstance(rec.get("exit"), bool)
                and rec.get("verdict") in ("PASS", "REUSED") and rec.get("project") == name):
            return True
    return False


def receipt_problem(top, rp, receipt, rev="HEAD"):
    """None when the full-pass receipt is what bin/post-fix-gate.py write_full_pass_receipt() writes on a full PASS of THIS
    repository - every field present with its type, `head` a commit here, `project` this repository, no failed suite, the
    fingerprint equal to that of head+dirty rebuilt from git, and the run-log line of that run present; else what is wrong.
    Audit 2026-10-09: a hand-written {"exit": 0, "head": "<HEAD>"} let any push through.
    ponytail: the receipt and runs.jsonl are files this user can write: a forger who rebuilds the fingerprint the way
    tree_fp.py does and appends a run-log line still passes; upgrade to a receipt signed with a key the agent cannot read
    (the user's keychain / ssh-agent) if a forged receipt is ever seen."""
    def number(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float("inf")
    if receipt.get("exit") != 0 or isinstance(receipt.get("exit"), bool):
        return "exit không phải 0"
    head = receipt.get("head")
    if not isinstance(head, str) or not HEX_SHA.fullmatch(head) or git(top, "cat-file", "-e", head + "^{commit}")[0] != 0:
        return "head không phải một commit của repo này"
    missing = [k for k in ("time", "tested_at", "fingerprint", "project", "dirty", "tests", "result_format", "gate_sha",
                           "matrix_sha", "local_sha") if k not in receipt]
    if missing:
        return "thiếu " + ", ".join(missing)
    if not number(receipt["time"]) or not number(receipt["tested_at"]) or receipt["time"] > time.time() + 300:
        return "time / tested_at không phải mốc thời gian hợp lệ"
    project = receipt["project"]
    if not isinstance(project, str) or not os.path.isdir(project) or not _inside(project, top):
        return f"project {str(project)[:80]} không thuộc repo {top}"
    dirty = receipt["dirty"]
    if not isinstance(dirty, dict) or not all(isinstance(p, str) and p and (v is None or (isinstance(v, str) and HEX_SHA.fullmatch(v)))
                                              for p, v in dirty.items()):
        return "dirty không đúng dạng {đường dẫn: blob sha | null}"
    tests = receipt["tests"]
    if not isinstance(tests, list) or not all(isinstance(t, dict) and isinstance(t.get("id"), str) and isinstance(t.get("status"), str)
                                              for t in tests):
        return "tests không đúng dạng"
    failed = [t["id"] for t in tests if t["status"] in ("FAIL", "TIMEOUT")]
    if failed:
        return "suite không PASS: " + ", ".join(failed[:5])
    fp = receipt["fingerprint"]
    if not isinstance(fp, str) or not re.fullmatch(r"[0-9a-f]{24}", fp):
        return "fingerprint (dấu vân tay code) thiếu hoặc sai dạng"
    want = tested_fingerprint(top, project, head, dirty, rev)
    if want is not None and want != fp:
        return "fingerprint không khớp code head+dirty mà biên nhận ghi"
    if not run_log_has(rp, receipt):
        return "không có dòng runs.jsonl của lần chạy gate này (biên nhận không do post-fix-gate --full ghi)"
    return None


def check(cwd, rev="HEAD", tag_remote=None):
    """(ok, reason)."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        return True, "not a git repo"
    if tag_remote and on_remote_only(top, rev, tag_remote):
        return True, "a tag of commits the remote already has: nothing new is pushed"
    rp = tree_fp.receipt_path(top)
    try:
        with open(rp, encoding="utf-8") as f:
            receipt = json.load(f)
    except (TypeError, OSError, ValueError, RecursionError):
        receipt = None
    if not isinstance(receipt, dict):
        receipt = None
    # a project outside this repository is not this repository's (a forged one could name a directory with no matrix)
    project = receipt.get("project") if receipt and _inside(receipt.get("project"), top) else top
    homes = [d for d in (project, top, os.path.abspath(cwd)) if os.path.isfile(os.path.join(d, MATRIX))]
    if not homes:
        return True, "no regression matrix"
    problem = None
    if receipt is not None and receipt.get("exit") == 0 and receipt.get("head"):
        problem = receipt_problem(top, rp, receipt, rev)
    if receipt is None or problem or receipt.get("exit") != 0 or not receipt.get("head"):
        ok, why_not = approved(top, "@{u}.." + rev)
        if ok:
            return True, why_not
        # --no-renames: a rename is also a delete of the old path (src/Foo.kt -> docs/Foo.md is code leaving)
        rc, out = git(top, "diff", "--name-only", "--no-renames", "-z", "@{u}", rev)
        if rc == 0 and untestable_only(top, homes[0], [p for p in out.split("\0") if p]):
            return True, "only files that need no test (docs / agent config), none watched by the matrix"
        return False, ("chưa có biên nhận gate --full exit 0 (có head) cho code sắp push"
                       + (f" (biên nhận hiện có không hợp lệ: {problem})" if problem else "") + (f"; {why_not}" if why_not else ""))
    head = receipt["head"]
    if subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", head, rev],
                      capture_output=True, timeout=5).returncode != 0:
        # D3 (2026-10-09): `git commit --amend` that only rewords the gated commit leaves its tree as it was - the same content,
        # covered like the gated commit itself. Any other rewrite (rebase, squash, an amend that changes a file) is refused.
        rc, trees = git(top, "rev-parse", head + "^{tree}", rev + "^{tree}")
        same_tree = rc == 0 and len(set(trees.split())) == 1 and len(trees.split()) == 2
        if not same_tree:
            return False, (f"lần gate PASS gần nhất ({head[:10]}) không nằm trong lịch sử của {rev} (pull/rebase sau gate?)\n"
                           + recovery_hint(top, rev, head))
    ok, why_not = approved(top, f"{head}..{rev}")
    if ok:
        return True, why_not
    rc, out = git(top, "diff", "--name-only", "--no-renames", "-z", head, rev)
    if rc != 0:
        raise RuntimeError("git diff failed")
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    prefix = "" if prefix == "." else prefix + "/"
    changed = [p for p in out.split("\0") if p
               and not any(p == prefix + e or p.startswith(prefix + e + "/") for e in tree_fp.EXCLUDE)]
    dirty = receipt.get("dirty") or {}
    now, then = blobs(top, rev, changed), blobs(top, head, changed)
    bad = [p for p in changed if now.get(p) != (dirty[p] if p in dirty else then.get(p))]
    if bad and untestable_only(top, project, bad):
        return True, "files changed since the gate need no test (docs / agent config), none watched by the matrix"
    if bad:
        return False, (f"{len(bad)} file sắp push khác bản gate đã test (sửa/commit sau lần gate PASS): "
                       + ", ".join(bad[:5]) + (f"; {why_not}" if why_not else ""))
    return True, "covered"


def main(argv):
    if hasattr(sys.stderr, "reconfigure"):   # untestable_only()'s warning may name a non-UTF-8 path too (see the print below)
        sys.stderr.reconfigure(errors="backslashreplace")
    argv = list(argv)
    tag_remote = None
    if "--tag-remote" in argv:
        k = argv.index("--tag-remote")
        tag_remote = argv[k + 1] if k + 1 < len(argv) else None
        del argv[k:k + 2]
    cwd = argv[1] if len(argv) > 1 else "."
    rev = argv[2] if len(argv) > 2 else "HEAD"
    try:
        if rev in ("--all-tags", "--all-branches") and len(argv) > 3:
            ok, reason = (check_all_tags if rev == "--all-tags" else check_all_branches)(cwd, argv[3])
        else:
            ok, reason = check(cwd, rev, tag_remote)
    except (subprocess.TimeoutExpired, RuntimeError, OSError) as e:
        ok, reason = False, f"không kiểm được biên nhận gate ({e})"
    if not ok:
        # backslashreplace: a reason naming a non-UTF-8 path or tag (decoded with surrogateescape) crashed the print on a
        # strict UTF-8 stdout (macOS, 2026-10-09). Set here, not at start: importing post-fix-gate.py resets it to "replace".
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(errors="backslashreplace")
        # a reason with a second line carries its own next step (recovery_hint): the generic one would contradict it
        print(reason if "\n" in reason else f"{reason} — chạy `{GATE}` (exit 0) trên đúng code sẽ push, commit, rồi push lại")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
