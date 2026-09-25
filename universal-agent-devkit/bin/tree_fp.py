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
           ".agents/CHECKLIST.md", ".agents/INBOX.md", ".agents/evidence", ".agents/archive", "reports")
RECEIPT = "full_pass.json"


def _git(project_dir, *args):
    return subprocess.run(["git", "-C", str(project_dir), *args], capture_output=True)


def receipt_path(project_dir):
    """.git/postfix-gate/full_pass.json of the repo holding project_dir, or None."""
    res = _git(project_dir, "rev-parse", "--absolute-git-dir")
    if res.returncode != 0:
        return None
    return os.path.join(res.stdout.decode().strip(), "postfix-gate", RECEIPT)


def tree_fingerprint(project_dir):
    """Hash of the CONTENT of project_dir as it stands (tracked + untracked, ignores and EXCLUDE
    left out), built in a throw-away index so the real one is never touched. It does not
    include the HEAD commit id: committing exactly the gated code keeps the receipt valid,
    any content change voids it."""
    import shutil
    import tempfile
    if _git(project_dir, "rev-parse", "HEAD").returncode != 0:
        return ""
    gitdir = _git(project_dir, "rev-parse", "--absolute-git-dir").stdout.decode().strip()
    prefix = _git(project_dir, "rev-parse", "--show-prefix").stdout.decode().strip()
    objects = _git(project_dir, "rev-parse", "--path-format=absolute", "--git-path", "objects").stdout.decode().strip()
    tree_fingerprint.error = ""
    with tempfile.TemporaryDirectory() as tmp:
        index = os.path.join(tmp, "index")
        if os.path.isfile(os.path.join(gitdir, "index")):
            shutil.copyfile(os.path.join(gitdir, "index"), index)
        # New blobs go to a throw-away object store that reads the real one as an alternate:
        # the real .git/objects never grows because the gate or the Stop hook looked.
        os.makedirs(os.path.join(tmp, "objects", "info"))
        os.makedirs(os.path.join(tmp, "objects", "pack"))
        env = dict(os.environ, GIT_INDEX_FILE=index, GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects)
        run = lambda *a: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True, env=env)
        # Exclude after adding: an exclude pathspec naming an ignored path makes `add` fail.
        added = run("add", "-A", "--", ".")
        if added.returncode != 0:
            tree_fingerprint.error = added.stderr.decode(errors="replace").strip()[:300]
            return ""
        run("rm", "-r", "--cached", "-q", "--ignore-unmatch", "--", *EXCLUDE)
        tree = run("write-tree").stdout.decode().strip()
        if prefix and tree:
            tree = run("rev-parse", f"{tree}:{prefix.rstrip('/')}").stdout.decode().strip()
    return hashlib.sha256(tree.encode()).hexdigest()[:24] if tree else ""


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
            if res.returncode == 0:   # bytes: a CRLF file must not look changed
                now = open(path, "rb").read() if os.path.isfile(path) else b""
                return parse(res.stdout.decode()), now != res.stdout
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
