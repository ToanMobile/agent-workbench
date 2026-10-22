#!/usr/bin/env python3
"""Fingerprint of a project's code state, shared by post-fix-gate.py (which records it in
the full-run receipt) and hooks/proof_gate.sh (which compares it on XONG).

It covers the content of every tracked and untracked, non-ignored file — so an edit made
after the gate ran changes it, while committing that same content does not. Files the gate and the proof step write themselves
are left out, otherwise running the gate or taking the screenshot would invalidate the
receipt: the checklist/status files, audit-gate logs, evidence, and reports/ (proof PNGs).

CLI: tree_fp.py <project_dir>  → prints the fingerprint (empty output outside git).
100% standard library.
"""
import hashlib
import os
import subprocess
import sys

EXCLUDE = (".claude/audit-gate", ".agents/regression_status.json", ".agents/regression_checklist.md",
           ".agents/CHECKLIST.md", ".agents/INBOX.md", ".agents/evidence", ".agents/archive", ".agents/instincts.md", "reports",
           "docs/super-board/runs",   # QA-lane evidence committed after the gate PASSed: not code (agent-workbench#248)
           ".agents/local/memory/claude-auto",   # the agent's own notes: not code (memory/voice is, GeelyEx2 tests read it)
           # the temp file of regression_checklist.save(): tempfile.mkstemp(dir=".agents", prefix=".regression_status.") = that prefix + exactly 8
           # characters of [a-z0-9_], in .agents/ until os.replace. The gate releases test_run.lock before the save, so a run that wins the lock
           # meanwhile fingerprinted a tree that holds it and refused the receipt of the run it waited for (tests/gates/test_tree_fp_checklist_temp.sh).
           # A git pathspec (the throw-away index `rm --cached` below and in push_gate.py): nothing else matches it, and the plain-string tests on
           # EXCLUDE (path == entry or startswith(entry + "/")) never do, which is harmless for a file that no commit holds.
           # The other mkstemp prefixes of that module need no entry: ".tmp." is written inside .agents/regression_journal/ (its own .gitignore
           # is "*") and ".worktree_checklist." inside the git dir.
           ".agents/.regression_status." + "[a-z0-9_]" * 8)
RECEIPT = "full_pass.json"
# #105: the --full exit-0 receipts again, one per tree fingerprint, in the git COMMON dir: they outlive the worktree that wrote them.
TREE_RECEIPT_MAX_AGE_S = 24 * 3600
TREE_RECEIPT_MAX = 64


def _git(project_dir, *args):
    return subprocess.run(["git", "-C", str(project_dir), *args], capture_output=True)


def receipt_path(project_dir):
    """.git/postfix-gate/full_pass.json of the repo holding project_dir, or .agents/audit-gate/full_pass.json for non-git."""
    res = _git(project_dir, "rev-parse", "--absolute-git-dir")
    if res.returncode != 0:
        return os.path.join(str(project_dir), ".agents", "audit-gate", RECEIPT)
    return os.path.join(res.stdout.decode(errors="surrogateescape").strip(), "postfix-gate", RECEIPT)   # a non-UTF-8 folder name (2026-10-09)


def tree_receipt_dir(project_dir):
    """<git common dir>/postfix-gate/tree_receipts (<fingerprint>.json each), shared by every worktree of the repo; None outside git."""
    res = _git(project_dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if res.returncode != 0:
        return None
    return os.path.join(res.stdout.decode(errors="surrogateescape").strip(), "postfix-gate", "tree_receipts")


def _non_git_fingerprint(project_dir):
    h = hashlib.sha256()
    try:
        from pathlib import Path
        proj = Path(project_dir)
        for root, dirs, files in os.walk(project_dir):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "build", "dist", "reports", "__pycache__")]
            for f in sorted(files):
                if f.startswith("."):
                    continue
                p = Path(root) / f
                try:
                    rel = str(p.relative_to(proj)).replace("\\", "/")
                except ValueError:
                    continue
                if any(rel == ex or rel.startswith(ex + "/") for ex in EXCLUDE):
                    continue
                try:
                    st = p.stat()
                    h.update(f"{rel}:{st.st_size}:{st.st_mtime_ns}".encode())
                except OSError:
                    continue
        return h.hexdigest()[:24]
    except Exception:
        return ""


