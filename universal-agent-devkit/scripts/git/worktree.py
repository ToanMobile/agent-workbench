#!/usr/bin/env python3
"""worktree.py — one git worktree per parallel agent, set up like the main checkout.

Usage (normally `agent-kit worktree …`, run inside the repo):
  worktree.py add <path> [branch] [--base=REF] [--profile=ID] [--no-init]
  worktree.py diff <path> [--with-checklist]   the worktree's own changes as a binary patch
  worktree.py remove <path>    remove it once nothing of its work would be lost
  worktree.py list
  worktree.py heal [--devkit=DIR] [--session=ID]   a checkout the host made (Grok): link the DevKit, copy ignored config

add: `git worktree add` on <branch> when one is named (created from --base or HEAD when it
does not exist); with none, a DETACHED worktree at --base or HEAD — the project keeps one
branch, and the work comes back with `diff | git apply --3way`. Copies the main checkout's git-ignored local config
(.env*, local.properties, keystore.properties, google-services.json, …) and git-ignored
build inputs (the red_proof.py set: libs/*.aar|jar, *.jks, … plus .agents/local/red_proof.json
{"copy": [...]} — scripts/build_inputs.py), runs the
DevKit installer with the main checkout's profile, agents and mode, then records what
that setup left in `git status` — file by file, with a content fingerprint — in the
worktree's own git dir. Hook state (.claude/audit-gate) and the gate report
(<git dir>/postfix-gate) are per worktree already. Claude Code's auto-memory
(.claude/settings.local.json autoMemoryDirectory, which the installer points at the
worktree's own empty folder) is pointed at the main checkout's, so a note saved in a
worktree is not lost with it.

diff: everything that differs from the recorded setup — commits since the base and
uncommitted edits — as one patch against the base, DevKit files left out. The checklist
bookkeeping the gate and the hooks rewrite (BOOKKEEPING below: .agents/CHECKLIST.md,
regression_status.json, …) is left out too, and named on stderr: two worktrees that
each rewrote it conflict when brought back; --with-checklist keeps it. Bring it
back with: agent-kit worktree diff <path> | git apply --3way

remove: refused while an uncommitted change of the worktree is not in the main
checkout byte-for-byte (the executable bit too; edits git hides with skip-worktree /
assume-unchanged count), while a commit is named only by the worktree's own reflog (also
on a branch worktree: detach, commit, go back), while a submodule has uncommitted changes
or commits the main checkout's own copy of it does not hold, and for a path git does not
list as a linked worktree (any spelling of one that exists is matched). A named branch
and its commits are kept (a detached worktree's commits must be brought back first).
Only the recorded setup and ignored files (copied config, hook logs) go with the folder.
"""

import errno
import fnmatch
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEVKIT = os.path.dirname(HERE)
if not os.path.isdir(os.path.join(DEVKIT, "profiles")) and os.path.isdir(os.path.join(os.path.dirname(DEVKIT), "profiles")):
    DEVKIT = os.path.dirname(DEVKIT)
sys.path.insert(0, HERE)
for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
    _sub_path = os.path.join(DEVKIT, "scripts", _sub)
    if _sub_path not in sys.path:
        sys.path.insert(0, _sub_path)
from build_inputs import build_inputs  # noqa: E402
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402

STATE = "devkit-worktree.json"
LOCAL_CONFIG = (".env", ".env.*", "*.env", "local.properties", "keystore.properties", "secrets.properties",
                "google-services.json", "GoogleService-Info.plist", ".npmrc")
AGENT_MARKERS = (("claude", ".claude/settings.json"), ("codex", ".codex/hooks.json"),
                 ("gemini", ".gemini/settings.json"), ("cursor", ".cursor/hooks.json"))
# Bookkeeping that the gate (post-fix-gate.py), the prompt and session hooks and render() regenerate: not the agent's work.
# regression_checklist.py STATUS_FILE / VIEW_FILE / OLD_VIEW_FILE / ARCHIVE_FILE + the derived .agents/instincts-index.md
# (tests/worktree_git/test_worktree_checklist.sh keeps them in step). INBOX.md is not here: people write it.
BOOKKEEPING = (".agents/regression_status.json", ".agents/CHECKLIST.md", ".agents/regression_checklist.md",
               ".agents/archive/BUG_ARCHIVE.md", ".agents/instincts-index.md")
MEMORY_REL = os.path.join(".agents", "local", "memory", "claude-auto")   # scripts/governance/claude_memory.py REL


GIT_TIMEOUT_S = 30.0   # one git call that takes longer reads as "cannot say" (rc 124), never as clean: a state file an agent replaced by a FIFO must not hang a hook or a person


INVENTORY_BUDGET_S = 300.0   # outside a hook: all the git calls of ONE inventory() together may take this long
_BUDGET = []                 # [absolute monotonic end, ...] while an inventory() runs: ONE deadline shared by every git call in it


def _alarm_left():
    try:
        return signal.getitimer(signal.ITIMER_REAL)[0]
    except (AttributeError, ValueError, OSError):
        return 0


def _env_seconds(name, default):
    try:
        t = float(os.environ.get(name, default))
    except ValueError:
        return default
    return t if 0 < t < 1e9 else default   # nan, inf, zero, negative


def _spent():
    """True once the shared deadline of the running inventory() has passed: nothing may be judged clean after that."""
    return bool(_BUDGET) and _BUDGET[-1] <= time.monotonic()


class _Budget:
    """`with _Budget(seconds):` one shared deadline for everything inside (never later than an enclosing one)."""

    def __init__(self, seconds):
        self.end = time.monotonic() + seconds

    def __enter__(self):
        if _BUDGET:
            self.end = min(self.end, _BUDGET[-1])
        _BUDGET.append(self.end)
        return self

    def __exit__(self, *exc):
        _BUDGET.pop()
        return False


def _inventory_budget():
    """Seconds ONE inventory() may take. Inside a hook's SIGALRM (the merge gate: 8 s, session start: 4 s) it ends 1.5 s BEFORE the alarm:
    the alarm's exit is a fail-open pass, so the verdict (the rows not finished are "cannot say" = held) must be ours."""
    t = _env_seconds("DEVKIT_WORKTREE_BUDGET_S", INVENTORY_BUDGET_S)
    left = _alarm_left()
    return min(t, max(left - 1.5, 0.5)) if left > 0 else t


def _timeout():
    """Seconds one git call may take: DEVKIT_WORKTREE_GIT_TIMEOUT_S (30), never more than what is left of the shared deadline or (inside a
    hook) of the alarm, so a hung call cannot take the whole budget twice."""
    t = _env_seconds("DEVKIT_WORKTREE_GIT_TIMEOUT_S", GIT_TIMEOUT_S)
    left = _alarm_left()
    if left > 0:
        t = min(t, max(left - 1.0, 0.5))
    if _BUDGET:
        t = min(t, max(_BUDGET[-1] - time.monotonic(), 0.05))
    return t


def _run(argv, inp=None, text=True, env=None, bounded=True):
    """subprocess.run with a bounded time. On timeout the child is killed and a CompletedProcess with returncode 124 comes back; so it does
    when the shared deadline of the running inventory() is spent (nothing is started then). `bounded=False` for a call that CHANGES the repo or the
    disk (worktree add / remove --force, the temp-index work of `diff`): killed midway it leaves a half checkout or a half-deleted folder."""
    if not bounded:
        return subprocess.run(argv, capture_output=True, text=text, input=inp, env=env)
    if _spent():
        return subprocess.CompletedProcess(argv, 124, "" if text else b"", "inventory deadline spent")
    try:
        return subprocess.run(argv, capture_output=True, text=text, input=inp, env=env, timeout=_timeout())
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "" if text else b"", "timed out")


def git(cwd, *args, check=True, env=None, inp=None, bounded=True):
    r = _run(["git", "-C", cwd, *args], inp=inp, text=inp is None or isinstance(inp, str), env=env, bounded=bounded)
    if check and r.returncode != 0:
        err = r.stderr if isinstance(r.stderr, str) else r.stderr.decode("utf-8", "replace")
        raise SystemExit(f"✖ worktree: git {' '.join(args[:2])}: {err.strip()}")
    return r


