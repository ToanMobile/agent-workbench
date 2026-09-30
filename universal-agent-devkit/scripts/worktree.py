#!/usr/bin/env python3
"""worktree.py — one git worktree per parallel agent, set up like the main checkout.

Usage (normally `agent-kit worktree …`, run inside the repo):
  worktree.py add <path> [branch] [--base=REF] [--profile=ID] [--no-init]
  worktree.py diff <path>      the worktree's own changes as a binary patch
  worktree.py remove <path>    remove it once nothing of its work would be lost
  worktree.py list
  worktree.py heal [--devkit=DIR] [--session=ID]   a checkout the host made (Grok): link the DevKit, copy ignored config

add: `git worktree add` on <branch> (default feat/<folder name>; created from --base or
HEAD when it does not exist), copies the main checkout's git-ignored local config
(.env*, local.properties, keystore.properties, google-services.json, …) and git-ignored
build inputs (the red_proof.py set: libs/*.aar|jar, *.jks, … plus .agents/local/red_proof.json
{"copy": [...]} — scripts/build_inputs.py), runs the
DevKit installer with the main checkout's profile, agents and mode, then records what
that setup left in `git status` — file by file, with a content fingerprint — in the
worktree's own git dir. Hook state (.claude/audit-gate) and the gate report
(<git dir>/postfix-gate) are per worktree already.

diff: everything that differs from the recorded setup — commits since the base and
uncommitted edits — as one patch against the base, DevKit files left out. Bring it
back with: agent-kit worktree diff <path> | git apply --3way

remove: refused while an uncommitted change of the worktree is not in the main
checkout byte-for-byte; the branch and its commits are kept. Only the recorded setup and
ignored files (copied config, hook logs) go with the folder.
"""

import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEVKIT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from build_inputs import build_inputs  # noqa: E402
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402

STATE = "devkit-worktree.json"
LOCAL_CONFIG = (".env", ".env.*", "*.env", "local.properties", "keystore.properties", "secrets.properties",
                "google-services.json", "GoogleService-Info.plist", ".npmrc")
AGENT_MARKERS = (("claude", ".claude/settings.json"), ("codex", ".codex/hooks.json"),
                 ("gemini", ".gemini/settings.json"), ("cursor", ".cursor/hooks.json"))


def git(cwd, *args, check=True, env=None, inp=None):
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=inp is None or isinstance(inp, str),
                       input=inp, env=env)
    if check and r.returncode != 0:
        err = r.stderr if isinstance(r.stderr, str) else r.stderr.decode("utf-8", "replace")
        raise SystemExit(f"✖ worktree: git {' '.join(args[:2])}: {err.strip()}")
    return r


def die(msg, code=2):
    sys.stderr.write(f"✖ worktree: {msg}\n")
    raise SystemExit(code)


def main_checkout(cwd):
    out = git(cwd, "worktree", "list", "--porcelain").stdout
    for line in out.splitlines():
        if line.startswith("worktree "):
            return line[len("worktree "):]
    die(tr("không tìm thấy main checkout", "cannot find the main checkout"))


def git_dir(wt):
    return git(wt, "rev-parse", "--absolute-git-dir").stdout.strip()


def fingerprint(path):
    if os.path.islink(path):
        return "L:" + os.readlink(path)
    if os.path.isfile(path):
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 16), b""):
                h.update(chunk)
        return "F:" + h.hexdigest()
    return "D" if not os.path.exists(path) else "O"


def status_paths(wt):
    """Every path `git status` reports (untracked files one by one, renames both sides)."""
    raw = git(wt, "status", "--porcelain=v1", "-z", "-uall").stdout
    toks = raw.split("\0")
    paths, i = [], 0
    while i < len(toks):
        t = toks[i]
        i += 1
        if len(t) < 4:
            continue
        paths.append(t[3:])
        if t[0] in "RC":           # the next token is the rename's source
            paths.append(toks[i])
            i += 1
    return paths


def snapshot(wt):
    return {p: fingerprint(os.path.join(wt, p)) for p in status_paths(wt)}