def tree_fingerprint(project_dir):
    """Hash of the CONTENT of project_dir as it stands (tracked + untracked, ignores and EXCLUDE
    left out), built in a throw-away index so the real one is never touched. It does not
    include the HEAD commit id: committing exactly the gated code keeps the receipt valid,
    any content change voids it."""
    import shutil
    import tempfile
    if _git(project_dir, "rev-parse", "HEAD").returncode != 0:
        return _non_git_fingerprint(project_dir)
    gitdir = _git(project_dir, "rev-parse", "--absolute-git-dir").stdout.decode().strip()
    prefix = _git(project_dir, "rev-parse", "--show-prefix").stdout.decode().strip()
    objects = _git(project_dir, "rev-parse", "--path-format=absolute", "--git-path", "objects").stdout.decode().strip()
    tree_fingerprint.error = ""
    with tempfile.TemporaryDirectory() as tmp:
        index = os.path.join(tmp, "index")
        if os.path.isfile(os.path.join(gitdir, "index")):
            # copy2, not copyfile: the copy must keep the index mtime, or git stops treating entries written in that same
            # second as "racily clean" and trusts their stat, so a same-size edit in that second is not seen
            shutil.copy2(os.path.join(gitdir, "index"), index)
        # New blobs go to a throw-away object store that reads the real one as an alternate:
        # the real .git/objects never grows because the gate or the Stop hook looked.
        os.makedirs(os.path.join(tmp, "objects", "info"))
        os.makedirs(os.path.join(tmp, "objects", "pack"))
        env = dict(os.environ, GIT_INDEX_FILE=index, GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects)
        run = lambda *a: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True, env=env)
        big_files, excludes = _big_untracked(project_dir)
        # Exclude after adding: an exclude pathspec naming an ignored path makes `add` fail (the big
        # files excluded here are untracked and NOT ignored, so their exclude is safe).
        added = run("add", "-A", "--", ".", *excludes)
        if added.returncode != 0:
            tree_fingerprint.error = added.stderr.decode(errors="replace").strip()[:300]
            return ""
        run("rm", "-r", "--cached", "-q", "--ignore-unmatch", "--", *EXCLUDE)
        tree = run("write-tree").stdout.decode().strip()
        if prefix and tree:
            tree = run("rev-parse", f"{tree}:{prefix.rstrip('/')}").stdout.decode().strip()
    if not tree:
        return ""
    # without big untracked files the value is the one it always was (receipts taken before stay valid)
    return hashlib.sha256((tree + "".join("\n" + b for b in big_files)).encode(errors="surrogateescape")).hexdigest()[:24]


def commit_fingerprint(project_dir, rev="HEAD", timeout=None):
    """The fingerprint tree_fingerprint gives a clean checkout of commit `rev` (#105: main's HEAD next to other sessions' uncommitted
    files), built from the commit alone in a throw-away index and object store. "" on a git error. An untracked file of
    TREE_FP_BIG_MB or more counts by its signature in tree_fingerprint and by content here, so such a tree never matches (fail closed).
    timeout: seconds for the WHOLE call (one deadline over its six git calls; a hook that runs past its own deadline is killed and its
    Stop goes through): subprocess.TimeoutExpired once it is spent."""
    import tempfile
    import time
    end = time.monotonic() + timeout if timeout else None
    rest = lambda: None if end is None else max(0.05, end - time.monotonic())
    git = lambda *a, env=None: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True, env=env, timeout=rest())
    objects = git("rev-parse", "--path-format=absolute", "--git-path", "objects").stdout.decode().strip()
    prefix = git("rev-parse", "--show-prefix").stdout.decode().strip()
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "objects", "info"))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"), GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects, GIT_NO_REPLACE_OBJECTS="1")
        run = lambda *a: git(*a, env=env)
        if not objects or run("read-tree", rev + "^{commit}").returncode:
            return ""
        run("rm", "-r", "-f", "--cached", "-q", "--ignore-unmatch", "--", *EXCLUDE)   # -f: the work tree (main's dirty files) is not this index
        tree = run("write-tree").stdout.decode().strip()
        if prefix and tree:
            tree = run("rev-parse", f"{tree}:{prefix.rstrip('/')}").stdout.decode().strip()
    return hashlib.sha256(tree.encode()).hexdigest()[:24] if tree else ""


def _big_untracked(project_dir):
    """Untracked, not ignored files of TREE_FP_BIG_MB MiB or more (default 8, the bound devkit_harness uses): (signatures
    "path<NUL>size<NUL>mtime_ns", sorted; exclude pathspecs for `git add`). GeelyEx2 2026-10-13: `git add -A` hashed 319 MB of
    untracked recordings on every fingerprint (6.5-7.3 s). Such a file counts by path, size and mtime, its content is never
    read. ponytail: a same-size edit that keeps mtime is not seen; content-hash big files only if a writer ever does that.
    TREE_FP_BIG_MB=0 hashes every file by content."""
    try:
        limit = int(float(os.environ.get("TREE_FP_BIG_MB", "8")) * (1 << 20))
    except ValueError:
        limit = 8 << 20
    if limit <= 0:
        return [], []
    listed = _git(project_dir, "ls-files", "-z", "--others", "--exclude-standard", "--", ".")
    if listed.returncode != 0:
        return [], []
    sigs, excludes = [], []
    for rel in listed.stdout.decode(errors="surrogateescape").split("\0"):
        if not rel or any(rel == ex or rel.startswith(ex + "/") for ex in EXCLUDE):
            continue
        try:
            st = os.lstat(os.path.join(str(project_dir), rel))
        except OSError:
            continue
        if st.st_size >= limit:
            sigs.append(f"{rel}\0{st.st_size}\0{st.st_mtime_ns}")
            excludes.append(":(exclude,literal)" + rel)
    return sorted(sigs), excludes


