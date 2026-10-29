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

It also removes a DevKit link the DevKit itself made obsolete: a `.claude/commands/` or
`.agents/skills/` symlink that is dangling AND points into this DevKit (absolute or through
the .agents/devkit alias) — a command or skill the kit dropped (1.2.0: review, qa, test,
bugs, crashlytics left 5 dangling links in every installed repo, health 90-93). A dangling
link pointing elsewhere, a regular file and a live link are never touched. SessionStart runs
it with --links-only (no context refresh: SessionStart does its own), so a session heals the
repo with no git operation and no `agent-kit init`.
"""
import contextlib
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile

DEVKIT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
if not os.path.isdir(os.path.join(DEVKIT, "profiles")) and os.path.isdir(os.path.join(os.path.dirname(DEVKIT), "profiles")):
    DEVKIT = os.path.dirname(DEVKIT)


def git(project, *args):
    r = subprocess.run(["git", "-C", project, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def should_run(project, argv):
    """False, True (checkout chính: mọi link + context), hoặc "worktree" (#644: linked worktree, chỉ với --links-only của SessionStart —
    chỉ link lệnh / skill của kit; .agents/devkit và hook do `agent-kit worktree add` / heal lo)."""
    if os.environ.get("DEVKIT_RELINK") == "0":
        return False
    if (os.path.realpath(project) + os.sep).startswith(os.path.realpath(DEVKIT) + os.sep):
        return False                    # a project inside the kit (a self-install): its links are the kit's own files
    hook = next((a.split("=", 1)[1] for a in argv if a.startswith("--hook=")), "")
    rest = [a for a in argv[2:] if not a.startswith("--")]
    if hook == "post-checkout" and len(rest) >= 3 and rest[2] == "0":
        return False                    # a file checkout, not a branch switch
    gd, cd = git(project, "rev-parse", "--absolute-git-dir"), git(project, "rev-parse", "--git-common-dir")
    if gd and cd:
        common = cd if os.path.isabs(cd) else os.path.join(project, cd)
        if os.path.realpath(gd) != os.path.realpath(common):
            # a linked worktree: .agents/context is git-ignored there, the tracked profile marks the install
            return "worktree" if ("--links-only" in argv
                                  and os.path.isfile(os.path.join(project, ".agents", "active-profile.json"))) else False
    return (os.path.isfile(os.path.join(project, ".agents", "active-profile.json"))
            and os.path.isdir(os.path.join(project, ".agents", "context")))


def main_checkout(project):
    """Thư mục checkout chính của repo (dòng đầu `git worktree list`), None khi không biết."""
    out = git(project, "worktree", "list", "--porcelain") or ""
    first = out.split("\n", 1)[0]
    return first[9:] if first.startswith("worktree ") else None


def foreign_kit(project):
    """True khi kit đang chạy nằm trong một checkout KHÁC của cùng repo (checkout chính chạy cho worktree, hay ngược lại): link lệnh /
    skill trỏ sang đó thì đổi theo nhánh của checkout kia và mất khi nó bị gỡ. Kit ở repo riêng (cài qua .agents/devkit) không phải."""
    top = git(DEVKIT, "rev-parse", "--show-toplevel")
    if not top:
        return False
    kc, pc = git(DEVKIT, "rev-parse", "--path-format=absolute", "--git-common-dir"), \
        git(project, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return bool(kc and pc and os.path.realpath(kc) == os.path.realpath(pc)
                and os.path.realpath(top) != os.path.realpath(project))


def in_kit(path):
    """True when path resolves into this DevKit: a link dir there lists (and would receive) the kit's own files. Shared by
    missing() and dangling() so both agree on which link directories are the project's to heal."""
    return (os.path.realpath(path) + os.sep).startswith(os.path.realpath(DEVKIT) + os.sep)


def excluded_skills(project):
    try:
        prof = json.load(open(os.path.join(project, ".agents", "active-profile", "profile.json"), encoding="utf-8"))
    except (OSError, ValueError):
        prof = {}
    return set(prof.get("exclude_skills", []))


def missing(project, worktree=False):
    """Relative paths of DevKit links the project should have and does not. worktree=True: only command / skill links (a linked
    worktree's .agents/skills/ holds git-ignored links only, so it is wanted when the main checkout has one). None of either when the
    running kit lies in another checkout of this repository (foreign_kit)."""
    out = []
    if worktree:
        return [] if foreign_kit(project) else _kit_items(project, main_checkout(project))
    out = [] if foreign_kit(project) else _kit_items(project, None)
    return sorted(set(_hooks_and_devkit(project) + out))


def _hooks_and_devkit(project):
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
    return out


