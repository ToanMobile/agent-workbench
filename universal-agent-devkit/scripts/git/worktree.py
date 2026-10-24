#!/usr/bin/env python3
"""worktree.py — one git worktree per parallel agent, set up like the main checkout.

Usage (normally `agent-kit worktree …`, run inside the repo):
  worktree.py add <path> [branch] [--base=REF] [--profile=ID] [--no-init] [--share-memory] [--session=ID] [--lane=build|qa|review]
  worktree.py trunk [on|off|wire|status]   trunk mode (W1 R1/R2/R7), ON by default: main merge-only, one worktree per session (hook-create /
                                      hook-remove are the WorktreeCreate / WorktreeRemove hooks it wires; payload JSON on stdin). `off` writes
                                      devkit.trunkMode=false into THIS repo's config: a global git config key is not read
  worktree.py diff <path> [--with-checklist]   the worktree's own changes as a binary patch
  worktree.py finish <path>    merge its work into the main branch AUTOMATICALLY, then remove it (exit 0 done, 3 conflict, 1 blocked)
  worktree.py automerge <path> the same, one JSON line on stdout (what the Stop gate runs)
  worktree.py remove <path>    remove it once nothing of its work would be lost
  worktree.py discard <path>   remove one `remove` refuses, only when it holds nothing but deleted files / untracked IDE junk, its HEAD is
                               in the trunk and no live session holds it; a fallback copy goes to refs/devkit/discarded/* (30 days)
  worktree.py restore <commit> -- <path>…   `git checkout <commit> -- <path>` for paths with no uncommitted change and no ignored file in
                               the way (not in a trunk-mode main)
  worktree.py prune-branch [--remote] <branch>   `git branch -D` for a branch the trunk holds (ancestor or squash) or whose PR merged into
                               the trunk at its tip; --remote: origin's branch too, when that PR merged at its tip
  worktree.py gc [--dry-run]   delete what DevKit worktrees left behind, only when nothing in it is unique (kept ones are named)
  worktree.py list
  worktree.py heal [--devkit=DIR] [--session=ID]   a checkout the host made (Grok): link the DevKit, copy ignored config

add: refuses (exit 4) under WORKTREE_DISK_MIN_GIB (3) free or when the repo already has WORKTREE_MAX (3) linked worktrees; under
WORKTREE_DISK_WARN_GIB (10) it runs gc first and warns (0 turns each off). Then `git worktree add` on <branch> when one is named (created from --base or HEAD when it
does not exist); with none, a DETACHED worktree at --base or HEAD — the project keeps one
branch, and the work comes back with `diff | git apply --3way`. `--lane=build|qa|review` (a super-board lane, agent-workbench#93; only
at .claude/worktrees/issue-<N>[-<lane>]): no WORKTREE_MAX slot is needed or taken (the disk floor still holds), a branch only origin has
is fetched and checked out from origin/<branch> (never a new branch off --base over the PR), the registered worktree already at the path
is reused (healed), and a detached one is marked a board worktree in its state (board_worktree). Copies the main checkout's git-ignored
hooks under .claude/hooks/ (copy_local_hooks: the project's and the user's settings run them) and git-ignored local config
(.env*, local.properties, keystore.properties, google-services.json, …) and git-ignored
build inputs (the red_proof.py set: libs/*.aar|jar, *.jks, … plus .agents/local/red_proof.json
{"copy": [...]} — scripts/build_inputs.py), runs the
DevKit installer with the main checkout's profile, agents, mode and lang (no tracked file changes), then records what
that setup left in `git status` — file by file, with a content fingerprint — in the
worktree's own git dir. Hook state (.claude/audit-gate) and the gate report
(<git dir>/postfix-gate) are per worktree already; the gate's run log (runs.jsonl) is the one
exception: it lives in the common dir (<git-common-dir>/postfix-gate), so it outlives the worktree. Claude Code's auto-memory
(.claude/settings.local.json autoMemoryDirectory) stays the worktree's OWN folder, as the
installer sets it. With --share-memory it is pointed at the main checkout's folder instead,
so a note saved in a worktree survives it; every worktree then shares ONE MEMORY.md: two
agents saving at once overwrite each other, and what one agent saves (even after reading
untrusted content) reaches every later session. Off by default for that reason.

diff: everything that differs from the recorded setup — commits since the base and
uncommitted edits — as one patch against the base, DevKit files left out. The checklist
bookkeeping the gate and the hooks rewrite (BOOKKEEPING below: .agents/CHECKLIST.md,
regression_status.json, …) is left out too, and named on stderr: two worktrees that
each rewrote it conflict when brought back; --with-checklist keeps it. Bring it
back with: agent-kit worktree diff <path> | git apply --3way

finish / automerge (run from the main checkout; the Stop gate runs automerge by itself): uncommitted work in the worktree is
REFUSED, files named (#366: it is never auto-committed as a `wip` commit; commit it there first); main is merged INTO the worktree (so a conflict is resolved there, in a folder nobody else touches);
then — after the gate on what the worktree brings (_merge_gate, W1 R3) — the main branch only FAST-FORWARDS to the
worktree's HEAD (`git merge --ff-only`: git itself refuses when main has uncommitted edits on a file the merge changes, and then
nothing moved), then `remove` (`--keep`: not). Main moved meanwhile: merged in and gated again, at most MERGE_ROUNDS times. A conflict leaves the merge open in the
worktree (exit 3, the files named): resolve them there, `git add`, and run it again (it concludes the merge). Works on worktrees
`worktree add` did not make (EnterWorktree, a subagent's isolated worktree): see _adopted_state.

remove: refused while an uncommitted change of the worktree is not in the main
checkout byte-for-byte (the executable bit too; edits git hides with skip-worktree /
assume-unchanged count), while a commit is named only by the worktree's own reflog (also
on a branch worktree: detach, commit, go back), while a submodule has uncommitted changes
or commits the main checkout's own copy of it does not hold, and for a path git does not
list as a linked worktree (any spelling of one that exists is matched). A named branch
and its commits are kept (a detached worktree's commits must be brought back first).
Only the recorded setup and ignored files (copied config, hook logs) go with the folder.
"""

import collections
import contextlib
import errno
import filecmp
import fnmatch
import hashlib
import importlib.util
import io
import json
import os
import random
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata

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
# Gợi ý thứ tự chạy test của kit (#365): một diff chỉ nằm ở đây không phải công việc, không được giữ lại việc gỡ worktree.
DURATIONS_HINT = "tests/lib/test_durations.txt"
# chỉ file của chính kit: ở gốc repo kit, hay trong thư mục kit của repo cài (đường dẫn khác tên đó vẫn là việc thật)
DURATIONS_HINT_PATHS = (DURATIONS_HINT, "universal-agent-devkit/" + DURATIONS_HINT, ".agents/devkit/" + DURATIONS_HINT)


def _is_durations_hint(p):
    return p in DURATIONS_HINT_PATHS
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


def _run(argv, inp=None, text=True, env=None, bounded=True, cwd=None):
    """subprocess.run with a bounded time. On timeout the child is killed and a CompletedProcess with returncode 124 comes back; so it does
    when the shared deadline of the running inventory() is spent (nothing is started then). `bounded=False` for a call that CHANGES the repo or the
    disk (worktree add / remove --force, the temp-index work of `diff`): killed midway it leaves a half checkout or a half-deleted folder."""
    if not bounded:
        return subprocess.run(argv, capture_output=True, text=text, input=inp, env=env, cwd=cwd)
    if _spent():
        return subprocess.CompletedProcess(argv, 124, "" if text else b"", "inventory deadline spent")
    try:
        return subprocess.run(argv, capture_output=True, text=text, input=inp, env=env, timeout=_timeout(), cwd=cwd)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "" if text else b"", "timed out")


def git(cwd, *args, check=True, env=None, inp=None, bounded=True):
    r = _run(["git", "-C", cwd, *args], inp=inp, text=inp is None or isinstance(inp, str), env=env, bounded=bounded)
    if check and r.returncode != 0:
        err = r.stderr if isinstance(r.stderr, str) else r.stderr.decode("utf-8", "replace")
        raise SystemExit(f"✖ worktree: git {' '.join(args[:2])}: {err.strip()}")
    return r


def _merge_tree(repo, attr_tree, *args):
    """`git merge-tree --write-tree <args>` for `repo`, run with a scratch cwd. An external merge driver (the matrix driver) writes its
    `.merge_file_*` temp files into git's cwd, and a probe killed by its time budget leaves them there: three files in the main checkout
    per kill (#309). `--git-dir` + `--attr-source=<attr_tree>` keep the repo's own attributes, so the driver still applies and the verdict is
    the one `git -C repo merge-tree` gave. Trouble finding the git dir: the CompletedProcess of that failed call.
    git 2.40 / 2.41 take `merge-tree --write-tree` but not `--attr-source` (exit 129, "unknown option"): the probe then runs again as plain
    `git -C repo merge-tree` (cwd = repo, as before #309), because "cannot say" would refuse a worktree or branch whose work is in the trunk (#358)."""
    gd = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir", check=False)
    if gd.returncode != 0 or not gd.stdout.strip():
        return gd
    with tempfile.TemporaryDirectory(prefix="devkit-merge-tree-") as scratch:
        r = _run(["git", f"--git-dir={gd.stdout.strip()}", f"--attr-source={attr_tree}", "merge-tree", "--write-tree", *args], cwd=scratch)
    if r.returncode == 129 and "attr-source" in (r.stderr or ""):
        return _run(["git", "-C", repo, "merge-tree", "--write-tree", *args])
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


def _write_state(wt, state):
    """devkit-worktree.json, replaced in one step: a Stop hook of another session reads it while `add` is still setting the worktree up."""
    path = os.path.join(git_dir(wt), STATE)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


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
        elif t == "locked" or t.startswith("locked "):
            cur["locked"] = t[len("locked "):]   # K11: lý do khoá ("" khi không có), đọc bởi kept_lock
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


def _into_kit(main, path):
    """True khi `path` (đi theo mọi link) nằm trong thư mục kit của main: universal-agent-devkit/ hoặc .agents/devkit/."""
    target = os.path.realpath(path)
    for kit in ("universal-agent-devkit", os.path.join(".agents", "devkit")):
        root = os.path.realpath(os.path.join(main, kit))
        if target == root or target.startswith(root + os.sep):
            return True
    return False


def _kit_link(wt, main, rel):
    """True when `rel` is an UNTRACKED symlink the DevKit installer or `heal` made: it points into the main checkout's own kit folder
    (universal-agent-devkit/ or .agents/devkit/). That is install state, never work. `heal` adds such a link later than the setup
    snapshot (a kit update brings a new hook) and main may lack that one, so neither the baseline nor _same_in_main vouched for it:
    `remove` kept the worktree and `finish` refused "a new symlink" for the user to clean by hand (agent-workbench 2026-10-17). A
    TRACKED path the user replaced by such a link (a type change) is still work: only an untracked one counts as setup."""
    path = os.path.join(wt, rel)
    if not os.path.islink(path) or not _into_kit(main, path):
        return False
    # Untracked means in NEITHER the index nor HEAD (`git rm f` then a link at f: gone from the index, still a type change from HEAD).
    # Only rc 1 of ls-files ("did not match any file known to git") and an empty, successful ls-tree prove it: a timeout (124) or a
    # git failure (128) is "cannot say" = work.
    lit = dict(os.environ, GIT_LITERAL_PATHSPECS="1")
    if git(wt, "ls-files", "--error-unmatch", "--", rel, check=False, env=lit).returncode != 1:
        return False
    head = git(wt, "ls-tree", "-z", "HEAD", "--", rel, check=False, env=lit)
    return head.returncode == 0 and not head.stdout


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


AUTOMERGE_SKIP = (".claude/", ".gemini/", ".idea/", ".vscode/", ".agents/devkit")   # harness and DevKit files: never "the work"


def _adopted_state(wt):
    """A state for a worktree `agent-kit worktree add` did not make (EnterWorktree, a subagent's isolated worktree, a plain `git
    worktree add`): it has no devkit-worktree.json, and `diff` / `remove` used to refuse it outright, so the Stop gate told the agent
    to run a command that could never succeed and the worktree stayed behind for the user to delete (OfficeReader 2026-10-08). The
    adopted state lives for one command and is never written: base = where the worktree left main; the only "setup" are
    harness / DevKit files (AUTOMERGE_SKIP) that main holds with the SAME bytes (a copy of its own local settings); everything else -
    an edited agent definition, a new agent-memory note under .claude/ - is work (review 2026-10-08: calling every dirty .claude/ path
    "setup" removed such a worktree and its work silently)."""
    main = main_checkout(wt)
    main_head = git(main, "rev-parse", "HEAD").stdout.strip()
    base = git(wt, "merge-base", main_head, "HEAD", check=False).stdout.strip() or git(wt, "rev-parse", "HEAD").stdout.strip()
    branch = git(wt, "symbolic-ref", "-q", "--short", "HEAD", check=False).stdout.strip() or None
    baseline = {p: fp for p, fp in snapshot(wt).items() if p.startswith(AUTOMERGE_SKIP) and _same_in_main(wt, main, p)}
    return {"base": base, "baseline": baseline, "branch": branch, "fp": FP_VERSION, "adopted": True}


def _has_state_file(wt):
    """True when something sits where the worktree's devkit-worktree.json belongs - a corrupt file, a FIFO an agent planted, a symlink - or
    when git cannot say. Only an ABSENT file lets a worktree be adopted: a state that is there and unreadable must never read as "no setup"."""
    try:
        return os.path.lexists(os.path.join(git_dir(wt), STATE))
    except SystemExit:
        return True


def load_state(wt):
    if not os.path.isdir(wt):
        die(tr(f"không có thư mục: {wt}", f"no such directory: {wt}"))
    try:
        return _read_state(wt)
    except (OSError, ValueError, SystemExit):
        if _has_state_file(wt):
            die(tr(f"{wt} không được tạo bằng 'agent-kit worktree add' (thiếu {STATE})",
                   f"{wt} was not made by 'agent-kit worktree add' (no {STATE})"))
        return _adopted_state(wt)


ESSENTIALS_START = "<!-- devkit-essentials:start"   # scripts/governance/context_sync.py MARK_START / MARK_END
ESSENTIALS_END = "<!-- devkit-essentials:end -->"


def _outside_essentials(text):
    """`text` without the DevKit-generated essentials section (the start/end marker lines stay), or None when it has no intact pair."""
    i = text.find(ESSENTIALS_START)
    j = text.find(ESSENTIALS_END, i) if i >= 0 else -1
    if i < 0 or j < 0:
        return None
    eol = text.find("\n", i)
    keep = j if eol < 0 or eol > j else eol + 1
    return text[:keep] + text[j:]


def _essentials_block_only(wt):
    """True when the tracked AGENTS.md differs from HEAD's ONLY inside the devkit-essentials block that context_sync.py generates: the
    installer run in a lane / merge-gate scratch worktree rewrites it (#234), and it is no work. Anything else (a symlink, no markers on
    either side, a byte outside the block, a git error) is False: the file counts as work, as before."""
    path = os.path.join(wt, "AGENTS.md")
    try:
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        with open(path, encoding="utf-8", newline="") as f:
            now = f.read()
        head = git(wt, "show", "HEAD:AGENTS.md", check=False)
        if head.returncode != 0:
            return False
        a, b = _outside_essentials(now), _outside_essentials(head.stdout)
    except (OSError, UnicodeError, SystemExit):
        return False
    return a is not None and a == b


def changes_since(wt, state):
    """Uncommitted paths whose content differs from the recorded setup. A state written before the executable bit was part of
    the fingerprint (no "fp" marker) holds "F:<sha>" for every file: for those, the bit is not compared."""
    base, exact = state["baseline"], state.get("fp") == FP_VERSION
    moved = [p for p, fp in snapshot(wt).items()
             if base.get(p) != fp and (exact or not (fp.startswith("F:") and fp.endswith(":x")) or base.get(p) != fp[:-2])]
    moved = [p for p in moved if not (p == "AGENTS.md" and _essentials_block_only(wt))]   # #234: the DevKit's own generated block is install state
    if not any(os.path.islink(os.path.join(wt, p)) for p in moved):
        return sorted(moved)
    main = main_checkout(wt)   # one place for diff / status / inventory / finish / remove: DevKit's own links into main's kit are not work
    return sorted(p for p in moved if not _kit_link(wt, main, p))


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
    old_umask = os.umask(0o077)   # shutil.copy creates the file with the umask's mode and fixes it afterwards: a keystore is never readable by others in between
    try:
        shutil.copy(src, dst)   # content + mode, NOT copy2: it carries macOS flags, and a copy of a keystore locked with `chflags uchg` could never be deleted
    finally:
        os.umask(old_umask)
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


HOOKS_DIR = ".claude/hooks"


def copy_local_hooks(main, wt):
    """agent-workbench#93 (19/10): the hooks of main's .claude/hooks/ that git ignores — the DevKit's links, and the user's own guards
    (guard-*.py, cleanup-wt.py) that the project's AND the user's settings (~/.claude*/settings.json) run under $CLAUDE_PROJECT_DIR. A
    worktree holds tracked files only, so a session started there runs a missing file for each (python3 on it exits 2: the tool is
    blocked) and `health` FAILs on "registered hooks missing". Mirror each top-level one the worktree lacks or holds as a dangling link: a
    file is copied (bytes + mode, never the BSD flags: INSTINCT-038), a link is made again to the file it really reaches (a relative one
    copied as-is dangles one folder deeper: NFH #18). Only where git ignores it in the worktree too and does not track it there."""
    out = git(main, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--", HOOKS_DIR + "/", check=False).stdout
    done = []
    for rel in out.split("\0"):
        if not rel or os.path.dirname(rel) != HOOKS_DIR:   # top level only: a cache folder (__pycache__/) holds no hook
            continue
        src, dst = os.path.join(main, rel), os.path.join(wt, rel)
        if os.path.exists(dst) or not os.path.isfile(src):   # a working file or link stays; a dangling one in main has nothing to give
            continue
        if git(wt, "check-ignore", "-q", "--no-index", "--", rel, check=False).returncode != 0 \
                or git(wt, "ls-files", "--error-unmatch", "--", rel, check=False).returncode == 0:
            continue
        try:
            if os.path.islink(dst):
                os.unlink(dst)   # dangling (exists() follows the link)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(src):
                os.symlink(os.path.realpath(src), dst)
            else:
                shutil.copy(src, dst)   # content + mode, NOT copy2 (flags)
            done.append(rel)
        except OSError as e:   # a race with another heal, a read-only folder: named, the other hooks still go
            print("• " + tr(f"không chép được {rel}: {e}", f"{rel} not copied: {e}"))
    return done


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


def copy_meta_assets(main, wt):
    """K2 (Goods 17/10, Unity): `<file>.meta` được track nhưng chính file đó bị git ignore (`*.dll.mdb`): worktree mới chỉ có file
    track nên thiếu nó, Unity xoá `.meta` mồ côi (kèm sinh `.vscode/`, `*.slnx`) và `finish` thấy worktree "đổi" rồi có thể commit
    rác đó vào main. Chép từ main đúng những file đó (_copy: chỉ file thường, chỉ khi worktree chưa có và cũng ignore nó, nên không
    bao giờ commit được). Tên file đọc dạng bytes: một tên không phải UTF-8 không làm `add` chết.
    ponytail: chỉ file, không chép thư mục bị ignore có `.meta` được track (chưa gặp); chép từng byte, thêm clonefile khi gặp file lớn."""
    r = _git_bytes(main, "ls-files", "-z", "--", "*.meta")
    if r.returncode != 0:
        return []
    cands = [m[:-5] for m in r.stdout.decode("utf-8", "surrogateescape").split("\0")
             if m.endswith(".meta") and len(m) > 5 and os.path.isfile(os.path.join(main, m[:-5])) and not os.path.lexists(os.path.join(wt, m[:-5]))]
    if not cands:
        return []
    # "./": một tên bắt đầu bằng ':' không bị đọc thành pathspec magic (như _carry_secrets)
    r = _git_bytes(main, "check-ignore", "-z", "--stdin", inp="".join("./" + p + "\0" for p in cands).encode("utf-8", "surrogateescape"))
    ignored = {p[2:] for p in r.stdout.decode("utf-8", "surrogateescape").split("\0") if p} if r.returncode in (0, 1) else set()
    return [rel for rel in cands if rel in ignored and _copy(main, wt, rel)]


# Where the Editor keeps its lock files in a Library (ArtifactDB-lock, SourceAssetDB-lock, DataStore/uds.lock, Search/<x>.index-lock): a copy
# holding them makes Unity in the worktree see the project as open in another Editor. Only these folders: nothing deeper is touched.
UNITY_LOCK_DIRS = ("", "DataStore", "Search")


def copy_unity_library(main, wt):
    """W1 R6: the Library of each Unity project of the main checkout (the root, or one level down: Neighbours keeps it in unity/) - GBs
    that git ignores, so a new worktree had none and Unity re-imported everything (tens of minutes) - is cloned with `cp -Rc` (APFS
    clonefile: no data copied, ~0 disk until a file changes). clonefile keeps the BSD user flags, and a uchg file makes the worktree
    undeletable (INSTINCT-038), so the copy gets `chflags -R nouchg,nouappnd` (no symlink followed: -P is chflags -R's default); the
    Editor's lock files are dropped from it. No clonefile here (not macOS, not APFS, the worktree on another volume than the main checkout - `cp -c`
    then silently copies every byte): nothing copied - a full copy would fill the disk.
    A Library git tracks, or one the worktree already has, is left alone. ponytail: an Editor writing the main Library while it is
    cloned can leave the copy mid-update (Unity then re-imports what it doubts); clone with the Editor closed if that is ever seen.
    Returns the cloned Library paths, relative."""
    if sys.platform != "darwin":
        return []
    # Hai worktree không cp -Rc cùng lúc. Khóa này tách khỏi khóa batch của Editor.
    # Không mở được file khóa thì vẫn copy. st_dev khác volume vẫn không copy.
    lock_fd = None
    try:
        import fcntl
        lock_path = os.environ.get("UNITY_LIBRARY_COPY_LOCK") or os.path.join(
            os.path.expanduser("~"), ".config", "universal-agent-devkit", "unity-library-copy.lock")
        os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
        lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except OSError:
        if lock_fd is not None:
            try:
                os.close(lock_fd)
            except OSError:
                pass
        lock_fd = None
    try:
        return _copy_unity_library_body(main, wt)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)


def _copy_unity_library_body(main, wt):
    cands = [""] + sorted(d for d in os.listdir(main) if not d.startswith(".") and os.path.isdir(os.path.join(main, d)))
    out = []
    for rel in cands:
        lib = os.path.join(rel, "Library") if rel else "Library"
        src, dst = os.path.join(main, lib), os.path.join(wt, lib)
        if not os.path.isfile(os.path.join(main, rel, "ProjectSettings", "ProjectVersion.txt")) or not os.path.isdir(src) \
                or os.path.lexists(dst) or os.path.islink(src):
            continue
        if git(main, "check-ignore", "-q", lib + "/", check=False).returncode != 0:
            continue   # tracked (or not ignored): git's business
        if os.stat(src).st_dev != os.stat(wt).st_dev:   # another volume: `cp -c` does not fail there, it copies every byte (measured 14/10: 300 MB -> rc 0, 302 MB used)
            print("• " + tr(f"không clone {lib}: worktree ở volume khác (cp -c sẽ chép từng byte, hàng GB): Unity sẽ import lại trong worktree",
                            f"{lib} not cloned: the worktree is on another volume (cp -c would copy every byte, GBs): Unity re-imports it in the worktree"))
            continue
        os.makedirs(os.path.dirname(dst) or wt, exist_ok=True)
        r = _run(["cp", "-Rc", src, dst], bounded=False)
        if r.returncode != 0:
            if os.path.lexists(dst):   # what it cloned before failing keeps uchg: rmtree cannot delete it (and ignore_errors says nothing)
                _run(["chflags", "-R", "nouchg,nouappnd", dst], bounded=False)
            shutil.rmtree(dst, ignore_errors=True)
            print("• " + tr(f"không clone được {lib} (clonefile không có ở đây?): Unity sẽ import lại trong worktree",
                            f"{lib} could not be cloned (no clonefile here?): Unity re-imports it in the worktree"))
            continue
        _run(["chflags", "-R", "nouchg,nouappnd", dst], bounded=False)
        for sub in UNITY_LOCK_DIRS:
            d = os.path.join(dst, sub)
            for name in os.listdir(d) if os.path.isdir(d) else ():
                if name.endswith(("-lock", ".lock")) and os.path.isfile(os.path.join(d, name)):
                    os.unlink(os.path.join(d, name))
        out.append(lib)
    return out