tree_fingerprint.error = ""   # why the last call returned "" (git's stderr), for the gate to print


# Proof image scope (rules/essentials.md step 4). The image is waived only for a change that
# surely never reaches a screen; anything else, of any extension at any depth, needs it.
NO_SCREEN_PROFILES = {"backend"}
PROFILE_FILES = (".agents/active-profile.json", ".active-profile.json")
OFF_SCREEN_TOP = {".agents", ".claude", ".gemini", ".github", ".githooks", ".codebase-memory",
                  "docs", "reports", "scripts", "bin", "tools"}      # first path component only
TEST_TOP = {"test", "tests", "__tests__", "spec", "Tests"}          # first path component, or *Tests
TEST_SOURCE_SETS = {"test", "androidTest", "androidUnitTest", "androidInstrumentedTest", "commonTest",
                    "jvmTest", "iosTest", "testDebug", "testRelease"}  # the segment right after src/
OFF_SCREEN_NAMES = {"LICENSE", "NOTICE", "AUTHORS", "CODEOWNERS", ".gitignore", ".editorconfig"}


def _off_screen(rel, profile=""):
    parts = rel.split("/")
    top = parts[0] if len(parts) > 1 else ""
    if top == "docs" and profile == "web":
        return False   # a web project's docs/ can be the site itself (Docusaurus, MkDocs)
    if top in OFF_SCREEN_TOP or top in TEST_TOP or top.endswith("Tests"):
        return True
    if rel.endswith(".log"):
        return True   # a log never reaches a screen, at any depth (GeelyEx2 artifacts/red-proof/*.log)
    if any(parts[i] == "src" and parts[i + 1] in TEST_SOURCE_SETS for i in range(len(parts) - 2)):
        return True
    if len(parts) == 1 and (rel.endswith((".md", ".rst", ".adoc")) or rel in OFF_SCREEN_NAMES):
        return True   # Markdown deeper down may be site content (Astro, Hugo, Docusaurus)
    return False


def _turn_base(project_dir, since):
    """Commit HEAD pointed at when the turn started (reflog), or None when unknown."""
    if not since:
        return "HEAD"
    res = _git(project_dir, "rev-parse", "-q", "--verify", f"HEAD@{{@{int(since)}}}")
    return res.stdout.decode().strip() or None if res.returncode == 0 else None


def _profile_at(project_dir, base, since):
    """(profile at the turn start, changed in the turn?). The committed file at `base`, else an
    uncommitted one (after `agent-kit init`, or an ignored .agents/) written before the turn."""
    import json
    parse = lambda raw: (json.loads(raw).get("profile") or "") if raw else ""
    for rel in PROFILE_FILES:
        res = _git(project_dir, "show", f"{base}:./{rel}")
        path = os.path.join(str(project_dir), rel)
        try:
            if res.returncode == 0:   # the profile VALUE: a re-init rewriting the same profile is no switch
                now = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
                return parse(res.stdout.decode()), parse(now) != parse(res.stdout.decode())
            if os.path.isfile(path):
                return parse(open(path, encoding="utf-8").read()), not since or os.path.getmtime(path) >= since
        except (OSError, ValueError, AttributeError):
            return "", True
    return "", False


def image_required(project_dir, since=None):
    """(required, reason). Changed = the working tree against the commit HEAD pointed at when
    the turn started (reflog, so commits, merges, pulls and resets of the turn all count) plus
    untracked files; renames show both paths. The profile is read at that commit, so switching
    it inside the turn waives nothing. Paths are relative to project_dir."""
    if _git(project_dir, "rev-parse", "HEAD").returncode != 0:
        return True, "git state unknown"
    base = _turn_base(project_dir, since)
    if not base:
        return True, "HEAD at the turn start unknown"
    names = _git(project_dir, "diff", base, "--name-only", "--relative", "--no-renames", "-z").stdout
    names += _git(project_dir, "ls-files", "-o", "--exclude-standard", "-z").stdout
    changed = {p.strip("\n") for p in names.decode(errors="replace").split("\0") if p.strip("\n")}
    prof, prof_changed = _profile_at(project_dir, base, since)
    if prof in NO_SCREEN_PROFILES and not prof_changed:
        return False, f"profile {prof} has no screen"
    for rel in sorted(changed):
        if not _off_screen(rel, prof):
            return True, f"may show on screen: {rel}"
    return False, "only tests, docs, scripts or agent files changed"


if __name__ == "__main__":
    print(tree_fingerprint(sys.argv[1] if len(sys.argv) > 1 else "."))
