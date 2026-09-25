#!/usr/bin/env python3
"""relink_check.py <project> [--hook=<name> <hook args…>] [--quiet] — put back DevKit links
a git operation removed.

A symlink-mode install keeps its links out of git (.git/info/exclude). A merge, checkout
or rebase onto a commit that deleted a tracked copy of such a link removes the file from
the working tree too: every hook that pointed at it then exits 127, which Claude Code
does not treat as blocking — guards and gates are silently off (measured 2026-09-24 in
three projects). Run from the post-merge / post-checkout / post-rewrite git hooks.

It only ever re-creates missing links (untracked, excluded from git) — never runs the
installer, never changes the profile, never touches a tracked file. It does nothing:
  * in a linked worktree (git-dir != git-common-dir; `agent-kit worktree add` sets those
    up) and on a file checkout (post-checkout flag 0: `git checkout -- f`, `git restore`);
  * in a tree without a DevKit 1.3 install (no .agents/active-profile.json or no
    .agents/context/: an older commit, a branch from before the install);
  * with DEVKIT_RELINK=0.
A link it cannot re-create is logged (.claude/audit-gate/relink.log) with "run agent-kit
init". When nothing is missing, .agents/context/ (generated, git-ignored) is brought up
to date. Exit 0 always.
"""
import json
import os
import re
import subprocess
import sys

DEVKIT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def git(project, *args):
    r = subprocess.run(["git", "-C", project, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def should_run(project, argv):
    if os.environ.get("DEVKIT_RELINK") == "0":
        return False
    hook = next((a.split("=", 1)[1] for a in argv if a.startswith("--hook=")), "")
    rest = [a for a in argv[2:] if not a.startswith("--")]
    if hook == "post-checkout" and len(rest) >= 3 and rest[2] == "0":
        return False                    # a file checkout, not a branch switch
    gd, cd = git(project, "rev-parse", "--absolute-git-dir"), git(project, "rev-parse", "--git-common-dir")
    if gd and cd:
        common = cd if os.path.isabs(cd) else os.path.join(project, cd)
        if os.path.realpath(gd) != os.path.realpath(common):
            return False                # a linked worktree
    return (os.path.isfile(os.path.join(project, ".agents", "active-profile.json"))
            and os.path.isdir(os.path.join(project, ".agents", "context")))


def excluded_skills(project):
    try:
        prof = json.load(open(os.path.join(project, ".agents", "active-profile", "profile.json"), encoding="utf-8"))
    except (OSError, ValueError):
        prof = {}
    return set(prof.get("exclude_skills", []))


def missing(project):
    """Relative paths of DevKit links the project should have and does not."""
    out = []
    try:
        settings = json.load(open(os.path.join(project, ".claude", "settings.json"), encoding="utf-8"))
    except (OSError, ValueError):
        settings = {}
    for arr in (settings.get("hooks") or {}).values():
        for m in arr:
            for h in m.get("hooks", []):
                for rel in re.findall(r"(?:^|[\s\"'/])(\.claude/hooks/[\w.-]+)", h.get("command", "")):
                    if not os.path.lexists(os.path.join(project, rel)):
                        out.append(rel)
    if not os.path.exists(os.path.join(project, ".agents", "devkit", "rules", "essentials.md")):
        out.append(".agents/devkit")    # master rules, core-rules, the post-fix gate
    excluded = excluded_skills(project)
    cmds = os.path.join(DEVKIT, "commands")
    if os.path.isdir(os.path.join(project, ".claude", "commands")):
        for name in sorted(os.listdir(cmds)):
            src = os.path.join(cmds, name)
            skill = os.path.basename(os.path.dirname(os.path.realpath(src))) if os.path.islink(src) else None
            if name.endswith(".md") and skill not in excluded and not os.path.lexists(os.path.join(project, ".claude", "commands", name)):
                out.append(f".claude/commands/{name}")
    return sorted(set(out))


def source_for(project, rel):
    """What a missing link should point at: the DevKit's item, else the project tier's."""
    if rel == ".agents/devkit":
        return DEVKIT
    kind, name = rel.split("/")[1], os.path.basename(rel)   # hooks | commands
    for cand in (os.path.join(DEVKIT, kind, name), os.path.join(project, ".agents", "local", kind, name)):
        if os.path.exists(cand):
            return cand
    return None


def relink(project, gone):
    left = []
    for rel in gone:
        src, dst = source_for(project, rel), os.path.join(project, rel)
        if not src or os.path.lexists(dst):
            left.append(rel)
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if src.startswith(os.path.join(project, ".agents", "local") + os.sep):
            src = os.path.relpath(src, os.path.dirname(dst))   # project tier: relative, like the installer
        os.symlink(src, dst)
    return left


def main(argv):
    project = os.path.realpath(argv[1] if len(argv) > 1 and not argv[1].startswith("-") else os.getcwd())
    if not should_run(project, argv):
        return 0
    gone = missing(project)
    if not gone:
        # --context-only: rewriting the tracked AGENTS.md right after a checkout would leave the
        # tree dirty (and could block the next checkout); SessionStart refreshes it instead.
        subprocess.run([sys.executable, os.path.join(DEVKIT, "scripts", "context_sync.py"), project, "--quiet",
                        "--context-only"], capture_output=True)
        return 0
    left = relink(project, gone)
    log = os.path.join(project, ".claude", "audit-gate", "relink.log")
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"restored {len(gone) - len(left)}/{len(gone)}; not restorable: {left}\n")
    except OSError:
        pass
    if "--quiet" not in argv:
        sys.stderr.write(f"DevKit: restored {len(gone) - len(left)} link(s) this git operation removed\n")
        if left:
            sys.stderr.write(f"DevKit: cannot restore {left} — run `agent-kit init`\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
