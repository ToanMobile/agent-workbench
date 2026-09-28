#!/usr/bin/env python3
"""Does the full-gate PASS cover what a `git push` sends? Called by hooks/block-dangerous-git.sh.

Rule (rules/essentials.md, Git): every push needs the latest `post-fix-gate --run-tests --full`
at exit 0 on the content pushed, or an edited test an Antigravity audit passed
(`Test-approved-by:` in the pushed commits). Audit 2026-09-28: nothing enforced it.

The receipt (.git/postfix-gate/full_pass.json, written by post-fix-gate on a full PASS) holds
`head` (HEAD when the gate ran) and `dirty` ({path: blob sha, or null when deleted} for every
file that differed from HEAD). The push passes when `head` is an ancestor of (or is) the pushed
commit and every file changed between them has, in the pushed commit, the blob the gate tested.

Only repos with an active regression matrix are checked: without one no receipt can exist.
Files the gate itself writes after the run (tree_fp.EXCLUDE) are not compared.
ponytail: a file dirty at gate time and left uncommitted (another session's work in a shared
checkout) was in the tested tree but is not pushed — accepted; checking it blocks every push
from a shared checkout. Upgrade when pushes from shared trees are rare.

CLI: push_gate.py <dir> [<rev>]  → exit 0 covered · 2 not covered (reason on stdout).
100% standard library.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tree_fp  # noqa: E402

MATRIX = os.path.join(".agents", "regression_matrix.active.json")
GATE = "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"
APPROVED = "Test-approved-by:"


def git(cwd, *args):
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    return r.returncode, r.stdout


def blobs(top, rev, paths):
    """{path: blob sha} of paths in rev (absent → not in the map), one git call."""
    if not paths:
        return {}
    rc, out = git(top, "ls-tree", "-r", "-z", rev, "--", *paths)
    if rc != 0:
        raise RuntimeError(f"git ls-tree {rev} failed")
    res = {}
    for rec in out.split("\0"):
        if "\t" in rec:
            meta, path = rec.split("\t", 1)
            res[path] = meta.split()[2]
    return res


def approved(top, rng):
    rc, out = git(top, "log", "--format=%B", rng)
    return rc == 0 and APPROVED in out


def check(cwd, rev="HEAD"):
    """(ok, reason)."""
    rc, top = git(cwd, "rev-parse", "--show-toplevel")
    if rc != 0:
        return True, "not a git repo"
    top = top.strip()
    rp = tree_fp.receipt_path(top)
    try:
        with open(rp, encoding="utf-8") as f:
            receipt = json.load(f)
    except (TypeError, OSError, ValueError):
        receipt = None
    project = (receipt or {}).get("project") or top
    if not any(os.path.isfile(os.path.join(d, MATRIX)) for d in {project, top, os.path.abspath(cwd)}):
        return True, "no regression matrix"
    if not isinstance(receipt, dict) or receipt.get("exit") != 0 or not receipt.get("head"):
        if approved(top, "@{u}.." + rev):
            return True, APPROVED
        return False, "chưa có biên nhận gate --full exit 0 (có head) cho code sắp push"
    head = receipt["head"]
    if subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", head, rev],
                      capture_output=True, timeout=5).returncode != 0:
        return False, f"lần gate PASS gần nhất ({head[:10]}) không nằm trong lịch sử của {rev} (pull/rebase sau gate?)"
    if approved(top, f"{head}..{rev}"):
        return True, APPROVED
    rc, out = git(top, "diff", "--name-only", "-z", head, rev)
    if rc != 0:
        raise RuntimeError("git diff failed")
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    prefix = "" if prefix == "." else prefix + "/"
    changed = [p for p in out.split("\0") if p
               and not any(p == prefix + e or p.startswith(prefix + e + "/") for e in tree_fp.EXCLUDE)]
    dirty = receipt.get("dirty") or {}
    now, then = blobs(top, rev, changed), blobs(top, head, changed)
    bad = [p for p in changed if now.get(p) != (dirty[p] if p in dirty else then.get(p))]
    if bad:
        return False, (f"{len(bad)} file sắp push khác bản gate đã test (sửa/commit sau lần gate PASS): "
                       + ", ".join(bad[:5]))
    return True, "covered"


def main(argv):
    cwd = argv[1] if len(argv) > 1 else "."
    rev = argv[2] if len(argv) > 2 else "HEAD"
    try:
        ok, reason = check(cwd, rev)
    except (subprocess.TimeoutExpired, RuntimeError, OSError) as e:
        ok, reason = False, f"không kiểm được biên nhận gate ({e})"
    if not ok:
        print(f"{reason} — chạy `{GATE}` (exit 0) trên đúng code sẽ push, commit, rồi push lại")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