def _kit_items(project, main):
    """Lệnh / skill của kit mà project chưa có link. main: checkout chính (linked worktree) — .agents/skills/ của worktree được muốn khi
    checkout chính có."""
    out = []
    excluded = excluded_skills(project)
    cmds = os.path.join(DEVKIT, "commands")
    # a link directory that resolves into the kit is the kit's own folder: never write into it. One that is absent is rebuilt
    # (`git rm -r .claude/commands`) in a Claude install (.claude/settings.json); a symlink to a project folder is healed as it is.
    cdir = os.path.join(project, ".claude", "commands")
    if ((os.path.isdir(cdir) or (not os.path.lexists(cdir) and os.path.isfile(os.path.join(project, ".claude", "settings.json"))))
            and not in_kit(cdir) and os.path.isdir(cmds)):
        for name in sorted(os.listdir(cmds)):
            src = os.path.join(cmds, name)
            skill = os.path.basename(os.path.dirname(os.path.realpath(src))) if os.path.islink(src) else None
            if name.endswith(".md") and skill not in excluded and not os.path.lexists(os.path.join(project, ".claude", "commands", name)):
                out.append(f".claude/commands/{name}")
    # every DevKit skill the profile keeps, in an install that has .agents/skills/: a skill the DevKit gained after the install
    # never got its link (OfficeReader 2026-10-13: health 96, .agents/skills/devkit-audit missing)
    skills_dir = os.path.join(project, ".agents", "skills")
    kit_skills = os.path.join(DEVKIT, "skills")
    # ponytail: a skills dir removed whole is not rebuilt (a claude-only install never had one), upgrade when the installer records it
    want = os.path.isdir(skills_dir) or (main is not None and not os.path.lexists(skills_dir)
                                         and os.path.isdir(os.path.join(main, ".agents", "skills")))
    if want and not in_kit(skills_dir) and os.path.isdir(kit_skills):
        for name in sorted(os.listdir(kit_skills)):
            if (name not in excluded and os.path.isfile(os.path.join(DEVKIT, "skills", name, "SKILL.md"))
                    and not os.path.lexists(os.path.join(skills_dir, name))):
                out.append(f".agents/skills/{name}")
    return out


