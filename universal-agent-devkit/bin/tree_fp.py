#!/usr/bin/env python3
"""Fingerprint of a project's code state, shared by post-fix-gate.py (which records it in
the full-run receipt) and hooks/proof_gate.sh (which compares it on XONG).

It covers HEAD, the tracked diff against HEAD and every untracked, non-ignored file — so an
edit made after the gate ran changes it. Files the gate and the proof step write themselves
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
    head = _git(project_dir, "rev-parse", "HEAD")
    if head.returncode != 0:
        return ""
    excl = [":(exclude)" + p for p in EXCLUDE]
    h = hashlib.sha256(head.stdout.strip())
    h.update(_git(project_dir, "diff", "HEAD", "--binary", "--no-ext-diff", "--", ".", *excl).stdout)
    untracked = _git(project_dir, "ls-files", "-o", "--exclude-standard", "-z", "--", ".", *excl).stdout
    for rel in sorted(p for p in untracked.decode(errors="replace").split("\0") if p):
        h.update(b"\0" + rel.encode())
        path = os.path.join(str(project_dir), rel)
        try:
            if os.path.islink(path):
                h.update(os.readlink(path).encode())
            else:
                with open(path, "rb") as f:
                    h.update(hashlib.sha256(f.read()).digest())
        except OSError:
            h.update(b"?")
    return h.hexdigest()[:24]


if __name__ == "__main__":
    print(tree_fingerprint(sys.argv[1] if len(sys.argv) > 1 else "."))