def _read_regular(path, limit=32_000_000):
    """The bytes of a REGULAR file, opened without blocking: a FIFO or a device planted at a path under the git dir (the agent can write
    there) must not hang the reader. OSError for anything else, for a file over `limit`, and for a path that is not there."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
            raise OSError(errno.EINVAL, "not a regular file or too large", path)
        chunks = []
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                return b"".join(chunks)
            chunks.append(chunk)
    finally:
        os.close(fd)


def _read_state(wt):
    """The worktree's devkit-worktree.json as a dict; OSError / ValueError (bad UTF-8, bad JSON, too deep, not an object) / SystemExit."""
    try:
        data = json.loads(_read_regular(os.path.join(git_dir(wt), STATE), 4_000_000).decode("utf-8"))
    except RecursionError as e:
        raise ValueError("state nested too deep") from e
    if not isinstance(data, dict):
        raise ValueError("state is not an object")
    return data


def die(msg, code=2):
    sys.stderr.write(f"✖ worktree: {msg}\n")
    raise SystemExit(code)


_Z_LISTING = []   # [False] once this git proved to have no `worktree list -z` (usage error): the line form is used from then on


def _worktree_entries(cwd):
    """`git worktree list --porcelain` as [{path, head, branch, detached, broken}], the main checkout first. NUL-separated (-z, git 2.36+):
    a path with a newline stays ONE path. An older git has no -z and its line form splits such a path: the line that is none of the
    keys git prints marks that entry `broken` (its path is a piece of the real one: it cannot be tied to a directory, so the callers
    read it as "cannot say" = held, and it never matches a path asked for). Never raises on that: a hook must still judge the others."""
    r = None
    if _Z_LISTING != [False]:
        r = git(cwd, "worktree", "list", "--porcelain", "-z", check=False)
        if r.returncode == 129:   # git's usage error: an unknown option
            _Z_LISTING[:] = [False]
    z = r is not None and r.returncode == 0
    if not z:
        r = git(cwd, "worktree", "list", "--porcelain")   # SystemExit when git fails
    entries, cur = [], None
    for t in r.stdout.split("\0" if z else "\n"):
        if t.startswith("worktree "):
            cur = {"path": t[len("worktree "):], "branch": None, "head": None, "detached": False, "broken": False}
        elif t == "":
            if cur is not None:
                entries.append(cur)
            cur = None
        elif cur is None:
            continue
        elif t.startswith("HEAD "):
            cur["head"] = t[len("HEAD "):]
        elif t.startswith("branch refs/heads/"):
            cur["branch"] = t[len("branch refs/heads/"):]
        elif t == "detached":
            cur["detached"] = True
        elif not z and t.split(" ", 1)[0] not in ("branch", "bare", "locked", "prunable"):
            cur["broken"] = True
    if cur is not None:
        entries.append(cur)
    return entries


def main_checkout(cwd):
    entries = _worktree_entries(cwd)
    if entries and not entries[0]["broken"]:
        return entries[0]["path"]
    die(tr("không tìm thấy main checkout", "cannot find the main checkout"))


def git_dir(wt):
    return git(wt, "rev-parse", "--absolute-git-dir").stdout.strip()


FP_VERSION = 2   # state["fp"]: 2 = the fingerprints in the baseline carry the executable bit (a state without it is older)


def fingerprint(path):
    """What a path holds, for comparing two checkouts: a link's target, a file's bytes and its executable bit (the one mode git
    tracks: a `chmod +x` is a change), "D" when it does not exist, "O" for anything else (a directory, a nested repo, a fifo):
    its content is NOT compared, so two "O" never vouch for each other (see _same_in_main)."""
    if os.path.islink(path):
        return "L:" + os.readlink(path)
    if os.path.isfile(path):
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 16), b""):
                h.update(chunk)
        return "F:" + h.hexdigest() + (":x" if os.stat(path).st_mode & 0o111 else "")
    return "D" if not os.path.exists(path) else "O"


def _same_gitlink(wt, main, rel):
    """True when `rel` is a submodule whose checked-out commit in the worktree is the one the main checkout's HEAD records for it.
    What is inside it (uncommitted edits, commits no remote holds) is the submodule checks' business, not this one's."""
    if not os.path.exists(os.path.join(wt, rel, ".git")):
        return False   # not a repository of its own: nothing to read a commit from (rev-parse would climb to the worktree's)
    rec = git(main, "ls-tree", "-z", "HEAD", "--", rel, check=False, env=dict(os.environ, GIT_LITERAL_PATHSPECS="1")).stdout.strip("\0")
    there = git(os.path.join(wt, rel), "rev-parse", "HEAD", check=False)
    fields = rec.split("\t", 1)[0].split()
    return "\0" not in rec and len(fields) == 3 and fields[:2] == ["160000", "commit"] and there.returncode == 0 and there.stdout.strip() == fields[2]


def _same_in_main(wt, main, rel):
    """True when the main checkout holds exactly what the worktree holds at `rel` (bytes and executable bit; both missing counts).
    A directory ("O": an untracked nested repo, a submodule) is not compared, so it cannot be proven the same, except a submodule at
    the very commit main's HEAD records (_same_gitlink)."""
    fp = fingerprint(os.path.join(wt, rel))
    if fp == "O":
        return _same_gitlink(wt, main, rel)
    return fp == fingerprint(os.path.join(main, rel))


def status_paths(wt):
    """Every path `git status` reports (untracked files one by one, renames both sides)."""
    if _reflog_file_entries(wt) is None:   # a detached `git status` reads the HEAD reflog: a FIFO planted there would block it
        raise SystemExit(f"✖ worktree: the HEAD reflog of {wt} is not a regular readable file: git status would block")
    raw = git(wt, "--no-optional-locks", "status", "--porcelain=v1", "-z", "-uall", "--ignore-submodules=none").stdout   # (a path that is not UTF-8 raises: the callers refuse, see cmd_remove)
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
        return _read_state(wt)
    except (OSError, ValueError, SystemExit):
        die(tr(f"{wt} không được tạo bằng 'agent-kit worktree add' (thiếu {STATE})",
               f"{wt} was not made by 'agent-kit worktree add' (no {STATE})"))


def changes_since(wt, state):
    """Uncommitted paths whose content differs from the recorded setup. A state written before the executable bit was part of
    the fingerprint (no "fp" marker) holds "F:<sha>" for every file: for those, the bit is not compared."""
    base, exact = state["baseline"], state.get("fp") == FP_VERSION
    return sorted(p for p, fp in snapshot(wt).items()
                  if base.get(p) != fp and (exact or not (fp.startswith("F:") and fp.endswith(":x")) or base.get(p) != fp[:-2]))


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