def keep_out_of_git(project, rel, common=None):
    """A new link is local state, as the installer keeps it: /rel goes to .git/info/exclude unless an ignore rule covers it.
    Gọi trong exclude_lock() (relink truyền common): đọc-sửa-ghi exclude là một bước, ghi qua file tạm cùng thư mục rồi os.replace —
    hai relink song song không mất / không trùng dòng, tiến trình chết giữa chừng không để exclude dở dang."""
    if subprocess.run(["git", "-C", project, "check-ignore", "-q", "--", rel], capture_output=True).returncode == 0:
        return
    common = common or git(project, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return
    path = os.path.join(common, "info", "exclude")
    line = "/" + rel
    tmp = None
    try:
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
            mode = os.stat(path).st_mode & 0o777
        except FileNotFoundError:
            raw, mode = "", 0o644
        if line in raw.splitlines():
            return
        fd, tmp = tempfile.mkstemp(prefix=".exclude.", dir=os.path.dirname(path))
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(raw + ("\n" if raw and not raw.endswith("\n") else "") + line + "\n")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        tmp = None
    except OSError as e:
        sys.stderr.write(f"DevKit: cannot add {line} to {path}: {e}\n")
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


@contextlib.contextmanager
def exclude_lock(project):
    """Khoá fcntl trên <git-common-dir>/info/exclude.lock (file riêng: exclude bị os.replace nên khoá trên chính nó không giữ được).
    Trả common dir (None khi không phải git / không mở được khoá — vẫn chạy, chỉ không khoá)."""
    common = git(project, "rev-parse", "--path-format=absolute", "--git-common-dir")
    fd = None
    if common:
        try:
            os.makedirs(os.path.join(common, "info"), exist_ok=True)
            fd = os.open(os.path.join(common, "info", "exclude.lock"), os.O_RDWR | os.O_CREAT, 0o644)
            fcntl.flock(fd, fcntl.LOCK_EX)
        except OSError as e:
            sys.stderr.write(f"DevKit: exclude lock not taken: {e}\n")
    try:
        yield common
    finally:
        if fd is not None:
            os.close(fd)


def _same_link(dst, src):
    """dst là symlink tới đúng nơi src trỏ (phiên kia tạo cùng link) — chỉ link như vậy mới được ghi exclude, file người dùng thì không."""
    return os.path.islink(dst) and os.path.realpath(dst) == os.path.realpath(src)


def link_root(project):
    """The DevKit path new links go through: the one the installer wrote into .agents/devkit when it is this DevKit (the
    stable alias of quick-install.sh: install.sh links through it, so a moved checkout only needs the alias re-pointed;
    2026-10-09, tests/worktree_git/test_relink_alias.sh), else DEVKIT (the real path)."""
    link = os.path.join(project, ".agents", "devkit")
    try:
        target = os.readlink(link)
    except OSError:
        return DEVKIT
    target = target if os.path.isabs(target) else os.path.normpath(os.path.join(os.path.dirname(link), target))
    return target if os.path.realpath(target) == os.path.realpath(DEVKIT) else DEVKIT


def source_for(project, rel):
    """What a missing link should point at: the DevKit's item, else the project tier's."""
    if rel == ".agents/devkit":
        return DEVKIT
    kind, name = rel.split("/")[1], os.path.basename(rel)   # hooks | commands
    for cand in (os.path.join(DEVKIT, kind, name), os.path.join(project, ".agents", "local", kind, name)):
        if os.path.exists(cand):
            return os.path.join(link_root(project), kind, name) if cand.startswith(DEVKIT + os.sep) else cand
    return None


def dangling(project):
    """Relative paths of DevKit links whose target the DevKit no longer has: a symlink under .claude/commands/ or
    .agents/skills/ that resolves to nothing and whose target lies inside this DevKit (the alias .agents/devkit resolved)."""
    kit = os.path.realpath(DEVKIT) + os.sep
    out = []
    for rel_dir in (os.path.join(".claude", "commands"), os.path.join(".agents", "skills")):
        d = os.path.join(project, rel_dir)
        if in_kit(d):
            continue         # a link directory that resolves into the kit lists the kit's own files
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for name in names:
            p = os.path.join(d, name)
            if not os.path.islink(p) or os.path.exists(p):
                continue
            try:
                target = os.readlink(p)
            except OSError:
                continue
            target = target if os.path.isabs(target) else os.path.join(d, target)
            where = os.path.join(os.path.realpath(os.path.dirname(target)), os.path.basename(target))
            if where.startswith(kit):
                out.append(os.path.join(rel_dir, name))
    return out


def prune(project, stale):
    """Remove the dangling DevKit links found by dangling(); returns how many went."""
    done = 0
    for rel in stale:
        p = os.path.join(project, rel)
        try:
            if os.path.islink(p) and not os.path.exists(p):
                os.unlink(p)
                done += 1
        except OSError as e:
            sys.stderr.write(f"DevKit: cannot remove dangling link {rel}: {e}\n")
    return done


def relink(project, gone, raced=None):
    """Re-create the links in gone; returns those it could not. A link another session made first is appended to raced.
    Tạo link + ghi exclude dưới cùng một khoá; link hợp lệ do phiên kia tạo (trước lúc kiểm hay lúc os.symlink) vẫn được ghi exclude."""
    left = []
    with exclude_lock(project) as common:
        for rel in gone:
            src, dst = source_for(project, rel), os.path.join(project, rel)
            if not src:
                left.append(rel)
                continue
            if os.path.lexists(dst):
                if not _same_link(dst, src):
                    left.append(rel)      # file / link khác của người dùng: không đụng, không ghi exclude
                    continue
                if raced is not None:
                    raced.append(rel)     # phiên kia tạo giữa missing() và đây
                keep_out_of_git(project, rel, common)
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            target = src
            if src.startswith(os.path.join(project, ".agents", "local") + os.sep):
                target = os.path.relpath(src, os.path.dirname(dst))   # project tier: relative, like the installer
            try:
                os.symlink(target, dst)
            except FileExistsError:
                if raced is not None:
                    raced.append(rel)     # another session's SessionStart made it a moment ago
                if not _same_link(dst, src):
                    continue              # không phải link của kit: không ghi exclude
            keep_out_of_git(project, rel, common)
    return left


def main(argv):
    project = os.path.realpath(argv[1] if len(argv) > 1 and not argv[1].startswith("-") else os.getcwd())
    mode = should_run(project, argv)
    if not mode:
        return 0
    if mode == "worktree":   # chỉ thêm link lệnh / skill còn thiếu; không dọn, không context (worktree add / heal lo phần còn lại)
        relink(project, missing(project, worktree=True))
        return 0
    stale = dangling(project)
    pruned = prune(project, stale) if stale else 0
    if pruned:
        try:
            log = os.path.join(project, ".claude", "audit-gate", "relink.log")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as f:
                f.write(f"pruned {pruned} dangling DevKit link(s): {stale}\n")
        except OSError as e:
            sys.stderr.write(f"DevKit: relink.log not written: {e}\n")
    gone = missing(project)
    if not gone and "--links-only" in argv:
        return 0
    if not gone:
        # --context-only: rewriting the tracked AGENTS.md right after a checkout would leave the
        # tree dirty (and could block the next checkout); SessionStart refreshes it instead.
        _cs_script = os.path.join(DEVKIT, "scripts", "governance", "context_sync.py")
        if not os.path.isfile(_cs_script):
            _cs_script = os.path.join(DEVKIT, "scripts", "context_sync.py")
        subprocess.run([sys.executable, _cs_script, project, "--quiet",
                        "--context-only"], capture_output=True)
        return 0
    raced = []
    left = relink(project, gone, raced)
    restored = len(gone) - len(left) - len(raced)
    log = os.path.join(project, ".claude", "audit-gate", "relink.log")
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"restored {restored}/{len(gone)}; not restorable: {left}\n")
    except OSError:
        pass
    if "--quiet" not in argv:
        sys.stderr.write(f"DevKit: restored {restored} link(s) this git operation removed\n")
        if left:
            sys.stderr.write(f"DevKit: cannot restore {left} — run `agent-kit init`\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
