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
import json
import os
import pathlib
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
                           timeout=10, stdin=subprocess.DEVNULL, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
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
                             input="".join(f"{r}^{{commit}}\n" for r in refs), capture_output=True, text=True, timeout=15)
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


def approved(top, rng):
    rc, out = git(top, "log", "--format=%B", rng)
    return rc == 0 and APPROVED in out


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
    except (TypeError, OSError, ValueError):
        receipt = None
    project = (receipt or {}).get("project") or top
    homes = [d for d in (project, top, os.path.abspath(cwd)) if os.path.isfile(os.path.join(d, MATRIX))]
    if not homes:
        return True, "no regression matrix"
    if not isinstance(receipt, dict) or receipt.get("exit") != 0 or not receipt.get("head"):
        if approved(top, "@{u}.." + rev):
            return True, APPROVED
        # --no-renames: a rename is also a delete of the old path (src/Foo.kt -> docs/Foo.md is code leaving)
        rc, out = git(top, "diff", "--name-only", "--no-renames", "-z", "@{u}", rev)
        if rc == 0 and untestable_only(top, homes[0], [p for p in out.split("\0") if p]):
            return True, "only files that need no test (docs / agent config), none watched by the matrix"
        return False, "chưa có biên nhận gate --full exit 0 (có head) cho code sắp push"
    head = receipt["head"]
    if subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", head, rev],
                      capture_output=True, timeout=5).returncode != 0:
        return False, f"lần gate PASS gần nhất ({head[:10]}) không nằm trong lịch sử của {rev} (pull/rebase sau gate?)"
    if approved(top, f"{head}..{rev}"):
        return True, APPROVED
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
                       + ", ".join(bad[:5]))
    return True, "covered"


def main(argv):
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
        print(f"{reason} — chạy `{GATE}` (exit 0) trên đúng code sẽ push, commit, rồi push lại")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