def load_state(wt):
    if not os.path.isdir(wt):
        die(tr(f"không có thư mục: {wt}", f"no such directory: {wt}"))
    try:
        with open(os.path.join(git_dir(wt), STATE)) as f:
            return json.load(f)
    except (OSError, ValueError):
        die(tr(f"{wt} không được tạo bằng 'agent-kit worktree add' (thiếu {STATE})",
               f"{wt} was not made by 'agent-kit worktree add' (no {STATE})"))


def changes_since(wt, state):
    """Uncommitted paths whose content differs from the recorded setup."""
    base = state["baseline"]
    return sorted(p for p, fp in snapshot(wt).items() if base.get(p) != fp)


def _copy(main, wt, rel):
    src, dst = os.path.join(main, rel), os.path.join(wt, rel)
    if not os.path.isfile(src) or os.path.lexists(dst):
        return False
    # Only where the DESTINATION ignores it too: a separate clone (Grok) has its own
    # .git/info/exclude, so a secret the source ignores only there would land un-ignored,
    # one `git add` from a push (security review 2026-09-28).
    if git(wt, "check-ignore", "-q", "--no-index", "--", rel, check=False).returncode != 0:
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    return True


def copy_local_config(main, wt):
    out = git(main, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory").stdout
    copied = []
    for rel in out.split("\0"):
        if not rel or rel.endswith("/"):
            continue
        if any(fnmatch.fnmatch(os.path.basename(rel), pat) for pat in LOCAL_CONFIG) and _copy(main, wt, rel):
            copied.append(rel)
    return copied


def copy_build_inputs(main, wt):
    """The build inputs red_proof.py furnishes its sandbox with (scripts/build_inputs.py: its
    defaults + .agents/local/red_proof.json "copy"), copied from the main checkout. Only files
    git IGNORES there: an ignored file stays ignored in the worktree, so it can never be committed
    from it; a matching file git does not ignore is left alone (tracked ones are already there)."""
    cands = build_inputs(main)
    if not cands:
        return []
    r = git(main, "check-ignore", "-z", "--stdin", check=False, inp="\0".join(cands) + "\0")
    ignored = {p for p in r.stdout.split("\0") if p} if r.returncode in (0, 1) else set()
    return [rel for rel in cands if rel in ignored and _copy(main, wt, rel)]


def profile_file(root):
    """<root>/.agents/active-profile.json, or the pre-1.3 <root>/.active-profile.json; None if neither."""
    for p in (os.path.join(root, ".agents", "active-profile.json"), os.path.join(root, ".active-profile.json")):
        if os.path.exists(p):
            return p
    return None


def install_args(main, wt, profile):
    """The installer run that reproduces the main checkout's DevKit setup, or None."""
    if not profile_file(main):
        return None                                   # the main checkout has no DevKit
    if os.path.isfile(os.path.join(wt, ".agents", "devkit", "rules", "essentials.md")):
        return None                                   # copy mode, committed with the project already
    # (.agents/active-profile.json is committed in every mode: it says which profile, not
    #  that the DevKit is in place — a symlink install's links are never in git.)
    if not profile:
        try:
            with open(profile_file(main)) as f:
                profile = json.load(f).get("profile") or "auto"
        except (OSError, ValueError):
            profile = "auto"
    agents = [a for a, marker in AGENT_MARKERS if os.path.exists(os.path.join(main, marker))] or ["claude"]
    mode = "symlink" if (os.path.islink(os.path.join(main, ".agents", "devkit"))
                         or os.path.islink(os.path.join(main, "AGENTS.md"))) else "copy"   # 1.2: AGENTS.md was the link
    return ["bash", os.path.join(DEVKIT, "bin", "install.sh"), f"--target={wt}", "--domain=auto",
            f"--mode={mode}", "-y", "--no-githooks", "-p", profile, "-a", ",".join(agents)]


def cmd_add(cwd, args):
    base, profile, no_init, pos = None, None, False, []
    for a in args:
        if a.startswith("--base="):
            base = a.split("=", 1)[1]
        elif a.startswith("--profile="):
            profile = a.split("=", 1)[1]
        elif a == "--no-init":
            no_init = True
        elif a.startswith("-"):
            die(tr(f"tuỳ chọn không hợp lệ '{a}'", f"unknown option '{a}'") + " (--base=REF, --profile=ID, --no-init)")
        else:
            pos.append(a)
    if not 1 <= len(pos) <= 2:
        die("usage: agent-kit worktree add <path> [branch] [--base=REF] [--profile=ID] [--no-init]")
    wt = os.path.abspath(os.path.join(cwd, pos[0]))
    name = os.path.basename(wt.rstrip("/"))
    branch = pos[1] if len(pos) == 2 else f"feat/{name}"
    main = main_checkout(cwd)
    if os.path.exists(wt) and os.listdir(wt):
        die(tr(f"{wt} đã có và không rỗng", f"{wt} exists and is not empty"))
    if git(main, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}", check=False).returncode == 0:
        git(main, "worktree", "add", wt, branch)
    else:
        git(main, "worktree", "add", "-b", branch, wt, *([base] if base else []))
    start = git(wt, "rev-parse", "HEAD").stdout.strip()

    copied = copy_local_config(main, wt)
    inputs = copy_build_inputs(main, wt)
    ran = install_args(main, wt, profile) if not no_init else None
    if ran:
        r = subprocess.run(ran, capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout[-2000:] + r.stderr[-2000:])
            die(tr(f"cài DevKit vào worktree thất bại (exit {r.returncode}); worktree vẫn ở {wt}",
                   f"DevKit install in the worktree failed (exit {r.returncode}); the worktree stays at {wt}"), 1)
    state = {"branch": branch, "base": start, "main": main, "baseline": snapshot(wt)}
    with open(os.path.join(git_dir(wt), STATE), "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)

    print(f"✔ worktree {wt}  ({tr('nhánh', 'branch')} {branch} @ {start[:10]})")
    if copied:
        print("  " + tr("đã chép cấu hình cục bộ (bị ignore): ", "copied local config (git-ignored): ") + ", ".join(copied))
    if inputs:
        shown = ", ".join(inputs[:12]) + (f" (+{len(inputs) - 12})" if len(inputs) > 12 else "")
        print("  " + tr("đã chép input build (bị ignore, như red_proof): ",
                        "copied build inputs (git-ignored, as red_proof): ") + shown)
    print("  " + (tr("đã cài DevKit như main checkout", "DevKit installed like the main checkout") if ran else
                  tr("không cài DevKit (main checkout không có, hoặc worktree đã có sẵn)",
                     "DevKit not installed (none in the main checkout, or the worktree has it already)")))
    print("  " + tr("Tiếp theo", "Next") + f": cd {wt}")
    print("  " + tr("Nghiệm thu", "Accept") + ': CLAUDE_PROJECT_DIR="$PWD" postfix-gate --run-tests')
    print("  " + tr("Đem về", "Bring back") + f": agent-kit worktree diff {pos[0]} | git apply --3way")
    return 0


def _uncommitted(path):
    """Number of uncommitted paths of a worktree (setup files of a `worktree add` worktree excluded), or
    None when git cannot say. Fail closed: an unreadable status must never read as clean."""
    if not os.path.isdir(path):
        return 0   # directory gone (prunable): nothing uncommitted is left to lose
    r = git(path, "status", "--porcelain", "-uall", check=False)
    if r.returncode != 0:
        return None
    try:
        with open(os.path.join(git_dir(path), STATE)) as f:
            return len(changes_since(path, json.load(f)))
    except (OSError, ValueError, KeyError, SystemExit):
        return len([l for l in r.stdout.splitlines() if l.strip()])


def _count(cwd, *revs, stdin=None):
    """`git rev-list --count`, or None when git fails (a broken ref must not read as zero commits)."""
    args = ["rev-list", "--count"] + (["--stdin"] if stdin is not None else list(revs))
    r = git(cwd, *args, inp=stdin, check=False)
    out = r.stdout.strip()
    return int(out) if r.returncode == 0 and out.isdigit() else None


def _patch_already_in_main(cwd, main_head, head):
    """True when every file the worktree's commits touch already has the same content in the main checkout's HEAD."""
    base = git(cwd, "merge-base", main_head, head, check=False).stdout.strip()
    if not base:
        return False
    files = git(cwd, "diff", "--name-only", "--no-renames", "-z", base, head, check=False).stdout.split("\0")
    files = [f for f in files if f]
    if not files or len(files) > 500:
        return False
    return git(cwd, "diff", "--quiet", main_head, head, "--", *files, check=False,
               env=dict(os.environ, GIT_LITERAL_PATHSPECS="1")).returncode == 0


def inventory(cwd, only=None):
    """Every linked worktree (or just `only`):
    [{path, branch, detached, dirty, ahead, unreachable, unintegrated}]. `ahead` = commits of its HEAD that are not
    in the main checkout's HEAD (and whose files are not already there with the same content): the work not
    integrated. `unreachable` = a detached HEAD whose commits no branch, tag or remote ref holds: a removal loses
    them. `dirty`/`ahead` are None when git could not say; that counts as unintegrated (fail closed)."""
    entries, cur = [], None
    for line in git(cwd, "worktree", "list", "--porcelain").stdout.splitlines() + [""]:
        if line.startswith("worktree "):
            cur = {"path": line[len("worktree "):], "branch": None, "head": None, "detached": False}
        elif cur is not None and line.startswith("HEAD "):
            cur["head"] = line[len("HEAD "):]
        elif cur is not None and line.startswith("branch refs/heads/"):
            cur["branch"] = line[len("branch refs/heads/"):]
        elif cur is not None and line == "detached":
            cur["detached"] = True
        elif cur is not None and line == "":
            entries.append(cur)
            cur = None
    main_head = entries[0]["head"] if entries else None
    refs = git(cwd, "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags",
               check=False).stdout.split()
    skip = os.path.realpath(only) if only else None
    rows = []
    for e in entries[1:]:
        path, head = e["path"], e["head"]
        if skip and os.path.realpath(path) != skip:
            continue
        dirty = _uncommitted(path)
        ahead = _count(cwd, f"{main_head}..{head}") if head and main_head else None   # None: git could not say
        if ahead and _patch_already_in_main(cwd, main_head, head):
            ahead = 0   # brought back the documented way (diff | apply, committed in main)
        held_only = None   # commits no other ref holds (what a removal would lose); None: git could not say
        if head and e["detached"]:   # a branch keeps its own commits reachable; only a detached HEAD can lose them
            rev_in = [head] + ["^" + r for r in refs] + (["^" + main_head] if main_head else [])
            held_only = _count(cwd, stdin="\n".join(rev_in) + "\n")
        rows.append({"path": path, "branch": e["branch"], "detached": e["detached"], "dirty": dirty, "ahead": ahead,
                     "unreachable": bool(e["detached"] and ahead != 0 and (held_only is None or held_only > 0)),
                     "unintegrated": bool(dirty is None or dirty or ahead is None or ahead)})
    return rows


def describe(r):
    tag = ("UNINTEGRATED" if r["unintegrated"] else "clean").ljust(12)
    where = r["branch"] or "(detached)"
    note = "  UNREACHABLE: its commits are on no branch, removing the worktree loses them" if r["unreachable"] else ""
    return f"{tag} {r['path']}  [{where}]  dirty={'?' if r['dirty'] is None else r['dirty']} ahead={'?' if r['ahead'] is None else r['ahead']}{note}"


def warn_others(cwd, exclude=None):
    """After bringing ONE worktree back: name every other worktree that still holds work."""
    skip = os.path.realpath(exclude) if exclude else None
    try:
        others = [r for r in inventory(cwd) if r["unintegrated"] and os.path.realpath(r["path"]) != skip]
    except (Exception, SystemExit) as e:   # a warning must never break the operation it accompanies
        print("⚠ " + tr(f"không kiểm kê được các worktree khác: {e}", f"could not inventory the other worktrees: {e}"), file=sys.stderr)
        return
    if others:
        print("⚠ " + tr(f"{len(others)} worktree khác còn việc CHƯA gộp — đừng xoá/bỏ khi chưa đem về:",
                        f"{len(others)} other worktree(s) still hold work that is NOT integrated — do not drop them before bringing it back:"),
              file=sys.stderr)
        for r in others:
            print("   " + describe(r), file=sys.stderr)


def cmd_status(cwd, args):
    rows = inventory(cwd)
    if not rows:
        print(tr("không có worktree nào khác main checkout", "no worktree besides the main checkout"))
        return 0
    for r in rows:
        print(describe(r))
    pending = [r for r in rows if r["unintegrated"]]
    print(tr(f"{len(pending)}/{len(rows)} worktree còn việc chưa gộp vào main checkout",
             f"{len(pending)}/{len(rows)} worktree(s) hold work not in the main checkout"))
    return 1 if pending and "--strict" in args else 0


def cmd_diff(cwd, args):
    if len(args) != 1:
        die("usage: agent-kit worktree diff <path>")
    wt = os.path.abspath(os.path.join(cwd, args[0]))
    state = load_state(wt)
    changed = changes_since(wt, state)
    fd, index = tempfile.mkstemp(prefix="devkit-wt-index.")
    os.close(fd)
    try:
        env = dict(os.environ, GIT_INDEX_FILE=index, GIT_LITERAL_PATHSPECS="1")
        git(wt, "read-tree", "HEAD", env=env)
        if changed:
            git(wt, "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", env=env,
                inp="\0".join(changed) + "\0")
        out = subprocess.run(["git", "-C", wt, "diff", "--cached", "--binary", state["base"]],
                             capture_output=True, env=env)
        if out.returncode != 0:
            die(out.stderr.decode("utf-8", "replace").strip(), 1)
        sys.stdout.buffer.write(out.stdout)
    finally:
        os.unlink(index)
    warn_others(cwd, exclude=wt)
    return 0


def cmd_remove(cwd, args):
    if len(args) != 1:
        die("usage: agent-kit worktree remove <path>")
    wt = os.path.abspath(os.path.join(cwd, args[0]))
    for r in inventory(cwd, only=wt):
        if r["unreachable"]:
            die(tr(f"{wt}: UNREACHABLE — HEAD tách rời, {r['ahead']} commit không thuộc nhánh nào; gỡ worktree là mất chúng. "
                   "Tạo nhánh giữ chúng trước: git -C <worktree> switch -c <tên>",
                   f"{wt}: UNREACHABLE — detached HEAD, {r['ahead']} commit(s) on no branch; removing the worktree loses them. "
                   "Keep them on a branch first: git -C <worktree> switch -c <name>"), 1)
    state = load_state(wt)
    main = main_checkout(cwd)
    if os.path.realpath(wt) == os.path.realpath(main):
        die(tr("đây là main checkout", "that is the main checkout"))
    changed = changes_since(wt, state)
    # Commits stay on the branch. Uncommitted work is safe once the main checkout
    # holds the same bytes at the same path (a deleted file: missing in both).
    lost = [p for p in changed if fingerprint(os.path.join(wt, p)) != fingerprint(os.path.join(main, p))]
    if lost:
        print(tr(f"✖ worktree: {len(lost)} thay đổi chưa có trong main checkout — giữ nguyên {wt}:",
                 f"✖ worktree: {len(lost)} change(s) not in the main checkout — {wt} kept:"), file=sys.stderr)
        for p in lost[:20]:
            print(f"    {p}", file=sys.stderr)
        print("  " + tr("Đem về trước", "Bring them back first") + f": agent-kit worktree diff {args[0]} | git apply --3way",
              file=sys.stderr)
        return 1
    # Verified above: nothing but the recorded setup and ignored files is left, so
    # --force here drops no work (plain `remove` refuses any untracked file).
    git(main, "worktree", "remove", "--force", wt)
    print(f"✔ {tr('đã gỡ', 'removed')} {wt}; {tr('nhánh', 'branch')} {state['branch']} "
          + tr("giữ lại (xoá khi đã merge: git branch -d ", "kept (delete once merged: git branch -d ") + state["branch"] + ")")
    return 0


def _grok_source(session, wt):
    """Grok's worktree is a separate clone: its session summary names the checkout it came from."""
    import glob
    if not session or not re.fullmatch(r"[\w.-]+", session):
        return None
    for f in glob.glob(os.path.join(os.path.expanduser("~"), ".grok", "sessions", "*", session, "summary.json")):
        try:
            with open(f, encoding="utf-8") as fh:
                src = json.load(fh).get("source_workspace_dir")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(src, str) and os.path.isdir(src) and os.path.realpath(src) != os.path.realpath(wt):
            top = git(src, "rev-parse", "--show-toplevel", check=False).stdout.strip()
            if top:
                return top
    return None


def cmd_heal(cwd, args):
    """A checkout the HOST made — Grok's worktree session, a separate clone (OfficeReader
    2026-09-28), or a plain `git worktree` — never went through `add`: no .agents/devkit link
    (git-ignored) and no ignored local config. Run at session start: link .agents/devkit to the
    running DevKit (--devkit) or the source checkout's, and copy the source checkout's ignored
    local config and build inputs when the source is known (git worktree list, or --session: the
    Grok session summary). Only what git ignores is created, so nothing of it can be committed.
    Never an error: a session must start whatever happens here."""
    devkit, session = None, None
    for a in args:
        if a.startswith("--devkit="):
            devkit = a.split("=", 1)[1]
        elif a.startswith("--session="):
            session = a.split("=", 1)[1]
    wt = git(cwd, "rev-parse", "--show-toplevel", check=False).stdout.strip()
    if not wt:
        return 0
    src = None
    try:
        main = main_checkout(cwd)
        if os.path.realpath(main) != os.path.realpath(wt):
            src = main
    except SystemExit:
        pass
    src = src or _grok_source(session, wt)
    done = []
    link = os.path.join(wt, ".agents", "devkit")
    target = os.path.join(src, ".agents", "devkit") if src else None
    target = target if target and os.path.isdir(target) else devkit
    if target and os.path.isfile(os.path.join(target, "bin", "post-fix-gate.py")) and not os.path.lexists(link) \
            and git(wt, "check-ignore", "-q", "--no-index", ".agents/devkit", check=False).returncode == 0:
        os.makedirs(os.path.dirname(link), exist_ok=True)
        os.symlink(os.path.realpath(target), link)
        done.append(".agents/devkit")
    if src:
        done += copy_local_config(src, wt) + copy_build_inputs(src, wt)
    if done:
        print(tr("checkout do host tạo: đã chuẩn bị như `agent-kit worktree add` — ",
                 "host-made checkout: set up like `agent-kit worktree add` — ") + ", ".join(done))
    return 0


def main(argv):
    cwd = os.getcwd()
    set_lang(resolve_lang(None, cwd))
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    if git(cwd, "rev-parse", "--git-dir", check=False).returncode != 0:
        die(tr("không ở trong git repository", "not inside a git repository"))
    action, rest = argv[1], argv[2:]
    if action == "add":
        return cmd_add(cwd, rest)
    if action == "diff":
        return cmd_diff(cwd, rest)
    if action in ("remove", "rm"):
        return cmd_remove(cwd, rest)
    if action == "status":
        return cmd_status(cwd, rest)
    if action == "heal":
        return cmd_heal(cwd, rest)
    if action == "list":
        return subprocess.run(["git", "-C", cwd, "worktree", "list"]).returncode
    die(tr(f"lệnh không hợp lệ '{action}'", f"unknown action '{action}'") + " (add | diff | remove | status | list)")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