def share_main_memory(main, wt):
    """(only for `worktree add --share-memory`) Point the worktree's Claude auto-memory at the main checkout's: .claude/settings.local.json
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
    try:
        with open(profile_file(main)) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data = data if isinstance(data, dict) else {}
    profile = profile or data.get("profile") or "auto"
    # main's lang, never the caller's DEVKIT_LANG: the installer writes it into the TRACKED active-profile.json (a lane with
    # DEVKIT_LANG=en in a vi repo left it modified, and the Builder's commit carried it into the PR; agent-workbench#93)
    lang = data.get("lang") if data.get("lang") in ("en", "vi") else None
    agents = [a for a, marker in AGENT_MARKERS if os.path.exists(os.path.join(main, marker))] or ["claude"]
    mode = "symlink" if (os.path.islink(os.path.join(main, ".agents", "devkit"))
                         or os.path.islink(os.path.join(main, "AGENTS.md"))) else "copy"   # 1.2: AGENTS.md was the link
    return ["bash", os.path.join(DEVKIT, "bin", "install.sh"), f"--target={wt}", "--domain=auto",
            f"--mode={mode}", "-y", "--no-githooks", "-p", profile, "-a", ",".join(agents)] + ([f"--lang={lang}"] if lang else [])


def _env_limit(name, default):
    """A non-negative number from the environment, 0 = off; anything else (not a number, negative, nan, inf) = the default."""
    try:
        v = float(os.environ.get(name, default))
    except ValueError:
        return default
    return v if 0 <= v < 1e9 else default


# W1 R5c (docs/workflow-improvements.md I.0): `add` runs `gc` and warns under the warning line, creates nothing under the floor, and
# keeps at most WORKTREE_MAX linked worktrees per repo. 0 turns each off. SessionStart (hooks/session_context.sh) reads the same numbers.
DISK_WARN_GIB = _env_limit("WORKTREE_DISK_WARN_GIB", 10.0)
DISK_MIN_GIB = _env_limit("WORKTREE_DISK_MIN_GIB", 3.0)
WORKTREE_MAX = _env_limit("WORKTREE_MAX", 3)
WORKTREE_MAX = int(WORKTREE_MAX) if WORKTREE_MAX == int(WORKTREE_MAX) else 3   # 0.5 is no number of worktrees, and not "off"
NO_ROOM = 4   # add's exit code when it refuses for want of room (disk or cap): what a hook that creates worktrees tells apart from a usage error
ADD_LOCK = "devkit-worktree-add.lock"
ADD_LOCK_WAIT_S = 600.0


def free_gib(path):
    """Free space (GiB) of the volume `path` — or its nearest existing parent — lives on; None when it cannot be read."""
    while path and not os.path.exists(path) and os.path.dirname(path) != path:
        path = os.path.dirname(path)
    try:
        return shutil.disk_usage(path).free / 2 ** 30
    except OSError:
        return None


def _make_room(main, wt):
    """Under DISK_WARN_GIB free: `gc` (the leftovers git no longer knows), then a warning; still under DISK_MIN_GIB: refuse (NO_ROOM)."""
    free = free_gib(wt)
    if free is None:
        print("• " + tr("không đọc được dung lượng đĩa trống; bỏ qua kiểm đĩa", "cannot read the free disk space; disk check skipped"))
        return
    if free >= max(DISK_WARN_GIB, DISK_MIN_GIB):   # each line holds on its own: the floor still applies with the warning off
        return
    cmd_gc(main, ["--log=" + os.path.join(main, ".claude", "audit-gate", "worktree_gc.log")])   # silent when another gc of this repo runs
    free = free_gib(wt)
    if free is None:   # as on the first read: cannot say, so no refusal
        return
    if free < DISK_MIN_GIB:
        die(tr(f"đĩa chỉ còn {free:.1f} GiB trống (dưới {DISK_MIN_GIB:g} GiB, đã chạy worktree gc): không tạo worktree mới — "
               "xoá build/cache cũ (build/, .gradle/, node_modules/, DerivedData) rồi chạy lại",
               f"only {free:.1f} GiB free on the disk (under {DISK_MIN_GIB:g} GiB, worktree gc ran): no new worktree — "
               "delete old build output and caches (build/, .gradle/, node_modules/, DerivedData), then run it again"), NO_ROOM)
    if free < DISK_WARN_GIB:
        print("⚠ " + tr(f"đĩa còn {free:.1f} GiB trống sau worktree gc (dưới {DISK_WARN_GIB:g} GiB): dọn build/cache cũ sớm",
                        f"{free:.1f} GiB free on the disk after worktree gc (under {DISK_WARN_GIB:g} GiB): clear old build output and caches soon"))


def _live_worktrees(main):
    """The linked worktrees that hold a slot: registered with a folder on disk. A red_proof sandbox (red-proof-*, removed by the run that
    made it), a merge-gate proof tree (.merge-scratch-*, #155: a SIGKILLed gate leaves it behind), a super-board worktree (K7:
    board_worktree) and a registration whose folder is gone (prunable) take none."""
    return [e["path"] for e in _worktree_entries(main)[1:]
            if not e["broken"] and os.path.isdir(e["path"])
            and not os.path.basename(e["path"]).startswith(("red-proof-", ".merge-scratch-"))
            and not board_worktree(e["path"], e["branch"] or "")]


BOARD_WT_RE = re.compile(r"issue-[0-9]+(-(build|qa|review))?")


def board_worktree(path, branch=None):
    """K1/K7 (18/10): worktree của super-board — `.claude/worktrees/issue-<N>[-build|-qa|-review]` (hoặc `.worktrees/issue-<N>` kiểu cũ),
    đúng mẫu tên mà super-board-run.sh quét, VÀ đang ở một nhánh có tên (board luôn dùng `issue-<N>-<slug>` / `loop/issue-N`; một
    EnterWorktree(name="issue-42") của phiên thường là detached nên vẫn là nợ, review 18/10). Runner và lane của board quản lý nó và gộp
    qua PR + merge gate: không phải nợ của phiên khác (không tự gộp vào main local, không giữ Stop), không chiếm chỗ WORKTREE_MAX.
    Worktree detached đúng mẫu tên chỉ là của board khi `add --lane` tạo nó (state ghi "board": checkout review/qa của lane, #93).
    branch None: đọc từ git."""
    if not _board_path(path):
        return False
    if branch is None:
        branch = git(path, "symbolic-ref", "-q", "--short", "HEAD", check=False).stdout.strip() if os.path.isdir(path) else ""
    if branch:
        return True
    try:
        return _read_state(path).get("board") is True
    except (OSError, ValueError, SystemExit):   # không state / không đọc được: như trước, nợ của phiên (K7)
        return False


def _board_path(path):
    """`.claude/worktrees/issue-<N>[-build|-qa|-review]` hoặc `.worktrees/issue-<N>…` kiểu cũ: mẫu tên super-board-run.sh quét."""
    p = os.path.normpath(path)
    parent, grand = os.path.basename(os.path.dirname(p)), os.path.basename(os.path.dirname(os.path.dirname(p)))
    return (parent == ".worktrees" or (parent == "worktrees" and grand == ".claude")) and bool(BOARD_WT_RE.fullmatch(os.path.basename(p)))


def published_branch(wt):
    """Tên nhánh của worktree khi nó đã PUBLISH (có ref remote cùng tên hoặc upstream); '' khi detached / chưa publish. automerge không bao
    giờ tự gộp nhánh như vậy (gộp bằng PR), nên nó cũng không thành nợ của phiên khác (K1)."""
    b = git(wt, "symbolic-ref", "-q", "--short", "HEAD", check=False).stdout.strip()
    if b and (git(wt, "for-each-ref", "--format=%(refname)", f"refs/remotes/*/{b}", check=False).stdout.strip()
              or git(wt, "config", "--get", f"branch.{b}.remote", check=False).stdout.strip()):
        return b
    return ""


def unpushed_or_dirty(wt):
    """True khi worktree còn commit không ref remote nào giữ, hoặc file chưa commit (chưa track tính, bị ignore thì không); lỗi git: True
    (không nói được = coi là còn việc). Chỉ để báo, không chặn (K1, OCR 18/10)."""
    ahead = git(wt, "rev-list", "-1", "HEAD", "--not", "--remotes", check=False)
    dirty = git(wt, "status", "--porcelain", check=False)
    return bool(ahead.returncode or dirty.returncode or ahead.stdout.strip() or dirty.stdout.strip())


KEPT_LOCK_RE = re.compile(r"devkit-kept session=([A-Za-z0-9][A-Za-z0-9._-]{0,127}) pid=([0-9]{1,10})")


def kept_lock(main, wt):
    """K11 (18/10): khoá `git worktree lock` mà hooks/session_worktree.py đặt khi phiên rời worktree bằng ExitWorktree "keep" — (session, pid,
    còn sống?) hoặc None. Còn sống: pid tiến trình claude của phiên đó trả lời (os.kill 0); không đủ quyền / lỗi khác thì coi là sống (giữ lại)."""
    try:
        entries = _worktree_entries(main)
    except SystemExit:
        return None
    for e in entries[1:]:
        if not e["broken"] and _same_path(e["path"], wt):
            m = KEPT_LOCK_RE.fullmatch(e.get("locked") or "")
            if not m:
                return None
            pid = int(m.group(2))
            if pid <= 1:   # pid 0/1 không bao giờ là phiên (os.kill(0) báo nhóm tiến trình của chính mình, pid 1 PermissionError): khoá vô hiệu
                return m.group(1), pid, False
            try:
                os.kill(pid, 0)
                alive = True
            except ProcessLookupError:
                alive = False
            except (OSError, OverflowError):   # PermissionError: tiến trình của người khác vẫn sống; còn lại: không biết = giữ
                alive = True
            return m.group(1), pid, alive
    return None


def _drop_dead_kept_lock(main, wt):
    """Khoá devkit-kept của một pid đã chết, hoặc của CHÍNH phiên đang gọi (pid là tổ tiên của tiến trình này: phiên GeelyEx2 18/10 rời bằng
    keep rồi tự gỡ worktree của mình và bị git từ chối), không giữ gì nữa: mở khoá để gỡ được (luật không-mất-việc của người gọi vẫn áp dụng).
    Trả lý do khoá đã mở (để đặt lại khi việc gỡ hỏng), None khi không mở gì."""
    k = kept_lock(main, wt)
    if k and (not k[2] or k[1] in _ancestor_pids()) and git(main, "worktree", "unlock", wt, check=False).returncode == 0:
        return f"devkit-kept session={k[0]} pid={k[1]}"
    return None


def _ancestor_pids():
    """pid của tiến trình này và các tổ tiên của nó, DỪNG ở tiến trình `claude` gần nhất (tiến trình của phiên, pid mà hook ghi vào khoá
    devkit-kept): phía trên nó là tiến trình mọi phiên dùng chung (app Claude, terminal, launchd), một khoá mang pid đó không được thành
    "của mình" với mọi phiên. Hỏi `ps` (macOS không có /proc); `ps` lỗi: chỉ những pid đã biết, không bao giờ thêm pid lạ."""
    pids, pid = {os.getpid()}, os.getppid()
    for _ in range(64):
        if pid <= 1 or pid in pids:
            break
        pids.add(pid)
        r = _run(["ps", "-ww", "-o", "ppid=,comm=", "-p", str(pid)])   # -ww: không cắt cột comm theo bề rộng terminal (audit T0044)
        ppid, _sp, comm = (r.stdout.strip() if r.returncode == 0 else "").partition(" ")
        if os.path.basename(comm.strip()) == "claude" or not ppid.isdigit():
            break
        pid = int(ppid)
    return pids


def _trunk_mode(path):
    """hooks/session_worktree.py trunk_mode(): no `devkit.trunkMode` key (the default) or `true`, and WORKTREE_TRUNK_MODE not 0 (W1 R1/R7 v6).
    Any failure to tell: False, the old behaviour."""
    hooks = os.path.join(DEVKIT, "hooks")
    if hooks not in sys.path:
        sys.path.append(hooks)   # after the stdlib: nothing in hooks/ may shadow it
    try:
        import session_worktree  # noqa: PLC0415 - only where trunk mode matters
        return session_worktree.trunk_mode(path)
    except Exception:  # noqa: BLE001 - a module that cannot be read means the old behaviour, never an add that dies
        return False


SESSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
PROVISIONAL_TTL_S = 900.0   # a set-up that has not finished in 15 min crashed: its provisional state is ignored (the worktree is adopted)


LANES = ("build", "qa", "review")   # super-board lanes (run.md): `add --lane` (agent-workbench#93)


def _reuse_lane(main, wt, branch, base, lane, no_init=False, profile=None):
    """`add --lane` at a path that already is a registered worktree of this repo — the Builder resuming a card super-board-run.sh moved
    back to Ready keeps its issue-<N>-build worktree: set it up again (heal: DevKit links, local config, hooks) instead of refusing a
    non-empty folder. Never a folder git does not know, nor one on another branch than the one asked for. A detached one (the Reviewer's
    checkout) is moved to --base — a stale PR head is no review — and marked the board's, only when it holds no work (OCR 19/10)."""
    entry = next((e for e in _worktree_entries(main)[1:] if not e["broken"] and _same_path(e["path"], wt)), None)
    if entry is None:
        die(tr(f"{wt} đã có, không rỗng và không phải worktree đã đăng ký của repo này: kiểm tra nó, không xoá",
               f"{wt} exists, is not empty and is no registered worktree of this repo: inspect it, never delete it"))
    if (branch or None) != (entry["branch"] or None):   # both ways: a detached checkout asked of a worktree on a branch would move it off it
        die(tr(f"{wt} là worktree của {entry['branch'] or 'một HEAD detached'}, không phải của {branch or 'một HEAD detached'}",
               f"{wt} is the worktree of {entry['branch'] or 'a detached HEAD'}, not of {branch or 'a detached HEAD'}"))
    state = None
    if not branch:
        state = load_state(wt)   # dies on a state file that is there and unreadable; none at all: the adopted reading
        unique = git(wt, "rev-list", "-1", "HEAD", "--not", "--branches", "--remotes", "--tags", check=False)
        if unique.returncode == 0 and unique.stdout.strip() and state.get("board") \
                and git(wt, "rev-parse", "HEAD", check=False).stdout.strip() == state.get("base"):
            unique.stdout = ""   # still at the PR head add/reuse put it on, which a force-push left unreferenced: nothing made here (OCR 19/10)
        held = changes_since(wt, state)
        if held or unique.returncode or unique.stdout.strip():
            die(tr(f"{wt} còn việc (chưa commit: {', '.join(held[:5]) or '-'}; commit không ref nào giữ: {unique.stdout.strip()[:10] or '-'}): "
                   "không dời, không đánh dấu; kiểm tra nó",
                   f"{wt} holds work (uncommitted: {', '.join(held[:5]) or '-'}; a commit no ref holds: {unique.stdout.strip()[:10] or '-'}): "
                   "not moved, not marked; inspect it"))
        if base:
            git(wt, "checkout", "-q", "--detach", base, bounded=False)
    # one an old plain `git worktree add` made has no DevKit and no Library at all: set them up as add does (each step leaves what is there)
    copy_unity_library(main, wt)
    ran = install_args(main, wt, profile) if not no_init else None
    if ran:
        r = subprocess.run(ran, capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout[-2000:] + r.stderr[-2000:])
            die(tr(f"cài DevKit vào worktree lane thất bại (exit {r.returncode}); worktree vẫn ở {wt}",
                   f"DevKit install in the lane worktree failed (exit {r.returncode}); the worktree stays at {wt}"), 1)
    cmd_heal(wt, [])
    if state is not None:
        if state.get("adopted"):   # never written (_adopted_state): a fresh one as add writes it, over a tree that holds no work
            state = {"branch": None, "main": main, "baseline": snapshot(wt), "fp": FP_VERSION}
        state.update(base=git(wt, "rev-parse", "HEAD").stdout.strip(), board=True, lane=lane)
        _write_state(wt, state)
    print(f"✔ worktree {wt}  ({tr('dùng lại worktree lane đã có', 'reused the lane worktree already there')}, "
          f"{tr('nhánh', 'branch') + ' ' + entry['branch'] if entry['branch'] else tr('tách rời (detached)', 'detached')})")
    return 0


def cmd_add(cwd, args):
    base, profile, no_init, share_memory, session, lane, pos = None, None, False, False, None, None, []
    for a in args:
        if a.startswith("--base="):
            base = a.split("=", 1)[1]
        elif a.startswith("--profile="):
            profile = a.split("=", 1)[1]
        elif a == "--no-init":
            no_init = True
        elif a == "--share-memory":
            share_memory = True
        elif a.startswith("--session="):   # the Claude session the worktree is for (the WorktreeCreate hook, W1 R1 v6)
            session = a.split("=", 1)[1]
            if not SESSION_RE.fullmatch(session):
                die(tr(f"--session không hợp lệ: '{session}'", f"invalid --session: '{session}'"))
        elif a.startswith("--lane="):   # a super-board lane worktree (LANES)
            lane = a.split("=", 1)[1]
            if lane not in LANES:
                die(tr(f"--lane không hợp lệ: '{lane}' (build, qa, review)", f"invalid --lane: '{lane}' (build, qa, review)"))
        elif a.startswith("-"):
            die(tr(f"tuỳ chọn không hợp lệ '{a}'", f"unknown option '{a}'")
                + " (--base=REF, --profile=ID, --no-init, --share-memory, --session=ID, --lane=build|qa|review)")
        else:
            pos.append(a)
    if not 1 <= len(pos) <= 2:
        die("usage: agent-kit worktree add <path> [branch] [--base=REF] [--profile=ID] [--no-init] [--share-memory] [--session=ID]"
            " [--lane=build|qa|review]")
    wt = os.path.abspath(os.path.join(cwd, pos[0]))
    branch = pos[1] if len(pos) == 2 else None   # none named: DETACHED (one developer, one branch; the folder name is no branch name)
    if lane and not _board_path(wt):   # the exemptions below are for the board's own folders only
        die(tr(f"--lane chỉ cho worktree của super-board (.claude/worktrees/issue-<N>[-build|-qa|-review]), không cho {wt}",
               f"--lane is for super-board worktrees only (.claude/worktrees/issue-<N>[-build|-qa|-review]), not {wt}"))
    main = main_checkout(cwd)
    if lane and os.path.realpath(os.path.dirname(wt)) != os.path.realpath(os.path.join(main, ".claude", "worktrees")):
        # the folder the runner and the board scan, of the MAIN checkout: a relative path from inside a session's own worktree would nest the
        # lane there (that worktree could then never be removed) and a legacy .worktrees/ one stops the runner (check_legacy_worktrees)
        die(tr(f"--lane: worktree phải nằm ngay trong {os.path.join(main, '.claude', 'worktrees')}, không phải {wt}",
               f"--lane: the worktree must sit right in {os.path.join(main, '.claude', 'worktrees')}, not at {wt}"))
    if os.path.exists(wt) and os.listdir(wt):
        if lane:
            return _reuse_lane(main, wt, branch, base, lane, no_init, profile)
        die(tr(f"{wt} đã có và không rỗng", f"{wt} exists and is not empty"))
    holder = next((e["path"] for e in _worktree_entries(main)[1:] if lane and branch and e["branch"] == branch), None)
    if holder:   # git's own "already used by worktree" names no way out; the Tester behind a Builder's leftover worktree needs one
        # agent-kit (kit) chứ không `git worktree remove` trần: git trần từ chối dấu vết cài DevKit mà worktree lane nào cũng có (AGENTS.md
        # sinh lại, hook link vào kit) dù không mất gì — 11 thẻ Blocked 20/10; kit chỉ từ chối (✖) khi có việc sẽ mất
        die(tr(f"nhánh {branch} đang được checkout ở {holder}: gỡ worktree đó trước (`agent-kit worktree remove {holder}`; bị từ chối (✖) = nó "
               "còn việc: chặn thẻ, ghi tên nó), rồi chạy lại",
               f"the branch {branch} is checked out at {holder}: remove that worktree first (`agent-kit worktree remove {holder}`; refused (✖) = it "
               "still holds work: block the card naming it), then run this again"), 1)
    origin_has = None   # does origin hold the issue branch: None = not asked (a local branch, no origin remote)
    if lane and branch and git(main, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}", check=False).returncode != 0 \
            and git(main, "remote", "get-url", "origin", check=False).returncode == 0:
        # the issue branch an earlier lane pushed and this clone has no local copy of: refresh origin/<branch> (outside the add lock: the
        # network) so the worktree starts from it below. Only "origin has no such branch" (ls-remote exit 2) makes a new one: offline or a
        # failed fetch must never start an empty branch off the base that the lane then pushes over the PR (review 19/10)
        probe = git(main, "ls-remote", "--exit-code", "--heads", "origin", f"refs/heads/{branch}", check=False)
        origin_has = probe.returncode == 0
        if probe.returncode == 0:
            fetched = git(main, "fetch", "--quiet", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}", check=False)
            if fetched.returncode != 0:
                die(tr(f"origin có nhánh {branch} nhưng fetch hỏng: {fetched.stderr.strip()[-300:]}",
                       f"origin has the branch {branch} but the fetch failed: {fetched.stderr.strip()[-300:]}"), 1)
        elif probe.returncode != 2:
            die(tr(f"không hỏi được origin có nhánh {branch} không (ls-remote exit {probe.returncode}): không tạo nhánh mới khi chưa biết",
                   f"cannot ask origin whether it has the branch {branch} (ls-remote exit {probe.returncode}): no new branch while that is unknown"), 1)
    _make_room(main, wt)
    common = os.path.realpath(git(main, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    try:   # count + add: one at a time per repo
        lock = _lock_file(os.path.join(common, ADD_LOCK), wait=ADD_LOCK_WAIT_S,
                          waiting=tr("chờ một lệnh worktree add khác của repo này…", "waiting for another worktree add in this repo…")) if WORKTREE_MAX else None
    except OSError as e:
        die(tr(f"không mở được khoá {ADD_LOCK} ({e})", f"cannot open the lock {ADD_LOCK} ({e})"), 1)
    if WORKTREE_MAX and lock is None:
        die(tr(f"một lệnh worktree add khác của repo này đã chạy quá {ADD_LOCK_WAIT_S / 60:g} phút; chạy lại sau",
               f"another worktree add in this repo has run for over {ADD_LOCK_WAIT_S / 60:g} minutes; run it again later"), 1)
    # W1 R1 v6 item 6: in trunk mode every live session has its worktree (and its subagents theirs, as the harness always made them with
    # no cap), so a session's own worktree takes no slot - the disk floor (_make_room) still applies. A fixed cap of 3 would leave the 4th
    # session nowhere to write: main is merge-only there.
    # A super-board lane (--lane) takes no slot either (board_worktree): the runner keeps at most one worker per lane, and a cap filled by
    # sessions' worktrees refused every lane with exit 4 while the board waited (agent-workbench#93: 7 ordinary worktrees in the workbench).
    capped = WORKTREE_MAX and not (session and _trunk_mode(main)) and not lane
    try:
        live = _live_worktrees(main) if capped else []
        if len(live) >= WORKTREE_MAX > 0:   # never "finish someone else's": a clean worktree may be a live session's that has not edited yet
            die(tr(f"repo đã có {len(live)} worktree (tối đa {WORKTREE_MAX}): {', '.join(live)} — chỉ gộp và gỡ worktree do CHÍNH phiên "
                   "này tạo mà đã xong (`agent-kit worktree finish <path>`); worktree của phiên khác, kể cả đang sạch, thì để yên và "
                   "chờ nó xong",
                   f"the repo already has {len(live)} worktrees (at most {WORKTREE_MAX}): {', '.join(live)} — merge and remove only a "
                   "finished worktree THIS session made (`agent-kit worktree finish <path>`); leave another session's alone, even a "
                   "clean one, and wait for it to finish"), NO_ROOM)
        if branch is None:
            git(main, "worktree", "add", "--detach", wt, *([base] if base else []), bounded=False)
        elif git(main, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}", check=False).returncode == 0:
            git(main, "worktree", "add", wt, branch, bounded=False)
        else:
            start, track = base, []
            if lane and origin_has is not False \
                    and git(main, "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}^{{commit}}", check=False).returncode == 0:
                # the PR's branch: a new branch off --base would push an empty one over it. Not a remote-tracking ref origin no longer has
                # (a merged and deleted PR branch picked up again: OCR 19/10) - that one would start the lane on an old merged head
                start = f"origin/{branch}"
            elif lane:
                track = ["--no-track"]   # a new issue branch off origin/<base> must not get origin/<base> as upstream (a bare push/pull hits main)
            git(main, "worktree", "add", *track, "-b", branch, wt, *([start] if start else []), bounded=False)
        start = git(wt, "rev-parse", "HEAD").stdout.strip()
        if session or lane:   # W1 v6 item 3: the owner is known from the moment git registers the worktree, not ~10 s later when the set-up
            # is done - until then another session's Stop could take a stateless new worktree for an orphan and merge or remove it under
            # its owner; a lane's detached checkout is the board's (board_worktree) from that moment too
            _write_state(wt, {"branch": branch, "base": start, "main": main, "baseline": {}, "fp": FP_VERSION, "provisional": True,
                              "at": time.time(), **({"session": session} if session else {}),
                              **({"board": True, "lane": lane} if lane else {})})
    finally:
        if lock:
            lock.close()

    copied = copy_local_config(main, wt)
    inputs = copy_build_inputs(main, wt)
    metas = copy_meta_assets(main, wt)   # K2: trước snapshot, nên là một phần của bước dựng
    unity_libs = copy_unity_library(main, wt)   # W1 R6
    ran = install_args(main, wt, profile) if not no_init else None
    if ran:
        r = subprocess.run(ran, capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout[-2000:] + r.stderr[-2000:])
            die(tr(f"cài DevKit vào worktree thất bại (exit {r.returncode}); worktree vẫn ở {wt}",
                   f"DevKit install in the worktree failed (exit {r.returncode}); the worktree stays at {wt}"), 1)
    hooks = copy_local_hooks(main, wt) if not no_init else []   # after the installer: only what it does not link (the user's guards)
    shared = share_main_memory(main, wt) if share_memory and not no_init else False   # only when asked; before the snapshot: it is part of the setup
    state = {"branch": branch, "base": start, "main": main, "baseline": snapshot(wt), "fp": FP_VERSION}
    stamps = _copy_stamps(wt, copied + inputs + metas)
    if stamps:   # what the carry-back must not mistake for a key made here (_ignored_secrets)
        state["copied_sha"] = stamps
    if session:
        state["session"] = session
    if lane:
        state.update(board=True, lane=lane)
    _write_state(wt, state)

    print(f"✔ worktree {wt}  ({tr('nhánh', 'branch') + ' ' + branch if branch else tr('tách rời (detached)', 'detached')} @ {start[:10]})")
    if shared:
        print("  " + tr("auto-memory của Claude dùng chung với main checkout (autoMemoryDirectory)",
                        "Claude auto-memory shared with the main checkout (autoMemoryDirectory)"))
    elif share_memory:
        print("  " + tr("auto-memory của Claude KHÔNG dùng chung (--share-memory): main checkout không có thư mục claude-auto riêng, hoặc worktree đã có giá trị của người dùng, hoặc --no-init",
                        "Claude auto-memory NOT shared (--share-memory): the main checkout has no claude-auto/ folder of its own, the worktree already has a value of the user's, or --no-init"))
    if copied:
        print("  " + tr("đã chép cấu hình cục bộ (bị ignore): ", "copied local config (git-ignored): ") + ", ".join(copied))
    if inputs:
        shown = ", ".join(inputs[:12]) + (f" (+{len(inputs) - 12})" if len(inputs) > 12 else "")
        print("  " + tr("đã chép input build (bị ignore, như red_proof): ",
                        "copied build inputs (git-ignored, as red_proof): ") + shown)
    if metas:
        shown = ", ".join(metas[:12]) + (f" (+{len(metas) - 12})" if len(metas) > 12 else "")
        print("  " + tr("đã chép file bị ignore có .meta được track (Unity): ", "copied git-ignored files whose .meta is tracked (Unity): ") + shown)
    if unity_libs:
        print("  " + tr("đã clone Library của Unity (clonefile, gỡ cờ uchg, bỏ file khoá): ", "Unity Library cloned (clonefile, uchg cleared, locks dropped): ")
              + ", ".join(unity_libs))
    if hooks:
        print("  " + tr("đã chép hook cục bộ (bị ignore) của .claude/hooks/: ", "copied local hooks (git-ignored) of .claude/hooks/: ")
              + ", ".join(os.path.basename(h) for h in hooks))
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
    r = _merge_tree(cwd, main_head, f"--merge-base={base}", main_head, head)
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


def _clean_merges(wt, unheld):
    """#386: the merge commits among `unheld` (commits no ref and not main holds) that carry nothing of their own: every parent is held
    (not in `unheld`) or itself such a merge, and `git show --cc` prints no hunk (a conflict resolution or any edit made in the merge
    would show). Losing one loses no content. Fail closed: over 200 commits, or any git trouble, vouches for none."""
    if not unheld or len(unheld) > 200:
        return set()
    r = git(wt, "rev-list", "--parents", "--no-walk=unsorted", "--stdin", inp="\n".join(sorted(unheld)) + "\n", check=False)
    if r.returncode != 0:
        return set()
    merges = {}
    for line in r.stdout.splitlines():
        sha, *parents = line.split()
        if len(parents) >= 2:
            merges[sha] = parents
    for sha in list(merges):
        shown = git(wt, "show", "--cc", "--format=", "--ignore-submodules=none", sha, check=False)
        if shown.returncode != 0 or shown.stdout.strip():
            del merges[sha]
    ok, grew = set(), True
    while grew:
        grew = False
        for sha, parents in merges.items():
            if sha not in ok and all(p not in unheld or p in ok for p in parents):
                ok.add(sha)
                grew = True
    return ok


def _same_on_origin(wt, paths):
    """#386: the subset of `paths` whose bytes AND executable bit equal the file at the same path on the tip of some origin branch
    (remote-tracking, already fetched): that content is on the remote, a removal loses nothing. Only plain files; any trouble: none."""
    paths = [p for p in paths if "\n" not in p and not p.startswith('"') and os.path.isfile(os.path.join(wt, p)) and not os.path.islink(os.path.join(wt, p))]
    if not paths or len(paths) > 500:
        return set()
    tips = git(wt, "for-each-ref", "--format=%(objectname)", "refs/remotes/origin", check=False)
    if tips.returncode != 0:
        return set()
    h = _git_bytes(wt, "hash-object", "--stdin-paths", inp=("\n".join(paths) + "\n").encode("utf-8", "surrogateescape"))
    ids = h.stdout.decode("utf-8", "surrogateescape").split()
    if h.returncode != 0 or len(ids) != len(paths):
        return set()
    want = {p: (blob, "100755" if os.stat(os.path.join(wt, p)).st_mode & 0o111 else "100644") for p, blob in zip(paths, ids)}
    found = set()
    for tip in dict.fromkeys(tips.stdout.split()):
        left = [p for p in want if p not in found]
        if not left:
            break
        t = git(wt, "ls-tree", "-z", tip, "--", *left, check=False, env=dict(os.environ, GIT_LITERAL_PATHSPECS="1"))
        if t.returncode != 0:
            continue
        for rec in t.stdout.split("\0"):
            meta, _, path = rec.partition("\t")
            parts = meta.split()
            if path in want and len(parts) == 3 and (want[path][1], want[path][0]) == (parts[0], parts[2]):
                found.add(path)
    return found


def _is_ancestor(wt, a, b):
    return git(wt, "merge-base", "--is-ancestor", a, b, check=False).returncode == 0   # rc 1 (no) and any trouble: no


def _reflog_only(wt, head, main_head, refs, attached=False, reflog_lines=False, admin=None):
    """Commits that nothing but this worktree's own HEAD reflog names (`checkout --detach HEAD~1`, `reset`, a commit made detached
    and then `checkout <branch>`): a removal deletes that reflog and the commit is gone at the next gc. [sha, ...] newest first,
    or None when git could not say (fail closed; an unreadable, irregular or corrupt reflog file is such a case). `refs`: the commit
    ids of the branch, remote and tag tips (inventory computes them once). Not counted: the predecessor of an amend / rebase fixup /
    squash, a commit whose files hold the same bytes in main, one that main (or the current HEAD) has as the same patch
    (cherry-picked, rebased), the commits of a chain whose whole patch is in main already (a squash brought back as one diff); for a
    worktree on a BRANCH (`attached`) also a commit the reflog of a local branch names (`reset --hard HEAD~1`, `commit --amend` on
    the branch: the branch reflog survives the removal). `admin`: read the HEAD reflog from that admin dir (a worktree whose folder
    is gone, A.2 #3); `wt` is then any checkout of the repository: every other check reads only the objects and refs all share."""
    if admin:
        # ONE read of the reflog file, parsed here (the format `git log -g` reads: newest last): git would also need the admin dir's
        # HEAD, which a removal running meanwhile may already have deleted, and an integrated worktree being removed read as "cannot say"
        try:
            lines = [l for l in _read_regular(os.path.join(admin, "logs", "HEAD")).split(b"\n") if l.strip()]
        except FileNotFoundError:
            return []   # no reflog (or the removal already deleted it): nothing only it names
        except OSError:
            return None   # a FIFO / device / unreadable file
        found = [re.fullmatch(rb"([0-9a-f]{40}|[0-9a-f]{64}) ([0-9a-f]{40}|[0-9a-f]{64}) [^\t]*(?:\t(.*))?", l.rstrip(b"\r")) for l in reversed(lines)]
        if not all(found):
            return None   # a line that is no reflog entry: what it names is unknown
        entries = [(m.group(2).decode(), (m.group(3) or b"").decode("utf-8", "replace")) for m in found if m.group(2).strip(b"0")]
    else:
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
    lost, chain_ok, memo, clean = [], [], {}, None
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
            if clean is None:
                clean = _clean_merges(wt, unreachable)   # #386: a merge with no hunk of its own and held parents loses nothing (asked once, lazily)
            if sha not in clean:
                lost.append(sha)
            continue
        # `git cherry <up> <sha>` lists every commit from the merge base, oldest first: only the line of THIS commit counts (only asked when the bytes differ)
        if not same_bytes and not any(("- " + sha) in git(wt, "cherry", up, sha, check=False).stdout.splitlines() for up in (main_head, head) if up):
            lost.append(sha)
    return lost

# ponytail (accepted, same as the base): the whole-patch rule above allows a chain that DELIBERATELY reverted itself (add V then delete V, edit then revert,
# a binary added then deleted, `merge -s ours` of a side commit): its net patch is empty / already in main. Patch ids ignore whitespace and EOL. Upgrade
# only if such a chain must keep the worktree: judge every commit's own diff against main as well.


def _admin_dir(cwd, path):
    """The admin dir (<common>/worktrees/<id>) git keeps for the registered worktree at `path` until a prune — also when its folder is
    gone, so the reflog there can still be read (A.2 #3). Matched the way `git worktree list` derives a path from <id>/gitdir (absolute,
    or relative to the admin dir: worktree.useRelativePaths). "" when git no longer lists `path` (pruned or removed: its reflog went with
    it); None when it cannot be told (git fails, an unreadable gitdir file, two registrations claiming the path, a listed path not found)."""
    r = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir", check=False)
    common = r.stdout.strip()
    if r.returncode != 0 or not common:
        return None
    root = os.path.join(common, "worktrees")
    try:
        ids = os.listdir(root)
    except FileNotFoundError:
        ids = []
    except OSError:
        return None
    found, unreadable = [], False
    for i in ids:
        adm = os.path.join(root, i)
        try:
            raw = _read_regular(os.path.join(adm, "gitdir"), 65536).decode("utf-8", "surrogateescape").rstrip()
        except FileNotFoundError:
            continue   # not a worktree's admin dir
        except OSError:
            unreadable = True
            continue
        p = raw[:-len("/.git")] if raw.endswith("/.git") else raw
        if not os.path.isabs(p):
            p = os.path.realpath(os.path.join(adm, p))
        if p == path or os.path.realpath(p) == os.path.realpath(path):
            found.append(adm)
    if len(found) == 1:
        return found[0]
    if found or unreadable:
        return None
    try:
        listed = any(not e["broken"] and _same_path(e["path"], path) for e in _worktree_entries(cwd))
    except SystemExit:
        return None
    return None if listed else ""


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
            unheld = git(cwd, "rev-list", "--stdin", inp="\n".join(rev_in) + "\n", check=False)
            if unheld.returncode == 0:
                ids = set(unheld.stdout.split())
                held_only = len(ids - _clean_merges(cwd, ids))   # #386: clean merges of held parents lose nothing
        if head:   # also a worktree on a branch: it can detach, commit, and go back (the commit is then named by its reflog only)
            try:
                reflog = _reflog_only(path, head, main_head, refs, attached=not e["detached"], reflog_lines=rl) if os.path.isdir(path) else None
                if not os.path.isdir(path):
                    # gone before (or while) its reflog was read: git keeps that reflog in the admin dir until a prune, so it is read
                    # there (A.2 #3: [] here let a commit only the reflog names pass); unregistered meanwhile: the reflog went with it
                    adm = _admin_dir(cwd, path)
                    reflog = None if adm is None else [] if not adm else _reflog_only(cwd, head, main_head, refs, attached=not e["detached"], admin=adm)
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


_LINK_KEYS = ("tests", "runs_in_suite", "test_refs")   # regression_checklist.LINK_KEYS


def _authored_cmp(item):
    """_authored as two copies of one row are COMPARED: a bug / REQ row's three link keys count as one set (the checklist sync moves a
    fixed bug's test_refs to runs_in_suite once they resolve: GeelyEx2 #41, 21/10)."""
    a = _authored(item)
    if a is None:
        return None
    if "covers" in a and len(a) == 1:   # a test row: its `covers` links are what a person made
        return a
    links = set()
    for k in _LINK_KEYS:
        v = a.pop(k, None)
        links.update(str(t) for t in (v if isinstance(v, list) else [] if v is None else [v]))
    if links:
        a["links"] = sorted(links)
    return a


def _bookkeeping_regenerated(wt, main):
    """True when the worktree's UNCOMMITTED bookkeeping (BOOKKEEPING) is nothing but what the gate and the checklist sync regenerate.
    Every row a person made (_authored_cmp) in its regression_status.json on disk is either:
      - the worktree's own HEAD row as it is (committed: the commit checks guard it; main may have edited it since, principal P2-2),
        or a row its own HEAD does not hold that main's HEAD holds as it is; a row its own HEAD holds that the disk changed back to
        main's version is work (Antigravity T0047 #3);
      - or the row the checklist's own sync (_synced_rows: the sync every `bugs` command runs) builds on the worktree's own HEAD from
        its guards.json and matrix, time stamps aside — a guards.json import, a guard claimed on a row, a moved ref (#41), never a
        person's link on it (P1-1, T0047 #1).
    And no such row of its own HEAD is gone from the disk (`agent-kit bugs drop`, a test row's `covers` removed: OCR, T0047 #2).
    Fail closed: a status file that cannot be read or parsed, on disk, in the worktree's HEAD or in main's HEAD, is work."""
    path = os.path.join(wt, STATUS_FILE)
    try:
        if not os.path.lexists(path):
            return True   # deleted in the worktree: main keeps its own copy
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        with open(path, encoding="utf-8") as f:
            mine_raw = json.load(f)
        own = git(wt, "ls-tree", "-z", "HEAD", "--", STATUS_FILE, check=False)   # rc 0 and nothing printed: HEAD has no status file
        if own.returncode != 0:
            return False
        base_raw = {"items": {}}
        if own.stdout.strip("\0"):
            got = git(wt, "show", f"HEAD:{STATUS_FILE}", check=False)
            if got.returncode != 0:
                return False
            base_raw = json.loads(got.stdout)
        held = git(main, "ls-tree", "-z", "HEAD", "--", STATUS_FILE, check=False)   # as the worktree's HEAD: a git error is not "none" (OCR)
        if held.returncode != 0:
            return False
        theirs_raw = {"items": {}}
        if held.stdout.strip("\0"):
            cur = git(main, "show", f"HEAD:{STATUS_FILE}", check=False)
            if cur.returncode != 0:
                return False
            theirs_raw = json.loads(cur.stdout)
        mine = {rid: a for rid, it in mine_raw["items"].items() for a in [_authored_cmp(it)] if a is not None}
        base = {rid: a for rid, it in base_raw["items"].items() for a in [_authored_cmp(it)] if a is not None}
        theirs = {rid: a for rid, it in theirs_raw["items"].items() for a in [_authored_cmp(it)] if a is not None}
        if any(rid not in mine for rid in base):
            return False   # a row of its own HEAD gone from the disk
        synced = None
        for rid, a in mine.items():
            if base.get(rid) == a or (rid not in base and theirs.get(rid) == a):
                continue
            if synced is None:
                synced = _synced_rows(wt, base_raw)
            want = _authored_cmp(synced.get(rid))
            if want is None or _unstamped(want) != _unstamped(a):
                return False
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
        return False
    return True


_SYNC_STAMPS = ("created_at", "linked_at", "linked_ts")   # what the checklist sync stamps with the time it ran


def _unstamped(a):
    return {k: v for k, v in a.items() if k not in _SYNC_STAMPS}


def _synced_rows(wt, head_raw):
    """The rows the checklist's own sync (regression_checklist.sync_project: matrix suites, guards.json guards, orphan tests, refs
    that resolve now — what every `bugs` command and the render run first) builds on top of the worktree's HEAD status from its
    own .agents/local/guards.json and matrix: {id: row}. GeelyEx2 #41 / the test: it imports a guard as a new row, or claims it on a
    row that already covers the guard's tests. {} when it cannot run (fail closed: then nothing counts as regenerated)."""
    try:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin", "regression_checklist.py")
        spec = importlib.util.spec_from_file_location("devkit_regression_checklist_sync", path)
        rc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(rc)
        data = json.loads(json.dumps(head_raw))   # a deep copy: the HEAD rows stay as read
        matrix = {}
        mf = os.path.join(wt, ".agents", "regression_matrix.active.json")
        if os.path.isfile(mf):
            with open(mf, encoding="utf-8") as f:
                matrix = json.load(f)
        rc.sync_project(data, rc.Path(wt), matrix)
        items = data.get("items")
        return items if isinstance(items, dict) else {}
    except Exception:  # noqa: BLE001 - the sync cannot run here: nothing counts as regenerated by it (fail closed)
        return {}


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


def _iter_blockers(cwd, wt, shown, budget, rows=None):
    """The reasons a worktree must NOT be removed, one at a time, in the order `remove` has always checked them. Yields
    (exit code, kind, text, detail lines). Lazy: a check that cannot run (not made by `worktree add`) is only reached when
    nothing earlier blocked. kind: unregistered | busy | unreachable | submodule | not_ours | main | uncommitted | secret."""
    if rows is None:
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
        if not os.path.isdir(wt) or _has_state_file(wt):   # (a state file that is there but unreadable is NOT "no setup": refused as ever)
            yield (2, "not_ours", tr(f"{wt} không được tạo bằng 'agent-kit worktree add' (thiếu {STATE})",
                                     f"{wt} was not made by 'agent-kit worktree add' (no {STATE})") if os.path.isdir(wt)
                   else tr(f"không có thư mục: {wt}", f"no such directory: {wt}"), [])
            return
        state = _adopted_state(wt)   # same checks as for any worktree; only the recorded-setup list is rebuilt (see _adopted_state)
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
    lost = [p for p in dict.fromkeys(changed + (hidden or [])) if not _same_in_main(wt, main, p)
            and not _is_durations_hint(p)]   # #365: file gợi ý thứ tự test, không phải công việc
    if lost:   # #386: the same bytes and mode already sit on an origin branch tip (the PR's own branch): the remote holds them
        on_origin = _same_on_origin(wt, lost)
        lost = [p for p in lost if p not in on_origin]
    # Bookkeeping the gate and the checklist sync regenerate is no work (GeelyEx2 #41, 21/10: it alone held a lane worktree and the
    # card went to Blocked); cmd_remove keeps a fallback copy first. A row a person made, or an edit git hides, still counts.
    if any(p in BOOKKEEPING and p not in (hidden or ()) for p in lost) and _bookkeeping_regenerated(wt, main):
        lost = [p for p in lost if p not in BOOKKEEPING or p in (hidden or ())]
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
    try:   # A.1b #12: a git-ignored secret only this worktree holds (or holds differently) goes with the folder; `finish` carries it first
        secrets, cut = _ignored_secrets(wt)
    except (OSError, UnicodeError) as e:   # (SystemExit - git cannot list them - is the caller's, as for every check here)
        secrets, cut = [], f"({e})"
    keys = [rel for rel, src in secrets if not _same_bytes(src, os.path.join(main, rel))]
    if keys:
        listing = ", ".join(keys[:6])
        yield (1, "secret", tr(f"{wt}: {len(keys)} file bí mật bị git ignore chỉ worktree có (main chưa có hoặc có bản khác): {listing} — gỡ worktree là mất chúng. "
                               f"Chạy `agent-kit worktree finish {shlex.quote(shown)}` (chép vào main trước khi gỡ) hoặc tự chép sang main",
                               f"{wt}: {len(keys)} git-ignored secret file(s) only the worktree holds (main lacks them or holds other bytes): {listing} — a removal "
                               f"deletes them. Run `agent-kit worktree finish {shlex.quote(shown)}` (it copies them into main first) or copy them to main yourself"), [])
    if cut:
        yield (1, "secret", tr(f"{wt}: dò file bí mật bị git ignore dừng ở {cut} (quá WORKTREE_SECRET_SCAN_MAX file hoặc không đọc được) — phần chưa đọc có thể có khoá",
                               f"{wt}: the scan for git-ignored secret files stopped at {cut} (over WORKTREE_SECRET_SCAN_MAX files, or unreadable) - what it did not read may hold a key"), [])


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


def _unsaved_memory(wt, main):
    """Notes saved in the worktree's OWN claude-auto folder that the main checkout's folder does not hold (missing there, or other bytes):
    they go with the worktree. [] when there are none, or when the worktree shares the main checkout's folder (--share-memory)."""
    own, theirs = os.path.join(wt, MEMORY_REL), os.path.join(main, MEMORY_REL)
    if not os.path.isdir(own) or _same_path(own, theirs):
        return []
    lost = []
    for d, _dirs, files in os.walk(own):
        for f in files:
            if f.startswith("."):
                continue
            rel = os.path.relpath(os.path.join(d, f), own)
            try:
                same = fingerprint(os.path.join(own, rel)) == fingerprint(os.path.join(theirs, rel))
            except OSError:
                same = False   # unreadable: it may be a note
            if not same:
                lost.append(rel)
        if len(lost) > 200:
            break
    return lost


UF_LOCK = stat.UF_IMMUTABLE | stat.UF_APPEND   # the user flags `chflags uchg` / `uappnd` set (defined on every OS; only macOS/BSD has lchflags)


def _clear_user_locks(top):
    """Clear the user-immutable / append-only flags (`chflags uchg`) under `top`; the paths that would not unlock. A worktree made
    before `_copy` stopped copying flags holds locked copies of the user's keystore, which git cannot delete. `top` is a directory git
    already took out of its registry: it is never the main checkout. os.walk does not follow links below `top`, so `.agents/devkit`
    or any other link into the main checkout is never entered: only files that live in `top` are unlocked."""
    stuck = []
    if not hasattr(os, "lchflags"):
        return stuck
    for dirpath, dirs, files in os.walk(top):
        for p in [dirpath] + [os.path.join(dirpath, n) for n in dirs + files]:
            try:
                st = os.lstat(p)
                if st.st_flags & UF_LOCK:
                    os.lchflags(p, st.st_flags & ~UF_LOCK)   # lchflags, never chflags: a path swapped for a link after the lstat must not unlock its target (the main checkout's keystore)
            except OSError:
                stuck.append(p)   # named in the refusal below, if the folder then survives
    return stuck


def _by_hand(wt):
    """What a person runs for a folder git no longer lists (it cannot remove it any more): unlock, make writable (a read-only directory stops rm), delete."""
    q = shlex.quote(wt)
    return f"chflags -R nouchg {q}; chmod -R u+rwX {q}; rm -rf {q}"


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
    entry = next((e for e in _worktree_entries(main) if _same_path(e["path"], wt)), None)
    wt = entry["path"] if entry else wt   # git's own spelling: a link to the worktree is not the folder
    # Worktree dựng detached rồi `git switch -c` (luồng PR): state không ghi branch, git vẫn biết nó đang ở branch nào.
    branch = state.get("branch") or (entry or {}).get("branch")
    # Verified above: nothing but the recorded setup and ignored files is left, so
    # --force here drops no work (plain `remove` refuses any untracked file).
    try:
        notes = _unsaved_memory(wt, main)   # read BEFORE the folder goes
    except Exception:  # noqa: BLE001 - a warning only: never in the way of the removal
        notes = []
    # Regenerated bookkeeping _iter_blockers let through: a fallback copy first (a git error there: SystemExit, nothing removed).
    dropped = [p for p in changes_since(wt, state) if p in BOOKKEEPING and not _same_in_main(wt, main, p)]
    if dropped:
        kept = _discard_backup(main, wt)
        print("ℹ " + tr(f"sổ sách checklist do gate / sync sinh lại ({', '.join(dropped)}) không đem về; bản cất: {kept} ({DISCARD_KEEP_DAYS} ngày)",
                        f"checklist bookkeeping the gate / sync regenerate ({', '.join(dropped)}) is not brought back; fallback copy: {kept} "
                        f"({DISCARD_KEEP_DAYS} days)"), file=sys.stderr)
    _remove_checked(main, wt, branch)
    if notes:
        shown = ", ".join(notes[:5]) + (f" (+{len(notes) - 5})" if len(notes) > 5 else "")
        print("⚠ " + tr(f"{len(notes)} memory note(s) lưu trong thư mục claude-auto RIÊNG của worktree (không có trong claude-auto của main) đã đi theo worktree: {shown}. "
                        f"Lần sau: chép chúng vào {os.path.join(main, MEMORY_REL)} TRƯỚC khi gỡ, hoặc tạo worktree với --share-memory.",
                        f"{len(notes)} memory note(s) saved in the worktree's OWN claude-auto folder (not in the main checkout's) went with it: {shown}. "
                        f"Next time: copy them into {os.path.join(main, MEMORY_REL)} BEFORE removing, or create the worktree with --share-memory."), file=sys.stderr)
    return 0


def _remove_checked(main, wt, branch, note=""):
    """Gỡ `wt` mà người gọi ĐÃ chứng minh là không mất gì (remove: _iter_blockers; discard: chỉ file xoá / rác IDE, hoặc đã cất vào
    refs/devkit/discarded), rồi xoá `branch` khi nó đã nằm trọn trong main. In một dòng ✔; die() khi git từ chối hay thư mục còn sót."""
    unlocked = _drop_dead_kept_lock(main, wt)   # K11: khoá ExitWorktree keep của phiên đã chết hoặc của CHÍNH phiên gọi; khoá của phiên khác còn sống thì git từ chối
    r = git(main, "worktree", "remove", "--force", wt, check=False, bounded=False)
    if r.returncode != 0 and any(_same_path(e["path"], wt) for e in _worktree_entries(main)):
        if unlocked:   # git từ chối trước khi xoá gì: trả khoá vừa mở về như cũ (audit T0044), lần chạy lại vẫn mở được nó
            git(main, "worktree", "lock", "--reason", unlocked, wt, check=False)
        raise SystemExit(f"✖ worktree: git worktree remove: {r.stderr.strip()}")   # refused before it deleted anything: still registered, flags untouched, retry works
    left, stuck = [], []
    if os.path.lexists(wt):   # git (2.55) drops its registration even when it cannot delete the folder (a locked keystore copy): unlock and finish here, or say what is left
        stuck = _clear_user_locks(wt)
        shutil.rmtree(wt, **{("onexc" if sys.version_info >= (3, 12) else "onerror"): lambda f, p, e: left.append(p)})
    if os.path.lexists(wt):
        names = ", ".join((left or stuck)[:5]) or r.stderr.strip()[-200:]
        die(tr(f"{wt} KHÔNG xoá hết được (git đã gỡ đăng ký nên không ai còn thấy nó): {names}. Người dùng: `{_by_hand(wt)}`",
               f"{wt} could NOT be deleted completely (git has dropped its registration, so no guard lists it any more): {names}. The user runs `{_by_hand(wt)}`"), 1)
    # Người dùng 17/10: branch cũ phải tự đi cùng worktree. Chỉ khi remote không còn ref của nó (chưa publish, hoặc remote đã xoá
    # sau khi PR gộp: remote là của người dùng) và nội dung của nó đã nằm trọn trong HEAD của main.
    gone, kept = False, ""
    if branch and branch != _trunk_branch(main) \
            and not git(main, "for-each-ref", "--format=%(refname)", f"refs/remotes/*/{branch}", check=False).stdout.strip():
        gone, kept = _branch_in_main(main, branch)
    print(f"✔ {tr('đã gỡ', 'removed')} {wt}" + (f"; {tr('nhánh', 'branch')} {branch} "
          + (tr("đã gộp vào main nên đã xoá", "was merged into main and is deleted") + kept if gone
             else tr("giữ lại (xoá khi đã merge: agent-kit worktree prune-branch ", "kept (delete once merged: agent-kit worktree prune-branch ") + branch + ")")
          if branch else "") + note)


def _branch_in_main(main, branch):
    """Xoá `branch` khi mọi thứ của nó đã có trong trunk (local hoặc origin/<trunk>: PR squash trên GitHub khi main local chưa đồng bộ,
    _content_in_trunk); (True, ghi chú bản cất) khi đã xoá, (False, "") khi giữ. Xung đột hay khác một byte là giữ."""
    tip = git(main, "rev-parse", "-q", "--verify", f"refs/heads/{branch}^{{commit}}", check=False).stdout.strip()
    if not tip or not _content_in_trunk(main, f"refs/heads/{branch}"):
        return False, ""
    ok, kept = _delete_branch(main, branch, tip)
    return ok, (tr(f"; commit chỉ nhánh giữ đã cất ở {kept} ({DISCARD_KEEP_DAYS} ngày)", f"; commits only the branch held are kept in {kept} ({DISCARD_KEEP_DAYS} days)")
                if ok and kept else "")


def _devkit_env(**extra):
    """Môi trường cho commit-tree của DevKit: máy không có danh tính git (INSTINCT-043) vẫn commit được bản cất."""
    env = {**os.environ, **extra}
    for k, v in (("GIT_AUTHOR_NAME", "DevKit"), ("GIT_AUTHOR_EMAIL", "devkit@localhost"),
                 ("GIT_COMMITTER_NAME", "DevKit"), ("GIT_COMMITTER_EMAIL", "devkit@localhost")):
        env.setdefault(k, v)
    return env


def _keep_ref(main, label, tree, parents, message):
    """Một ref mới refs/devkit/discarded/<label>-<stamp>-<pid> trỏ vào commit (tree, parents): sống DISCARD_KEEP_DAYS ngày, worktree gc
    dọn. Không bao giờ đè một bản cất khác (update-ref với cũ = ""). Git lỗi: SystemExit (người gọi không xoá gì)."""
    sha = git(main, "commit-tree", tree, *[a for p in parents for a in ("-p", p)], "-m", message, env=_devkit_env()).stdout.strip()
    name = re.sub(r"[^A-Za-z0-9._-]", "_", label)[:80] or "worktree"
    ref = f"{DISCARD_REF}{name}-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    git(main, "update-ref", ref, sha, "")
    return ref


def _delete_branch(main, name, tip):
    """Xoá refs/heads/<name> chỉ khi nó vẫn ở `tip` (update-ref so-và-xoá: không đua với commit mới), cùng cấu hình branch.<name>. Reflog
    của nhánh đi cùng nó, nên commit mà sau khi xoá không ref nào còn giữ — tip, và commit chỉ reflog đó nêu (commit rồi reset về, amend,
    dời nhánh qua lại: review 18/10) — được cất trước vào refs/devkit/discarded/branch-<name>-* (_keep_ref). (True, tên bản cất hoặc "")
    khi đã xoá; (False, lý do) khi giữ (git lỗi, nhánh vừa đổi tip)."""
    ref = f"refs/heads/{name}"
    log = git(main, "log", "-g", "--format=%H", ref, check=False)
    others = git(main, "for-each-ref", "--format=%(objectname) %(refname)", check=False)
    if log.returncode or others.returncode:
        return False, tr("git không đọc được reflog / danh sách ref", "git could not read the reflog / the refs")
    cands = list(dict.fromkeys([tip] + log.stdout.split()))
    keep = ["^" + line.split(" ", 1)[0] for line in others.stdout.splitlines() if line and line.split(" ", 1)[-1] != ref]
    lost = git(main, "rev-list", "--stdin", inp="\n".join(cands + keep) + "\n", check=False)
    if lost.returncode:
        return False, tr("git không tính được commit sẽ mất", "git could not tell which commits would be lost")
    gone = set(lost.stdout.split())
    parents = [c for c in cands if c in gone]
    try:
        kept = _keep_ref(main, f"branch-{name}", f"{tip}^{{tree}}", parents, f"devkit prune-branch {name}") if parents else ""
    except SystemExit as e:
        return False, str(e.code)
    if git(main, "update-ref", "-d", ref, tip, check=False).returncode:
        return False, tr(f"{name} vừa đổi tip: không xoá", f"{name} moved meanwhile: not deleted")
    git(main, "config", "--remove-section", f"branch.{name}", check=False)
    return True, kept


# K2/K4 (người dùng 18/10 duyệt "làm cả 3"): guard git chặn `git worktree remove --force`, `git branch -D`, `git checkout <sha> -- <path>`
# theo dạng lệnh, kể cả khi không mất gì. Ba lệnh dưới tự chứng minh "không mất gì" rồi mới làm; dạng git trần vẫn bị guard chặn như cũ.
DISCARD_REF = "refs/devkit/discarded/"
DISCARD_KEEP_DAYS = 30
DISCARD_REF_DATE_RE = re.compile(r".*-([0-9]{8})-[0-9]{6}(?:-[0-9]+)?")
IDE_JUNK_RE = re.compile(r"(?:[^/]+/)*(?:\.vscode|\.idea)/.+")   # VS Code / Rider / IntelliJ tự sinh, chưa track
UNITY_JUNK_RE = re.compile(r"(?:[^/]+/)*[^/]+\.(?:slnx|sln|csproj)")   # Unity tự sinh; ở repo khác đó là file dự án thật (review 18/10)


def _unity_project(wt):
    """True khi `wt` là project Unity (ProjectSettings/ProjectVersion.txt ở gốc hoặc một tầng dưới, như copy_unity_library)."""
    try:
        cands = [""] + [d for d in os.listdir(wt) if not d.startswith(".") and os.path.isdir(os.path.join(wt, d))]
    except OSError:
        return False
    return any(os.path.isfile(os.path.join(wt, d, "ProjectSettings", "ProjectVersion.txt")) for d in cands)


def _ide_junk(wt, p, unity):
    """`p` là rác IDE chưa từng track: đúng mẫu (*.sln/*.csproj chỉ trong project Unity), là FILE (một thư mục là repo git lồng git không
    đi vào, review 18/10), index không có mục nào và HEAD không có nó (một file đã `git add` không phải rác, audit T0044). Lỗi git: False."""
    full = os.path.join(wt, p)
    if p.endswith("/") or not (IDE_JUNK_RE.fullmatch(p) or (unity and UNITY_JUNK_RE.fullmatch(p))):
        return False
    if os.path.isdir(full) or not (os.path.isfile(full) or os.path.islink(full)):
        return False
    idx = git(wt, "--literal-pathspecs", "ls-files", "-s", "-z", "--", p, check=False)
    head = git(wt, "--literal-pathspecs", "ls-tree", "-z", "HEAD", "--", p, check=False)
    return idx.returncode == 0 and not idx.stdout.strip("\0") and head.returncode == 0 and not head.stdout.strip("\0")
PROTECTED_BRANCH_RE = re.compile(r"(?:main|master|trunk|develop|release/.+|hotfix/.+)")


def _content_in_trunk(main, ref):
    """True khi mọi thứ `ref` mang đã có trong trunk (nhánh local hoặc origin/<trunk>): là tổ tiên, hoặc gộp thử (merge-tree, không đụng
    cây làm việc) ra đúng cây của trunk — PR squash. Không biết trunk, xung đột, lỗi git: False."""
    trunk = _trunk_branch(main)
    if not trunk:
        return False
    return any(_is_ancestor(main, ref, tip) or _merges_to(main, tip, ref) for tip in (f"refs/heads/{trunk}", f"refs/remotes/origin/{trunk}")
               if git(main, "rev-parse", "-q", "--verify", f"{tip}^{{commit}}", check=False).returncode == 0)


def _same_patches_verbatim(cwd, tip, head, cap=300):
    """Như `_same_patches_in_main` nhưng so `git patch-id --verbatim`: patch-id mặc định bỏ khoảng trắng nên `a2` và `a 2` coi như một,
    còn discard xoá thật. Mọi commit của `head` mà `tip` chưa có phải có patch-id y hệt một commit của tip (từ merge-base). Có merge
    commit, quá `cap` commit, lỗi git: False."""
    base = git(cwd, "merge-base", tip, head, check=False).stdout.strip()
    if not base:
        return False
    merges = git(cwd, "rev-list", "--merges", "--count", f"{base}..{head}", check=False)
    mine_n = git(cwd, "rev-list", "--count", f"{base}..{head}", check=False)
    total = git(cwd, "rev-list", "--count", f"{base}..{tip}", check=False)
    if merges.returncode or merges.stdout.strip() != "0":
        return False
    # cap áp cho CẢ hai chuỗi: chuỗi head dài cũng chạy `git log -p` + patch-id không giới hạn (#326)
    if any(r.returncode or not r.stdout.strip().isdigit() or int(r.stdout) > cap for r in (total, mine_n)):
        return False

    def ids(rng):   # BYTES: text mode đổi \r\n thành \n trước patch-id; --submodule=short: commit chỉ đổi gitlink vẫn có patch-id
        log = _git_bytes(cwd, "log", "-p", "--no-merges", "--no-color", "--no-ext-diff", "--no-textconv", "--submodule=short",
                         "--ignore-submodules=none", "--full-index", "--format=commit %H", rng)
        pid = _git_bytes(cwd, "patch-id", "--verbatim", inp=log.stdout) if log.returncode == 0 else None
        return collections.Counter(l.split()[0] for l in pid.stdout.splitlines() if l.strip()) if pid is not None and pid.returncode == 0 else None
    mine, theirs = ids(f"{base}..{head}"), ids(f"{base}..{tip}")
    return mine is not None and theirs is not None and not (mine - theirs)   # đếm số lần: add, delete, add lại không bằng add, delete


def _merges_to_strict(main, into, other):
    """`_merges_to` cho discard (xoá thật): chỉ khi KHÔNG file nào `other` đổi có thuộc tính `merge=<driver>` (driver như `ours` giữ bản của
    trunk) và gộp thử không chuẩn hoá lại dòng (`merge.renormalize` làm commit chỉ khác CRLF trông như đã có). Lỗi git: False."""
    base = git(main, "merge-base", into, other, check=False).stdout.strip()
    names = git(main, "diff", "--name-only", "-z", "--no-renames", base, other, check=False) if base else None
    attrs = git(main, "check-attr", "-z", "--stdin", "merge", check=False, inp=names.stdout) if names is not None and names.returncode == 0 else None
    if attrs is None or attrs.returncode or any(v not in ("unspecified", "set") for v in attrs.stdout.split("\0")[2::3]):
        return False
    tree = git(main, "rev-parse", "-q", "--verify", f"{into}^{{tree}}", check=False).stdout.strip()
    r = git(main, "-c", "merge.renormalize=false", "merge-tree", "--write-tree", into, other, check=False)
    return bool(tree) and r.returncode == 0 and r.stdout.split("\n", 1)[0].strip() == tree


def _chain_in_trunk(main, head):
    """Mọi commit `head` có hơn một đầu trunk (local hoặc origin/<trunk>) đã được tích hợp theo cách `remove` tính: là tổ tiên, gộp thử
    ra đúng cây trunk, cùng patch-id với một commit ở đó, hoặc cả patch đã nằm trong trunk (squash). Commit rỗng, lỗi git: False."""
    trunk = _trunk_branch(main)
    for ref in ((f"refs/heads/{trunk}", f"refs/remotes/origin/{trunk}") if trunk else ()):
        tip = git(main, "rev-parse", "-q", "--verify", f"{ref}^{{commit}}", check=False).stdout.strip()
        if tip and (_is_ancestor(main, head, tip) or _merges_to_strict(main, tip, head) or _same_patches_verbatim(main, tip, head)) and not _empty_commit_between(main, tip, head):
            return True
    return False


def _merged_pr_at(main, branch, tip):
    """Số PR MERGED VÀO TRUNK (baseRefName = trunk, không phải PR từ fork) có head là `branch` và headRefOid đúng `tip` (không còn commit mới
    sau lần gộp), theo `gh`; None khi không có, không biết trunk, gh không chạy được, quá 15 s hay trả gì đọc không được (không nói được =
    không xoá). Một PR gộp vào nhánh khác (feat/parent) chưa đưa gì vào trunk (review + audit T0044)."""
    trunk = _trunk_branch(main)
    if not trunk:
        return None
    try:
        r = subprocess.run(["gh", "pr", "list", "--head", branch, "--base", trunk, "--state", "merged",
                            "--json", "number,headRefOid,baseRefName,isCrossRepository", "--limit", "20"],
                           cwd=main, capture_output=True, text=True, timeout=15)
        rows = json.loads(r.stdout or "[]") if r.returncode == 0 else []
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    for row in rows if isinstance(rows, list) else []:
        if isinstance(row, dict) and row.get("headRefOid") == tip and row.get("baseRefName") == trunk and row.get("isCrossRepository") is False:
            return row.get("number") or "?"
    return None


def _discard_leftovers(wt):
    """Ca (a) của discard: những gì `wt` còn giữ ngoài file đã xoá và rác IDE chưa track — [] khi không mất gì. Danh sách file đổi lấy như
    `remove` (changes_since: so với setup đã ghi), cộng file git ẩn (skip-worktree / assume-unchanged); không đọc được: coi là còn."""
    try:
        state = _read_state(wt)
    except (OSError, ValueError, SystemExit):
        state = None
    if not isinstance(state, dict):
        state = _adopted_state(wt)
    try:
        hidden = _hidden_edits(wt)
    except Exception:  # noqa: BLE001 - cannot say: refuse
        hidden = None
    if hidden is None:
        return [tr(f"{wt}: không đọc được danh sách file git ẩn (skip-worktree / assume-unchanged)",
                   f"{wt}: the files git hides (skip-worktree / assume-unchanged) could not be listed")]
    left, unity = [], _unity_project(wt)
    for p in dict.fromkeys(changes_since(wt, state) + hidden):
        if p not in hidden and not os.path.lexists(os.path.join(wt, p)) and _index_is_head(wt, p):
            continue   # đã xoá và index không giữ bản nào khác HEAD (` D`, `D `): HEAD (hoặc setup) vẫn giữ bản của nó
        if p not in hidden and _ide_junk(wt, p, unity):
            continue   # rác IDE chưa từng được track
        left.append(p)
    if not left:
        return []
    return [tr(f"{wt}: {len(left)} file sửa hoặc mới (không phải file đã xoá hay rác IDE): ", f"{wt}: {len(left)} edited or new file(s) (not deleted, not IDE junk): ")
            + ", ".join(left[:10]) + (f" (+{len(left) - 10})" if len(left) > 10 else "")]


def _index_is_head(wt, p):
    """True khi index không giữ gì của `p` ngoài bản HEAD: không có mục nào (đã stage xoá), hoặc đúng mode + blob của HEAD. Một file đã stage
    rồi xoá khỏi đĩa (`AD`, `MD`, OCR 18/10) chỉ còn trong index: False. Lỗi git: False (không nói được = còn)."""
    idx = git(wt, "--literal-pathspecs", "ls-files", "-s", "-z", "--", p, check=False)
    head = git(wt, "--literal-pathspecs", "ls-tree", "-z", "HEAD", "--", p, check=False)
    if idx.returncode or head.returncode:
        return False
    entries = [e for e in idx.stdout.split("\0") if e]
    if not entries:
        return True
    if len(entries) != 1:   # (một mục conflict có nhiều stage: còn việc)
        return False
    mode, sha, _stage = entries[0].split("\t", 1)[0].split(" ")
    tree = [e for e in head.stdout.split("\0") if e]
    return len(tree) == 1 and tree[0].split("\t", 1)[0].split(" ") == [mode, "blob", sha]


def _discard_backup(main, wt):
    """Bản cất phòng hờ của discard (chỉ chạy sau khi đã chứng minh không mất gì), sống DISCARD_KEEP_DAYS ngày (worktree gc dọn): cây làm
    việc trong một index tạm chép từ index THẬT (file `add -f` dù bị ignore; rồi `add -A`: file chưa track trừ file ignore) với cờ
    skip-worktree / assume-unchanged đã gỡ (không thì `add -A` bỏ qua bản sửa ẩn, review 18/10), commit với HEAD, cây của index thật khi
    nó khác HEAD (bản stage, audit T0044) và MỌI commit chỉ reflog của worktree còn giữ làm cha. Git lỗi ở bất kỳ bước nào: SystemExit,
    không gỡ gì. Trả tên ref."""
    head = git(wt, "rev-parse", "-q", "--verify", "HEAD^{commit}", check=False).stdout.strip()
    real_index = git(wt, "rev-parse", "--path-format=absolute", "--git-path", "index").stdout.strip()
    tmpd = tempfile.mkdtemp(prefix="devkit-discard-")
    env = _devkit_env(GIT_INDEX_FILE=os.path.join(tmpd, "index"))   # chỉ cho các lệnh dưới: index thật của worktree không bị đụng
    staged = ""
    try:
        if os.path.isfile(real_index):
            shutil.copyfile(real_index, env["GIT_INDEX_FILE"])   # một bản chép: index thật chỉ được đọc
            staged = git(wt, "write-tree", env=env).stdout.strip()
            flagged = [e[2:] for e in git(wt, "ls-files", "-v", "-z", env=env).stdout.split("\0") if len(e) > 2 and (e[0] == "S" or e[0].islower())]
            if flagged:
                git(wt, "update-index", "-z", "--no-skip-worktree", "--no-assume-unchanged", "--stdin", env=env, inp="\0".join(flagged) + "\0")
        elif head:
            git(wt, "read-tree", head, env=env, bounded=False)
        git(wt, "add", "-A", "--", ".", env=env, bounded=False)
        tree = git(wt, "write-tree", env=env).stdout.strip()
    finally:
        shutil.rmtree(tmpd, ignore_errors=True)
    seen = list(dict.fromkeys(git(wt, "log", "-g", "--format=%H", "HEAD").stdout.split()))   # (không có reflog: rỗng, rc 0)
    lone = set(git(wt, "rev-list", *seen, "--not", "--all").stdout.split()) if seen else set()
    parents = ([head] if head else []) + [c for c in seen if c in lone and c != head]
    if staged and head and staged != git(wt, "rev-parse", f"{head}^{{tree}}").stdout.strip():
        parents.append(git(wt, "commit-tree", staged, "-p", head, "-m", f"devkit discard {wt}: index", env=_devkit_env()).stdout.strip())
    return _keep_ref(main, os.path.basename(wt.rstrip(os.sep)), tree, parents, f"devkit discard {wt}")


def cmd_discard(cwd, args):
    """Gỡ một worktree mà `remove` từ chối, chỉ khi không mất gì: nó chỉ còn file đã xoá và rác IDE chưa track, HEAD của nó đã nằm trong
    trunk, và mọi luật khác của remove vẫn áp dụng (commit chỉ worktree giữ, submodule, bí mật chỉ nó có, worktree lồng, …). Không bao giờ
    gỡ worktree mà một phiên còn sống đang giữ: khoá devkit-kept / khoá của người dùng, phiên chủ trong state, khoá checkout. (Chế độ
    "worktree của chính phiên" đã bỏ, review 18/10: chứng minh "của mình" qua cây tiến trình không chắc; phiên tự gỡ worktree của mình bằng
    `remove` / `finish`.) Trước khi gỡ vẫn cất một bản phòng hờ vào refs/devkit/discarded/* (DISCARD_KEEP_DAYS ngày). Exit 0 đã gỡ, 1 từ
    chối (lý do trên stderr), 2 dùng sai."""
    if len(args) != 1:
        die("usage: agent-kit worktree discard <path>")
    wt = os.path.abspath(os.path.join(cwd, args[0]))
    main = main_checkout(cwd)
    if _same_path(wt, main):
        die(tr("đây là main checkout", "that is the main checkout"))
    entry = next((e for e in _worktree_entries(main)[1:] if not e["broken"] and _same_path(e["path"], wt)), None)
    if entry is None:
        die(tr(f"{wt}: git không liệt kê đường dẫn này là worktree liên kết của repo", f"{wt}: git does not list this path as a linked worktree of the repository"))
    wt = entry["path"]
    k = kept_lock(main, wt)
    if "locked" in entry and not (k and not k[2]):
        die(tr(f"{wt} đang bị khoá ({entry['locked'] or 'không lý do'}) bởi một phiên còn sống hoặc bởi người dùng: để yên "
               "(worktree của chính phiên: `agent-kit worktree remove` / `finish`)",
               f"{wt} is locked ({entry['locked'] or 'no reason'}) by a live session or by the user: left alone "
               "(the session's own worktree: `agent-kit worktree remove` / `finish`)"), 1)
    live = _live_holder(main, wt)
    if live:
        die(tr(f"{wt}: {live} — để yên", f"{wt}: {live} - left alone"), 1)
    head = git(wt, "rev-parse", "-q", "--verify", "HEAD^{commit}", check=False).stdout.strip()
    try:
        in_trunk = bool(head) and _chain_in_trunk(main, head)
        # `remove` so commit của worktree với HEAD của main checkout, mà PR squash trên origin để lại phía sau: UNREACHABLE của nó chỉ nói
        # "hơn main local". Bỏ qua khi trunk (local hoặc origin) đã giữ cả chuỗi và không commit nào chỉ còn trong reflog
        rows = inventory(cwd, only=wt, budget=None)   # một kiểm kê cho cả waive lẫn blocker: không lệch nhau giữa hai lần đọc
        waive = in_trunk and [r["reflog"] for r in rows] == [[]] \
            and git(wt, "rev-parse", "-q", "--verify", "HEAD^{commit}", check=False).stdout.strip() == head   # HEAD không đổi giữa hai lần đọc
        refused = [text for _code, kind, text, _detail in _iter_blockers(cwd, wt, args[0], None, rows=rows)
                   if kind != "uncommitted" and not (waive and kind == "unreachable")]
        refused += _discard_leftovers(wt)
    except UnicodeError as e:
        die(tr(f"không kiểm tra được {wt} (tên file không phải UTF-8: {e}) — không gỡ", f"cannot check {wt} (a file name that is not UTF-8: {e}) - nothing removed"), 1)
    if not in_trunk:   # một nhánh có tên giữ commit của nó, nhưng discard chỉ cho HEAD trunk đã có (audit T0044)
        refused.append(tr(f"{wt}: HEAD ({head[:12] or '?'}) có commit trunk chưa có (không là tổ tiên, gộp thử squash cũng thêm vào): đem về hoặc PR trước",
                          f"{wt}: HEAD ({head[:12] or '?'}) holds commits the trunk lacks (neither an ancestor nor a squash): bring them back or PR them first"))
    try:
        notes = _unsaved_memory(wt, main)
    except Exception:  # noqa: BLE001 - cannot say: refuse
        notes = ["(unreadable)"]
    if notes:   # bị git ignore nên bản cất không mang được: chép sang main trước
        refused.append(tr(f"{wt}: {len(notes)} memory note chỉ worktree có ({', '.join(notes[:5])}) — chép vào {os.path.join(main, MEMORY_REL)} trước",
                          f"{wt}: {len(notes)} memory note(s) only the worktree holds ({', '.join(notes[:5])}) - copy them into {os.path.join(main, MEMORY_REL)} first"))
    if refused:
        for t in refused:
            print("✖ worktree discard: " + t, file=sys.stderr)
        return 1
    ref = _discard_backup(main, wt)
    try:
        branch = _read_state(wt).get("branch")
    except (OSError, ValueError, SystemExit):
        branch = None
    _remove_checked(main, wt, branch or entry.get("branch"),
                    note=tr(f"; bản phòng hờ {ref} (giữ {DISCARD_KEEP_DAYS} ngày)", f"; a fallback copy is kept in {ref} for {DISCARD_KEEP_DAYS} days"))
    return 0


def _live_holder(main, wt):
    """Lý do `wt` đang thuộc một phiên CÒN SỐNG (review 18/10), '' khi không có bằng chứng sống: phiên chủ mà state ghi (`add --session`)
    có pid trả lời — ở bản ghi session_worktree hoặc ở registry (session_lock.owner_gone / info_alive) —, hoặc khoá checkout
    (devkit-session.lock trong git dir của nó) mang pid trả lời. Không nạp được session_lock: coi là còn sống (không gỡ)."""
    owner = _owner(wt)
    for d in (os.path.join(DEVKIT, "bin"), os.path.join(DEVKIT, "hooks")):
        if d not in sys.path:
            sys.path.append(d)   # sau stdlib: không gì trong bin/ hooks/ được che nó
    try:
        import session_lock  # noqa: PLC0415 - chỉ discard cần
        import session_worktree  # noqa: PLC0415
        if owner:
            dead, why = session_lock.owner_gone(main, owner, session_worktree, main)
            if (not dead and why == "alive") or session_lock.info_alive(session_lock.read_session(main, owner)):
                return tr(f"phiên chủ {owner} (state của worktree) còn sống", f"its owner session {owner} (the worktree's state) is alive")
            # không pid nào nói được (owner_gone "unknown" = coi là SỐNG, review 18/10): chỉ khi state đã quá 24 h, như việc nhận nuôi worktree
            if not dead and time.time() - os.lstat(os.path.join(git_dir(wt), STATE)).st_mtime < session_lock.RECORD_NO_PID_TAKEOVER_S:
                return tr(f"phiên chủ {owner} (state của worktree) chưa chứng minh được đã dừng (không pid nào, state chưa quá 24 h)",
                          f"its owner session {owner} (the worktree's state) is not proven gone (no pid anywhere, the state is under 24 h old)")
        lock = session_lock.read_checkout_lock(git_dir(wt))
        pid = (lock or {}).get("pid")
        if isinstance(pid, int) and pid > 1 and session_lock.is_pid_alive(pid):   # (idle ở prompt vẫn là phiên sống, review 18/10)
            return tr(f"phiên {lock.get('session_id', '?')} giữ khoá checkout của nó (pid {pid} còn sống)",
                      f"session {lock.get('session_id', '?')} holds its checkout lock (pid {pid} is alive)")
    except Exception as e:  # noqa: BLE001 - cannot tell who holds it: never removed
        return tr(f"không kiểm được phiên nào đang giữ nó ({e!r})", f"cannot tell which session holds it ({e!r})")
    return ""


def cmd_restore(cwd, args):
    """`git checkout <commit> -- <path>…` khi không có gì để mất: mọi path không có thay đổi chưa commit (so với HEAD, cả index, submodule,
    cả bản sửa git ẩn bằng skip-worktree / assume-unchanged), không giữ file chưa track, và không có file / thư mục bị ignore va chạm với
    một file của commit — trùng tên, là cha của nó (file `cfg` ↔ `cfg/a.txt`) hay là con của nó (thư mục `foo/` ↔ file `foo`): git đè hay
    xoá chúng im lặng (review + audit T0044, 18/10). Path tính từ thư mục đang đứng như git; không chạy ở main checkout của trunk mode."""
    if len(args) < 3 or args[1] != "--" or args[0].startswith("-") or any(not p for p in args[2:]):
        die("usage: agent-kit worktree restore <commit> -- <path>…")   # (path rỗng: git hiểu là cả thư mục đang đứng)
    rev, paths = args[0], args[2:]
    main = main_checkout(cwd)
    top = git(cwd, "rev-parse", "--show-toplevel").stdout.strip()
    if _same_path(top, main) and _trunk_mode(main):
        die(tr("main checkout của trunk mode chỉ để gộp: restore trong worktree của phiên", "the trunk-mode main checkout is merge-only: restore in the session's worktree"))
    sha = git(cwd, "rev-parse", "-q", "--verify", f"{rev}^{{commit}}", check=False).stdout.strip()
    if not sha:
        die(tr(f"không phải commit: {rev}", f"not a commit: {rev}"))
    lit, bad = ("--literal-pathspecs",), []
    for p in paths:
        for d in (git(cwd, *lit, "diff", "--quiet", "--ignore-submodules=none", "HEAD", "--", p, check=False),               # cây làm việc so với HEAD
                  git(cwd, *lit, "diff", "--cached", "--quiet", "--ignore-submodules=none", "HEAD", "--", p, check=False)):  # index so với HEAD (OCR 18/10)
            if d.returncode:
                bad.append(f"{p}: " + (tr("có thay đổi chưa commit", "has uncommitted changes") if d.returncode == 1 else (d.stderr or "").strip()[-200:]))
                break
    # Từ đây mọi đường dẫn tính từ gốc worktree (--full-name): cwd có thể là thư mục con (audit T0044)
    full = [os.path.normpath(os.path.relpath(os.path.join(cwd, p), top)) for p in paths]
    others = git(cwd, *lit, "ls-files", "--full-name", "-z", "--others", "--exclude-standard", "--", *paths, check=False)
    ignored = git(cwd, *lit, "ls-files", "--full-name", "-z", "--others", "--ignored", "--exclude-standard", "--", *paths, check=False)
    tracked = git(cwd, *lit, "ls-tree", "-r", "-z", "--name-only", "--full-name", sha, "--", *paths, check=False)
    try:
        hidden = _hidden_edits(top)
    except Exception:  # noqa: BLE001 - cannot say: refuse
        hidden = None
    if others.returncode or ignored.returncode or tracked.returncode or hidden is None:
        bad.append(tr("git không liệt kê được file chưa track / file git ẩn", "git could not list the untracked / hidden files"))
    else:
        under = lambda q: any(f == "." or q == f or q.startswith(f + "/") for f in full)   # noqa: E731 - q nằm trong một path được nêu
        new = [f for f in others.stdout.split("\0") if f]
        want = {t for t in tracked.stdout.split("\0") if t}
        dirs = {"/".join(t.split("/")[:i]) for t in want for i in range(1, t.count("/") + 1)}   # mọi thư mục cha của file commit mang
        clash = []
        for f in (f for f in ignored.stdout.split("\0") if f):   # file ignore trùng, hoặc nằm DƯỚI một file của commit (thư mục foo/ ↔ file foo)
            parts = f.split("/")
            if f in want or any("/".join(parts[:i]) in want for i in range(1, len(parts))):
                clash.append(f)
        for d in sorted(dirs):   # một file / link không được track đứng đúng chỗ thư mục cha của file commit mang (file cfg ↔ cfg/a.txt)
            dp = os.path.join(top, d)
            if (os.path.islink(dp) or (os.path.lexists(dp) and not os.path.isdir(dp))) \
                    and git(top, *lit, "ls-files", "--error-unmatch", "--", d, check=False).returncode:
                clash.append(d)
        shadow = [h for h in hidden if under(h)]
        if new:
            bad.append(tr("file chưa track sẽ bị lẫn: ", "untracked files in the way: ") + ", ".join(new[:10]))
        if clash:
            bad.append(tr("file / thư mục bị ignore sẽ bị đè hoặc xoá: ", "ignored files or folders it would overwrite or delete: ") + ", ".join(clash[:10]))
        if shadow:
            bad.append(tr("file git ẩn (skip-worktree / assume-unchanged) đang có sửa: ", "files git hides (skip-worktree / assume-unchanged) hold edits: ")
                       + ", ".join(shadow[:10]))
    if bad:
        for t in bad:
            print("✖ worktree restore: " + t, file=sys.stderr)
        return 1
    r = git(cwd, *lit, "checkout", sha, "--", *paths, check=False, bounded=False)
    if r.returncode:
        die((r.stderr or "").strip()[-400:], 1)
    print(f"✔ restore: {', '.join(paths[:5])}{' …' if len(paths) > 5 else ''} ← {sha[:12]}")
    return 0


def cmd_prune_branch(cwd, args):
    """`git branch -D <nhánh>` khi không mất gì: tip của nó đã nằm trong trunk (tổ tiên, hoặc squash: gộp thử ra đúng cây của trunk), hoặc một
    PR MERGED vào trunk có head đúng tip đó (gh); commit chỉ reflog của nhánh còn giữ được cất trước (_delete_branch). Không bao giờ: trunk
    và nhánh bảo vệ, nhánh một worktree đang checkout. `--remote` (yêu cầu qua phiên GeelyEx2, 18/10): xoá cả nhánh cùng tên trên origin
    (`git push --delete` mà guard chặn ở dạng trần), chỉ khi PR MERGED vào trunk có headRefOid đúng tip của nhánh REMOTE (ls-remote) và
    lệnh xoá kèm --force-with-lease đúng tip đó; kiểm cả hai phía trước, một phía không qua thì không xoá gì."""
    remote = "--remote" in args
    rest = [a for a in args if a != "--remote"]
    if len(rest) != 1:
        die("usage: agent-kit worktree prune-branch [--remote] <branch>")
    name = rest[0]
    if name.startswith("-") or git(cwd, "check-ref-format", "--branch", name, check=False).returncode:
        die(tr(f"tên nhánh không hợp lệ: {name}", f"not a valid branch name: {name}"))
    main = main_checkout(cwd)
    if name == _trunk_branch(main) or PROTECTED_BRANCH_RE.fullmatch(name):
        die(tr(f"{name} là trunk hoặc nhánh bảo vệ: không xoá", f"{name} is the trunk or a protected branch: not deleted"))
    ref = f"refs/heads/{name}"
    tip = git(main, "rev-parse", "-q", "--verify", f"{ref}^{{commit}}", check=False).stdout.strip()
    if not tip and not remote:
        die(tr(f"không có nhánh {name}", f"no branch {name}"))
    holders = [e["path"] for e in _worktree_entries(main) if e.get("branch") == name]
    if holders:
        die(tr(f"{name} đang được checkout ở {holders[0]}: gỡ worktree đó trước", f"{name} is checked out in {holders[0]}: remove that worktree first"), 1)
    pr = None
    if tip:
        in_trunk = _content_in_trunk(main, ref)
        pr = None if in_trunk else _merged_pr_at(main, name, tip)
        if pr is None and not in_trunk:
            print("✖ worktree prune-branch: " + tr(f"{name} ({tip[:12]}) còn commit trunk chưa có và không có PR MERGED vào trunk đúng tip đó: giữ",
                                                   f"{name} ({tip[:12]}) holds commits the trunk lacks and no PR merged into the trunk at that tip: kept"), file=sys.stderr)
            return 1
    rtip, rpr = "", None
    if remote:
        ls = git(main, "ls-remote", "--heads", "origin", ref, check=False)
        if ls.returncode:
            die(tr(f"không đọc được nhánh {name} trên origin: {(ls.stderr or '').strip()[-200:]}", f"cannot read branch {name} on origin: {(ls.stderr or '').strip()[-200:]}"), 1)
        rtip = next((l.split("\t", 1)[0] for l in ls.stdout.splitlines() if l.endswith("\t" + ref)), "")
        if rtip:
            rpr = _merged_pr_at(main, name, rtip)
            if rpr is None:
                print("✖ worktree prune-branch: " + tr(f"origin/{name} ({rtip[:12]}) không có PR MERGED vào trunk đúng tip đó (đi tiếp sau lần gộp?): không xoá gì",
                                                       f"origin/{name} ({rtip[:12]}) has no PR merged into the trunk at that tip (moved on after the merge?): nothing deleted"), file=sys.stderr)
                return 1
        elif not tip:
            die(tr(f"không có nhánh {name}, cả local lẫn trên origin", f"no branch {name}, neither local nor on origin"))
    done = []
    if rtip:   # remote TRƯỚC: lệnh push bị từ chối (lease lệch, mạng, quyền) thì nhánh local vẫn còn nguyên (OCR 18/10)
        r = git(main, "push", f"--force-with-lease={ref}:{rtip}", "origin", "--delete", ref, check=False, bounded=False)
        if r.returncode:
            die(tr(f"origin/{name}: git push --delete bị từ chối, không xoá gì: ", f"origin/{name}: git push --delete refused, nothing deleted: ")
                + (r.stderr or "").strip()[-300:], 1)
        done.append(f"origin/{name} ({rtip[:12]}) " + tr(f"PR #{rpr} đã MERGED đúng tip này", f"PR #{rpr} merged at this tip"))
    if tip:
        ok, kept = _delete_branch(main, name, tip)
        if not ok:
            die(f"{name}: {kept}" + (tr(" (nhánh trên origin đã xoá)", " (the origin branch is deleted)") if done else ""), 1)
        done.append(f"{name} ({tip[:12]}) " + (tr(f"PR #{pr} đã MERGED đúng tip này", f"PR #{pr} merged at this tip") if pr is not None
                                               else tr("đã nằm trong trunk", "is in the trunk"))
                    + (tr(f"; commit chỉ nhánh giữ đã cất ở {kept} ({DISCARD_KEEP_DAYS} ngày)",
                          f"; commits only the branch held are kept in {kept} ({DISCARD_KEEP_DAYS} days)") if kept else ""))
    print("✔ prune-branch: " + "; ".join(done) + tr(", đã xoá", ", deleted"))
    return 0


AUTOMERGE_LOCK = "devkit-automerge.lock"


def _trunk_branch(main):
    """The branch worktrees are merged into: origin's default branch, else the first of main / master / trunk that exists; None when
    neither can be told (then any branch the main checkout is on is accepted)."""
    r = git(main, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD", check=False)
    if r.returncode == 0 and "/" in r.stdout.strip():
        return r.stdout.strip().split("/", 1)[1]
    for name in ("main", "master", "trunk"):
        if git(main, "show-ref", "--verify", "-q", f"refs/heads/{name}", check=False).returncode == 0:
            return name
    return None


def _lock_file(path, wait=0.0, waiting=None):
    """An exclusive flock on `path`, held until the returned handle is closed. The kernel drops it when its holder dies, so it never goes
    stale, and a holder that lives is never taken over however long it runs; the file is never deleted (a waiter would then lock a dead
    inode). Review 14/10: the O_EXCL lock FILE this replaces let two waiters that both saw a dead holder's file take it over together,
    and one deleted between the failed create and the read made a waiter give up at once. Waits up to `wait` seconds (printing
    `waiting` once, on stderr: automerge's stdout is one JSON line); None when somebody else still holds it then. No fcntl (Windows
    Python) or no flock on this filesystem (NFS, SMB): the handle unlocked, said on stderr. Not a regular file (a planted FIFO, which
    an open() would wait on forever, a folder, a symlink) or not openable: OSError at once. The fd is not inherited (O_CLOEXEC)."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0), 0o600)   # POSIX-only flags
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError(errno.EINVAL, "not a regular file", path)
    fh = os.fdopen(fd, "a")
    try:
        import fcntl
        deadline = time.monotonic() + wait
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fh
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    fh.close()
                    return None
                if waiting:
                    print("• " + waiting, file=sys.stderr, flush=True)
                    waiting = None
                time.sleep(0.1)
    except (OSError, ImportError) as e:   # no fcntl, or ENOLCK / EOPNOTSUPP: unlocked
        # ponytail: no mutual exclusion where flock is missing (Windows Python, NFS/SMB) — automerge and MAIN_LOCK had an O_EXCL file there;
        # add an O_EXCL fallback (with the takeover races fixed) if a main checkout ever lives on such a filesystem
        print("• " + tr(f"không khoá được {os.path.basename(path)} ({e}); chạy không khoá",
                        f"cannot lock {os.path.basename(path)} ({e}); running unlocked"), file=sys.stderr)
        return fh


def _lock_automerge(wt):
    """One automatic merge per worktree at a time (the Stop hooks of two sessions may both start one). None: somebody else is merging it."""
    return _lock_file(os.path.join(git_dir(wt), AUTOMERGE_LOCK), wait=0.0)


MAIN_LOCK = "devkit-automerge-main.lock"
TEST_RUN_LOCK = "test_run.lock"   # in <worktree>/.claude/audit-gate: held by post-fix-gate, the Stop gates and stale_rerun while they test that tree


@contextlib.contextmanager
def _test_run_lock(wt):
    """The worktree's own test_run.lock for the merge of main INTO it, which rewrites the files a test run of that tree is reading (R3 review
    14/10, P2-6). Yields False when a test run holds it (never waited for: the caller skips the merge this time), else True with the lock held.
    Not for the gate that runs after it: post-fix-gate takes the same lock itself. Every other holder retries, so a few seconds cost them nothing.
    A lock that cannot be made (a planted FIFO, no flock here) is no lock, said on stderr: post-fix-gate's own 'never worse than no lock'."""
    d, lock = os.path.join(wt, ".claude", "audit-gate"), None
    try:
        os.makedirs(d, exist_ok=True)
        if not os.path.exists(os.path.join(d, ".gitignore")):
            with open(os.path.join(d, ".gitignore"), "w", encoding="utf-8") as fh:
                fh.write("*\n")
        lock = _lock_file(os.path.join(d, TEST_RUN_LOCK), wait=0.0)
        free = lock is not None
    except OSError as e:
        print("• " + tr(f"không khoá được {TEST_RUN_LOCK} ({e}); gộp không khoá", f"cannot lock {TEST_RUN_LOCK} ({e}); merging unlocked"), file=sys.stderr)
        free = True
    try:
        yield free
    finally:
        if lock is not None:
            lock.close()


def _unlink_quiet(path):
    try:
        os.unlink(path)
    except OSError:
        pass

MERGE_ROUNDS = 3   # W1 R3: merges of main into the worktree per finish / automerge; main moving past that: refused, run it again
MERGE_GATE_TIMEOUT_S = _env_seconds("WORKTREE_MERGE_GATE_TIMEOUT_S", 3600.0)
# K8 (17/10, Unity: 6 finish cùng lúc, 6 gate song song, tải 100–187 trên 12 nhân, test timeout thành FAIL): gate gộp của CÙNG một repo chạy lần
# lượt — flock trong git dir của main, giữ từ ngay trước gate đầu tiên tới sau fast-forward, nên người chờ thấy main đã đi tiếp, gộp nó vào rồi gate
# một lần. Chờ tối đa WORKTREE_MERGE_GATE_LOCK_WAIT_S một lần cho mỗi automerge; đã giữ khoá thì mỗi gate vẫn có đủ WORKTREE_MERGE_GATE_TIMEOUT_S.
# Trần mỗi lần automerge: LOCK_WAIT + MERGE_ROUNDS × TIMEOUT (+ 180 s khoá main); hết chờ = "running" (không "moved": finish không tự chạy lại).
MERGE_GATE_LOCK = "devkit-merge-gate.lock"
MERGE_GATE_LOCK_WAIT_S = _env_seconds("WORKTREE_MERGE_GATE_LOCK_WAIT_S", MERGE_GATE_TIMEOUT_S)
MERGE_GATE_RESULT = "devkit-merge-gate.json"   # in the worktree's git dir: the last red verdict, for (worktree HEAD, main HEAD)
MERGE_GATE_RESULT_TTL_S = _env_seconds("WORKTREE_MERGE_GATE_RESULT_TTL_S", 1200.0)   # a load-made FAIL must not stick: re-gated after this
MATRIX_REL = os.path.join(".agents", "regression_matrix.active.json")


def _gate_matrix(main):
    """The regression matrix the merge gate uses: MAIN's, the side it protects — a worktree that dropped or weakened its own copy is still
    gated with main's mandatory tests (OCR 14/10). "" = no gate: WORKTREE_TRUNK_MODE=0, or main has no matrix (no mandatory test protects
    main yet; a matrix the worktree brings is new, so the gate would not trust it and would run nothing anyway). Asked BEFORE a kept
    verdict is replayed: the opt-out must work after a refusal."""
    if os.environ.get("WORKTREE_TRUNK_MODE", "1") == "0":
        return ""
    m = os.path.join(main, MATRIX_REL)
    return m if os.path.isfile(m) else ""


def _merge_gate(wt, base, matrix):
    """W1 R3: the gate on what the worktree brings (`--diff base`, `base` = the main it merged; K8: or the worktree HEAD that passed a
    round ago, so only what main brought since is gated) BEFORE main moves — a merge with no
    textual conflict can still break (main renamed what a new caller in the worktree uses). (None, False): it passes, there is nothing
    to audit (exit 3). Otherwise (reason, verdict): a regression test that FAILed (verdict True: the same commits get the same answer,
    kept), or one that TIMED OUT, tests that could not run because another run holds the lock, or a gate that did not finish (verdict
    False: often the machine's load, so tried again next time), refuse. What the session owes (an edited test to approve, an untested file) is its own gate's
    business, and a suite that cannot run here (no device) never strands a merge. Past WORKTREE_MERGE_GATE_TIMEOUT_S the gate gets
    SIGTERM (it stops its suites and puts back what it reverted), then SIGKILL; VACUITY_REVERT=0, so it reverts nothing here."""
    gate = os.path.join(DEVKIT, "bin", "post-fix-gate.py")
    try:
        p = subprocess.Popen([sys.executable, gate, "--run-tests", "--brief", "--json", "--diff", base, "--matrix", matrix], cwd=wt,
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             env=dict(os.environ, CLAUDE_PROJECT_DIR=wt, VACUITY_REVERT="0",
                                      # #154: its exit 2 (what the session owes) leaves the session's gate receipt as it is
                                      DEVKIT_GATE_MERGE_CHECK="1",
                                      # P1 (20/10): gộp vào main chặn người khác — đứng đầu hàng đợi khoá Unity;
                                      # đặt hẳn merge (giá trị của phiên gọi, vd interactive, không được thay — OCR 20/10)
                                      DEVKIT_SLOT_PRIORITY="merge"))
    except OSError as e:
        return tr(f"gate không chạy được ({e})", f"the gate did not start ({e})"), False
    try:
        out, err = p.communicate(timeout=MERGE_GATE_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        p.terminate()
        try:
            p.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            p.kill()
            p.communicate()
        return tr(f"gate không chạy xong trong {MERGE_GATE_TIMEOUT_S:g} s (WORKTREE_MERGE_GATE_TIMEOUT_S)",
                  f"the gate did not finish within {MERGE_GATE_TIMEOUT_S:g} s (WORKTREE_MERGE_GATE_TIMEOUT_S)"), False
    if p.returncode == 3:   # nothing to audit: the worktree brings nothing net (its work came back by hand, or was reverted)
        return None, False
    try:
        res = json.loads((out.strip().splitlines() or [""])[-1])
    except ValueError:
        res = None
    tests = res.get("regression_tests", []) if isinstance(res, dict) else None
    if not isinstance(tests, list) or not all(isinstance(x, dict) for x in tests):
        # no JSON object on the last line, or its tests no list of objects (`null`, `3`, `[null]` parse too: the gate died early, or something
        # else printed last) = no result, refused — never an AttributeError that leaves the Stop hook without its JSON line (OCR 14/10)
        return tr(f"gate không trả kết quả (exit {p.returncode}): ", f"the gate gave no result (exit {p.returncode}): ") + (err or out).strip()[-300:], False
    if res.get("busy"):
        return tr("một lần chạy test khác đang giữ khoá của worktree: chưa kiểm được, chạy lại sau",
                  "another test run holds the worktree's lock: nothing was checked, run it again later"), False
    if res.get("budget_exhausted"):   # mandatory suites cut by GATE_TOTAL_BUDGET_S never ran: no pass (OCR 14/10)
        return tr("gate hết ngân sách thời gian (GATE_TOTAL_BUDGET_S) trước khi chạy hết test bắt buộc: chạy lại",
                  "the gate ran out of its time budget (GATE_TOTAL_BUDGET_S) before every mandatory test ran: run it again"), False
    bad = [x for x in tests if x.get("status") in ("FAIL", "TIMEOUT")]
    if bad:
        return (tr("test hồi quy ĐỎ trên kết quả gộp: ", "regression tests RED on the merged result: ")
                + ", ".join(f"{x.get('id')} {x.get('status')}" for x in bad) + f" ({res.get('report', '')})",
                any(x.get("status") == "FAIL" and not x.get("flaky") for x in bad))   # failed, then passed on a retry: not kept
    return None, False


def _gate_refusal(wt, why):
    return "blocked", tr(f"gate trên những gì worktree mang vào main KHÔNG qua: {why}. Main không đổi; worktree giữ nguyên (cả commit gộp nếu có) — sửa "
                         f"trong worktree rồi chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                         f"the gate on what the worktree brings into main did NOT pass: {why}. Main is unchanged; the worktree is kept as it is "
                         f"(its merge commit too) - fix it there, then run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"gate": True}


def _authored_status_changed(wt):
    """True when the worktree's regression_status.json differs from HEAD's in a row a PERSON made (the rows nothing regenerates)."""
    old = git(wt, "show", f"HEAD:{STATUS_FILE}", check=False)
    try:
        with open(os.path.join(wt, STATUS_FILE), encoding="utf-8") as f:
            cur = json.load(f)
        prev = json.loads(old.stdout) if old.returncode == 0 else {"items": {}}
        a = {k: _authored(v) for k, v in cur["items"].items() if _authored(v) is not None}
        b = {k: _authored(v) for k, v in prev["items"].items() if _authored(v) is not None}
        return a != b
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return True   # cannot tell: treat it as work


SECRET_FILES = LOCAL_CONFIG + (".netrc", "*.p8", "AuthKey_*", "*serviceAccount*.json", "*service-account*.json", "credentials*.json",
                               "key.properties")   # extras on top of the gate's list (key.properties: Flutter / Unity Android signing, holds storePassword)
_GATE_SECRETS = []


def _secret_like(path):
    """True for a path the post-fix gate's own forbidden-file rules reject (FORBIDDEN_SECRET_FILES: one classifier, INSTINCT-015), a name in
    SECRET_FILES, and not an exact template (.env.example, ...), whatever the case of the name (Release.JKS: `worktree gc` already matched its
    GC_SECRETS that way). The gate module is read once; if it cannot be, a short built-in list stands in."""
    if not _GATE_SECRETS:
        try:
            spec = importlib.util.spec_from_file_location("post_fix_gate_rules", os.path.join(DEVKIT, "bin", "post-fix-gate.py"))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            _GATE_SECRETS.append(([re.compile(p, re.I) for p, _label in mod.FORBIDDEN_SECRET_FILES], tuple(mod.SAFE_TEMPLATE_SUFFIXES)))
        except Exception:  # noqa: BLE001 - a rules file that cannot be loaded must not stop a merge that the built-in list can still guard
            _GATE_SECRETS.append(([re.compile(r"\.(keystore|jks|p12|pfx|mobileprovision|pem|key)$", re.I), re.compile(r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$", re.I)],
                                  (".example", ".sample", ".template", ".dist")))
    pats, suffixes = _GATE_SECRETS[0]
    if path.lower().endswith(suffixes):
        return False
    base = os.path.basename(path).lower()
    return any(p.search(path) for p in pats) or any(fnmatch.fnmatchcase(base, pat.lower()) for pat in SECRET_FILES)


def _carry_skip_dirs():
    """Folder names whose files are never carried back into main (A.1b #12): rebuilt or downloaded ones only — GC_BUILD_DIRS and the usual
    dependency folders. A package's own test key there (node_modules/**/test.pem) would differ from main's copy and refuse every removal; a
    key copied into main's build/ would be wiped by the next clean. NOT build_inputs.SKIP_WALK (what `worktree add` never copies in): it
    also names .agents, .claude, .idea and Logs, which are no rebuildable folders - .agents/local/ is where the kit keeps long-lived files."""
    return GC_BUILD_DIRS | {".git", ".venv", "venv", ".kotlin", "vendor", "bower_components", "jspm_packages", ".tox", ".nox", ".bundle", ".terraform",
                            ".yarn", ".pnpm-store", ".cache", "site-packages", ".nuxt", ".svelte-kit", ".parcel-cache", ".turbo", ".expo"}


def _ignored_secrets(wt, limit=None):
    """A.1b #12: ([(rel, absolute path)], cut) — the git-ignored, secret-like (_secret_like) REGULAR files of worktree `wt`: no link, nothing
    under a _carry_skip_dirs() folder. A folder git lists whole as ignored is walked (links never followed), `limit` files at most
    (WORKTREE_SECRET_SCAN_MAX, 200000; 0: no limit); `cut`: the ignored folder the walk stopped in ("" when it read everything): what it
    did not read may hold a key, so the caller must keep the worktree. SystemExit when git cannot list them."""
    limit = _env_limit("WORKTREE_SECRET_SCAN_MAX", 200000) if limit is None else limit
    skip = _carry_skip_dirs()
    r = _git_bytes(wt, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory")
    if r.returncode != 0:
        raise SystemExit(f"✖ worktree: git ls-files --ignored: {r.stderr.decode('utf-8', 'replace').strip()}")
    found, seen, cut = {}, 0, ""
    for ent in r.stdout.decode("utf-8", "surrogateescape").split("\0"):
        parts = ent.rstrip("/").split("/")
        if not ent or any(p in skip for p in (parts if ent.endswith("/") else parts[:-1])):
            continue
        names = [ent]
        if ent.endswith("/"):
            names = []
            for d, dirs, files in os.walk(os.path.join(wt, ent)):
                dirs[:] = [x for x in dirs if x not in skip and not os.path.islink(os.path.join(d, x))]
                names += [os.path.relpath(os.path.join(d, f), wt).replace(os.sep, "/") for f in files]
                seen += len(files)
                if limit and seen > limit:   # a huge ignored folder outside the skip list (a cache): not read to the end, so not removed either
                    cut = ent
                    break
        for rel in names:
            try:
                if _secret_like(rel) and stat.S_ISREG(os.lstat(os.path.join(wt, rel)).st_mode):
                    found[rel] = os.path.join(wt, rel)
            except OSError:
                continue   # gone meanwhile: nothing to carry
        if cut:
            break
    for rel, stamp in _copied_at_add(wt).items():   # a copy `worktree add` made and nobody changed is main's, not a key made here
        try:
            if rel in found and _sha256_file(found[rel]) == stamp:
                del found[rel]
        except OSError:
            continue   # unreadable: it stays a candidate (the carry refuses it by name)
    return sorted(found.items()), cut


def _sha256_file(path):
    return hashlib.sha256(_read_regular(path)).hexdigest()


def _copy_stamps(wt, rels):
    """{rel: sha256} of the secret-like files `worktree add` just copied into `wt` (state: copied_sha): only those the carry-back could meet."""
    stamps = {}
    for rel in rels:
        try:
            if _secret_like(rel):
                stamps[rel] = _sha256_file(os.path.join(wt, rel))
        except OSError:
            continue   # no stamp: it is judged like a key made here, as before
    return stamps


def _copied_at_add(wt):
    """The copied_sha `worktree add` recorded in the worktree's state; {} for a worktree without it (made before, adopted) or an unreadable state."""
    try:
        got = _read_state(wt).get("copied_sha")
    except (OSError, ValueError, SystemExit):
        return {}
    return {k: v for k, v in got.items() if isinstance(k, str) and isinstance(v, str)} if isinstance(got, dict) else {}


def _same_bytes(src, dst):
    """True when `dst` is a regular file (not a link) holding the bytes of `src`; False for anything else, also a file that cannot be read."""
    try:
        return not os.path.islink(dst) and _read_regular(dst) == _read_regular(src)
    except OSError:
        return False


def _carry_secrets(main, items):
    """A.1b #12: put each (rel, src) — a secret-like file only a worktree (or a leftover folder) holds — at the same path in the main checkout,
    BEFORE that folder is deleted. Never overwrites: the same bytes already there need nothing; anything else there (other bytes, a link, a
    folder), a path main tracks, or a parent in main that is a link or a file is refused. A path main's own rules do not ignore first gets an
    anchored line in main's .git/info/exclude, checked again (a negation in a .gitignore outranks it: refused). Copied with O_EXCL (mode: the
    source's, at most 0600; new folders 0700) and read back byte for byte; a copy that does not verify is deleted. (copied, [(rel, why)])."""
    copied, refused, todo = [], [], []
    for rel, src in items:
        try:
            data, mode = _read_regular(src), stat.S_IMODE(os.lstat(src).st_mode) & 0o600 | 0o400   # (the owner can always read it back)
        except OSError as e:
            refused.append((rel, tr(f"không đọc được: {e}", f"unreadable: {e}")))
            continue
        dst = os.path.join(main, rel)
        if os.path.lexists(dst):
            try:
                same = not os.path.islink(dst) and _read_regular(dst) == data
            except OSError:
                same = False
            if not same:
                refused.append((rel, tr("main có thứ KHÁC ở đúng đường dẫn này: không bao giờ ghi đè", "main has something DIFFERENT at that path: never overwritten")))
            continue
        cur, bad = main, "\n" in rel or "\r" in rel
        for part in rel.split("/")[:-1]:
            cur = os.path.join(cur, part)
            if not os.path.lexists(cur):
                break
            if os.path.islink(cur) or not os.path.isdir(cur):
                bad = True
                break
        if bad:
            refused.append((rel, tr("đường dẫn ở main đi qua một link hoặc file, hoặc tên có ký tự xuống dòng", "its path in main runs through a link or a file, or its name has a line break")))
            continue
        todo.append((rel, src, dst, data, mode))
    if not todo:
        return copied, refused

    def tracked_in_main(paths):   # literal pathspecs: a name with * or [ is no pattern; None when git fails
        r = _git_bytes(main, "--literal-pathspecs", "ls-files", "-z", "--", *paths)
        return set(r.stdout.decode("utf-8", "surrogateescape").split("\0")) if r.returncode == 0 else None

    def ignored_in_main(paths):   # check-ignore takes no literal magic; "./" keeps a name that starts with ':' from reading as magic
        r = _git_bytes(main, "check-ignore", "-z", "--stdin", inp=("".join("./" + p + "\0" for p in paths)).encode("utf-8", "surrogateescape"))
        return {p[2:] for p in r.stdout.decode("utf-8", "surrogateescape").split("\0") if p} if r.returncode in (0, 1) else None

    tracked = tracked_in_main([t[0] for t in todo])
    ignored = ignored_in_main([t[0] for t in todo])
    if tracked is None or ignored is None:
        return copied, refused + [(t[0], tr("git không kiểm được ở main", "git could not check it in main")) for t in todo]
    need = [t[0] for t in todo if t[0] not in tracked and t[0] not in ignored]
    if need:
        try:
            ex = os.path.join(main, git(main, "rev-parse", "--git-path", "info/exclude").stdout.strip())
            try:
                prev = _read_regular(ex)
            except FileNotFoundError:
                prev = b""
                os.makedirs(os.path.dirname(ex), exist_ok=True)
            fd = os.open(ex, os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0), 0o644)
            try:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    raise OSError(errno.EINVAL, "not a regular file", ex)
                os.write(fd, (("" if not prev or prev.endswith(b"\n") else "\n") + "# DevKit worktree: secret files copied back from a worktree (A.1b #12)\n"
                              + "".join("/" + re.sub(r"([\\*?\[ ])", r"\\\1", p) + "\n" for p in need)).encode("utf-8", "surrogateescape"))
            finally:
                os.close(fd)
        except (OSError, SystemExit) as e:
            return copied, refused + [(p, tr(f"không thêm được vào .git/info/exclude của main: {e}", f"could not add it to main's .git/info/exclude: {e}")) for p in need]
        ignored |= ignored_in_main(need) or set()
    for rel, src, dst, data, mode in todo:
        if rel in tracked or rel not in ignored:
            refused.append((rel, tr("main theo dõi đường dẫn này", "main tracks that path") if rel in tracked else
                                 tr("không làm cho git ở main ignore nó được (một dòng ! trong .gitignore?)", "it cannot be made git-ignored in main (a ! line in a .gitignore?)")))
            continue
        made = False
        try:
            cur = main
            for part in rel.split("/")[:-1]:   # one by one: makedirs(mode=) applies it to the last folder only, its parents get 0777 & ~umask
                cur = os.path.join(cur, part)
                try:
                    os.mkdir(cur, 0o700)
                except FileExistsError:
                    pass
            fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0), 0o600)
            made = True
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
                fh.flush()
                os.fchmod(fh.fileno(), mode)
                os.fsync(fh.fileno())
            if _read_regular(dst) != data or _read_regular(src) != data:   # the copy, and the file the removal deletes, hold what was read
                raise OSError(errno.EIO, "the copy does not read back the same as the source", dst)
            copied.append(rel)
        except OSError as e:
            if made:
                _unlink_quiet(dst)
            refused.append((rel, tr(f"chép sang main không được: {e}", f"could not copy it into main: {e}")))
    return copied, refused


def _staged_merge_refusal(wt):
    """Issue #14: `git commit --no-edit` on an open merge commits everything staged and never reaches _commit_pending's scan. A staged
    path that differs from BOTH parents (HEAD and MERGE_HEAD: what main brought is not the worktree's to answer for) gets the same two
    checks: a secret-looking file, or a symlink HEAD does not hold as a link, stops the merge before anything is committed.
    None when clean, else a (status, message, extra) refusal."""
    def staged(against):
        r = git(wt, "diff", "--cached", "--name-only", "-z", against, check=False)
        return set(filter(None, r.stdout.split("\0"))) if r.returncode == 0 else None
    mine, theirs = staged("HEAD"), staged("MERGE_HEAD")
    if mine is None or theirs is None:
        return "blocked", tr("không đọc được phần đã stage của merge đang mở: không kết thúc nó", "cannot read the staged part of the open merge: not concluding it"), {}
    own = sorted(mine & theirs)
    secret = [p for p in own if _secret_like(p)]
    if secret:
        return ("blocked", tr(f"{len(secret)} file giống bí mật đã stage trong merge đang mở sẽ không được tự commit: {', '.join(secret[:6])}. `git rm --cached` rồi thêm vào "
                              f".gitignore hoặc chuyển ra ngoài; chưa có gì bị commit hay gộp", f"{len(secret)} secret-looking file(s) staged in the open merge are never "
                              f"committed automatically: {', '.join(secret[:6])}. `git rm --cached` them and ignore or move them out; nothing was committed or merged"),
                {"files": secret[:20]})
    if not own:
        return None
    lit = dict(os.environ, GIT_LITERAL_PATHSPECS="1")
    # Merge được kết thúc bằng `git commit --no-edit`, thứ ghi nội dung INDEX: xét mode đã stage (120000 = symlink) thay vì islink trên đĩa.
    # Ca 5 của tests/worktree_git/test_worktree_automerge_staged_secret.sh: stage một link rồi đặt file thường (chưa stage) đè lên,
    # islink trả False và link vẫn vào merge commit.
    r = git(wt, "ls-files", "-s", "-z", "--", *own, check=False, env=lit)
    if r.returncode != 0:
        return "blocked", tr("không đọc được mode đã stage của merge đang mở: không kết thúc nó", "cannot read the staged modes of the open merge: not concluding it"), {}
    links = sorted({rec.partition("\t")[2] for rec in r.stdout.split("\0") if rec.partition("\t")[0].split()[:1] == ["120000"]})
    if links:
        held = {rec.partition("\t")[2] for rec in git(wt, "ls-tree", "-r", "-z", "HEAD", "--", *links, check=False, env=lit).stdout.split("\0")
                if rec.partition("\t")[0].split()[:1] == ["120000"]}
        new = [p for p in links if p not in held]
        if new:
            return ("blocked", tr(f"{len(new)} symlink mới đã stage trong merge đang mở sẽ không được tự commit: {', '.join(new[:6])}. `git rm --cached` nó; chưa có gì bị commit hay gộp",
                                  f"{len(new)} new symlink(s) staged in the open merge are never committed automatically: {', '.join(new[:6])}. `git rm --cached` them; "
                                  "nothing was committed or merged"), {"files": new[:20]})
    return None


def _commit_pending(wt, state):
    """REFUSE the worktree's uncommitted real work, naming the files (#366: it used to become a `wip(...)` commit that went straight into
    main without a PR or review). Bookkeeping the gate and the
    hooks regenerate is put back to HEAD (a file HEAD does not have is deleted), except the rows a person made. A local-config or
    secret-looking file, or a symlink HEAD does not have, is NEVER committed on its own: the whole merge stops, naming it, before
    anything is touched (A.4: a `node_modules` link made to run npm test was committed, and the fast-forward put it in place of main's
    real, ignored node_modules/). None when done, else a (status, message, extra) refusal."""
    changed = changes_since(wt, state)
    if not changed:
        return None
    book = [p for p in changed if p in BOOKKEEPING and not (p == STATUS_FILE and _authored_status_changed(wt))]
    work = [p for p in changed if p not in book and not _is_durations_hint(p)]   # #365: gợi ý thứ tự test, không phải việc (cùng luật với _iter_blockers)
    secret = [p for p in work if _secret_like(p)]
    if secret:
        return ("blocked", tr(f"{len(secret)} file cấu hình cục bộ / giống bí mật sẽ không được tự commit: {', '.join(secret[:6])}. Thêm vào .gitignore, chuyển ra ngoài, "
                              f"hoặc tự commit nếu cố ý; chưa có gì bị commit hay gộp", f"{len(secret)} local-config / secret-looking file(s) are never committed "
                              f"automatically: {', '.join(secret[:6])}. Add them to .gitignore, move them out, or commit them yourself if meant; nothing was committed or merged"),
                {"files": secret[:20]})
    links = [p for p in work if os.path.islink(os.path.join(wt, p))]
    if links:   # (staged or not: `git add -A` would have staged one) a link HEAD already holds AS A LINK (mode 120000), retargeted, is ordinary work;
        # a tracked regular file replaced by a link is not (main's config.json would become a link, to itself when it points at main's own copy)
        held = {rec.partition("\t")[2] for rec in git(wt, "ls-tree", "-r", "-z", "HEAD", "--", *links, check=False,
                                                       env=dict(os.environ, GIT_LITERAL_PATHSPECS="1")).stdout.split("\0")
                if rec.partition("\t")[0].split()[:1] == ["120000"]}
        new = [p for p in links if p not in held]
        if new:
            def shown(p):
                try:
                    return f"{p} -> {os.readlink(os.path.join(wt, p))}"
                except OSError:
                    return p
            listing = ", ".join(shown(p) for p in new[:6])
            return ("blocked", tr(f"{len(new)} symlink mới (HEAD chưa giữ dưới dạng link) không bao giờ được tự commit: {listing}. Link tạo để mượn node_modules / cache build của main "
                                  "không phải là việc: xoá nó (hoặc ignore bằng mẫu KHÔNG có dấu / cuối: `node_modules/` chỉ khớp thư mục, không khớp link); nếu link "
                                  "đúng là một phần của repo thì tự `git add` + `git commit` nó trong worktree; chưa có gì bị commit hay gộp",
                                  f"{len(new)} new symlink(s) (HEAD does not hold them as links) are never committed automatically: {listing}. A link made to borrow main's node_modules / "
                                  "build cache is not work: delete it (or ignore it with a pattern WITHOUT the trailing slash: `node_modules/` matches a directory, not a "
                                  "link); if the link belongs in the repository, `git add` + `git commit` it in the worktree yourself; nothing was committed or merged"),
                    {"files": new[:20]})
    if work:   # #366: việc thật chưa commit không bao giờ bị tự gói thành commit wip đưa thẳng vào main (không qua PR/review): từ chối, nêu file
        return ("blocked", tr(f"{len(work)} file chưa commit trong worktree: {', '.join(work[:6])}. finish không tự commit việc thật: "
                              f"commit chúng trong {shlex.quote(wt)} (`git add <file>` rồi `git commit`), sau đó chạy lại; chưa có gì bị commit hay gộp",
                              f"{len(work)} uncommitted file(s) in the worktree: {', '.join(work[:6])}. finish never commits real work for you: "
                              f"commit them in {shlex.quote(wt)} (`git add <file>` then `git commit`), then run it again; nothing was committed or merged"),
                {"files": work[:20]})
    if book:
        in_head = set(git(wt, "ls-tree", "-r", "--name-only", "HEAD", "--", *book, check=False).stdout.split("\n"))
        tracked = [p for p in book if p in in_head]
        if tracked:
            git(wt, "checkout", "HEAD", "--", *tracked, check=False, bounded=False)
        for p in book:
            if p not in in_head:
                try:
                    os.unlink(os.path.join(wt, p))
                except OSError:
                    pass
    return None


def _conflict(wt, unmerged):
    # K6 (17/10): lời khuyên dùng `cd <wt> && git ...`, không `git -C <wt>`: harness của Claude chặn `git -C` với đường dẫn tính lúc chạy
    return ("conflict", tr(f"xung đột khi gộp main vào worktree ở {len(unmerged)} file: {', '.join(unmerged[:8])}. Sửa NGAY trong {wt} (đây là thư mục riêng, an toàn): "
                           f"bỏ dấu <<<<<<< ======= >>>>>>> giữ đúng ý cả hai bên, `cd {shlex.quote(wt)} && git add <file> && git commit --no-edit`; xong chạy lại "
                           f"`agent-kit worktree finish {shlex.quote(wt)}` (nó fast-forward main và gỡ worktree)",
                           f"conflict merging main into the worktree in {len(unmerged)} file(s): {', '.join(unmerged[:8])}. Resolve it NOW in {wt} "
                           f"(a folder of its own, so it is safe): remove the <<<<<<< ======= >>>>>>> markers keeping what both sides meant, "
                           f"`cd {shlex.quote(wt)} && git add <file> && git commit --no-edit`; then run `agent-kit worktree finish {shlex.quote(wt)}` again "
                           f"(it fast-forwards main and removes the worktree)"), {"files": unmerged})


def _carry_gate_receipt(main, wt):
    """Issue #5 (trunk mode): biên nhận gate --full của worktree nằm dưới git dir riêng của nó và mất khi gỡ worktree, còn main chỉ nhận
    merge nên `git push` từ main không còn biên nhận nào. Biên nhận nào bin/push_gate.py xác nhận phủ HEAD mới của main (cùng luật như
    biên nhận của main) thì chép sang git dir của main: `project` trỏ về main, `carried_from` giữ project gốc để push_gate khớp dòng
    runs.jsonl của lần gate đó (runs.jsonl ở common dir, sống qua việc gỡ worktree). Gọi sau mỗi lần main fast-forward (cả `--keep`
    của hook Stop: worktree có thể bị gỡ sau đó bằng `worktree remove` / WorktreeRemove). Trả câu ghi chú cho thông báo, luôn nói đã
    chép hay chưa; lỗi nào cũng chỉ thành ghi chú (fail-closed: không chép thì push từ main bị chặn tới khi gate lại)."""
    try:
        bin_dir = os.path.join(DEVKIT, "bin")
        if bin_dir not in sys.path:
            sys.path.insert(0, bin_dir)
        import push_gate  # noqa: PLC0415 - module anh em trong bin/, chỉ nạp khi gộp xong
        head = git(main, "rev-parse", "HEAD").stdout.strip()
        if not push_gate.check(wt, head, linked=True)[0]:
            return tr(" (không có biên nhận gate --full nào của worktree phủ HEAD mới của main: push từ main cần chạy gate lại)",
                      " (no gate --full receipt of the worktree covers main's new HEAD: a push from main needs the gate again)")
        receipt = json.loads(_read_regular(push_gate.tree_fp.receipt_path(wt), 4_000_000).decode("utf-8"))
        rel = os.path.relpath(os.path.realpath(receipt["project"]), os.path.realpath(wt))
        receipt = dict(receipt, project=os.path.normpath(os.path.join(main, rel)), carried_from=receipt["project"])
        dst = push_gate.tree_fp.receipt_path(main)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst), prefix=".full_pass.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(receipt, fh)
            os.replace(tmp, dst)   # thay cả một symlink đặt sẵn ở dst, không ghi theo nó
        except BaseException:
            _unlink_quiet(tmp)
            raise
    except (Exception, SystemExit) as e:   # kit cài dở (ImportError), biên nhận hỏng, lỗi ghi: báo trong thông báo, không chặn việc gộp
        return tr(f" (không chép được biên nhận gate sang main: {type(e).__name__}: {e}; push từ main cần chạy gate lại)",
                  f" (the gate receipt could not be copied into main: {type(e).__name__}: {e}; a push from main needs the gate again)")
    return tr(" (biên nhận gate --full đã chép sang main)", " (gate --full receipt copied into main)")


IDENTICAL_OVERLAP_MAX = 500   # ponytail: kiểm từng đường dẫn trùng một lần hash-object; quá số này thì từ chối như cũ, nâng khi có repo cần


def _stage_identical_overlap(main, main_head, w_head):
    """17/10: main giữ CHƯA commit đúng nội dung mà commit của worktree mang về (bản triển khai chép thẳng vào main) thì `merge --ff-only`
    từ chối dù không mất gì, và trunk mode cấm agent tự stage ở main: không ai gộp được. Stage đúng các đường dẫn trùng khi MỌI đường dẫn
    đều: index ở main còn bằng HEAD, là file thường (không link, không thư mục), mode và byte giống hệt blob commit mang về; file chưa track
    chỉ khi git không ignore nó. Một đường dẫn sai là không stage gì: git từ chối như trước. Trả về danh sách đã stage ([] nếu không)."""
    r = git(main, "diff", "--no-renames", "--name-status", "-z", main_head, w_head, check=False)
    if r.returncode:
        return []
    parts = [p for p in r.stdout.split("\0") if p]
    changes = dict(zip(parts[1::2], parts[0::2]))   # đường dẫn -> A/M/D/T
    if not changes:
        return []
    dirty = git(main, "diff", "--name-only", "-z", check=False)
    cached = git(main, "diff", "--cached", "--name-only", "-z", check=False)
    # chỉ file commit thêm vào mà main đang có sẵn trên đĩa mới cần hỏi git (commit thêm hàng nghìn file thì argv không phình)
    added = [p for p, s in changes.items() if s == "A" and os.path.lexists(os.path.join(main, p))]
    if len(added) > IDENTICAL_OVERLAP_MAX:
        return []
    untracked = git(main, "ls-files", "--others", "--exclude-standard", "-z", "--", *(":(literal)" + p for p in added), check=False) if added else None
    if dirty.returncode or cached.returncode or (untracked is not None and untracked.returncode):
        return []
    dirty_set, cached_set = set(dirty.stdout.split("\0")) - {""}, set(cached.stdout.split("\0")) - {""}
    untracked_set = set(untracked.stdout.split("\0")) - {""} if untracked is not None else set()
    # file commit thêm vào: chỉ khi CHƯA track (một entry `git add -N` của phiên khác hiện trong `git diff`, không trong --cached)
    overlap = [p for p in changes if (p in untracked_set if changes[p] == "A" else p in dirty_set)]
    if not overlap or len(overlap) > IDENTICAL_OVERLAP_MAX or any(p in cached_set or changes[p] not in ("A", "M") for p in overlap):
        return []
    tree = git(main, "ls-tree", "-z", w_head, "--", *(":(literal)" + p for p in overlap), check=False)
    if tree.returncode:
        return []
    want = {}
    for line in (l for l in tree.stdout.split("\0") if l):
        meta, _, path = line.partition("\t")
        mode, kind, oid = meta.split()
        want[path] = (mode, oid)
    for p in overlap:
        mode, oid = want.get(p, (None, None))
        if mode not in ("100644", "100755"):   # link, submodule: không tự xử lý (A.4)
            return []
        full = os.path.join(main, p)
        try:
            st = os.lstat(full)   # lstat: link trỏ tới file thường không được tính là file thường
            if not stat.S_ISREG(st.st_mode) or ("100755" if st.st_mode & 0o100 else "100644") != mode:
                return []
            data = _read_regular(full)   # không treo trên FIFO (INSTINCT-040)
        except OSError:
            return []
        h = git(main, "hash-object", "--no-filters", "--stdin", inp=data, check=False)
        if h.returncode or h.stdout.decode("ascii", "replace").strip() != oid:
            return []
    specs = [":(literal)" + p for p in overlap]
    if git(main, "add", "--", *specs, check=False, bounded=False).returncode == 0:
        staged = git(main, "ls-files", "-s", "-z", "--", *specs, check=False)
        got = {}
        for line in (l for l in staged.stdout.split("\0") if l):
            meta, _, path = line.partition("\t")
            m, o, _stage = meta.split()
            got[path] = (m, o)
        if staged.returncode == 0 and all(got.get(p) == want[p] for p in overlap):
            return overlap
    # main đổi giữa lúc kiểm và lúc add (phiên khác ghi): trả index về HEAD, đúng trạng thái trước đó (index bằng HEAD là điều kiện ở trên)
    git(main, "reset", "-q", "--", *specs, check=False, bounded=False)
    return []


def _merges_to(main, into, other):
    """True khi gộp `other` vào `into` ra ĐÚNG cây của `into` (merge-tree, không đụng cây làm việc): `other` không mang thêm gì, kể cả
    file sổ sách (khác _adds_nothing_to_main). Xung đột, git cũ, lỗi: False."""
    tree = git(main, "rev-parse", "-q", "--verify", f"{into}^{{tree}}", check=False).stdout.strip()
    r = _merge_tree(main, into, into, other)
    return bool(tree) and r.returncode == 0 and r.stdout.split("\n", 1)[0].strip() == tree


def _squashed_on_origin(main, head):
    """sha của origin/<trunk> khi mọi thứ `head` mang đã có trên đó mà main local CHƯA có (PR đã gộp trên GitHub — squash, rebase hay merge
    — trước khi main local đồng bộ); '' khi không (không biết trunk, không có origin/<trunk>, main đã chứa nó, hay origin thiếu gì đó)."""
    trunk = _trunk_branch(main)
    origin = git(main, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{trunk}^{{commit}}", check=False).stdout.strip() if trunk else ""
    main_head = git(main, "rev-parse", "-q", "--verify", "HEAD^{commit}", check=False).stdout.strip()
    if not origin or not head or not main_head or _is_ancestor(main, head, main_head):
        return ""
    return origin if _is_ancestor(main, head, origin) or _merges_to(main, origin, head) else ""


def _published_squashed(main, wt):
    """Worktree ở nhánh đã publish: PR của nó đã gộp vào origin/<trunk> (_squashed_on_origin) và nó không còn gì chưa commit (ngoài sổ
    sách) — automerge chỉ đồng bộ main rồi gỡ nó, không commit thêm vào nhánh đã publish. state không đọc được: False (từ chối như cũ)."""
    try:
        state = _read_state(wt)
    except (OSError, ValueError, SystemExit):
        if _has_state_file(wt):
            return False
        state = _adopted_state(wt)
    # cùng luật với _commit_pending: regression_status.json do NGƯỜI sửa là việc thật (nó sẽ bị commit lên nhánh đã publish, OCR 18/10)
    if [p for p in changes_since(wt, state) if p not in BOOKKEEPING or (p == STATUS_FILE and _authored_status_changed(wt))]:
        return False
    return bool(_squashed_on_origin(main, git(wt, "rev-parse", "HEAD", check=False).stdout.strip()))


def _ignored_in_way(main, frm, to):
    """Một file / thư mục / link bị git IGNORE trùng, là cha, hay là con của một đường dẫn đổi giữa `frm` và `to` (so không phân biệt hoa
    thường, NFC: ổ macOS) — `reset --keep` (không có --no-overwrite-ignore) sẽ đè nó im lặng; luật của merge gate (audit 18/10). [đường
    dẫn], hoặc None khi git không nói được."""
    d = git(main, "diff", "--no-renames", "--name-only", "-z", frm, to, check=False)
    ign = git(main, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory", check=False)
    if d.returncode or ign.returncode:
        return None
    fold = lambda p: unicodedata.normalize("NFC", p).casefold()   # noqa: E731
    changed = {fold(p) for p in d.stdout.split("\0") if p}
    near = set(changed)
    for p in changed:
        parts = p.split("/")
        near.update("/".join(parts[:i]) for i in range(1, len(parts)))
    hits = []
    for raw in (x for x in ign.stdout.split("\0") if x):
        e = fold(raw.rstrip("/"))
        parts = e.split("/")
        if e in near or any("/".join(parts[:i]) in changed for i in range(1, len(parts))):
            hits.append(raw)
    return hits


def _extras_in_merged_prs(main, head, origin):
    """True khi MỌI commit main có mà `origin` chưa có (origin..head) nằm trong danh sách commit của một PR MERGED VÀO TRUNK (không từ fork)
    mà merge commit của nó `origin` đã chứa — commit gốc của một PR đã squash từ head SAU đó (agent-workbench 18/10: main 7897399 = ba
    commit của #70, origin có squash 81e6c6e dựng từ 99114f1). Hỏi `gh pr list --search <sha>` theo commit mới nhất chưa được phủ: một PR
    phủ cả loạt commit của nó. Không biết trunk, quá 200 commit / 5 lần hỏi, gh lỗi hay quá 15 s, dữ liệu đọc không được: False.
    Ngoại lệ có chủ ý: commit giữa chừng mà chính PR đó revert sau này cũng tính là đã phủ — reset bỏ nó khỏi main đúng như người viết PR
    muốn (nó còn ở refs/pull/<n>/head và reflog), dù nội dung của nó không có trên trunk."""
    trunk = _trunk_branch(main)
    r = git(main, "rev-list", f"{origin}..{head}", check=False)
    left = r.stdout.split() if r.returncode == 0 else []
    if not trunk or not left or len(left) > 200:
        return False
    for _ in range(5):   # tối đa 5 x 15 s, dưới MAIN_LOCK: còn dưới 180 s mà lần finish khác chờ khoá
        try:
            p = subprocess.run(["gh", "pr", "list", "--state", "merged", "--base", trunk, "--search", left[0], "--limit", "5",
                                "--json", "number,baseRefName,isCrossRepository,mergeCommit,commits"], cwd=main, capture_output=True, text=True, timeout=15)
            rows = json.loads(p.stdout or "[]") if p.returncode == 0 else []
        except (OSError, subprocess.SubprocessError, ValueError):
            return False
        covered = set()
        for row in rows if isinstance(rows, list) else []:
            if not (isinstance(row, dict) and row.get("baseRefName") == trunk and row.get("isCrossRepository") is False):
                continue
            merged = row.get("mergeCommit", {}).get("oid") if isinstance(row.get("mergeCommit"), dict) else None
            oids = {c.get("oid") for c in row["commits"] if isinstance(c, dict)} if isinstance(row.get("commits"), list) else set()
            if isinstance(merged, str) and re.fullmatch(r"[0-9a-f]{40}", merged) and _is_ancestor(main, merged, origin):
                covered |= oids
        if left[0] not in covered:
            return False
        left = [s for s in left if s not in covered]
        if not left:
            return True
    return False


def _sync_main_to(main, origin):
    """Dời nhánh trunk của main checkout về `origin` (sha của origin/<trunk>) khi không mất gì, dưới MAIN_LOCK: fast-forward (git tự từ
    chối khi chạm file đang sửa, --no-overwrite-ignore); không ff được (squash viết lại commit của PR) thì `reset --keep` chỉ khi gộp main
    vào origin KHÔNG thêm gì (_merges_to) hoặc mọi commit thừa của main là commit gốc của PR đã merge vào trunk (_extras_in_merged_prs),
    không đang dở merge / rebase…, index bằng HEAD (kể cả mục `add -N`) và không file bị ignore nào nằm đường (_ignored_in_way). None khi
    đã dời (hoặc main đã chứa origin); ("blocked", lý do, {}) khi để nguyên."""
    mlock = _lock_file(os.path.join(git_dir(main), MAIN_LOCK), wait=180.0)
    if mlock is None:
        return "blocked", tr("một lần tự gộp khác giữ khoá main quá lâu: chạy lại", "another automatic merge held the main lock too long: run it again"), {"running": True}
    try:
        head = git(main, "rev-parse", "HEAD").stdout.strip()
        if _is_ancestor(main, origin, head):
            return None
        why = ""
        if _is_ancestor(main, head, origin):
            r = git(main, "merge", "--ff-only", "--no-overwrite-ignore", origin, check=False, bounded=False)
            why = "" if r.returncode == 0 else (r.stderr or r.stdout).strip()[-300:]
        elif _in_progress(main):
            why = tr(f"main đang dở một {_in_progress(main)}", f"a {_in_progress(main)} is in progress in main")
        elif git(main, "diff", "--cached", "--quiet", "--ita-visible-in-index", check=False).returncode != 0:
            why = tr("index của main có thay đổi đã stage (của phiên khác): reset sẽ làm rơi chúng", "main's index holds staged changes (another session's): a reset would drop them")
        elif not _merges_to(main, origin, head) and not _extras_in_merged_prs(main, head, origin):   # gọi gh (mạng) sau các kiểm tra rẻ
            why = tr("main local có commit origin chưa có và không thuộc PR nào đã merge vào trunk (đẩy / PR chúng trước)",
                     "the local main holds commits origin lacks that belong to no PR merged into the trunk (push / PR them first)")
        else:
            hits = _ignored_in_way(main, head, origin)
            if hits is None or hits:
                why = tr(f"file bị git ignore nằm đường của origin ({', '.join((hits or ['?'])[:5])}): reset sẽ đè chúng",
                         f"git-ignored files are in the way of origin ({', '.join((hits or ['?'])[:5])}): a reset would overwrite them")
            else:
                r = git(main, "reset", "-q", "--keep", origin, check=False, bounded=False)
                why = "" if r.returncode == 0 else (r.stderr or r.stdout).strip()[-300:]
        if why:
            return "blocked", tr(f"PR của worktree đã gộp vào origin nhưng main local chưa đồng bộ được về origin ({origin[:12]}): {why}. "
                                 "Không gộp commit gốc của PR vào main (main sẽ lệch origin mãi)",
                                 f"the worktree's PR is merged on origin but the local main cannot be synced to it ({origin[:12]}): {why}. "
                                 "The PR's own commits are not merged into main (it would diverge from origin for good)"), {}
        return None
    finally:
        mlock.close()


def automerge(cwd, wt, keep=False):
    """Merge a worktree's work into the main branch and remove it (`keep`: leave it in place, W1 R3). (status, message, extra); status: merged | nothing | conflict | blocked.
    Main's working tree is only ever touched by `git merge --ff-only`, so another session's uncommitted or staged files are safe (its index
    only for paths whose uncommitted copy is identical to what the merge brings: _stage_identical_overlap)."""
    main = main_checkout(cwd)
    top = git(cwd, "rev-parse", "--show-toplevel").stdout.strip()
    if not _same_path(top, main):
        # K4 (17/10): agent trong worktree gọi `finish` ngay tại đó. cwd là một worktree đã đăng ký của cùng repo: làm việc từ main
        # checkout thay vì từ chối (cmd_remove ở cuối phải chạy từ main, không từ thư mục sắp bị gỡ). Chỗ khác: vẫn từ chối như cũ.
        if not any(_same_path(e["path"], top) for e in _worktree_entries(cwd)[1:] if not e["broken"]):
            return "blocked", tr(f"chạy từ MAIN checkout ({main})", f"run it from the MAIN checkout ({main})"), {}
        cwd = main
    if not any(_same_path(e["path"], wt) for e in _worktree_entries(cwd)[1:] if not e["broken"]):
        return "blocked", tr(f"{wt} không phải worktree đã đăng ký của repo này", f"{wt} is not a registered worktree of this repository"), {}
    if not os.path.isdir(wt):
        return "blocked", tr(f"thư mục {wt} đã mất: `git worktree prune`", f"the folder {wt} is gone: `git worktree prune`"), {}
    branch = git(main, "symbolic-ref", "-q", "--short", "HEAD", check=False).stdout.strip()
    if not branch:
        return "blocked", tr("main checkout đang detached HEAD: không fast-forward được", "the main checkout has a detached HEAD: it cannot be fast-forwarded"), {}
    trunk = _trunk_branch(main)
    if trunk and branch != trunk:
        return "blocked", tr(f"main checkout đang ở nhánh '{branch}', không phải nhánh chính '{trunk}': không tự gộp vào nhánh khác (release/hotfix...). "
                             f"Chuyển về '{trunk}' rồi chạy lại",
                             f"the main checkout is on branch '{branch}', not on the trunk '{trunk}': nothing is merged into another branch (release/hotfix ...). "
                             f"Switch back to '{trunk}' and run it again"), {}
    wt_branch = published_branch(wt)
    squashed = bool(wt_branch) and _published_squashed(main, wt)
    if squashed:
        wt_branch = ""   # PR của nó đã gộp vào origin/<trunk> và worktree không còn gì chưa commit: chỉ đồng bộ main rồi gỡ (GeelyEx2 18/10)
    elif board_worktree(wt):   # lane super-board (detached review/qa, nhánh issue chưa push): chỉ vào main qua PR + merge gate (review 19/10:
        # `finish` / Stop của phiên tự chạy lane đã gộp một checkout review detached, commit PR chưa review, vào main local)
        return "blocked", tr("worktree của lane super-board (.claude/worktrees/issue-<N>-…): chỉ vào main qua PR + merge gate, không tự gộp; "
                             "xong lane thì gỡ nó: `agent-kit worktree remove <path>`",
                             "a super-board lane worktree (.claude/worktrees/issue-<N>-…): it reaches main only through its PR and the merge gate, "
                             "never merged automatically; remove it when the lane is done: `agent-kit worktree remove <path>`"), {}
    if wt_branch:
        return "blocked", tr(f"worktree đang ở nhánh '{wt_branch}' đã PUBLISH (có nhánh remote / upstream): không tự commit thêm hay gộp nó vào main — gộp bằng tay (merge/PR)",
                             f"the worktree is on branch '{wt_branch}', which is PUBLISHED (a remote ref / upstream exists): nothing is committed to it or merged from it automatically - merge it by hand (merge / PR)"), {}
    lock = _lock_automerge(wt)
    if lock is None:
        return "blocked", tr("một lần tự gộp khác của worktree này đang chạy", "another automatic merge of this worktree is running"), {"running": True}
    held = []   # K8: khoá gate gộp của repo nếu _automerge_locked đã lấy; nhả ở đây khi nó trả về giữa vòng gộp
    try:
        return _automerge_locked(cwd, main, wt, keep, held)
    finally:
        for h in held:
            h.close()
        lock.close()


def _automerge_locked(cwd, main, wt, keep=False, held=None):
    held = [] if held is None else held
    try:
        state = _read_state(wt)
    except (OSError, ValueError, SystemExit):
        if _has_state_file(wt):
            return "blocked", tr(f"{wt}: file {STATE} có mặt nhưng không đọc được (hỏng? bị thay?): không tự gộp, không đụng gì",
                                 f"{wt}: the {STATE} file is there but unreadable (corrupt? replaced?): nothing is merged or touched"), {}
        state = _adopted_state(wt)
    if state.get("provisional"):   # `add --session` is still copying config / installing the DevKit (W1 v6 item 3): what is there is no work yet
        at = state.get("at")
        if isinstance(at, (int, float)) and 0 <= time.time() - at < PROVISIONAL_TTL_S:
            return "blocked", tr("worktree đang được dựng (worktree add chưa xong): chưa gộp", "the worktree is still being set up (worktree add has not finished): not merged yet"), {"running": True}
        state = _adopted_state(wt)   # a set-up that never finished: judged like a worktree add did not make
    busy = _in_progress(wt)
    if busy == "merge":   # a conflict left open earlier: resolved and staged -> conclude it; still unmerged -> say so again
        unmerged = git(wt, "diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
        if unmerged:
            return _conflict(wt, unmerged)
        refusal = _staged_merge_refusal(wt)
        if refusal:
            return refusal
        r = git(wt, "commit", "--no-edit", "-q", check=False, bounded=False)
        if r.returncode != 0:
            return "blocked", tr("không kết thúc được merge đang mở trong worktree: ", "cannot conclude the merge open in the worktree: ") + (r.stdout + r.stderr).strip()[-400:], {}
    elif busy:
        return "blocked", tr(f"worktree đang dở một {busy}: hoàn tất hoặc huỷ nó trước", f"a {busy} is in progress in the worktree: finish or abort it first"), {}
    refusal = _commit_pending(wt, state)
    if refusal:
        return refusal
    # GeelyEx2 18/10: PR của worktree đã được SQUASH lên origin/<trunk> (GitHub): gộp chính các commit gốc vào main local làm main lệch origin
    # mãi (INSTINCT-047). Main đồng bộ về origin thay vào đó (như K13 của merge gate); không đồng bộ an toàn được thì từ chối, main giữ nguyên.
    squashed = _squashed_on_origin(main, git(wt, "rev-parse", "HEAD").stdout.strip())
    if squashed:
        refusal = _sync_main_to(main, squashed)
        if refusal:
            return refusal
    # W1 R3: main is merged INTO the worktree and what it brings gated (_merge_gate) under the repo's merge-gate lock only (K8: one gate at a
    # time per repo, MERGE_GATE_LOCK) — a gate takes minutes; then,
    # under MAIN_LOCK, main fast-forwards only if it is still the commit that was merged in. Main moved meanwhile (a person, another merge):
    # merge it in and gate again, at most MERGE_ROUNDS times. Only ONE fast-forward of main at a time: two `merge --ff-only` racing on
    # main's index left staged renames / deletions behind (review 2026-10-08).
    status, merges, gated, tried_lock = None, 0, None, False
    for _ in range(8):   # main may also move (a person committing) between reading it and fast-forwarding it
        main_head = git(main, "rev-parse", "HEAD").stdout.strip()
        w_head = git(wt, "rev-parse", "HEAD").stdout.strip()
        if _is_ancestor(main, w_head, main_head) or (squashed and _adds_nothing_to_main(main, main_head, w_head)):
            status = "nothing"   # everything the worktree has is already in main (squashed: as the squash commit, never its own commits)
            break
        if squashed:   # main đã về origin mà hai phép kiểm (merge-tree tự chọn base / một merge-base) vẫn bất đồng: không bao giờ gộp commit gốc của PR (review 18/10)
            return "blocked", tr("PR của worktree đã gộp vào origin và main đã đồng bộ về đó, nhưng worktree vẫn còn mang thêm thay đổi: không tự gộp "
                                 "commit gốc của PR vào main — đem phần còn lại về bằng PR mới",
                                 "the worktree's PR is merged on origin and main is synced to it, yet the worktree still adds changes: the PR's own "
                                 "commits are not merged into main automatically - bring the rest back in a new PR"), {}
        w_before, merged_in = w_head, False   # K8: HEAD worktree trước khi gộp main ở vòng này
        if not _is_ancestor(main, main_head, w_head):
            if merges >= MERGE_ROUNDS:
                return "blocked", tr(f"main đi tiếp {merges} lần trong lúc gộp và chạy gate: chạy lại", f"main moved on {merges} times while merging and gating: run it again"), {"moved": True}
            merges += 1
            with _test_run_lock(wt) as free:   # the merge rewrites the tree: not while a test run reads it (the next Stop merges)
                if not free:
                    return "blocked", tr("một lần chạy test đang giữ worktree: chưa gộp main vào, lần dừng sau gộp",
                                         "a test run holds the worktree: main is not merged into it now, the next Stop merges it"), {"running": True}
                r = git(wt, "merge", "--no-edit", "-m", f"Merge main into {os.path.basename(wt)} (DevKit auto-merge)", main_head, check=False, bounded=False)
            if r.returncode != 0:
                unmerged = git(wt, "diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
                if unmerged:
                    return _conflict(wt, unmerged)
                git(wt, "merge", "--abort", check=False, bounded=False)
                return "blocked", tr("git merge thất bại: ", "git merge failed: ") + (r.stderr or r.stdout).strip()[-400:], {}
            w_head, merged_in = git(wt, "rev-parse", "HEAD").stdout.strip(), True
        # before EVERY fast-forward, not only after a merge-in: a refused merge run again, a conflict resolved by hand or a later commit
        # has main in it already and would otherwise reach main unchecked (OCR 14/10). A red verdict for these very commits is given
        # again at once: the Stop hook waits 9 s for a merge, so one re-gated on every Stop never reached the session (review 14/10)
        key = {"worktree": w_head, "main": main_head}
        rpath = os.path.join(git_dir(wt), MERGE_GATE_RESULT)
        matrix = _gate_matrix(main)
        try:
            with open(rpath, encoding="utf-8") as fh:
                last = json.load(fh)
        except (OSError, ValueError):
            last = {}
        if matrix and isinstance(last, dict) and last.get("worktree") == w_head and last.get("main") == main_head and last.get("why") \
                and isinstance(last.get("at"), (int, float)) and 0 <= time.time() - last["at"] < MERGE_GATE_RESULT_TTL_S:
            return _gate_refusal(wt, str(last["why"]) + tr(" (kết quả lần trước: chưa đổi gì từ đó)", " (the last verdict: nothing changed since)"))
        if gated == (w_head, main_head):
            why, verdict = None, False   # this very pair passed a moment ago (a --ff-only that failed for a passing reason): no second run
        else:
            # K8 (17/10, Unity: gate 1–6 phút, chạy lại bị cắt ở 900 s): cặp (HEAD worktree, main cũ) vừa PASS ở vòng trước, và từ đó worktree
            # chỉ nhận đúng commit gộp main mới của vòng này => chỉ gate phần main mới mang vào (`--diff <HEAD đã PASS>`): post-fix-gate chỉ chạy
            # lại suite có watch_files khớp file main mới đổi, trên cây đã gộp. KHÔNG bỏ gate chỉ vì file main đổi không giao với file worktree
            # đổi: main đổi tên một hàm (lib.sh) mà một nơi gọi mới của worktree (app2.sh) dùng là đúng ca W1 R3 chặn, và suite theo dõi cả hai.
            # ponytail: suite chỉ theo dõi file của worktree nhưng phụ thuộc file main vừa đổi (watch_files thiếu) không được chạy lại ở vòng
            # này — cùng trần với cách gate chọn test theo watch_files; gate lại toàn bộ khi gặp một lần lọt như thế hoặc watch_files được
            # biết là phủ thiếu phụ thuộc.
            if matrix and not tried_lock:   # K8: một gate gộp mỗi repo một lúc (MERGE_GATE_LOCK), giữ tới sau fast-forward
                tried_lock = True
                try:
                    glock = _lock_file(os.path.join(git_dir(main), MERGE_GATE_LOCK), wait=MERGE_GATE_LOCK_WAIT_S,
                                       waiting=tr("đang chờ gate gộp của một lần finish khác trong repo này (chạy lần lượt)",
                                                  "waiting for another finish's merge gate in this repository (one at a time)"))
                except OSError as e:   # một FIFO cài sẵn, git dir không ghi được: không khoá, như _test_run_lock
                    print("• " + tr(f"không khoá được {MERGE_GATE_LOCK} ({e}); gate không khoá", f"cannot lock {MERGE_GATE_LOCK} ({e}); gating unlocked"), file=sys.stderr)
                    glock = False
                if glock is None:
                    return "blocked", tr(f"một lần finish khác giữ gate gộp của repo quá {MERGE_GATE_LOCK_WAIT_S:g} s (WORKTREE_MERGE_GATE_LOCK_WAIT_S): chạy lại sau",
                                         f"another finish held the repository's merge gate over {MERGE_GATE_LOCK_WAIT_S:g} s (WORKTREE_MERGE_GATE_LOCK_WAIT_S): run it again later"), {"running": True}
                if glock:
                    held.append(glock)
                if git(main, "rev-parse", "HEAD").stdout.strip() != main_head:
                    continue   # main đi tiếp trong lúc chờ: gộp nó vào khi đang giữ khoá, rồi gate một lần
            narrow = merged_in and gated is not None and gated[0] == w_before and _is_ancestor(main, gated[1], main_head)
            why, verdict = _merge_gate(wt, gated[0] if narrow else main_head, matrix) if matrix else (None, False)
        # the gate tested the working tree, main gets the COMMIT: an edit made meanwhile (uncommitted) may have made it green — or red, so
        # this is checked before any verdict is kept or acted on (OCR 14/10)
        edited = [p for p in changes_since(wt, state) if p not in BOOKKEEPING]
        if edited:
            return "blocked", tr(f"worktree đổi trong lúc gate chạy (chưa commit: {', '.join(edited[:5])}): gate không kiểm đúng commit sẽ vào main. "
                                 f"Chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                                 f"the worktree changed while the gate ran (uncommitted: {', '.join(edited[:5])}): the gate did not check the commit main "
                                 f"would get. Run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"files": edited[:20]}
        if why:
            if verdict:
                try:
                    with open(rpath, "w", encoding="utf-8") as fh:
                        json.dump(dict(key, why=why, at=time.time()), fh)
                except OSError:
                    pass   # only a cache: the next run gates again
            return _gate_refusal(wt, why)
        _unlink_quiet(rpath)
        gated = (w_head, main_head)
        if git(wt, "rev-parse", "HEAD").stdout.strip() != w_head:
            continue   # the worktree moved while the gate ran (its session committed): gate what it is now
        mlock = _lock_file(os.path.join(git_dir(main), MAIN_LOCK), wait=180.0)
        if mlock is None:
            return "blocked", tr("một lần tự gộp khác giữ khoá main quá lâu: chạy lại", "another automatic merge held the main lock too long: run it again"), {"running": True}
        try:
            if git(main, "rev-parse", "HEAD").stdout.strip() != main_head:
                continue   # main moved while merging / gating: another round
            # --no-overwrite-ignore: git's default overwrites IGNORED files and folders of main with what the merge brings (A.4: a committed
            # link replaced main's real node_modules/); git checks every path before it writes one, so a refusal leaves main as it was
            try:
                staged = _stage_identical_overlap(main, main_head, w_head)
            except ValueError:   # tên file không phải UTF-8 (git chạy ở text mode, lỗi trước mọi `git add`): không tự stage, git từ chối như cũ
                staged = []
            r = git(main, "merge", "--ff-only", "--no-overwrite-ignore", w_head, check=False, bounded=False)
            if r.returncode == 0:
                status = "merged"
                break
            if staged:   # ff vẫn hỏng vì lý do khác: trả index các đường dẫn vừa stage về HEAD như trước
                git(main, "reset", "-q", "--", *(":(literal)" + p for p in staged), check=False, bounded=False)
            err = r.stdout + r.stderr
            files = [l.strip() for l in err.splitlines() if l.startswith("\t")]
            if "untracked working tree files would be" in err or "would lose untracked files" in err:
                return "blocked", tr(f"main có file/thư mục CHƯA track hoặc bị git ignore ở đúng đường dẫn mà commit của worktree thêm hoặc thay (không gì bị đụng; "
                                     f"fast-forward sẽ xoá chúng): {', '.join(files[:8]) or err.strip()[-200:]}. Thường là link hoặc file commit đè lên thư mục main "
                                     f"để ngoài git (node_modules, output build, cấu hình cục bộ): bỏ nó khỏi commit của worktree (`git rm --cached <path>` rồi commit "
                                     f"trong worktree), hoặc dời bản ở main đi nếu không cần, rồi chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                                     f"main has UNTRACKED or git-ignored files at paths the worktree's commits add or replace (nothing was touched; the fast-forward "
                                     f"would have deleted them): {', '.join(files[:8]) or err.strip()[-200:]}. Usually a link or file committed over a folder main keeps "
                                     f"out of git (node_modules, build output, local config): take it out of the worktree's commits (`git rm --cached <path>` and commit "
                                     f"in the worktree), or move main's copy away if it is not needed, then run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"files": files}
            if "overwritten" in err or "commit your changes or stash" in err:
                return "blocked", tr(f"main có sửa đổi CHƯA commit trên file mà worktree cũng đổi (không gì bị đụng): {', '.join(files[:8]) or err.strip()[-200:]}. "
                                     f"Commit hoặc cất chúng ở main rồi chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                                     f"main has UNCOMMITTED edits on files the worktree also changed (nothing was touched): {', '.join(files[:8]) or err.strip()[-200:]}. "
                                     f"Commit or stash them in main, then run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"files": files}
        finally:
            mlock.close()
    for h in held:   # K8: main đã fast-forward (hoặc không còn gì để gộp): nhả gate gộp cho lần finish đang chờ
        h.close()
    if status is None:
        return "blocked", tr("main liên tục có commit mới trong lúc gộp: chạy lại", "main kept moving while merging: run it again"), {}
    receipt_note = _carry_gate_receipt(main, wt)   # issue #5: trước cả nhánh --keep, vì worktree có thể bị gỡ sau đó mà không qua đây
    if keep:
        return status, (tr("đã gộp vào main; worktree giữ lại (--keep)", "merged into main; the worktree is kept (--keep)") if status == "merged"
                        else tr("không có gì chưa về main; worktree giữ lại (--keep)", "nothing that was not in main; the worktree is kept (--keep)")) + receipt_note, {"kept": True}
    kept = kept_lock(main, wt)
    if kept and kept[2]:   # K11 (18/10): phiên rời worktree bằng ExitWorktree "keep" và còn sống: gộp thì được, gỡ thì không
        head = (tr("đã gộp vào main", "merged into main") if status == "merged"
                else tr("không có gì chưa về main", "nothing that was not in main"))
        return status, head + tr(f"; worktree giữ lại (ExitWorktree keep của phiên {kept[0]} còn sống)",
                                 f"; the worktree is kept (ExitWorktree keep by session {kept[0]}, still alive)") + receipt_note, {"kept": True}
    saved = []
    try:
        for rel in _unsaved_memory(wt, main):   # notes only the worktree's own (git-ignored) agent-memory folder holds: a removal would delete them
            src, dst = os.path.join(wt, MEMORY_REL, rel), os.path.join(main, MEMORY_REL, rel)
            if os.path.exists(dst):
                dst += ".from-" + os.path.basename(wt)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            saved.append(rel)
    except (OSError, SystemExit) as e:
        return "blocked", tr(f"đã gộp vào main nhưng không chép được memory note của worktree ({e}); worktree còn nguyên", f"merged into main but the worktree's memory notes could not be copied ({e}); the worktree is untouched"), {"merged": True}
    try:   # A.1b #12: a git-ignored secret only the worktree holds (a keystore made there) goes to main, never with the folder
        secrets, cut = _ignored_secrets(wt)
        carried, refused = ([], []) if cut else _carry_secrets(main, secrets)
    except (OSError, SystemExit, UnicodeError) as e:
        return "blocked", tr(f"đã gộp vào main nhưng không kiểm / chép được file bí mật bị ignore của worktree ({e}); worktree còn nguyên",
                             f"merged into main but the worktree's git-ignored secret files could not be checked or copied ({e}); the worktree is untouched"), {"merged": True}
    if cut:   # what the scan did not read may hold a key: never removed unread
        return "blocked", tr(f"đã gộp vào main nhưng CHƯA gỡ worktree: dò file bí mật bị git ignore dừng trong {cut} (quá WORKTREE_SECRET_SCAN_MAX file) — phần chưa "
                             f"đọc có thể có khoá. Thư mục đó là output build / cache thì xoá nó trong worktree, hoặc nâng WORKTREE_SECRET_SCAN_MAX (0: không giới hạn), "
                             f"rồi chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                             f"merged into main but the worktree is NOT removed: the scan for git-ignored secret files stopped in {cut} (over WORKTREE_SECRET_SCAN_MAX "
                             f"files) - what it did not read may hold a key. If that folder is build output or a cache, delete it in the worktree, or raise "
                             f"WORKTREE_SECRET_SCAN_MAX (0: no limit), then run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"merged": True, "files": [cut]}
    if refused:
        # (a copy `worktree add` made and nobody changed is not here: _ignored_secrets drops it by the sha256 `add` recorded. ponytail: a worktree
        # made before that record, or one whose copy the worktree edited while main changed it too, is refused like a key made here)
        listing = "; ".join(f"{rel} ({why})" for rel, why in refused[:6])
        return "blocked", tr(f"đã gộp vào main nhưng CHƯA gỡ worktree: {len(refused)} file bí mật bị git ignore chỉ worktree có, không đặt được vào main: {listing}. "
                             f"Không gì bị ghi đè. So hai bản, tự giữ bản cần dùng ở main, xoá bản trong worktree rồi chạy lại `agent-kit worktree finish {shlex.quote(wt)}`",
                             f"merged into main but the worktree is NOT removed: {len(refused)} git-ignored secret file(s) only the worktree holds cannot be put in main: "
                             f"{listing}. Nothing was overwritten. Compare the two copies, keep the one you need in main yourself, delete the worktree's copy, then "
                             f"run `agent-kit worktree finish {shlex.quote(wt)}` again"), {"merged": True, "files": [rel for rel, _why in refused][:20]}
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = cmd_remove(cwd, [wt])
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 1
            if not isinstance(e.code, int):
                err.write(str(e.code))
    if rc != 0:
        why = (err.getvalue() + out.getvalue()).strip()[:600]   # the head: it names what failed (the tail of a long reason is only the how-to)
        try:
            registered = any(_same_path(e["path"], wt) for e in _worktree_entries(main))
        except SystemExit:
            registered = True   # cannot tell: the old advice is the safe one
        if registered:
            how = tr(f". Nếu chỉ còn file sinh ra/ không cần: NGƯỜI DÙNG chạy `git worktree remove --force {wt}`",
                     f". If only generated / unneeded files are left: the USER runs `git worktree remove --force {wt}`")
        else:   # git no longer knows the folder (a locked keystore copy): only the by-hand command helps, and `why` is cut at 600 chars, often before the command
            how = "" if _by_hand(wt) in why else tr(f". NGƯỜI DÙNG chạy `{_by_hand(wt)}`", f". The USER runs `{_by_hand(wt)}`")
        return "blocked", tr(f"đã gộp vào main nhưng CHƯA gỡ được worktree: {why}{how}",
                             f"merged into main but the worktree could NOT be removed: {why}{how}"), {"merged": True}
    note = (tr(f" ({len(saved)} memory note đã chép sang main: {', '.join(saved[:5])})", f" ({len(saved)} memory note(s) copied into main: {', '.join(saved[:5])})") if saved else "")
    note += (tr(f" ({len(carried)} file bí mật bị git ignore đã chép sang main, ở đó vẫn bị ignore: {', '.join(carried[:5])})",
                f" ({len(carried)} git-ignored secret file(s) copied into main, ignored there too: {', '.join(carried[:5])})") if carried else "")
    note += receipt_note
    return status, (tr("đã gộp vào main và gỡ worktree", "merged into main and the worktree is removed") if status == "merged"
                    else tr("không có gì chưa về main; đã gỡ worktree", "nothing that was not in main; the worktree is removed")) + note, {"memory_saved": saved, "secrets_saved": carried}


def _automerge_args(cwd, args, usage):
    pos = [a for a in args if a != "--keep"]
    if len(pos) != 1 or pos[0].startswith("--"):
        die(usage)
    return os.path.abspath(os.path.join(cwd, pos[0])), "--keep" in args


def _run_automerge(cwd, args, usage):
    wt, keep = _automerge_args(cwd, args, usage)
    try:
        status, message, extra = automerge(cwd, wt, keep)
    except SystemExit as e:
        status, message, extra = "blocked", str(e.code), {}
    except OSError as e:   # a lock path that is no regular file, an admin dir removed meanwhile: still the one JSON line the Stop hook reads
        status, message, extra = "blocked", tr("lỗi hệ thống tệp: ", "filesystem error: ") + str(e)[:300], {}
    return wt, status, message, extra


def cmd_automerge(cwd, args):
    wt, status, message, extra = _run_automerge(cwd, args, "usage: agent-kit worktree automerge <path> [--keep]")
    print(json.dumps(dict(extra, status=status, message=message, path=wt), ensure_ascii=False))
    return {"merged": 0, "nothing": 0, "conflict": 3}.get(status, 1)


FINISH_RETRIES = int(_env_limit("WORKTREE_FINISH_RETRIES", 4))   # 17/10: many sessions finishing at once keep moving main; 0 = no retry


def cmd_finish(cwd, args):
    usage = "usage: agent-kit worktree finish <path> [--keep]"
    wt, status, message, extra = _run_automerge(cwd, args, usage)
    for _ in range(FINISH_RETRIES):   # "main moved on" is no failure of this worktree: wait a jittered moment, merge again
        if not (status == "blocked" and extra.get("moved")):
            break
        time.sleep(random.uniform(0.5, 1.5) * _env_limit("WORKTREE_FINISH_RETRY_WAIT_S", 3.0))
        wt, status, message, extra = _run_automerge(cwd, args, usage)
    mark = {"merged": "✔", "nothing": "✔", "conflict": "⚠", "blocked": "✖"}[status]
    print(f"{mark} worktree {status}: {message}")
    return {"merged": 0, "nothing": 0, "conflict": 3}.get(status, 1)


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


MERGE_FILE_MIN_AGE_S = 600   # a `.merge_file_*` younger than this may still be in use by a merge driver that is running


def _sweep_merge_files(top):
    """Delete the untracked top-level `.merge_file_*` files that killed `git merge-tree` probes left in `top` (#309): only a regular file
    (never a link) whose name is git's own `.merge_file_XXXXXX`, that git does not track and nobody wrote to for MERGE_FILE_MIN_AGE_S.
    Returns the names removed; an error on one file is skipped (heal never fails a session start)."""
    out = []
    try:
        names = os.listdir(top)
    except OSError:
        return out
    for n in names:
        path = os.path.join(top, n)
        try:
            if not re.fullmatch(r"\.merge_file_[A-Za-z0-9]{6}", n) or not stat.S_ISREG(os.lstat(path).st_mode) \
                    or time.time() - os.lstat(path).st_mtime < MERGE_FILE_MIN_AGE_S \
                    or git(top, "ls-files", "--error-unmatch", "--", n, check=False).returncode == 0:
                continue
            os.unlink(path)
            out.append(n)
        except OSError:
            continue
    return out


GITHOOK_MARK = "universal-agent-devkit:githook"
GITHOOK_NAMES = ("pre-commit", "commit-msg", "post-merge", "post-checkout", "post-rewrite")
# the absolute fallback line `githooks.sh install` writes (`[ -f "$VAR" ] || VAR=<printf %q path>`); the repo-relative lookups above it are quoted
GITHOOK_FALLBACK = re.compile(r'^\[ -f "\$(?:DEVKIT_HOOK|RELINK)" \] \|\| (?:DEVKIT_HOOK|RELINK)=(/.+|\$\'.+\')$')


def _unquote_printf_q(text):
    """The path `printf %q` wrote: backslash escapes (a space, `$`, …) or the `$'…'` form (a tab, a newline). Nothing is evaluated by a shell.
    Text that cannot be read back is returned as it is (an unreadable path then reads as gone and the hook is reinstalled)."""
    try:
        if text.startswith("$'") and text.endswith("'"):
            import ast
            return ast.literal_eval("'" + text[2:-1] + "'")   # \t \n \\ \' \xHH, the escapes %q emits, as a Python literal
        parts = shlex.split(text)
        return parts[0] if len(parts) == 1 else text
    except (ValueError, SyntaxError):
        return text


def _dangling_githooks(hooks_dir):
    """The DevKit's own hooks in `hooks_dir` whose absolute fallback path no longer exists (the kit they were installed from is gone: a removed
    worktree, a moved checkout, #363). A project's own hook (no marker) is never listed."""
    out = []
    for name in GITHOOK_NAMES:
        try:
            with open(os.path.join(hooks_dir, name), encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        if not any(GITHOOK_MARK in l for l in lines[:3]):
            continue
        for l in lines:
            m = GITHOOK_FALLBACK.match(l)
            if m:
                if not os.path.exists(_unquote_printf_q(m.group(1))):
                    out.append(name)
                    break
    return out


def _heal_githooks(wt):
    """SessionStart: a DevKit git hook that points at a kit path that is gone fails every commit and merge of every worktree (#363, 24/10), so
    it is installed again from the running kit (`githooks.sh install` writes the main checkout's copy, never a worktree's). Only a hook the
    DevKit wrote and only when its fallback dangles; never an error: a session must start whatever happens here."""
    try:
        r = git(wt, "rev-parse", "--path-format=absolute", "--git-path", "hooks", check=False)
        hooks_dir = r.stdout.strip() if r.returncode == 0 else ""
        bad = _dangling_githooks(hooks_dir) if hooks_dir else []
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "githooks.sh")
        if not bad or not os.path.isfile(script):
            return
        done = subprocess.run(["bash", script, "install", wt], capture_output=True, text=True, timeout=60)
        if done.returncode == 0 and not _dangling_githooks(hooks_dir):
            print(tr(f"git hook của DevKit trỏ tới đường không còn ({', '.join(bad)}): đã cài lại",
                     f"DevKit git hook pointed at a path that is gone ({', '.join(bad)}): reinstalled"))
        else:
            print(tr(f"git hook của DevKit trỏ tới đường không còn ({', '.join(bad)}) và chưa cài lại được: chạy `agent-kit githooks install`",
                     f"DevKit git hook points at a path that is gone ({', '.join(bad)}) and could not be reinstalled: run `agent-kit githooks install`"))
    except (OSError, subprocess.SubprocessError, SystemExit) as e:
        print(tr(f"không kiểm được git hook của DevKit: {e}", f"could not check the DevKit git hooks: {e}"))


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
    for top in {wt, src} - {None}:
        done += _sweep_merge_files(top)
    link = os.path.join(wt, ".agents", "devkit")
    target = os.path.join(src, ".agents", "devkit") if src else None
    target = target if target and os.path.isdir(target) else devkit
    # missing or DANGLING (exists() follows the link): a dangling one used to be skipped, so heal could not repair it (19/10)
    if target and os.path.isfile(os.path.join(target, "bin", "post-fix-gate.py")) and not os.path.exists(link) \
            and git(wt, "check-ignore", "-q", "--no-index", ".agents/devkit", check=False).returncode == 0 \
            and git(wt, "ls-files", "--error-unmatch", "--", ".agents/devkit", check=False).returncode != 0:   # never a tracked path
        try:
            if os.path.islink(link):
                os.unlink(link)
            os.makedirs(os.path.dirname(link), exist_ok=True)
            os.symlink(os.path.realpath(target), link)
            done.append(".agents/devkit")
        except OSError as e:   # a race with another heal: reported, the rest of heal still runs
            print(tr(f"không sửa được .agents/devkit: {e}", f".agents/devkit not repaired: {e}"))
    # .agents/active-profile, the profile link matrix commands call through (bash .agents/active-profile/scripts/unity-batch.sh):
    # a worktree made with plain `git worktree add` lacks it, or holds main's RELATIVE link copied as-is, which dangles one folder
    # deeper (Neighbours-From-Hell #18, 19/10: matrix exit 127, gate REJECT, 5 cards waiting on it). Point it where main's link
    # points, relative like the installer's (P-4); only when it is missing or dangling and git ignores it.
    plink = os.path.join(wt, ".agents", "active-profile")
    try:   # heal never fails a session start (docstring): a race with another heal, or no symlinks here, is reported and skipped
        if src and os.path.islink(os.path.join(src, ".agents", "active-profile")) and not os.path.exists(plink):
            # a relative link resolves from the PHYSICAL folder it sits in (the installer measures it from agents_dir.resolve())
            ptarget = os.path.normpath(os.path.join(os.path.realpath(os.path.join(src, ".agents")),
                                                    os.readlink(os.path.join(src, ".agents", "active-profile"))))
            if os.path.isfile(os.path.join(ptarget, "profile.json")) \
                    and git(wt, "check-ignore", "-q", "--no-index", ".agents/active-profile", check=False).returncode == 0 \
                    and git(wt, "ls-files", "--error-unmatch", "--", ".agents/active-profile", check=False).returncode != 0:   # never a tracked path
                if os.path.islink(plink):
                    os.unlink(plink)
                os.makedirs(os.path.dirname(plink), exist_ok=True)
                os.symlink(os.path.relpath(ptarget, os.path.realpath(os.path.dirname(plink))), plink)
                done.append(".agents/active-profile")
    except (OSError, ValueError) as e:
        print(tr(f"không sửa được .agents/active-profile: {e}", f".agents/active-profile not repaired: {e}"))
    if src:
        done += copy_local_config(src, wt) + copy_build_inputs(src, wt) + copy_meta_assets(src, wt) + copy_local_hooks(src, wt)
    try:   # trunk mode is the default: wire its hooks once per machine (settings.local.json is untracked, a fresh clone has none)
        main_co = main_checkout(cwd)
        if _trunk_mode(main_co):
            try:
                _trunk_wire(main_co)   # silent: the SessionStart text is the same every time, and the message above is for host-made checkouts
            except (SystemExit, OSError):   # (a settings.local.json that does not parse, an unreadable one, a failed git call or write) trunk is ON and the hooks stay unwired, so say it
                print(tr("trunk mode BẬT nhưng hook WorktreeCreate/WorktreeRemove chưa đấu được: chạy `agent-kit worktree trunk wire` để xem lý do",
                         "trunk mode is ON but the WorktreeCreate/WorktreeRemove hooks could not be wired: run `agent-kit worktree trunk wire` to see why"))
    except (SystemExit, OSError):
        pass   # a session must start whatever happens here
    _heal_githooks(wt)
    if done:
        print(tr("checkout do host tạo: đã chuẩn bị như `agent-kit worktree add` — ",
                 "host-made checkout: set up like `agent-kit worktree add` — ") + ", ".join(done))
    return 0


GC_NOISE = {".DS_Store", "Thumbs.db", "desktop.ini"}
# machine-written only: .antigravity-pm/ is not here, people write briefs, plans and scripts in it
GC_BOOKKEEPING_DIRS = (".claude/audit-gate/", ".agents/evidence/", ".agents/regression_journal/")
GC_SECRETS = LOCAL_CONFIG + ("*.jks", "*.keystore", "*.p12", "*.p8", "*.pem", "*.key", "key.properties", "id_rsa*", "id_ed25519*",
                             "credentials.json", "*service-account*.json", "*.mobileprovision", "*.keychain*")
# Only these are rebuildable: an ignored file anywhere else (a database, an IDE workspace, .agents/local/ handoffs) may be the only copy
GC_BUILD_DIRS = {"build", ".gradle", "node_modules", "dist", "out", "target", "Library", "Temp", "obj", ".dart_tool", "Pods",
                 "DerivedData", ".cxx", ".externalNativeBuild", "__pycache__", ".pytest_cache", ".next", "coverage"}
# Regenerated views only: regression_status.json / BUG_ARCHIVE.md hold rows people wrote (_carry_authored_rows protects them)
GC_VIEWS = (".agents/CHECKLIST.md", ".agents/regression_checklist.md", ".agents/instincts-index.md")
try:   # a folder changed this recently may be a `worktree add` still being written: never touched
    GC_MIN_AGE_S = max(0, int(os.environ.get("WORKTREE_GC_MIN_AGE_S", "600")))
except ValueError:
    GC_MIN_AGE_S = 600


def _gc_young(*paths):
    """True when one of `paths` changed less than GC_MIN_AGE_S ago, or cannot be read (keep)."""
    try:
        return time.time() - max(os.lstat(x).st_mtime for x in paths if os.path.lexists(x)) < GC_MIN_AGE_S
    except (OSError, ValueError):
        return True


_REACHABLE = {}


def _reachable_blobs(main):
    """((blob id, path) pairs, paths, blob ids) some ref still holds (`rev-list --objects --all`): a blob merely present in the object DB
    may belong to a commit no ref names any more (a detached commit, a staged file of a worktree whose admin dir is gone) and `git gc`
    would drop it. A file is a committed version only when a kept tree holds its bytes AT ITS PATH: the same bytes under another path (a
    copy, an empty __init__.py, old code restored under a new name) are a new file, uncommitted work (issue #12). rev-list names a blob
    once, under the newest path it meets, so a pair it misses for a blob it does hold is asked of that path's history (_path_versions).
    A path a kept tree holds is tracked somewhere (a branch force-adds build/keep.txt), so an edit of it is never a build output.
    None = cannot say. ponytail: for the same reason a tracked path whose every version is also stored elsewhere can be missed, so an
    ignored edit of it under a build folder reads as rebuildable; upgrade to `ls-tree -r` of each ref tip if that ever bites."""
    if main not in _REACHABLE:
        r = git(main, "rev-list", "--objects", "--all", "--filter=object:type=blob", check=False, inp=b"")   # bytes: a path need not be UTF-8
        if r.returncode != 0:
            _REACHABLE[main] = None
        else:   # a blob a ref names directly has no path: no file version
            pairs = [x for x in (ln.split(" ", 1) for ln in r.stdout.decode("utf-8", "surrogateescape").splitlines()) if len(x) == 2]
            _REACHABLE[main] = ({(x[0], x[1]) for x in pairs}, {x[1] for x in pairs}, {x[0] for x in pairs})
    return _REACHABLE[main]


def _path_versions(main, rels):
    """{(blob id, path)} every version of `rels` some ref's history holds (`log --all --raw`, the paths literal, on stdin: no argv limit),
    for the files rev-list paired with another path. None = cannot say.
    ponytail: a version only a merge commit introduced (a conflict resolution) is not listed, so that file reads as unique and is KEPT;
    add `--diff-merges=separate` if that ever strands a leftover."""
    r = git(main, "--literal-pathspecs", "log", "--all", "--root", "--no-renames", "--raw", "--no-abbrev", "-z", "--format=", "--stdin",
            check=False, inp=("--\n" + "\n".join(rels) + "\n").encode("utf-8", "surrogateescape"))
    if r.returncode != 0:
        return None
    toks = r.stdout.decode("utf-8", "surrogateescape").split("\0")
    out = set()
    for i in range(0, len(toks) - 1, 2):   # `:<mode> <mode> <old> <new> <status>`, then the path; a trailing "" closes the list
        meta, path = toks[i].lstrip("\n"), toks[i + 1]
        f = meta[1:].split()
        if not meta.startswith(":") or len(f) != 5:
            return None
        out.update((sha, path) for sha in f[2:4] if sha.strip("0"))
    return out


def _gc_link_known(main, rel, p):
    """#40: True khi symlink `p` (đường dẫn `rel` trong orphan) không phải việc riêng: main có symlink cùng đường dẫn + cùng đích
    (`readlink` bằng nhau), hoặc nó trỏ vào thư mục kit của main (trạng thái cài DevKit mà `worktree add` / heal tạo, như _kit_link).
    Không đi theo link khi so; đọc lỗi = việc riêng (giữ)."""
    try:
        mine = os.path.join(main, rel)
        if os.path.islink(mine) and os.readlink(mine) == os.readlink(p):
            return True
        return _into_kit(main, p)
    except OSError:
        return False


def _gc_unique(main, top, dangling, carry=None):
    """[(rel, why)] of the files in `top` that may be the only copy of something; [] when every file is provably not unique. With no
    `.git` pointer (`dangling` False) the folder must hold DevKit bookkeeping and nothing but it and noise: anything else (an empty
    folder or one of links only too) means it is not a leftover. `carry` (a list): a secret (GC_SECRETS, and _secret_like) that main
    lacks, outside a _carry_skip_dirs() folder, goes there as (rel, path) instead of counting as unique: cmd_gc copies it into main first
    (A.1b #12)."""
    files, links = [], []
    # #40: với orphan (`.git` trỏ treo), tuổi xét mọi file / link / thư mục mà vòng duyệt này đi qua (không thêm một lượt duyệt), không
    # chỉ gốc + .git như _gc_young. Thư mục không `.git` chỉ chứa sổ sách DevKit giữ luật cũ (gốc): gate ghi sổ sách vào đó bất cứ lúc nào
    young = lambda q: dangling and GC_MIN_AGE_S > 0 and _gc_young(q)  # noqa: E731
    for dirpath, dirs, names in os.walk(top):
        linked = [d for d in dirs if os.path.islink(os.path.join(dirpath, d))]
        dirs[:] = [d for d in dirs if d not in linked]   # a link is never followed (.agents/devkit, a link to main)
        drel_here = os.path.relpath(dirpath, top).replace(os.sep, "/") + "/"
        if drel_here != "./" and "/__pycache__/" not in "/" + drel_here and not drel_here.startswith(GC_BOOKKEEPING_DIRS) and young(dirpath):
            return [(drel_here, tr("vừa đổi, chưa đủ WORKTREE_GC_MIN_AGE_S", "changed within WORKTREE_GC_MIN_AGE_S"))]
        for d in dirs if not dangling else ():   # a folder outside the bookkeeping (even an empty one) is a person's
            drel = os.path.relpath(os.path.join(dirpath, d), top).replace(os.sep, "/") + "/"
            if d != "__pycache__" and not any(b.startswith(drel) or drel.startswith(b) for b in GC_BOOKKEEPING_DIRS):
                return [(drel, tr("không phải sổ sách DevKit", "not DevKit bookkeeping"))]
        for n in names + linked:
            p = os.path.join(dirpath, n)
            rel = os.path.relpath(p, top).replace(os.sep, "/")
            if rel == ".git" or n in GC_NOISE or "/__pycache__/" in "/" + rel or rel in GC_VIEWS or rel.startswith(GC_BOOKKEEPING_DIRS):
                continue
            if young(p):
                return [(rel, tr("vừa đổi, chưa đủ WORKTREE_GC_MIN_AGE_S", "changed within WORKTREE_GC_MIN_AGE_S"))]
            if os.path.islink(p):
                if dangling and not _gc_link_known(main, rel, p):   # #40: một symlink mới là việc riêng, mất im lặng khi xoá
                    links.append((rel, tr("symlink main không có (cùng đường dẫn + cùng đích)", "a symlink main lacks (same path, same target)")))
                continue
            if not dangling:
                return [(rel, tr("không phải sổ sách DevKit", "not DevKit bookkeeping"))]
            files.append((rel, p))
    if not dangling and not any(os.path.isdir(os.path.join(top, d)) for d in GC_BOOKKEEPING_DIRS):
        return [("*", tr("không có sổ sách DevKit", "no DevKit bookkeeping"))]
    unique, later = links, []
    for rel, p in files:
        mine = os.path.join(main, rel)
        try:
            same = os.path.isfile(mine) and not os.path.islink(mine) and filecmp.cmp(p, mine, shallow=False)
        except OSError:
            same = False
        if same:
            continue
        if "\r" in rel or "\n" in rel:   # git's line protocol (hash-object --stdin-paths, check-ignore) cannot carry the name
            unique.append((rel.replace("\r", "\\r").replace("\n", "\\n"), tr("tên có ký tự xuống dòng", "a name with a line break")))
        elif rel.startswith(MEMORY_REL.replace(os.sep, "/") + "/"):
            unique.append((rel, tr("ghi chú memory không có ở main", "a memory note main lacks")))
        elif any(fnmatch.fnmatch(os.path.basename(rel).lower(), g.lower()) for g in GC_SECRETS):   # (a name only _secret_like knows is judged below, as ever)
            if carry is not None and _secret_like(rel) and not os.path.lexists(mine) and not set(rel.split("/")[:-1]) & _carry_skip_dirs():
                carry.append((rel, p))
            elif os.path.lexists(mine):
                unique.append((rel, tr("file bí mật KHÁC bản ở main: không ghi đè", "a secret that differs from main's at that path: never overwritten")))
            else:
                unique.append((rel, tr("file bí mật chỉ có ở đây: chép về main trước", "a secret only here: copy it to main first")))
        else:
            later.append((rel, p))
    if later:   # one hash-object + one check-ignore for all of them, against the blobs some ref still holds
        reachable = _reachable_blobs(main)
        try:
            hashes = git(main, "hash-object", "--no-filters", "--stdin-paths", inp="\n".join(p for _r, p in later) + "\n", check=False)
            ignored = git(main, "-c", "core.quotePath=false", "check-ignore", "--stdin", inp="\n".join(r for r, _p in later) + "\n", check=False)   # WITH the index: a tracked file is never "ignored"
        except UnicodeError:   # a name that is not UTF-8 cannot go through git's text protocol: cannot say, keep
            return [("*", tr("git không kiểm được nội dung", "git could not check the content"))]
        shas = hashes.stdout.split()
        if reachable is None or hashes.returncode != 0 or len(shas) != len(later) or ignored.returncode not in (0, 1):
            return [("*", tr("git không kiểm được nội dung", "git could not check the content"))]
        versions, tracked, blobs = reachable
        build = set(ignored.stdout.splitlines())
        missed = sorted({rel for (rel, _p), sha in zip(later, shas) if (sha, rel) not in versions and sha in blobs})
        more = _path_versions(main, missed) if missed else set()   # rev-list named those blobs under another path: ask these paths' history
        if more is None:
            return [("*", tr("git không kiểm được nội dung", "git could not check the content"))]
        for (rel, _p), sha in zip(later, shas):
            rebuildable = rel in build and rel not in tracked and any(part in GC_BUILD_DIRS for part in rel.split("/")[:-1])
            if (sha, rel) not in versions and (sha, rel) not in more and not rebuildable:
                unique.append((rel, tr("nội dung không có trong commit nào còn giữ ở đường dẫn này", "content no kept commit holds at this path")))
    return unique


def _gc_log(log, lines):
    """Append `lines` to the gc log, keeping its last 400 lines (tmp + replace). Called under the gc lock right after each delete, so a
    crash or kill later in the sweep keeps the record of what was already deleted."""
    try:
        os.makedirs(os.path.dirname(os.path.abspath(log)), exist_ok=True)
        try:
            with open(log, encoding="utf-8", errors="replace") as fh:
                old = fh.read().splitlines()
        except FileNotFoundError:
            old = []
        tmp = f"{log}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8", errors="replace") as fh:
            fh.write("\n".join((old + lines)[-400:]) + "\n")
        os.replace(tmp, log)
    except OSError as e:
        print("• gc: " + tr(f"không ghi được log ({e})", f"could not write the log ({e})"))


def _gc_why(unique):
    return "; ".join(f"{rel} ({why})" for rel, why in unique[:3]) + (" …" if len(unique) > 3 else "")


def cmd_gc(cwd, args):
    """Delete the folders DevKit worktrees left behind that git no longer knows, only when nothing in them is unique
    (docs/workflow-improvements.md I.0 R5b): `<repo>-*` siblings whose `.git` pointer dangles into this repo, or with no `.git` that hold
    DevKit bookkeeping only, and any folder of main's own `.claude/worktrees/` git does not register (#327); every file is checked
    (_gc_unique). An agent cannot `rm -rf` them (hardware_safety_gate), so before gc they
    waited for the user. Registered worktrees are never gc's: worktree_merge_gate (Stop) and `worktree remove` judge those (review 3,
    13/10: removing them from gc opened data-loss holes round after round). Kept: anything with work not in main, a unique file, a secret
    only there, a folder changed in the last GC_MIN_AGE_S, a person's folder or clone. --dry-run deletes nothing."""
    dry = "--dry-run" in args
    log = next((a.split("=", 1)[1] for a in args if a.startswith("--log=")), None)   # the SessionStart hook's record of deletions
    main = main_checkout(cwd)
    common = os.path.realpath(git(main, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    try:   # held until exit: two sessions starting together run gc once
        import fcntl
        gc_lock = open(os.path.join(common, "devkit-gc.lock"), "a")
        fcntl.flock(gc_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0   # another gc runs in this repo and records what it deletes: silent
    except (OSError, ImportError) as e:   # no flock here (NFS, SMB, no fcntl) or a read-only git dir: run unlocked, and say so
        print("• gc: " + tr(f"không khoá được ({e}); chạy không khoá", f"no lock ({e}); running unlocked"))
    here = os.path.realpath(cwd)
    deleted, kept, notes = [], [], {}
    registered = [e["path"] for e in _worktree_entries(main)]   # compared with _same_path: realpath keeps APFS case spellings apart (#327 review)
    parent, prefix = os.path.dirname(main), os.path.basename(main) + "-"
    try:
        siblings = sorted(os.listdir(parent))
    except OSError:
        siblings = []
    # (path, owned): `<repo>-*` siblings, then what sits in main's own .claude/worktrees/ (#327: git dropped the registration but the
    # folder stayed, and with no `.git` left it was never a candidate). There every file is judged as in a dangling orphan.
    cands = [(os.path.join(parent, n), False) for n in siblings if n.startswith(prefix)]
    wt_home = os.path.join(main, ".claude", "worktrees")
    try:
        cands += [(os.path.join(wt_home, n), True) for n in sorted(os.listdir(wt_home))]
    except OSError:
        pass
    for top, owned in cands:
        real = os.path.realpath(top)
        if os.path.islink(top) or not os.path.isdir(top) or any(_same_path(p, top) for p in registered) \
                or real == os.path.realpath(main) or here == real or here.startswith(real + os.sep):
            continue
        gitp = os.path.join(top, ".git")
        if os.path.isdir(gitp) or _gc_young(top, gitp):
            continue   # a clone or a copy of its own: never ours; or just changed
        dangling = owned and not os.path.isfile(gitp)
        if os.path.isfile(gitp):
            try:
                with open(gitp, encoding="utf-8") as fh:
                    ptr = fh.read().strip()
            except (OSError, ValueError):   # unreadable or not UTF-8: not a pointer gc can judge
                continue
            if not ptr.startswith("gitdir:"):
                continue
            target = os.path.realpath(os.path.join(top, ptr[len("gitdir:"):].strip()))
            if not target.startswith(os.path.join(common, "worktrees") + os.sep) or os.path.exists(target):
                continue   # points into another repo, or git still has it: not a leftover of this one
            dangling = True
        carry = []
        unique = _gc_unique(main, top, dangling, carry)
        if unique:
            if dangling:   # a no-.git folder with a person's file is not ours: not even reported
                kept.append((top, _gc_why(unique)))
            continue
        if carry:   # A.1b #12: the secrets only this folder holds go to main first (--dry-run: only said)
            notes[top] = (tr(" (sẽ chép vào main trước: ", " (would copy into main first: ") if dry else tr(" (chép vào main trước: ", " (copied into main first: ")) \
                + ", ".join(rel for rel, _p in carry[:5]) + ")"
            if not dry:
                _copied, refused = _carry_secrets(main, carry)
                if not refused:   # checked again: the copies are main's now, so nothing left may be unique
                    refused = _gc_unique(main, top, dangling)
                if refused:
                    kept.append((top, _gc_why(refused)))
                    continue
        if dry:
            deleted.append(top)
            continue
        _clear_user_locks(top)
        shutil.rmtree(top, ignore_errors=True)
        if os.path.exists(top):
            kept.append((top, tr("không xoá hết được: ", "could not delete it all: ") + _by_hand(top)))
            continue
        deleted.append(top)
        if log:
            _gc_log(log, (["== " + time.strftime("%Y-%m-%d %H:%M:%S")] if len(deleted) == 1 else [])
                    + ["✔ gc: " + tr("đã xoá ", "deleted ") + top + notes.get(top, "")])
    for e in _worktree_entries(main)[1:]:   # #327 b: a devkit-kept lock of a dead pid was opened only by `remove`; a live pid's lock is never touched
        k = None if e["broken"] else kept_lock(main, e["path"])
        if k and not k[2]:
            why = f"devkit-kept session={k[0]} pid={k[1]}"
            if dry or git(main, "worktree", "unlock", e["path"], check=False).returncode == 0:
                print(("• gc (dry-run): " + tr("sẽ mở khoá ", "would unlock ") if dry else "✔ gc: " + tr("đã mở khoá ", "unlocked ")) + e["path"] + f" ({why}, " + tr("pid đã chết)", "pid is dead)"))
    oldest = time.strftime("%Y%m%d", time.localtime(time.time() - DISCARD_KEEP_DAYS * 86400))
    for ref in git(main, "for-each-ref", "--format=%(refname)", DISCARD_REF, check=False).stdout.split():
        m = DISCARD_REF_DATE_RE.fullmatch(ref)   # bản cất của `worktree discard` quá DISCARD_KEEP_DAYS ngày; tên không có ngày thì để yên
        if m and m.group(1) < oldest and (dry or git(main, "update-ref", "-d", ref, check=False).returncode == 0):
            deleted.append(ref)   # (cả bản cất branch-<nhánh>-* của prune-branch / remove: lời báo của chúng nói rõ DISCARD_KEEP_DAYS ngày)
            if log and not dry:   # vào sổ gc như thư mục đã xoá (OCR 18/10)
                _gc_log(log, (["== " + time.strftime("%Y-%m-%d %H:%M:%S")] if len(deleted) == 1 else []) + ["✔ gc: " + tr("đã xoá ", "deleted ") + ref])
    for p in deleted:
        print(("• gc (dry-run): " + tr("sẽ xoá ", "would delete ") if dry else "✔ gc: " + tr("đã xoá ", "deleted ")) + p + notes.get(p, ""))
    for p, why in kept:
        print("• gc: " + tr("giữ ", "kept ") + p + ": " + why)
    if not deleted and not kept:
        print("✔ gc: " + tr("không có gì để dọn", "nothing to clean"))
    return 0


WT_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}")
HOOK_CMD = 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/session_worktree.sh" '
TRUNK_HOOKS = {"WorktreeCreate": ("worktree-create", 300), "WorktreeRemove": ("worktree-remove", 120)}


def _hook_payload():
    try:
        d = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        return {}
    return d if isinstance(d, dict) else {}


def _registered(main, wt):
    try:
        return any(_same_path(e["path"], wt) for e in _worktree_entries(main) if not e["broken"])
    except SystemExit:
        return False


def _owner(wt):
    """The session a worktree's devkit-worktree.json names (`add --session`, written from the moment git registers it); None: none, or unreadable."""
    try:
        o = _read_state(wt).get("session")
    except (OSError, ValueError, SystemExit):
        return None
    return o if isinstance(o, str) and o else None


def cmd_hook_create(cwd, args):
    """Claude Code's WorktreeCreate hook in trunk mode (W1 R1 v6; wired by `worktree trunk wire`: init, every SessionStart, `trunk on`). EnterWorktree, `claude --worktree` and a
    subagent's isolation: "worktree" get their worktree from `add --session`: detached at HEAD under <main>/.claude/worktrees/<name> (where
    Claude puts its own: EnterWorktree never asks the user there), local config copied, the DevKit installed, the owning session in its
    state from the moment git registers it. Configuring this hook REPLACES Claude's own `git worktree add` (code.claude.com hooks docs),
    so: the path is the LAST stdout line and everything else goes to stderr; a worktree of that name already registered is handed back
    only to the session that owns it - another session (also `fix/login` against `fix-login`, one folder name) gets <name>-<8 characters of
    its id>, so two sessions never work in one tree (R3 review 14/10: the second merged and could remove the first one's work); one create
    at a time per repo (flock), so a race for a name ends the same way; a refusal for room (the disk floor) fails the creation with exit 4
    and says why; any other failure of the set-up still
    hands back a plain detached worktree - no EnterWorktree and no isolated subagent is ever stranded by a DevKit fault."""
    d = _hook_payload()
    name, sid = str(d.get("name") or ""), str(d.get("session_id") or "")
    segs = name.split("/")   # EnterWorktree names are "/"-separated segments (fix/login): one folder, the "/" a "-"
    name = "-".join(segs) if all(WT_NAME_RE.fullmatch(s) for s in segs) else name
    if not WT_NAME_RE.fullmatch(name) or ".." in name:
        print(f"✖ worktree hook: not a worktree name: {name!r}", file=sys.stderr)
        return 2
    here = d.get("cwd") if isinstance(d.get("cwd"), str) and os.path.isdir(d["cwd"]) else cwd
    main = os.path.realpath(main_checkout(here))
    lock = None
    try:
        lock = _lock_file(os.path.join(os.path.realpath(git(main, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()),
                                       "devkit-hook-create.lock"), wait=150.0)
        if lock is None:
            print("• worktree hook: create lock still held after 150 s; going ahead without it", file=sys.stderr)
    except (OSError, SystemExit) as e:   # no lock: the create goes ahead (a stranded EnterWorktree is worse than a race for one name)
        print(f"• worktree hook: create lock not taken ({e})", file=sys.stderr)
    try:
        return _hook_create(main, name, sid)
    finally:
        if lock is not None:
            lock.close()


def _hook_create(main, name, sid):
    sid_ok = bool(SESSION_RE.fullmatch(sid))
    root = os.path.join(main, ".claude", "worktrees")
    base = os.path.join(root, name)
    own = os.path.join(root, f"{name[:90]}-{re.sub('[^A-Za-z0-9]', '', sid)[:8] or os.getpid()}")

    def mine(p):
        return os.path.isdir(p) and _registered(main, p) and sid_ok and _owner(p) == sid
    if mine(base):
        print(base)
        return 0
    wt = base
    if os.path.isdir(base) and _registered(main, base):   # another session's (or an unowned) worktree of this name: not shared
        wt = own
        if mine(own):
            print(own)
            return 0
    rc = 1
    try:
        with contextlib.redirect_stdout(sys.stderr):
            rc = cmd_add(main, [wt] + ([f"--session={sid}"] if SESSION_RE.fullmatch(sid) else []))
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else 1
    except Exception as e:  # noqa: BLE001 - any other fault of the set-up (a full disk, a bug): the plain worktree below is still handed back
        print(f"⚠ worktree hook: set-up failed ({type(e).__name__}: {e})", file=sys.stderr)
        rc = 1
    if rc == NO_ROOM:
        return NO_ROOM
    if rc != 0:
        if not os.path.lexists(wt):
            r = git(main, "worktree", "add", "--detach", wt, check=False, bounded=False)
            if r.returncode != 0:
                print("✖ worktree hook: " + (r.stderr or r.stdout).strip()[-400:], file=sys.stderr)
                return 1
        elif not _registered(main, wt):
            print(f"✖ worktree hook: {wt} exists and is not a worktree of this repo", file=sys.stderr)
            return 1
        elif (o := _owner(wt)) is not None and o != sid:   # `add` failed on a folder another session owns (lock timeout, two ids with one suffix): never hand it over
            print(f"✖ worktree hook: {wt} belongs to another session; not handed back", file=sys.stderr)
            return 1
        try:   # whatever the set-up got to is set-up - but only OUR set-up: a create of the same name still running elsewhere keeps its
            # provisional state and its owner (OCR 14/10: the second create of one name used to stamp its own final state over it)
            try:
                cur = _read_state(wt)
            except (OSError, ValueError, SystemExit):
                cur = None
            if cur is None and not _has_state_file(wt) or (isinstance(cur, dict) and cur.get("provisional") and cur.get("session") == sid):
                _write_state(wt, {"branch": None, "base": git(wt, "rev-parse", "HEAD").stdout.strip(), "main": main, "baseline": snapshot(wt),
                                  "fp": FP_VERSION, **({"session": sid} if SESSION_RE.fullmatch(sid) else {})})
        except (Exception, SystemExit) as e:   # (a full disk here too: the worktree is still handed back)
            print(f"• worktree hook: state not written ({e})", file=sys.stderr)
        print("⚠ worktree hook: " + tr("cài đặt DevKit vào worktree lỗi; trả về worktree trơn", "the DevKit set-up failed; a plain worktree is handed back"),
              file=sys.stderr)
    print(wt)
    return 0


def cmd_hook_remove(cwd, args):
    """WorktreeRemove in trunk mode: Claude cleans up a worktree the hook made (ExitWorktree "remove", a finished isolated subagent).
    `worktree remove` decides: it removes it only when nothing of its work would be lost, else it refuses - exit non-zero, the folder
    stays, Claude keeps the worktree and the Stop hook merges it. A path that is not one of this repo's worktrees: refused, nothing removed."""
    d = _hook_payload()
    wt = d.get("worktree_path")
    if not isinstance(wt, str) or not os.path.isabs(wt) or not os.path.isdir(wt):
        print(f"✖ worktree hook: no such worktree: {wt!r}", file=sys.stderr)
        return 1
    try:
        main = main_checkout(wt)
    except SystemExit:
        return 1
    if _same_path(main, wt) or not _registered(main, wt):
        print(f"✖ worktree hook: {wt} is not a linked worktree of this repo", file=sys.stderr)
        return 1
    try:
        with contextlib.redirect_stdout(sys.stderr):
            return cmd_remove(main, [wt])
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else 1


def _load_local_settings(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as e:
        die(tr(f"{path} không đọc được ({e}): không sửa", f"{path} cannot be read ({e}): left untouched"), 1)
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        die(tr(f"{path} không phải object JSON có `hooks` là object: không sửa", f"{path} is not a JSON object with an object `hooks`: left untouched"), 1)
    return data


def _trunk_hooks_wired(data):
    hooks = data.get("hooks") or {}
    return all(any(HOOK_CMD + sub in str(h.get("command", "")) for m in hooks.get(ev) or [] if isinstance(m, dict)
                   for h in m.get("hooks") or [] if isinstance(h, dict)) for ev, (sub, _t) in TRUNK_HOOKS.items())


def _trunk_install_files(main):
    """The non-settings half of the wiring: the session_worktree.sh link and the worktrees folder out of git's sight. Idempotent."""
    link = os.path.join(main, ".claude", "hooks", "session_worktree.sh")
    if not os.path.exists(link):   # missing, or dangling (the DevKit moved since): make it again
        if os.path.islink(link):
            os.unlink(link)
        os.makedirs(os.path.dirname(link), exist_ok=True)
        os.symlink(os.path.join(DEVKIT, "hooks", "session_worktree.sh"), link)
    for pattern, probe in (("/.claude/worktrees/", ".claude/worktrees/x/"), ("/.claude/settings.local.json", ".claude/settings.local.json"),
                           ("/.claude/hooks/session_worktree.sh", ".claude/hooks/session_worktree.sh")):
        if git(main, "check-ignore", "-q", "--no-index", probe, check=False).returncode != 0:   # the sessions' worktrees live there; Claude Code normally ignores the file; --no-index: a tracked path never reads as ignored, so each call added the line again
            exclude = os.path.join(git(main, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip(), "info", "exclude")
            os.makedirs(os.path.dirname(exclude), exist_ok=True)   # never untracked noise in main's status (local, not committed)
            with open(exclude, "a", encoding="utf-8") as f:
                f.write(f"\n{pattern}\n")


def _trunk_wire(main):
    """Trunk mode is the default, so its WorktreeCreate / WorktreeRemove hooks must exist on every machine: settings.local.json is untracked
    and a fresh clone has none. Idempotent (nothing is written when both hooks and the link are there); raises SystemExit(1) on a settings file
    that does not parse, which callers that must not fail (init, heal) catch: that file is never rewritten. Returns True when it wrote."""
    local = os.path.join(main, ".claude", "settings.local.json")
    data = _load_local_settings(local)
    link = os.path.join(main, ".claude", "hooks", "session_worktree.sh")
    if _trunk_hooks_wired(data) and os.path.exists(link):
        _trunk_install_files(main)   # idempotent: a repo wired by the earlier `trunk on` excluded only /.claude/worktrees/
        return False
    _trunk_install_files(main)   # first: the script the hooks call must exist before the hooks that call it (a WorktreeCreate hook REPLACES `git worktree add`)
    _trunk_set_hooks(main, data, True)
    return True


def _trunk_set_hooks(main, data, on):
    """Add (on) or remove (off) exactly the two trunk hooks in main's settings.local.json, everything else kept; atomic write."""
    local = os.path.join(main, ".claude", "settings.local.json")
    hooks = data.setdefault("hooks", {})
    for ev, (sub_cmd, timeout) in TRUNK_HOOKS.items():
        kept = [m for m in hooks.get(ev) or [] if not (isinstance(m, dict) and any(
            isinstance(h, dict) and HOOK_CMD + sub_cmd in str(h.get("command", "")) for h in m.get("hooks") or []))]
        if on:
            kept.append({"hooks": [{"type": "command", "command": HOOK_CMD + sub_cmd, "timeout": timeout}]})
        if kept:
            hooks[ev] = kept
        else:
            hooks.pop(ev, None)
    if not hooks:
        data.pop("hooks", None)
    os.makedirs(os.path.dirname(local), exist_ok=True)
    tmp = f"{local}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, local)


def cmd_trunk(cwd, args):
    """`agent-kit worktree trunk on|off|wire|status` - trunk mode for this repo (W1 R1/R2/R7 v6, docs/workflow-improvements.md I.0). It is the
    DEFAULT (user, 2026-10-15: a repo with no `devkit.trunkMode` key is on). `on` sets `git config devkit.trunkMode true` and wires the
    WorktreeCreate / WorktreeRemove hooks into the main checkout's .claude/settings.local.json (untracked, this machine only: Claude Code reads
    the main checkout's local file in its worktrees too); `off` writes `false` (an unset key would mean ON) and unwires them; `wire` only wires
    (init and every SessionStart do it for a repo that has not said `false`). New sessions pick it up. WORKTREE_TRUNK_MODE=0 in the
    environment turns it off everywhere without touching a repo."""
    action = args[0] if args else "status"
    if action not in ("on", "off", "wire", "status") or len(args) > 1:
        die("usage: agent-kit worktree trunk [on|off|wire|status]")
    main = main_checkout(cwd)
    local = os.path.join(main, ".claude", "settings.local.json")
    if action == "wire":   # init and SessionStart: never fatal (a settings file that does not parse stays as it is), never touches a repo that said false
        if _trunk_mode(main):
            try:
                _trunk_wire(main)
            except (SystemExit, OSError) as e:
                if not isinstance(e, SystemExit):   # `die` has already said why a settings file was left alone
                    print(tr(f"trunk mode: không đấu được hook ({e}); {local} giữ nguyên", f"trunk mode: hooks not wired ({e}); {local} left as it is"))
        return 0
    if action == "off":   # the user's way out never depends on settings.local.json: the key goes first, unwiring the hooks is best effort
        git(main, "config", "--replace-all", "devkit.trunkMode", "false")   # not --unset: with the default ON, an unset key means ON
        try:
            data = _load_local_settings(local)
            if any(ev in (data.get("hooks") or {}) for ev in TRUNK_HOOKS):   # never wired: nothing to remove, and no `{}` file left in git status
                _trunk_set_hooks(main, data, False)
        except (SystemExit, OSError):   # `die` has said why a file that cannot be read was left alone; a failed write is no reason to fail the opt-out
            print("✔ " + tr(f"trunk mode TẮT (devkit.trunkMode=false); hook trong {local} chưa gỡ được",
                            f"trunk mode OFF (devkit.trunkMode=false); the hooks stay in {local}, which could not be changed"))
            return 0
        print("✔ " + tr("trunk mode TẮT: như cũ", "trunk mode OFF: the old behaviour"))
        return 0
    data = _load_local_settings(local)
    if action == "status":
        on, wired = _trunk_mode(main), _trunk_hooks_wired(data)
        print(f"trunk mode: {'on' if on else 'off'}" + (" (WORKTREE_TRUNK_MODE=0)" if os.environ.get("WORKTREE_TRUNK_MODE") == "0" else "")
              + f"; WorktreeCreate/WorktreeRemove hooks {'wired' if wired else 'not wired'} in {local}")
        return 0
    try:
        _trunk_install_files(main)   # first: the script the hooks call must exist before the hooks that call it (a WorktreeCreate hook REPLACES `git worktree add`)
    except OSError as e:
        die(tr(f"không tạo được link hay file ignore ({e}): hook chưa đấu", f"cannot make the link or the excludes ({e}): hooks not wired"), 1)
    git(main, "config", "--replace-all", "devkit.trunkMode", "true")   # --replace-all: a config that holds the key twice makes a plain set exit 5; before the hooks, so a failed write never leaves hooks next to `false`
    try:
        _trunk_set_hooks(main, data, True)
    except OSError as e:
        die(tr(f"không ghi được {local} ({e}): hook chưa đấu", f"cannot write {local} ({e}): hooks not wired"), 1)
    print("✔ " + tr("trunk mode BẬT: main chỉ để gộp; mỗi phiên làm trong worktree riêng (EnterWorktree). Phiên mới mới thấy hook.",
                    "trunk mode ON: main is merge-only; every session works in its own worktree (EnterWorktree). New sessions pick up the hooks."))
    return 0


def main(argv):
    cwd = os.getcwd()
    set_lang(resolve_lang(None, cwd))
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    if argv[1] == "hook-create":   # Claude Code hooks: the repo comes from the payload, not from where the hook process runs
        return cmd_hook_create(cwd, argv[2:])
    if argv[1] == "hook-remove":
        return cmd_hook_remove(cwd, argv[2:])
    if git(cwd, "rev-parse", "--git-dir", check=False).returncode != 0:
        if argv[1:3] == ["trunk", "wire"]:
            return 0   # init in a project that is not a git repo: nothing to wire, never an error
        die(tr("không ở trong git repository", "not inside a git repository"))
    action, rest = argv[1], argv[2:]
    if action == "add":
        return cmd_add(cwd, rest)
    if action == "diff":
        return cmd_diff(cwd, rest)
    if action == "finish":
        return cmd_finish(cwd, rest)
    if action == "automerge":
        return cmd_automerge(cwd, rest)
    if action in ("remove", "rm"):
        return cmd_remove(cwd, rest)
    if action == "discard":
        return cmd_discard(cwd, rest)
    if action == "restore":
        return cmd_restore(cwd, rest)
    if action == "prune-branch":
        return cmd_prune_branch(cwd, rest)
    if action == "status":
        return cmd_status(cwd, rest)
    if action == "heal":
        return cmd_heal(cwd, rest)
    if action == "gc":
        return cmd_gc(cwd, rest)
    if action == "trunk":
        return cmd_trunk(cwd, rest)
    if action == "list":
        return subprocess.run(["git", "-C", cwd, "worktree", "list"]).returncode
    die(tr(f"lệnh không hợp lệ '{action}'", f"unknown action '{action}'") + " (add | diff | finish | remove | discard | restore | prune-branch | status | gc | trunk | list)")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