def share_main_memory(main, wt):
    """Point the worktree's Claude auto-memory at the main checkout's: .claude/settings.local.json
    autoMemoryDirectory, which the installer (claude_memory.py) set to the worktree's own empty folder. A note an
    agent saves in a worktree then outlives it (worktree_guard.sh lets a worktree session write M's claude-auto/).
    Only that default is replaced, and only by the main checkout's OWN <main>/.agents/local/memory/claude-auto folder
    when it exists (a value that points anywhere else, or climbs out of it with .., is not followed). Left alone: a value
    of the user's, an unreadable or non-object file, and a missing file whose name git does not ignore (one `git add`
    from a commit, with an absolute path of this machine in it). Every worktree then shares ONE MEMORY.md: two agents
    saving a note at the same moment can overwrite each other. True when the file was changed."""
    rel = os.path.join(".claude", "settings.local.json")
    try:
        with open(os.path.join(main, rel), encoding="utf-8") as f:
            target = json.load(f).get("autoMemoryDirectory")
    except (OSError, ValueError, AttributeError):
        return False
    want = os.path.join(os.path.realpath(main), MEMORY_REL)
    if not isinstance(target, str) or os.path.realpath(target) != want or not os.path.isdir(want):
        return False   # only the main checkout's own claude-auto/ folder, and only when it exists (no traversal, nobody else's folder)
    path = os.path.join(wt, rel)
    try:
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            cur = data.get("autoMemoryDirectory") if isinstance(data, dict) else False
            if cur is False or (cur is not None and (not isinstance(cur, str) or os.path.realpath(cur)
                                                      != os.path.realpath(os.path.join(os.path.realpath(wt), MEMORY_REL)))):
                return False
        elif git(wt, "check-ignore", "-q", "--no-index", "--", rel, check=False).returncode == 0:
            data = {}
        else:
            return False
        if data.get("autoMemoryDirectory") == target:
            return False
        data["autoMemoryDirectory"] = target
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".devkit-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp, path)
    except (OSError, ValueError):
        return False
    return True


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
    branch = pos[1] if len(pos) == 2 else None   # none named: DETACHED (one developer, one branch; the folder name is no branch name)
    main = main_checkout(cwd)
    if os.path.exists(wt) and os.listdir(wt):
        die(tr(f"{wt} đã có và không rỗng", f"{wt} exists and is not empty"))
    if branch is None:
        git(main, "worktree", "add", "--detach", wt, *([base] if base else []), bounded=False)
    elif git(main, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}", check=False).returncode == 0:
        git(main, "worktree", "add", wt, branch, bounded=False)
    else:
        git(main, "worktree", "add", "-b", branch, wt, *([base] if base else []), bounded=False)
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
    shared = share_main_memory(main, wt) if not no_init else False   # before the snapshot: it is part of the setup
    state = {"branch": branch, "base": start, "main": main, "baseline": snapshot(wt), "fp": FP_VERSION}
    with open(os.path.join(git_dir(wt), STATE), "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)

    print(f"✔ worktree {wt}  ({tr('nhánh', 'branch') + ' ' + branch if branch else tr('tách rời (detached)', 'detached')} @ {start[:10]})")
    if shared:
        print("  " + tr("auto-memory của Claude dùng chung với main checkout (autoMemoryDirectory)",
                        "Claude auto-memory shared with the main checkout (autoMemoryDirectory)"))
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


HIDDEN_CHECK_MAX = 2000   # flagged files present on disk that are verified one by one; more than this, they all count


def _git_bytes(wt, *args, inp=None):
    """git's output as BYTES: a tracked path need not be UTF-8, and a strict decode of the whole listing would raise for one odd name."""
    return _run(["git", "-C", wt, *args], inp=inp, text=False)


def _hidden_edits(wt):
    """Paths the index marks skip-worktree or assume-unchanged whose file differs from the index (or is gone, for assume-unchanged):
    `git status` does not report an edit of those. [path, ...], or None when git cannot say (fail closed). A flagged file that is
    absent (a sparse checkout) or equal to the index is no change; one that is not a plain file, or too many to check, counts.
    Paths are decoded with surrogateescape (the listing covers EVERY tracked path, and one that is not UTF-8 must not raise)."""
    def text(b):
        return b.decode("utf-8", "surrogateescape")
    r = _git_bytes(wt, "ls-files", "-v", "-z")
    if r.returncode != 0:
        return None
    flagged = {e[2:]: e[0] for e in text(r.stdout).split("\0") if len(e) > 2 and (e[0] == "S" or e[0].islower())}
    if not flagged:
        return []
    edited = [p for p, tag in flagged.items() if tag == "h" and not os.path.lexists(os.path.join(wt, p))]   # assume-unchanged, deleted
    present = [p for p in flagged if os.path.lexists(os.path.join(wt, p))]
    if not present:
        return edited
    if len(present) > HIDDEN_CHECK_MAX:
        return edited + present
    staged = _git_bytes(wt, "ls-files", "-s", "-z")
    if staged.returncode != 0:
        return None
    want = set(present)
    index = {}   # path -> blob id of the index entry (stage 0)
    for rec in text(staged.stdout).split("\0"):
        meta, _, path = rec.partition("\t")
        parts = meta.split()
        if path in want and len(parts) == 3 and parts[2] == "0" and parts[0] in ("100644", "100755"):
            index[path] = parts[1]
    # not a regular file in the index (symlink, submodule), or a name `hash-object --stdin-paths` cannot take: cannot compare
    plain = [p for p in present if p in index and "\n" not in p and not p.startswith('"') and os.path.isfile(os.path.join(wt, p))
             and not os.path.islink(os.path.join(wt, p))]
    plain_set = set(plain)
    edited += [p for p in present if p not in plain_set]
    if plain:
        h = _git_bytes(wt, "hash-object", "--stdin-paths", inp=("\n".join(plain) + "\n").encode("utf-8", "surrogateescape"))
        ids = text(h.stdout).split()
        if h.returncode != 0 or len(ids) != len(plain):
            return None
        edited += [p for p, blob in zip(plain, ids) if index[p] != blob]
    return edited


def _uncommitted(path, reflog_lines=False):
    """Number of uncommitted paths of a worktree (setup files of a `worktree add` worktree excluded; files git hides with
    skip-worktree / assume-unchanged included when they were edited), or None when git cannot say. Fail closed: an unreadable
    status must never read as clean."""
    if not os.path.isdir(path):
        return 0   # directory gone (prunable): nothing uncommitted is left to lose
    if (_reflog_file_entries(path) if reflog_lines is False else reflog_lines) is None:
        return None   # (a detached `git status` reads the HEAD reflog: a FIFO planted there would block it) cannot say
    r = git(path, "--no-optional-locks", "status", "--porcelain", "-uall", "--ignore-submodules=none", check=False)
    if r.returncode != 0:
        return None
    try:
        hidden = _hidden_edits(path)
    except Exception:  # noqa: BLE001 - cannot say: counts as unintegrated, never as an exception out of an inventory
        hidden = None
    if hidden is None:
        return None
    try:
        return len(changes_since(path, _read_state(path))) + len(hidden)
    except (OSError, ValueError, KeyError, SystemExit):
        return len([l for l in r.stdout.splitlines() if l.strip()]) + len(hidden)


def _count(cwd, *revs, stdin=None):
    """`git rev-list --count`, or None when git fails (a broken ref must not read as zero commits)."""
    args = ["rev-list", "--count"] + (["--stdin"] if stdin is not None else list(revs))
    r = git(cwd, *args, inp=stdin, check=False)
    out = r.stdout.strip()
    return int(out) if r.returncode == 0 and out.isdigit() else None


def _ignorable(cwd, main_head, rev, memo=None):
    """The BOOKKEEPING paths that do not count as work when `rev` is compared with main's HEAD: all of them, except the status
    file when `rev` holds a row people made (bug, REQ, test link: _authored) that main does not hold the same way: that row
    exists nowhere else, and `worktree diff` carries it. Fail closed: a status file git cannot read, or a revision git cannot
    read at all (that is not 'no status file'), counts. `memo`: a dict that keeps the answer per (main_head, rev) for the caller's run."""
    key = (main_head, rev)
    if memo is not None and key in memo:
        return set(memo[key])
    got = _ignorable_uncached(cwd, main_head, rev)
    if memo is not None:
        memo[key] = frozenset(got)
    return got


def _ignorable_uncached(cwd, main_head, rev):
    try:
        tree = git(cwd, "ls-tree", "-z", rev, "--", STATUS_FILE, check=False)   # rc 0 and nothing printed: the file is not in rev
        if tree.returncode != 0:
            return set(BOOKKEEPING) - {STATUS_FILE}   # git could not read rev at all: not "no status file"
        if not tree.stdout.strip("\0"):
            return set(BOOKKEEPING)   # no status file in rev: nothing authored there
        new = git(cwd, "show", f"{rev}:{STATUS_FILE}", check=False)
        if new.returncode != 0:
            return set(BOOKKEEPING) - {STATUS_FILE}   # there, but unreadable: it counts
        cur = git(cwd, "show", f"{main_head}:{STATUS_FILE}", check=False)
    except Exception:  # noqa: BLE001 - unreadable: the status file counts
        return set(BOOKKEEPING) - {STATUS_FILE}
    try:
        mine = {rid: a for rid, it in json.loads(new.stdout)["items"].items() for a in [_authored(it)] if a is not None}
        theirs = ({rid: a for rid, it in json.loads(cur.stdout)["items"].items() for a in [_authored(it)] if a is not None}
                  if cur.returncode == 0 else {})
    except (ValueError, KeyError, TypeError, AttributeError):
        return set(BOOKKEEPING) - {STATUS_FILE}
    return set(BOOKKEEPING) if all(theirs.get(rid) == a for rid, a in mine.items()) else set(BOOKKEEPING) - {STATUS_FILE}


def _patch_already_in_main(cwd, main_head, head, memo=None):
    """True when every file the worktree's commits touch already has the same content in the main checkout's HEAD."""
    base = git(cwd, "merge-base", main_head, head, check=False).stdout.strip()
    if not base:
        return False
    files = git(cwd, "--no-optional-locks", "diff", "--name-only", "--no-renames", "--ignore-submodules=none", "-z", base, head, check=False).stdout.split("\0")
    ign = _ignorable(cwd, main_head, head, memo)
    files = [f for f in files if f and f not in ign]   # the gate and hooks rewrite those: not work (authored rows are)
    if not files or len(files) > 500:
        return False
    return git(cwd, "--no-optional-locks", "diff", "--quiet", "--ignore-submodules=none", main_head, head, "--", *files, check=False,
               env=dict(os.environ, GIT_LITERAL_PATHSPECS="1")).returncode == 0


def _empty_commit_between(cwd, main_head, head):
    """True when a commit of main_head..head changes no file (a message only), or git could not say. `--cherry-pick` and the byte
    check cannot vouch for it: every empty commit has the same (empty) patch id, so ANY empty commit of main would 'contain' it."""
    r = git(cwd, "log", "--no-merges", "--format=%x01%H", "--name-only", "--ignore-submodules=none", f"{main_head}..{head}", check=False)
    if r.returncode != 0:
        return True
    return any(len([l for l in chunk.splitlines()[1:] if l.strip()]) == 0 for chunk in r.stdout.split("\x01") if chunk.strip())


def _same_patches_in_main(cwd, main_head, head):
    """True when every commit of the worktree that main lacks has the same patch (patch-id) as a commit of main:
    cherry-picked or rebased there, also after main edited the same files (then _patch_already_in_main sees other bytes).
    A merge commit has no patch-id and counts as not integrated. Any git trouble: False."""
    r = git(cwd, "rev-list", "--count", "--cherry-pick", "--right-only", f"{main_head}...{head}", check=False)
    return r.returncode == 0 and r.stdout.strip() == "0"


def _gd(git_dir_, *args, inp=None, env=None):
    return _run(["git", "--git-dir", git_dir_, *args], inp=inp, env=env)


def _submodule_gitdirs(wt):
    """[(name, git dir)] of the submodules a worktree has initialized. Their git dirs live in the WORKTREE's git dir
    (<git dir>/modules/<name>, nested ones under <name>/modules/...): a removal deletes them, and the commits made in them."""
    if not os.path.isdir(wt):
        return []
    modules = os.path.join(git_dir(wt), "modules")   # SystemExit when git cannot say: the caller refuses
    found = []
    for d, dirs, files in os.walk(modules):
        if "HEAD" in files and "objects" in dirs:   # a submodule's git dir: its own submodules sit under its modules/
            found.append((os.path.relpath(d, modules), d))
            dirs[:] = ["modules"] if "modules" in dirs else []
    return found


def _submodule_unpushed(wt):
    """[(name, n, head sha)] of the worktree's submodules whose HEAD, or a commit their HEAD reflog still names, is not held by a
    remote-tracking ref of the MAIN checkout's OWN copy of that submodule (n = how many commits; None: git could not say, or the
    main checkout has no copy to compare with). Refs in the worktree's own module dir do not count: the agent can write them by
    hand, and they go with the folder; a push from the worktree counts once the main checkout's copy has fetched it."""
    mods = _submodule_gitdirs(wt)
    if not mods:
        return []
    try:
        common = os.path.abspath(os.path.join(wt, git(wt, "rev-parse", "--git-common-dir").stdout.strip()))
    except SystemExit:
        common = ""
    out = []
    for name, d in mods:
        h = _gd(d, "rev-parse", "HEAD")
        head = h.stdout.strip() if h.returncode == 0 else ""
        tips = [head] if head else []
        log = _gd(d, "log", "-g", "--format=%H", "HEAD")
        if log.returncode != 0:   # the reflog is where a commit made and then moved away from is named: unreadable = cannot say
            out.append((name, None, head[:12] or "?"))
            continue
        tips += log.stdout.split()
        main_mod = os.path.join(common, "modules", name) if common else ""
        n = None
        if head and os.path.isfile(os.path.join(main_mod, "HEAD")) and os.path.isdir(os.path.join(main_mod, "objects")):
            held = _gd(main_mod, "for-each-ref", "--format=%(objectname)", "refs/remotes")
            if held.returncode == 0:   # the worktree module's objects are visible through an alternate; only MAIN's refs vouch
                r = _gd(main_mod, "rev-list", "--count", "--stdin", inp="\n".join(tips + ["^" + x for x in held.stdout.split()]) + "\n",
                        env=dict(os.environ, GIT_ALTERNATE_OBJECT_DIRECTORIES=os.path.join(d, "objects")))
                n = int(r.stdout) if r.returncode == 0 and r.stdout.strip().isdigit() else None
        if n is None or n:
            out.append((name, n, head[:12] or "?"))
    return out


def _submodule_dirty(wt):
    """[(name, n)] of the worktree's initialized submodules with n uncommitted paths in their folder (n None: git could not say).
    The superproject's `git status` can hide them (diff.ignoreSubmodules, ignore = all in .gitmodules); a removal deletes the folder."""
    out = []
    for name, d in _submodule_gitdirs(wt):
        c = _gd(d, "config", "--get", "core.worktree")
        where = c.stdout.strip() if c.returncode == 0 else ""
        folder = os.path.normpath(where if os.path.isabs(where) else os.path.join(d, where)) if where else ""
        if not folder:
            out.append((name, None))   # where it is checked out is unknown
            continue
        if not os.path.isdir(folder):
            continue   # deinitialised: no folder, nothing in it to lose
        r = _run(["git", "-C", folder, "--no-optional-locks", "status", "--porcelain", "-uall", "--ignore-submodules=none"])
        n = len([l for l in r.stdout.splitlines() if l.strip()]) if r.returncode == 0 else None
        if n is None or n:
            out.append((name, n))
    return out


_MERGE_TREE = []   # [bool]: this git has `merge-tree --write-tree --merge-base` (2.40+)


def _merge_tree_ok():
    if not _MERGE_TREE:
        m = re.search(r"(\d+)\.(\d+)", _run(["git", "version"]).stdout)
        _MERGE_TREE.append(bool(m) and (int(m.group(1)), int(m.group(2))) >= (2, 40))
    return _MERGE_TREE[0]


def _adds_nothing_to_main(cwd, main_head, head):
    """True when a three-way merge of the worktree's commits into main's HEAD leaves main's tree as it is (BOOKKEEPING
    paths ignored): the changes are in main already, also when another worktree edited the same file around them
    (the byte and patch-id checks above cannot see that). git without `merge-tree --write-tree` (< 2.40), a conflict
    or any trouble: False."""
    if not _merge_tree_ok():
        return False
    base = git(cwd, "merge-base", main_head, head, check=False).stdout.strip()
    if not base:
        return False
    r = git(cwd, "merge-tree", "--write-tree", f"--merge-base={base}", main_head, head, check=False)
    merged = (r.stdout.splitlines() or [""])[0].strip()
    if r.returncode != 0 or not merged:
        return False
    d = git(cwd, "diff-tree", "-r", "--name-only", "--no-renames", "--ignore-submodules=none", "-z", merged, f"{main_head}^{{tree}}", check=False)
    ign = _ignorable(cwd, main_head, head)
    return d.returncode == 0 and not [p for p in d.stdout.split("\0") if p and p not in ign]


def _in_progress(wt):
    """The git operation a worktree is in the middle of (rebase, bisect, merge, cherry-pick, revert), or None: its commits
    live in state files that a removal deletes. "unknown operation" when git cannot say where its state lives (a spent deadline,
    a timeout, a broken link): cannot say is BUSY, never "nothing in progress"."""
    try:
        gd = git_dir(wt)
    except SystemExit:
        return "unknown operation"
    for name, what in (("rebase-merge", "rebase"), ("rebase-apply", "rebase"), ("BISECT_LOG", "bisect"), ("MERGE_HEAD", "merge"),
                       ("CHERRY_PICK_HEAD", "cherry-pick"), ("REVERT_HEAD", "revert")):
        if os.path.exists(os.path.join(gd, name)):
            return what
    return None


def _reflog_file_entries(wt):
    """Entries in the worktree's own HEAD reflog FILE (0 when there is none: nothing to lose), or None when it cannot be read.
    `git log -g` prints nothing and exits 0 for an unreadable or corrupt reflog: only the file shows the difference."""
    r = git(wt, "rev-parse", "--git-path", "logs/HEAD", check=False)
    path = r.stdout.strip()
    if r.returncode != 0 or not path:
        return None
    try:
        return sum(1 for line in _read_regular(os.path.join(wt, path)).split(b"\n") if line.strip())
    except FileNotFoundError:
        return 0
    except OSError:   # a FIFO / device / directory / unreadable file / over 32 MB: git would block or skip lines
        return None


def _branch_reflog_shas(wt):
    """The commits the reflogs of the LOCAL BRANCHES name (shared by every worktree: a removal keeps them), or None when git cannot say.
    A commit one of them names is recoverable by name after `reset --hard HEAD~1` / `commit --amend` moved the branch off it."""
    r = git(wt, "log", "-g", "--format=%H", "--glob=refs/heads/*", check=False)
    return set(r.stdout.split()) if r.returncode == 0 else None


def _is_ancestor(wt, a, b):
    return git(wt, "merge-base", "--is-ancestor", a, b, check=False).returncode == 0   # rc 1 (no) and any trouble: no


def _reflog_only(wt, head, main_head, refs, attached=False, reflog_lines=False):
    """Commits that nothing but this worktree's own HEAD reflog names (`checkout --detach HEAD~1`, `reset`, a commit made detached
    and then `checkout <branch>`): a removal deletes that reflog and the commit is gone at the next gc. [sha, ...] newest first,
    or None when git could not say (fail closed; an unreadable, irregular or corrupt reflog file is such a case). `refs`: the commit
    ids of the branch, remote and tag tips (inventory computes them once). Not counted: the predecessor of an amend / rebase fixup /
    squash, a commit whose files hold the same bytes in main, one that main (or the current HEAD) has as the same patch
    (cherry-picked, rebased), the commits of a chain whose whole patch is in main already (a squash brought back as one diff); for a
    worktree on a BRANCH (`attached`) also a commit the reflog of a local branch names (`reset --hard HEAD~1`, `commit --amend` on
    the branch: the branch reflog survives the removal)."""
    on_file = _reflog_file_entries(wt) if reflog_lines is False else reflog_lines   # BEFORE git reads that file: a FIFO there would block `git log -g`
    if on_file is None:
        return None
    r = git(wt, "log", "-g", "--format=%H%x09%gs", "HEAD", check=False)
    if r.returncode != 0:
        return None
    entries = [(l.split("\t", 1) + [""])[:2] for l in r.stdout.splitlines() if l]
    if on_file > len(entries):
        return None   # git skipped lines it could not read: what they named is unknown
    superseded = {entries[i + 1][0] for i in range(len(entries) - 1)
                  if entries[i][1].startswith(("commit (amend)", "rebase (fixup", "rebase (squash"))}   # (reflog subjects: an agent can write them)
    cands = list(dict.fromkeys(e[0] for e in entries if e[0] not in superseded and e[0] != head))
    if not cands:
        return []
    minimal = ["^" + head] + (["^" + main_head] if main_head else [])
    out = git(wt, "rev-list", "--stdin", inp="\n".join(cands + minimal + ["^" + x for x in refs]) + "\n", check=False)
    if out.returncode != 0 and attached:
        # one broken ref anywhere (an interrupted fetch) fails the whole call: a worktree on a branch is then shielded by its own
        # HEAD and main only. That excludes LESS, so it can only keep more commits on the list; a detached one stays unreadable (None)
        out = git(wt, "rev-list", "--stdin", inp="\n".join(cands + minimal) + "\n", check=False)
    if out.returncode != 0:
        return None
    unreachable = set(out.stdout.split())
    tips = [c for c in cands if c in unreachable]
    if attached and tips:
        named = _branch_reflog_shas(wt)
        if named is None:
            return tips
        tips = [c for c in tips if c not in named]
    if len(tips) > 40:
        return tips   # too many to vouch for one by one
    lost, chain_ok, memo = [], [], {}
    for sha in tips:   # newest first
        if _spent():   # the shared deadline of this inventory is gone: what is not judged yet is NOT clean (held), never waved through
            lost.append(sha)
            continue
        if main_head and any(_is_ancestor(wt, sha, d) for d in chain_ok):
            continue   # a newer commit that contains this one has its whole patch in main already (a squash / fixup brought back as one diff)
        if main_head and _patch_already_in_main(wt, main_head, sha, memo) and not _empty_commit_between(wt, main_head, sha):
            chain_ok.append(sha)
            continue
        ign = _ignorable(wt, main_head, sha, memo) if main_head else set(BOOKKEEPING)
        diff_names = [f for f in git(wt, "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "--no-renames", "--ignore-submodules=none", "-z", sha,
                                     check=False).stdout.split("\0") if f]
        files = [f for f in diff_names if f not in ign]
        same_bytes = bool(files) and len(files) <= 500 and bool(main_head) and git(
            wt, "--no-optional-locks", "diff", "--quiet", "--ignore-submodules=none", main_head, sha, "--", *files, check=False,
            env=dict(os.environ, GIT_LITERAL_PATHSPECS="1")).returncode == 0
        if not any(diff_names):   # an empty commit (or a merge) has no patch to compare: its message would be lost
            lost.append(sha)
            continue
        # `git cherry <up> <sha>` lists every commit from the merge base, oldest first: only the line of THIS commit counts (only asked when the bytes differ)
        if not same_bytes and not any(("- " + sha) in git(wt, "cherry", up, sha, check=False).stdout.splitlines() for up in (main_head, head) if up):
            lost.append(sha)
    return lost

# ponytail (accepted, same as the base): the whole-patch rule above allows a chain that DELIBERATELY reverted itself (add V then delete V, edit then revert,
# a binary added then deleted, `merge -s ours` of a side commit): its net patch is empty / already in main. Patch ids ignore whitespace and EOL. Upgrade
# only if such a chain must keep the worktree: judge every commit's own diff against main as well.


EXTRA_CHECK_BUDGET_S = 3.0   # the checks that can only CLEAR a worktree (patch ids, merge-tree) stop after this much time per inventory


def _same_path(a, b):
    """True when two spellings name the same directory: the same inode (case-insensitive and normalization-insensitive filesystems,
    symlinks, `..`), or, when one of them cannot be stat-ed (a prunable worktree: its folder is gone), the same realpath."""
    try:
        return os.path.samefile(a, b)
    except OSError:
        return os.path.realpath(a) == os.path.realpath(b)


def inventory(cwd, only=None, budget=EXTRA_CHECK_BUDGET_S):
    """ONE shared deadline for the whole call (_inventory_budget: inside a hook it ends before the hook's alarm): when it is spent, no further git
    call is started and every worktree or commit not judged yet reads as "cannot say" = unintegrated. Every linked worktree (or just `only`):
    [{path, branch, detached, dirty, ahead, unreachable, unintegrated}]. `ahead` = commits of its HEAD that are not
    in the main checkout's HEAD (and whose files are not already there with the same content): the work not
    integrated. `unreachable` = a detached HEAD whose commits no branch, tag or remote ref holds, or (also on a branch)
    commits only the worktree's own HEAD reflog names (`reflog`): a removal loses them. `dirty`/`ahead` are None when git
    could not say; that counts as unintegrated (fail closed). `only` is any spelling of the directory (same inode), or a list of them.
    The branch / remote / tag tips are read ONCE here (one `for-each-ref`, as commit ids): a ref scan per worktree cost seconds with
    tens of thousands of tags, and a hook's alarm turns a slow scan into "all clear"."""
    with _Budget(_inventory_budget()):
        return _inventory(cwd, only, budget)


def _inventory(cwd, only, budget):
    entries = _worktree_entries(cwd)
    main_head = entries[0]["head"] if entries else None
    refs = sorted(set(git(cwd, "for-each-ref", "--format=%(objectname)", "refs/heads", "refs/remotes", "refs/tags",
                          check=False).stdout.split()))
    wanted = [only] if isinstance(only, str) else list(only or [])
    rows = []
    started = time.monotonic()   # hooks fail open after a few seconds: a slow repo must not turn the slowness into "all clear"
    for e in entries[1:]:
        path, head = e["path"], e["head"]
        if e["broken"]:   # git < 2.36 split this path at a newline: it cannot be tied to a directory. Held, and never matched by a path asked for
            if not wanted:
                rows.append({"path": path, "branch": None, "detached": False, "dirty": None, "ahead": None, "reflog": None, "busy": None,
                             "unreachable": True, "unintegrated": True})
            continue
        if wanted and not any(_same_path(path, w) for w in wanted):
            continue
        rl = _reflog_file_entries(path) if os.path.isdir(path) else 0   # read once: _uncommitted and _reflog_only both need it
        dirty = _uncommitted(path, rl)
        ahead = _count(cwd, f"{main_head}..{head}") if head and main_head else None   # None: git could not say
        try:   # the checks that CLEAR a worktree: any trouble (a name git prints in another encoding...) leaves it unintegrated
            cleared = bool(ahead) and (_patch_already_in_main(cwd, main_head, head)
                                       or ((budget is None or time.monotonic() - started < budget)
                                           and (_same_patches_in_main(cwd, main_head, head) or _adds_nothing_to_main(cwd, main_head, head)))) \
                and not _empty_commit_between(cwd, main_head, head)
        except Exception:  # noqa: BLE001
            cleared = False
        if cleared:
            ahead = 0   # brought back the documented way (diff | apply, committed in main), cherry-picked / rebased, or merged there
        held_only = None   # commits no other ref holds (what a removal would lose); None: git could not say
        reflog = []        # commits only this worktree's own reflog names; None: git could not say
        if head and e["detached"]:   # a branch keeps the commits made ON it reachable; a detached HEAD does not
            rev_in = [head] + ["^" + r for r in refs] + (["^" + main_head] if main_head else [])
            held_only = _count(cwd, stdin="\n".join(rev_in) + "\n")
        if head:   # also a worktree on a branch: it can detach, commit, and go back (the commit is then named by its reflog only)
            try:
                reflog = _reflog_only(path, head, main_head, refs, attached=not e["detached"], reflog_lines=rl) if os.path.isdir(path) else []
            except Exception:  # noqa: BLE001 - cannot say: counts as holding commits no ref keeps
                reflog = None
        try:
            busy = _in_progress(path) if os.path.isdir(path) else None
        except Exception:  # noqa: BLE001
            busy = "unknown operation"
        rows.append({"path": path, "branch": e["branch"], "detached": e["detached"], "dirty": dirty, "ahead": ahead,
                     "reflog": reflog, "busy": busy,
                     "unreachable": bool((e["detached"] and ahead != 0 and (held_only is None or held_only > 0)) or reflog is None or reflog),
                     "unintegrated": bool(dirty is None or dirty or ahead is None or ahead or reflog is None or reflog or busy)})
    return rows


def describe(r):
    tag = ("UNINTEGRATED" if r["unintegrated"] else "clean").ljust(12)
    where = r["branch"] or "(detached)"
    note = ("  UNREACHABLE: its commits are on no branch, removing the worktree loses them" if r["detached"] else
            "  UNREACHABLE: commits only this worktree's own reflog names (or its reflog cannot be read), removing the worktree loses them") \
        if r["unreachable"] else ""
    note += f"  IN PROGRESS: {r['busy']}" if r.get("busy") else ""
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


STATUS_FILE = ".agents/regression_status.json"
_GENERATED_KEYS = {"last", "history", "stale_since", "stale_files", "red_proof", "sessions", "touched_at"}   # the gate and the hooks rewrite these


def _authored(item):
    """What a person made of a checklist row (`agent-kit bugs add|link|drop`, `req add|link`, `link UNCOVERED:<f> <TEST>`): a bug or
    REQ row without the keys that are regenerated, or a test row's `covers` links; None for every other row."""
    if not isinstance(item, dict):
        return None
    if item.get("kind") in ("bug", "req"):
        return {k: v for k, v in item.items() if k not in _GENERATED_KEYS}
    if item.get("kind") == "test" and item.get("covers"):
        return {"covers": item["covers"]}
    return None


def _carry_authored_rows(wt, base, env):
    """When the worktree's regression_status.json (as in the temp index `env` names) differs from the base's in an AUTHORED row,
    put base-plus-those-rows into that index and return True: the patch then carries just what nothing can regenerate."""
    old = git(wt, "show", f"{base}:{STATUS_FILE}", env=env, check=False)
    new = git(wt, "show", f":{STATUS_FILE}", env=env, check=False)
    if old.returncode != 0 or new.returncode != 0:
        return False
    try:
        b, w = json.loads(old.stdout), json.loads(new.stdout)
        b_items, w_items = b["items"], w["items"]
    except (ValueError, KeyError, TypeError):
        return False
    changed = False
    for rid, item in w_items.items():
        auth = _authored(item)
        if auth is None:
            continue
        cur = b_items.get(rid)
        if cur is None:
            b_items[rid], changed = item, True
        elif _authored(cur) != auth:
            merged = {k: v for k, v in cur.items() if k in _GENERATED_KEYS or k == "id"}
            merged.update(auth)
            b_items[rid], changed = merged, True
    for rid in [r for r, it in b_items.items() if _authored(it) is not None and r not in w_items]:
        del b_items[rid]
        changed = True
    if not changed:
        return False
    sha = git(wt, "hash-object", "-w", "--stdin", env=env, inp=json.dumps(b, ensure_ascii=False, indent=2) + "\n", bounded=False).stdout.strip()
    git(wt, "update-index", "--cacheinfo", f"100644,{sha},{STATUS_FILE}", env=env, bounded=False)
    return True


def cmd_diff(cwd, args):
    flags = [a for a in args if a.startswith("--")]
    pos = [a for a in args if not a.startswith("--")]
    if len(pos) != 1 or set(flags) - {"--with-checklist"}:
        die("usage: agent-kit worktree diff <path> [--with-checklist]")
    wt = os.path.abspath(os.path.join(cwd, pos[0]))
    state = load_state(wt)
    changed = changes_since(wt, state)
    fd, index = tempfile.mkstemp(prefix="devkit-wt-index.")
    os.close(fd)
    left_out, spec, carried = [], [], False
    try:
        env = dict(os.environ, GIT_INDEX_FILE=index, GIT_LITERAL_PATHSPECS="1")
        git(wt, "read-tree", "HEAD", env=env, bounded=False)
        if changed:
            git(wt, "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", env=env,
                inp="\0".join(changed) + "\0", bounded=False)
        if "--with-checklist" not in flags:
            # which bookkeeping files differ from the base (committed or not): named on stderr, not carried
            r = git(wt, "diff", "--cached", "--name-only", "-z", state["base"], "--", *BOOKKEEPING, env=env, check=False)
            left_out = [p for p in r.stdout.split("\0") if p] if r.returncode == 0 else []
            keep = []
            if STATUS_FILE in left_out and _carry_authored_rows(wt, state["base"], env):
                keep, carried = [STATUS_FILE], True   # the rows people made (bugs, REQs, links) replace that file's content in the patch
                left_out = [p for p in left_out if p != STATUS_FILE]
            spec = [":/"] + [":(top,exclude,literal)" + p for p in BOOKKEEPING if p not in keep]   # magic: GIT_LITERAL_PATHSPECS off below
        out = subprocess.run(["git", "-C", wt, "diff", "--cached", "--binary", state["base"], "--", *spec],
                             capture_output=True, env=dict(env, GIT_LITERAL_PATHSPECS="0"))
        if out.returncode != 0:
            die(out.stderr.decode("utf-8", "replace").strip(), 1)
        sys.stdout.buffer.write(out.stdout)
    finally:
        os.unlink(index)
    if carried:
        print("ℹ " + tr(f"worktree diff: {STATUS_FILE} chỉ mang các dòng do người tạo (bug, REQ, link test); phần gate/hook ghi lại bị bỏ",
                        f"worktree diff: {STATUS_FILE} carries only the rows people made (bugs, REQs, test links); what the gate and hooks regenerate is left out"),
              file=sys.stderr)
    if left_out:
        print("ℹ " + tr(f"worktree diff: bỏ {len(left_out)} file sổ sách checklist (gate/hook ghi lại, gộp là xung đột): ",
                        f"worktree diff: left out {len(left_out)} checklist bookkeeping file(s) (rewritten by the gate and hooks, they conflict on merge): ")
              + ", ".join(left_out) + " — " + tr("thêm --with-checklist để lấy cả chúng", "add --with-checklist to include them"),
              file=sys.stderr)
    warn_others(cwd, exclude=wt)
    return 0


def _iter_blockers(cwd, wt, shown, budget):
    """The reasons a worktree must NOT be removed, one at a time, in the order `remove` has always checked them. Yields
    (exit code, kind, text, detail lines). Lazy: a check that cannot run (not made by `worktree add`) is only reached when
    nothing earlier blocked. kind: unregistered | busy | unreachable | submodule | not_ours | main | uncommitted."""
    rows = inventory(cwd, only=wt, budget=budget)
    if not rows and os.path.isdir(wt):
        # git does not list this directory as a linked worktree (a subdirectory of one, the main checkout, a plain folder, a name the
        # listing could not tie to it): the busy / reflog / unreachable checks have nothing to run on, so nothing may be assumed safe
        if _same_path(wt, main_checkout(cwd)):
            yield (2, "main", tr("đây là main checkout", "that is the main checkout"), [])
        else:
            yield (2, "unregistered", tr(f"{wt}: git không liệt kê đường dẫn này là worktree liên kết của repo — không chứng minh được là gỡ an toàn "
                                         "(thư mục con của worktree? đường dẫn viết khác? thư mục thường?). Dùng đúng đường dẫn `git worktree list` in ra",
                                         f"{wt}: git does not list this path as a linked worktree of the repository, so it cannot be proven safe to remove "
                                         "(a subdirectory of a worktree? another spelling of its path? a plain folder?). Use the path exactly as `git worktree list` prints it"), [])
        return
    if rows:
        # the checks below run in `wt`; the removal deletes the directory git listed: they must be one and the same (an agent can
        # point a per-worktree core.worktree elsewhere), and no OTHER registered worktree may live inside it (ignored folders go with it)
        top = git(wt, "rev-parse", "--show-toplevel", check=False)
        if top.returncode != 0 or not _same_path(top.stdout.strip(), wt):
            yield (1, "toplevel", tr(f"{wt}: git coi thư mục làm việc của nó là {top.stdout.strip() or '(không đọc được)'} — kiểm tra sẽ chạy trên thư mục khác với thư mục bị xoá",
                                     f"{wt}: git takes its work tree to be {top.stdout.strip() or '(unreadable)'} - the checks would run on another directory than the one removed"), [])
        try:
            inside = [e["path"] for e in _worktree_entries(cwd)[1:]   # (also an entry git < 2.36 split at a newline: its first piece lies inside too)
                      if os.path.realpath(e["path"]) != os.path.realpath(wt)
                      and os.path.realpath(e["path"]).startswith(os.path.realpath(wt) + os.sep)]
        except (Exception, SystemExit):
            inside = ["(unreadable)"]
        if inside:
            yield (1, "nested", tr(f"{wt}: worktree khác nằm TRONG nó ({', '.join(inside[:3])}) — gỡ nó là xoá luôn việc chưa lưu ở đó. Đem về hoặc gỡ cái trong trước",
                                   f"{wt}: another registered worktree lives INSIDE it ({', '.join(inside[:3])}) - removing it deletes that one's unsaved work too. Bring back or remove the inner one first"), [])
    for r in rows:
        if r["busy"]:
            yield (1, "busy", tr(f"{wt}: đang dở một {r['busy']} — hoàn tất hoặc huỷ nó trước (commit của nó nằm trong file trạng thái, gỡ worktree là mất)",
                                 f"{wt}: a {r['busy']} is in progress — finish or abort it first (its commits live in state files that a removal deletes)"), [])
        if r["unreachable"]:
            sha = git(wt, "rev-parse", "--short=12", "HEAD", check=False).stdout.strip() or "HEAD"
            main = main_checkout(cwd)
            vi, en = [], []
            if r["detached"] and r["ahead"] != 0:   # (a worktree on a branch keeps those commits on it; only its reflog-only ones are lost)
                vi.append(f"HEAD tách rời ({sha}), {r['ahead']} commit không thuộc nhánh nào và main chưa có (cùng nội dung hoặc cùng patch hoặc "
                          f"gộp ba chiều không đổi gì). Đem về trước: agent-kit worktree diff {shlex.quote(shown)} | git apply --3way rồi commit ở main checkout "
                          "(file sổ sách checklist được bỏ qua khi so, trừ dòng bug/REQ do người tạo; nếu commit có sửa chúng thì dùng "
                          f"diff --with-checklist). Hoặc giữ bằng nhánh: `git -C {shlex.quote(main)} branch rescue/<tên> {sha}`")
                en.append(f"detached HEAD ({sha}), {r['ahead']} commit(s) on no branch and not in main (by content, by patch, or as a three-way merge "
                          f"that adds nothing). Bring them back first: agent-kit worktree diff {shlex.quote(shown)} | git apply --3way, then commit in the main "
                          "checkout (checklist bookkeeping files are ignored in that comparison, except the bug/REQ rows people made; if the commit "
                          f"changed those too, use diff --with-checklist). Or keep them on a branch: `git -C {shlex.quote(main)} branch rescue/<name> {sha}`")
            lost = r["reflog"]
            if lost is None:
                vi.append("không đọc được reflog của worktree — coi như còn commit chưa được ref nào giữ")
                en.append("the worktree's reflog could not be read — treated as holding commits no ref keeps")
            elif lost:
                listed = "; ".join((git(wt, "log", "-1", "--format=%h %s", c, check=False).stdout.strip() or c) for c in lost[:10])
                vi.append(f"{len(lost)} commit CHỈ còn trong reflog của worktree (sau checkout --detach / reset): {listed}. Gỡ worktree xoá reflog "
                          f"đó và commit mất sau lần git gc. Giữ chúng: xin người dùng tạo nhánh `git -C {shlex.quote(main)} branch rescue/<tên> {lost[0]}`")
                en.append(f"{len(lost)} commit(s) ONLY the worktree's reflog still names (after checkout --detach / reset): {listed}. A removal deletes "
                          f"that reflog and the commits are lost at the next git gc. Keep them: ask the user for a branch, "
                          f"`git -C {shlex.quote(main)} branch rescue/<name> {lost[0]}`")
            tail_vi = (f". Nếu đã kiểm là bỏ được (main đã có dưới dạng khác, hoặc commit bị huỷ có chủ đích), người dùng chạy "
                       f"`git worktree remove --force {shlex.quote(wt)}` (commit còn cứu được theo sha tới khi git gc)")
            tail_en = (f". If you checked they can go (main has them in another shape, or they were dropped on purpose), the user runs "
                       f"`git worktree remove --force {shlex.quote(wt)}` (the commits stay recoverable by sha until git gc)")
            if not _merge_tree_ok():
                tail_vi += "; git này cũ (< 2.40, không có merge-tree --write-tree) nên không kiểm được sửa chồng lên cùng file"
                tail_en += "; this git is older than 2.40 (no merge-tree --write-tree): edits merged around the change cannot be recognised"
            yield (1, "unreachable", tr(f"{wt}: UNREACHABLE — " + " | ".join(vi) + tail_vi, f"{wt}: UNREACHABLE — " + " | ".join(en) + tail_en), [])
    try:
        sub = _submodule_unpushed(wt)
    except (Exception, SystemExit):  # noqa: BLE001 - cannot say: refuse
        sub = [("?", None, "?")]
    if sub:
        listed = ", ".join(f"{name} (HEAD {head}: {'?' if n is None else n} commit(s) of it or its reflog)" for name, n, head in sub[:5])
        main = main_checkout(cwd)
        yield (1, "submodule", tr(f"{wt}: submodule có commit mà bản submodule CỦA MAIN CHECKOUT chưa giữ trên remote-tracking ref nào: {listed} — chúng nằm trong git dir "
                                  f"của worktree, gỡ worktree là mất. Push chúng (git -C <worktree>/<submodule> push …) rồi fetch ở main: git -C {shlex.quote(main)}/<submodule> fetch "
                                  "(main chưa init submodule đó thì init trước). Ref tự viết trong worktree không tính",
                                  f"{wt}: submodule commit(s) the MAIN checkout's own copy of the submodule does not hold on a remote-tracking ref: {listed} — they "
                                  "live in the worktree's git dir and a removal deletes them. Push them (git -C <worktree>/<submodule> push …), then fetch in the main "
                                  f"checkout: git -C {shlex.quote(main)}/<submodule> fetch (initialize the submodule there first when it is not). A ref written by hand in the "
                                  "worktree does not count"), [])
    try:
        sub_dirty = _submodule_dirty(wt)
    except (Exception, SystemExit):  # noqa: BLE001 - cannot say: refuse
        sub_dirty = [("?", None)]
    if sub_dirty:
        listed = ", ".join(f"{name} ({'?' if n is None else n} path(s))" for name, n in sub_dirty[:5])
        yield (1, "submodule", tr(f"{wt}: submodule có thay đổi CHƯA commit (file sửa hoặc mới): {listed} — gỡ worktree xoá cả thư mục đó. "
                                  "Commit rồi push trong submodule, hoặc đem về bằng tay",
                                  f"{wt}: submodule with UNCOMMITTED changes (edited or new files): {listed} — a removal deletes that folder. "
                                  "Commit and push them inside the submodule, or bring them back by hand"), [])
    state = None
    if os.path.isdir(wt):   # (load_state() die()s with a message on stderr: a blocker list must stay quiet)
        try:
            state = _read_state(wt)
        except (OSError, ValueError, SystemExit):
            state = None
    if not isinstance(state, dict):
        yield (2, "not_ours", tr(f"{wt} không được tạo bằng 'agent-kit worktree add' (thiếu {STATE})",
                                 f"{wt} was not made by 'agent-kit worktree add' (no {STATE})") if os.path.isdir(wt)
               else tr(f"không có thư mục: {wt}", f"no such directory: {wt}"), [])
        return
    main = main_checkout(cwd)
    if os.path.realpath(wt) == os.path.realpath(main):
        yield (2, "main", tr("đây là main checkout", "that is the main checkout"), [])
        return
    changed = changes_since(wt, state)
    try:
        hidden = _hidden_edits(wt)   # edits `git status` cannot see (skip-worktree / assume-unchanged); None: git could not say
    except Exception:  # noqa: BLE001 - cannot say: refuse
        hidden = None
    # Commits stay on the branch. Uncommitted work is safe once the main checkout
    # holds the same bytes (and executable bit) at the same path (a deleted file: missing in both).
    lost = [p for p in dict.fromkeys(changed + (hidden or [])) if not _same_in_main(wt, main, p)]
    if lost or hidden is None:
        detail = [f"    {p}" + ("   (git hides it: skip-worktree / assume-unchanged)" if p in (hidden or ()) else "") for p in lost[:20]]
        if hidden is None:
            detail.append("  " + tr("Không đọc được danh sách file git ẩn (skip-worktree / assume-unchanged): coi như còn sửa chưa đem về",
                                    "The files git hides (skip-worktree / assume-unchanged) could not be listed: treated as edited and not brought back"))
        detail.append("  " + tr("Đem về trước", "Bring them back first") + f": agent-kit worktree diff {shlex.quote(shown)} | git apply --3way")
        if any(p in BOOKKEEPING for p in lost):
            detail.append("  " + tr("File sổ sách checklist: `diff` bỏ chúng; thêm --with-checklist để đem về, hoặc hỏi người dùng có bỏ thay đổi đó không",
                                    "Checklist bookkeeping: `diff` leaves it out; add --with-checklist to bring it back, or ask the user whether to drop the change"))
        yield (1, "uncommitted", tr(f"{len(lost)} thay đổi chưa có trong main checkout — giữ nguyên {wt}:",
                                    f"{len(lost)} change(s) not in the main checkout — {wt} kept:"), detail)


def removal_blockers(cwd, wt, budget=None, shown=None):
    """THE rule for removing a worktree (`agent-kit worktree remove` and `worktree land` both call it): the list of reasons it
    must NOT be removed now, empty when it can go. Covers everything a removal would lose: a rebase/bisect/merge in progress,
    commits that are in main neither by content, patch nor as a no-op merge (a detached HEAD's commits, also those only its
    reflog still names, also empty commits), submodule commits on no remote ref, uncommitted changes main does not hold
    byte for byte (executable bit included), edits git hides (skip-worktree / assume-unchanged), a submodule with uncommitted
    changes or commits the main checkout's own copy does not hold, and a path git does not list as a linked worktree (any
    spelling of one that exists IS matched, by inode). `wt` is absolute; `cwd` any checkout of the repo; `budget` seconds for
    the checks that can only clear a worktree (None: no limit, the default; inventory()'s own default is EXTRA_CHECK_BUDGET_S);
    `shown` is how the path is written in the advice (default: wt). Returns list[str]. A check that RAISES an Exception reads as
    a blocker (fail closed); a git that cannot run at all (main_checkout, `worktree list`, `status`) raises SystemExit, which
    the caller must catch (`except (Exception, SystemExit)`): it is not turned into a blocker here."""
    out = []
    try:
        for code, kind, text, detail in _iter_blockers(cwd, wt, shown or wt, budget):
            out.append(text + ("".join("\n" + d for d in detail)))
    except Exception as e:  # noqa: BLE001 - a check that blows up must never read as "safe to remove"
        out.append(f"{wt}: cannot check whether it can be removed: {e}")
    return out


def cmd_remove(cwd, args):
    if len(args) != 1:
        die("usage: agent-kit worktree remove <path>")
    wt = os.path.abspath(os.path.join(cwd, args[0]))
    try:
        for code, kind, text, detail in _iter_blockers(cwd, wt, args[0], None):   # a person is waiting: a git call is still bounded (_timeout)
            if kind == "uncommitted":
                print("✖ worktree: " + text, file=sys.stderr)
                for d in detail:
                    print(d, file=sys.stderr)
                return code
            die(text, code)
    except UnicodeError as e:   # a path git prints that is not UTF-8: what it names cannot be compared, so nothing is removed
        die(tr(f"không kiểm tra được {wt} (tên file không phải UTF-8: {e}) — không gỡ", f"cannot check {wt} (a file name that is not UTF-8: {e}) - nothing removed"), 1)
    state = load_state(wt)
    main = main_checkout(cwd)
    # Verified above: nothing but the recorded setup and ignored files is left, so
    # --force here drops no work (plain `remove` refuses any untracked file).
    git(main, "worktree", "remove", "--force", wt, bounded=False)
    branch = state.get("branch")
    print(f"✔ {tr('đã gỡ', 'removed')} {wt}" + (f"; {tr('nhánh', 'branch')} {branch} "
          + tr("giữ lại (xoá khi đã merge: git branch -d ", "kept (delete once merged: git branch -d ") + branch + ")" if branch else ""))
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
