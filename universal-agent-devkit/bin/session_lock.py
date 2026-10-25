#!/usr/bin/env python3
"""One agent session per checkout (owner request, GeelyEx2 2026-09-29).

Two Claude sessions worked in one checkout: the full gate of one ran 9 times, twice passed without writing a receipt
because the OTHER session changed files mid-run, and push_gate then blocked the push; shared status files had to be
excluded by hand from every commit. Rule: a checkout (one git dir — a linked worktree is its own) has ONE holder.

Lock: <git dir>/devkit-session.lock = {"session_id", "started", "heartbeat", "cwd"}. A session takes it when it is
free, its own, or stale (heartbeat older than DEVKIT_SESSION_LOCK_STALE_S, default 600 s). Another live session is
READ-ONLY here: PreToolUse blocks (exit 2) its Edit/Write/MultiEdit/NotebookEdit and the Bash calls that collide —
git writes, post-fix-gate, and shell redirects into the checkout. Reads, builds and tests pass. SessionStart never
blocks: it takes the lock or prints who holds it. SessionEnd releases the holder's lock. Sub-agents share their
parent's session_id, so they count as the same session.

An IDLE holder frees the checkout (user, 2026-10-09: "phiên đó ngừng chạy thì là ok rồi chứ sao bắt phải /exit"): a
session that finished its turn and waits at the prompt is a live process, so the pid check kept its lock for the whole
heartbeat window. Claude Code's Notification `idle_prompt` (about 60 s after the turn ended, the user has not typed, no
background agent runs) marks the lock `idle_since` and the session's registry entry `status: idle`; an idle lock is free
for another session and an idle session is not an active sibling for the gate's --full. Not marked while the project's
test_run.lock is held (an end-of-turn gate still running). The holder's next Bash/Edit call clears it. Not Stop: Stop
hooks run in parallel (the end-of-turn gate among them) and a blocked Stop means the turn goes on.

Agents with no hook API (Antigravity) cannot be blocked, so they ask (2026-09-29, rules/essentials.md):
`python3 .agents/devkit/bin/session_lock.py --status [--session ID] [dir]` — read-only; exit 3 while another live
session holds the checkout (do not edit it), 0 when free, stale, its own, or not a git checkout.

Writes are judged by their TARGET (OfficeReader 2026-10-08, three hours lost): a git write or gate run aimed at ANOTHER
repository (`cd /clone && git commit`, `git -C /clone push`, `CLAUDE_PROJECT_DIR=/clone post-fix-gate`) and an Edit/Write of a
path outside this checkout never collide; a target that cannot be resolved ($VAR, ~, a missing directory) still does.

Escape hatches (both logged to <git dir>/devkit-session.log): DEVKIT_ALLOW_SHARED_CHECKOUT=1 in the hook's own environment, and
the user's approval for a RUNNING session: `! agent-kit allow-shared [--minutes N]` (default 60) writes
<git dir>/devkit-allow-shared, `agent-kit allow-shared off` removes it. An agent's own Bash call that runs the command or
writes the flag file is blocked (pattern-based: ponytail — a python one-liner that opens the file is not recognised;
upgrade to a signed flag if that is ever seen).
ponytail: Bash writes are recognised by pattern (git writes, post-fix-gate, `>`/`>>` into the checkout) — cp/mv/rm/
sed -i by a second session still pass; upgrade to hooks/worktree_guard.sh's write classifier if that happens.

Read-decide-write of the lock runs under an exclusive flock on <git dir>/devkit-session.guard (audit 2026-10-09: two sessions
whose first writes started together were both allowed). A lock or registry number that is not a number (heartbeat, started)
counts as missing, so the lock is stale — as a lock with no heartbeat always was, and as an unreadable lock is free.
"""
import json
import os
import re
import stat
import sys
import time
# subprocess is imported where git really has to run (2026-10-09: it cost ~7 ms of every PreToolUse call; see _find_git)

LOCK = "devkit-session.lock"
LOG = "devkit-session.log"
GUARD = "devkit-session.guard"
GUARD_WAIT_S = 2.0   # the guard covers a read, a pid check and one small write: held for about a millisecond
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


class _Re:
    """A regex compiled on first use (2026-10-09: compiling these at import cost ~1.7 ms of every Edit call, which uses none)."""
    def __init__(self, pattern):
        self._pattern, self._rx = pattern, None

    def __getattr__(self, name):
        if self._rx is None:
            self._rx = re.compile(self._pattern)
        return getattr(self._rx, name)


# (?![\w-]) ends the verb: `git merge-base`, `merge-tree` and `commit-tree` are read-only plumbing, not `merge` / `commit` (the old
# `\b` matched before the hyphen and blocked them). `opts` are git's global options before the verb (-C <dir>, -c k=v, --git-dir ...).
GIT_WRITE = _Re(
    r"(^|[\s;&|(/])git\s+(?P<opts>(?:(?:-C\s+(?:\"[^\"]*\"|'[^']*'|\S+)|-c\s+(?:[^\s\"']|\"[^\"]*\"|'[^']*')+|--(?:git-dir|work-tree)\s+\S+|--[\w-]+(?:=\S+)?|-[pP])\s+)*)"
    r"(commit|push|pull|add|rm|mv|reset|checkout|restore|switch|stash(?![ \t]+(?:list|show)(?![\w-]))|merge|rebase|cherry-pick|revert|am|apply|tag|clean)(?![\w-])")
# (?!/): <git dir>/postfix-gate/ is the folder of its receipt and runs.jsonl, read by anyone (14/10: a `python3 -c` reading it was a gate run)
GATE = _Re(r"post-fix-gate(\.py)?\b(?!/)|\bpostfix-gate\b(?!/)|\bagent-kit\s+(?:worktree|wt)\s+(?:finish|automerge)\b|worktree\.py\s+(?:finish|automerge)\b")
# Commands that only READ: naming the gate to them (`grep -c post-fix-gate AGENTS.md`, `cat bin/post-fix-gate.py`) does not run it. echo / printf
# stay out (`echo $(postfix-gate)` runs it) and so does awk; sed đọc khi không có -i (_gate_run); a substitution anywhere in the segment is never excused.
# git reads only through its read verbs, named right after it: `git bisect run`, `git submodule foreach` and `git -c alias.x=!… x` run commands.
_GATE_READERS = frozenset(("grep", "egrep", "fgrep", "rg", "ag", "cat", "bat", "less", "more", "head", "tail", "wc", "nl", "file", "stat", "ls",
                           "diff", "cmp", "pgrep", "pidof"))   # pgrep/pidof chỉ tìm tiến trình (K9 17/10: `pgrep -fl post-fix-gate` ở main bị chặn)
_GIT_READ_VERBS = frozenset(("log", "show", "diff", "grep", "blame", "status", "ls-files", "rev-parse", "rev-list", "cat-file", "describe", "shortlog"))
_GATE_PREFIX = frozenset(("env", "time", "nohup", "command", "exec", "builtin", "sudo", "nice"))


def _gate_run(seg):
    """The segment runs the post-fix gate / worktree finish: GATE names it and the first command word is not a pure reader. A quote or a
    backslash in the words up to the command word means the plain word split cannot tell which is the command: it counts as running."""
    if not GATE.search(seg):
        return False
    if "$(" in seg or "`" in seg or "<(" in seg:
        return True
    words = seg.split()
    for k, w in enumerate(words):
        if any(c in w for c in "\"'\\"):
            return True
        if w in _GATE_PREFIX or ("=" in w and w.split("=", 1)[0].isidentifier()):
            continue
        head = os.path.basename(w)
        if head == "git":   # K9 17/10: bỏ qua `-C <dir>`, `--no-pager`, `-P` trước verb (`git -C $w log -- …/post-fix-gate.py` là đọc); -c và
            j = k + 1       # option khác vẫn tính là chạy (`-c core.pager=…` chạy được lệnh)
            while j < len(words) and words[j] in ("-C", "--no-pager", "-P"):
                j += 2 if words[j] == "-C" else 1
            verb, nxt = (words[j] if j < len(words) else ""), (words[j + 1] if j + 1 < len(words) else "")
            return not (verb in _GIT_READ_VERBS or (verb == "branch" and nxt in ("--list", "-l")) or (verb == "worktree" and nxt == "list"))
        if head == "sed":   # sed không có -i chỉ đọc (17/10: `sed -n 3260,3300p …/post-fix-gate.py` ở main bị coi là chạy gate); mẫu -i như hooks/shell_writes.py
            return any(re.fullmatch(r"-[A-Za-z]*i.*|--in-place.*", a) for a in words[k + 1:])
        return head not in _GATE_READERS
    return True
SEPARATOR = _Re(r"(&&|\|\||[;|&\n])")
CD_ONLY = _Re(r"^\s*(?:builtin\s+)?cd\s+(?:--\s+)?(\"[^\"]*\"|'[^']*'|[^\s;&|()<>$`\\]+)\s*$")
PROJECT_DIR = _Re(r"\bCLAUDE_PROJECT_DIR=(\"[^\"]*\"|'[^']*'|\S+)")
ALLOW_FLAG = "devkit-allow-shared"
# A directory change the segment walk cannot follow (subshell, `bash -c`, eval, pushd, a cd with a redirect, GIT_DIR=...): the directory
# is UNKNOWN from there on, so every later write fails closed (review 2026-10-08: `cd B && (cd A && git commit)` slipped through).
DIR_CHANGE = _Re(r"(?:^|[\s;&|(`])(?:cd|pushd|popd)\b|\beval\b|\b(?:ba|z|da)?sh\s+-\w*c\b|\bGIT_DIR=|\bGIT_WORK_TREE=|--git-dir|--work-tree|\benv\s+(?:-\S+\s+)*-C\b|--chdir|^\s*\(")
WRAPPERS = {"env", "command", "exec", "xargs", "nohup", "time", "sudo", "bash", "sh", "zsh", "dash", "eval"}
WRITE_CMDS = {"touch", "cp", "mv", "ln", "install", "tee", "dd", "rsync", "truncate", "perl", "ruby", "node"}
READERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "cat", "bat", "less", "more", "head", "tail", "wc", "file", "stat", "ls", "echo",
           "printf", "diff", "cmp", "git", "man", "type", "which", "find", "sed", "awk"}   # (sed writes only with -i: see is_self_grant)
_HEREDOC = _Re(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
RUNS_BODY = {"bash", "sh", "zsh", "dash", "ksh", "python", "python3", "perl", "ruby", "node", "eval", "source", "."}   # a heredoc fed to these is CODE
SHELL_BODY = {"bash", "sh", "zsh", "dash", "ksh", "eval", "source", "."}   # ... and these run it as SHELL code (a `>` there redirects)


def _strip_heredocs(cmd, shell_only=False):
    """Drop the body of every heredoc that feeds a data command (cat, a commit message, a patch): its lines are text, not commands. A
    heredoc fed to a shell or an interpreter keeps its body - those lines run. shell_only: keep only bodies a SHELL runs (the redirect
    check: `print(1 > 0)` fed to python is not a shell redirect)."""
    lines = cmd.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        m = _HEREDOC.search(line)
        if not m:
            continue
        head = re.split(r"[;&|(]|\$\(|`", line[:m.start()])[-1].split()
        head = [w for w in head if not re.match(r"^[A-Za-z_]\w*=", w)]
        word = os.path.basename(head[0]) if head else ""
        runs = word in SHELL_BODY if shell_only else (word in RUNS_BODY or word.startswith("python"))
        j = i
        while j < len(lines) and lines[j].strip() != m.group(2):
            j += 1
        if runs:
            out.extend(lines[i:j])
        i = j
    return "\n".join(out)


def _split_segments(cmd):
    """[segment, separator, segment, ...] like SEPARATOR.split, but a separator inside quotes does not split, a `&` that belongs to a
    redirect (2>&1, &>) does not split, and heredoc bodies of data commands are gone."""
    cmd = _strip_heredocs(cmd)
    out, buf, quote, i, n = [], [], None, 0, len(cmd)
    while i < n:
        c = cmd[i]
        if quote:
            buf.append(c)
            if c == "\\" and quote == '"' and i + 1 < n:
                buf.append(cmd[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            buf.append(c)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if c in "\"'":
            quote = c
            buf.append(c)
            i += 1
            continue
        if cmd[i:i + 2] in ("&&", "||"):
            out.append("".join(buf))
            out.append(cmd[i:i + 2])
            buf = []
            i += 2
            continue
        if c == "&" and ((i > 0 and cmd[i - 1] in "<>") or cmd[i + 1:i + 2] == ">"):
            buf.append(c)
            i += 1
            continue
        if c in ";|&\n":
            out.append("".join(buf))
            out.append(c)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    out.append("".join(buf))
    return out


def _redirect_targets(cmd):
    """The target of every output redirect (`>`, `>>`, `>|`, `&>`, `N>`) in cmd, unquoted; "" for a fd copy (`>&2`) or `>(...)`. A `>`
    inside quotes, escaped, or in the body of a heredoc no shell runs is text (D5, audit 2026-10-09: `grep -n "a > b" f`,
    `git log --format='%h -> %s'` and `python3 -c "print(1>0)"` were blocked as redirects into the checkout)."""
    s = _strip_heredocs(cmd, shell_only=True)
    out, quote, i, n = [], None, 0, len(s)
    while i < n:
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        i += 1
        if c != ">":
            continue
        if i < n and s[i] in ">|":
            i += 1
        while i < n and s[i] in " \t":
            i += 1
        word, q = [], None
        while i < n:
            ch = s[i]
            if q:
                if ch == q:
                    q = None
                else:
                    word.append(ch)
            elif ch in "\"'":
                q = ch
            elif ch.isspace() or ch in ";&|<>()":
                break
            else:
                word.append(ch)
            i += 1
        out.append("".join(word))
    return out


# Variables that change how git finds the repository: with any of them set, git itself is asked (_find_git).
_GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM")


def _env_moves_git():
    """True when the environment can change which repository git finds: a _GIT_ENV variable, or config given in the environment
    (GIT_CONFIG_COUNT / GIT_CONFIG_PARAMETERS) that names a core.*, safe.* or include key. Other config there (a proxy, a CA file:
    cloud sessions set http.* this way) leaves discovery alone."""
    if any(os.environ.get(k) for k in _GIT_ENV):
        return True
    keys = os.environ.get("GIT_CONFIG_PARAMETERS", "").lower()
    try:
        n = int(os.environ.get("GIT_CONFIG_COUNT") or 0)
    except ValueError:
        return True
    if n > 100:
        return True
    keys += " ".join(os.environ.get(f"GIT_CONFIG_KEY_{i}", "") for i in range(n)).lower()
    return any(k in keys for k in ("core.", "safe.", "include"))


def _plain_config(path):
    """False when a repository config file sets core.worktree / core.bare or includes another file (git must read it); True when it
    sets none of those or does not exist."""
    try:
        with open(path, "rb") as f:
            raw = f.read(1 << 20)
    except FileNotFoundError:
        return True
    except OSError:
        return False
    for line in raw.lower().splitlines():
        s = line.split(b"#")[0].split(b";")[0].replace(b" ", b"").replace(b"\t", b"")
        if s.startswith((b"worktree=", b"[include")) or s in (b"bare=true", b"bare=yes", b"bare=on", b"bare=1", b"bare"):
            return False
    return True


def _find_git(cwd):
    """(absolute git dir, toplevel, common dir) found WITHOUT spawning git; (None, None, None) when cwd is in no repository; None when
    the layout is not a plain one and git must say (D7, 2026-10-09: two `git rev-parse` per hook call were ~12 ms of the ~50 ms every
    Bash/Edit call pays on macOS). Plain: nothing in the environment moves git (_env_moves_git); cwd an existing directory; walking up (realpath, same filesystem) the
    first `.git` is a directory, or a regular file `gitdir: <dir>` (linked worktree: <dir>/commondir names the shared git dir;
    submodule: none); its git dir has HEAD; this user owns the toplevel and the git dir; no core.worktree / core.bare / include in
    the repository config; no level on the way is itself a git dir (cwd inside .git or a bare repo). Anything else: None.
    ponytail: core.worktree set from the user's global config is not seen; nobody sets it there — fall back if that is ever met."""
    if _env_moves_git():
        return None
    try:
        d = os.path.realpath(cwd)
        st = os.stat(d)
    except (OSError, ValueError, TypeError):
        return None
    if not stat.S_ISDIR(st.st_mode):
        return None
    dev = st.st_dev
    while True:
        dotgit = os.path.join(d, ".git")
        try:
            lst = os.lstat(dotgit)
        except FileNotFoundError:
            lst = None
        except OSError:
            return None
        if lst is not None:
            break
        if os.path.isfile(os.path.join(d, "HEAD")) and os.path.isdir(os.path.join(d, "objects")):
            return None   # a git dir itself (inside .git, a bare repository): git knows what that means
        parent = os.path.dirname(d)
        if parent == d:
            return None, None, None
        try:
            if os.stat(parent).st_dev != dev:
                return None   # git stops at a filesystem boundary unless told otherwise: let it decide
        except OSError:
            return None
        d = parent
    if stat.S_ISDIR(lst.st_mode):
        gdir = dotgit
    elif stat.S_ISREG(lst.st_mode):
        try:
            with open(dotgit, "rb") as f:
                head = f.read(4096).decode("utf-8")
        except (OSError, UnicodeDecodeError):
            return None
        if not head.startswith("gitdir: ") or head.count("\n") > 1:
            return None
        gdir = os.path.realpath(os.path.join(d, head[len("gitdir: "):].strip()))
    else:
        return None   # a symlink or anything stranger
    common = gdir
    try:
        if os.path.lexists(os.path.join(gdir, "commondir")):
            with open(os.path.join(gdir, "commondir"), encoding="utf-8") as f:
                common = os.path.realpath(os.path.join(gdir, f.read(4096).strip()))
        uid = os.geteuid()
        if (not os.path.isfile(os.path.join(gdir, "HEAD")) or not os.path.isdir(common)
                or os.stat(d).st_uid != uid or os.stat(gdir).st_uid != uid):
            return None   # broken pointer, or another user's repository (safe.directory): git decides
    except (OSError, ValueError):
        return None
    if not _plain_config(os.path.join(common, "config")) or not _plain_config(os.path.join(gdir, "config.worktree")):
        return None
    return gdir, d, common


def git_dir(cwd):
    found = _find_git(cwd)
    if found is not None:
        return found[0], found[1]
    import subprocess  # noqa: PLC0415 - only a layout _find_git cannot read pays for it
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--absolute-git-dir", "--show-toplevel"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None, None
    if r.returncode != 0:
        return None, None
    lines = r.stdout.strip().splitlines()
    return (lines[0], lines[1]) if len(lines) >= 2 else (lines[0], cwd)


def read_lock(path):
    try:
        if not stat.S_ISREG(os.lstat(path).st_mode):
            return None   # a FIFO planted here would block open() until the hook times out
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError, RecursionError):   # (nesting deep enough to overflow the parser: as unreadable)
        return None


def _num(v, default=0.0):
    """A lock / registry number (heartbeat, started) as a float; anything else - a string that is not a number, a bool, a list,
    NaN, ±inf - is `default`: a garbled value counts as missing (D6, audit 2026-10-09: float("abc") crashed the hook and --status
    with a traceback, exit 1, and the write went ahead)."""
    if isinstance(v, bool) or not isinstance(v, (int, float, str)):
        return default
    try:
        f = float(v)
    except (ValueError, OverflowError):
        return default
    return f if f - f == 0 else default   # NaN and ±inf fail f - f == 0


def read_checkout_lock(gdir):
    """The lock in git dir `gdir`, or None when it was copied along with that git dir (`cp -Rc <checkout> <scratch>`,
    AGENTS.md §7.1): its recorded gitdir is another directory (compared by inode — paths differ in case on APFS and by
    symlinks), so it belongs to the checkout it came from and nobody holds the copy. A lock without a gitdir (written
    before 2026-10-09) still counts: fail closed; the holder rewrites it within 30 s."""
    lock = read_lock(os.path.join(gdir, LOCK))
    lock_gdir = lock.get("gitdir") if lock else None
    if isinstance(lock_gdir, str) and lock_gdir:
        try:
            same = os.path.samefile(lock_gdir, gdir)
        except OSError:
            same = False   # the original git dir is gone: certainly not this one
        if not same:
            return None
    return lock


def write_lock(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def git_common_dir(cwd):
    found = _find_git(cwd)
    if found is not None:
        return found[2], found[1]
    import subprocess  # noqa: PLC0415 - only a layout _find_git cannot read pays for it
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--git-common-dir", "--show-toplevel"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None, None
    if r.returncode != 0:
        return None, None
    lines = r.stdout.strip().splitlines()
    common = lines[0]
    top = lines[1] if len(lines) >= 2 else cwd
    if not os.path.isabs(common):
        common = os.path.normpath(os.path.join(cwd, common))
    return common, top


def sessions_dir(cwd):
    common, top = git_common_dir(cwd)
    if not common:
        return None, None
    sdir = os.path.join(common, "devkit-sessions")
    return sdir, top


def register_session(cwd, sid, agent="agent", pid=None, status="working"):
    if not sid:
        return
    sdir, top = sessions_dir(cwd)
    if not sdir:
        return
    try:
        os.makedirs(sdir, exist_ok=True)
        now = time.time()
        file_path = os.path.join(sdir, f"{sid}.json")
        if pid is None:
            pid = holder_pid()
        data = {
            "session_id": sid,
            "agent": agent,
            "pid": pid,
            "pid_start": pid_start(pid),
            "started": now,
            "heartbeat": now,
            "cwd": os.path.abspath(cwd),
            "gitdir": git_dir(cwd)[0],
            "status": status,
        }
        write_lock(file_path, data)
    except OSError:
        pass


def heartbeat_session(cwd, sid):
    if not sid:
        return
    sdir, top = sessions_dir(cwd)
    if not sdir:
        return
    file_path = os.path.join(sdir, f"{sid}.json")
    data = read_lock(file_path)
    now = time.time()
    if data:
        if data.get("status") != "idle" and now - _num(data.get("heartbeat")) < 15:
            return  # throttle (an idle session's first call always writes: it is working again)
        data["heartbeat"] = now
        data["status"] = "working"
        write_lock(file_path, data)
    else:
        register_session(cwd, sid)


def read_session(cwd, sid):
    """This session's registry entry, or None."""
    sdir, _top = sessions_dir(cwd)
    return read_lock(os.path.join(sdir, f"{sid}.json")) if sdir and sid else None


def mark_idle_session(cwd, sid, expect_heartbeat=None):
    """Registry entry -> status idle (Notification idle_prompt); heartbeat_session sets it back to working.
    expect_heartbeat: compare-then-write — a session whose heartbeat moved since the hook read it has resumed: left working."""
    sdir, _top = sessions_dir(cwd)
    if not sdir:
        return
    file_path = os.path.join(sdir, f"{sid}.json")
    data = read_lock(file_path)
    if data and data.get("status") != "idle" and (expect_heartbeat is None or data.get("heartbeat") == expect_heartbeat):
        data["status"] = "idle"
        try:
            write_lock(file_path, data)
        except OSError as e:
            print(f"session_lock: không ghi được trạng thái rảnh: {e}", file=sys.stderr)


def test_run_active(dirs):
    """True when a test run (post-fix gate, testsourceset gate, stale re-run) holds <dir>/.claude/audit-gate/test_run.lock.
    Probed with a shared non-blocking flock released at once; every holder of that lock retries, so the probe costs nothing.
    Anything that cannot be probed counts as running (the lock then stays, as before)."""
    import fcntl
    for d in dirs:
        p = os.path.join(d, ".claude", "audit-gate", "test_run.lock")
        try:
            fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
        except FileNotFoundError:
            continue
        except OSError:
            return True
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
        except OSError:
            return True
        finally:
            os.close(fd)
    return False


def unregister_session(cwd, sid):
    if not sid:
        return
    sdir, top = sessions_dir(cwd)
    if not sdir:
        return
    file_path = os.path.join(sdir, f"{sid}.json")
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
    except OSError:
        pass


def _ps(pid, fields):
    """`ps -o <fields>= -p pid` output, stripped; None when the process is gone or ps fails (macOS has no /proc)."""
    # `lstart` is printed in local time: pin TZ/locale so a start recorded under one TZ equals the one read under another
    env = dict(os.environ, TZ="UTC", LC_ALL="C")
    import subprocess  # noqa: PLC0415 - only a platform without /proc forks ps
    try:
        r = subprocess.run(["ps", "-o", "=,".join(fields.split(",")) + "=", "-p", str(pid)], capture_output=True, text=True, timeout=1, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    out = r.stdout.strip()
    return out if r.returncode == 0 and out else None


def _parse_starttime(stat):
    """`proc:<starttime>` (field 22 of /proc/<pid>/stat), None when unparsable. comm may hold spaces or ')': count after the last ')'."""
    try:
        return "proc:" + str(int(stat[stat.rfind(b")") + 2:].split()[19]))   # fields after ") " start at 3 (state): 22 is index 19
    except (IndexError, ValueError):
        return None


def _proc_start(pid):
    """`proc:<starttime>` read from /proc without a fork (Linux); None when there is no /proc entry."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            return _parse_starttime(f.read())
    except OSError:
        return None


def pid_start(pid):
    """Start time of `pid`: `proc:<starttime>` from /proc on Linux (no fork), else `ps -o lstart=`; None when unknown. Recorded with
    the pid: the OS may hand the same pid to another process later, and only a different start time tells that apart from the session."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1:
        return None
    return _proc_start(pid) or _ps(pid, "lstart")


def _parent_and_comm(pid):
    """(ppid, command name) of `pid`: /proc on Linux, `ps -o ppid=,comm=` elsewhere (macOS); None when unreadable."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            stat = f.read()
    except OSError:
        out = _ps(pid, "ppid,comm")
        if not out:
            return None
        head, _, comm = out.partition(" ")
        try:
            return int(head), os.path.basename(comm.strip()).encode()
        except ValueError:
            return None
    close = stat.rfind(b")")   # comm may hold spaces or ')': it ends at the last ')'
    try:
        return int(stat[close + 2:].split()[1]), stat[stat.find(b"(") + 1:close]   # after ") ": state, ppid
    except (IndexError, ValueError):
        return None


def holder_pid():
    """The process that lives as long as the session: the hook's parent. Claude Code runs a hook as `/bin/sh -c 'bash …'`; bash
    (macOS /bin/sh) execs that last command, so the parent is claude. dash (Linux /bin/sh) forks it and stays as a short-lived
    parent: its pid was dead at the next call and every lock read as free (audit 2026-10-09,
    tests/context_memory/test_session_lock_sh_parent.sh). Such a sh/dash parent is skipped (/proc on Linux, `ps` on macOS, where
    a `sh -c 'a; b'` parent forks too, issue #17)."""
    pid = os.getppid()
    for _ in range(3):
        info = _parent_and_comm(pid)
        if info is None or info[1] not in (b"sh", b"dash"):
            return pid
        if info[0] <= 1:
            return pid
        pid = info[0]
    return pid


def is_pid_alive(pid, start=None):
    """`start`: the pid_start recorded with the pid. A live pid whose start time differs was recycled by the OS: dead."""
    if not pid or not isinstance(pid, int) or pid <= 1:
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass   # exists, owned by another user: a recycled pid is told apart by `start` below
    except (OSError, OverflowError):   # (a pid past the OS range: unknown, like a pid that is not a number)
        return True
    if start:
        # a `proc:` record is compared with /proc, a ps record (written on macOS or before this format) with ps
        now = _proc_start(pid) if str(start).startswith("proc:") else _ps(pid, "lstart")
        if now is not None and now != start:
            return False
    return True


def get_active_sessions(cwd=None, current_sid=None, stale_s=180.0):
    """Returns (all_active_sessions, other_sessions, is_last_active).
    is_last_active is True if NO other sessions are currently actively working."""
    target = cwd or os.getcwd()
    sdir, top = sessions_dir(target)
    my_gitdir = git_dir(target)[0] if sdir else None
    now = time.time()
    active = []
    other = []
    if not sdir or not os.path.exists(sdir):
        # Fallback check legacy devkit-session.lock
        gdir, _ = git_dir(target)
        if gdir:
            lock = read_lock(os.path.join(gdir, LOCK))
            if lock and lock.get("session_id") and not lock.get("idle_since") and (now - _num(lock.get("heartbeat")) <= stale_s):
                sid = lock.get("session_id")
                active.append(lock)
                if current_sid and sid != current_sid:
                    other.append(lock)
        return active, other, len(other) == 0

    try:
        entries = os.listdir(sdir)
    except OSError:
        return active, other, True

    for entry in entries:
        if not entry.endswith(".json"):
            continue
        file_path = os.path.join(sdir, entry)
        info = read_lock(file_path)
        if not info or not info.get("session_id"):
            try:
                os.remove(file_path)
            except OSError:
                pass
            continue

        hb = _num(info.get("heartbeat"))
        pid = info.get("pid")
        alive = is_pid_alive(pid, info.get("pid_start"))
        # Dual-tier pruning:
        # 1. Dead process -> prune immediately (0s delay)
        # 2. Alive process -> allow up to 600s before stale (handles long builds/tests)
        # 3. Unknown PID -> fallback to stale_s (180s)
        is_stale = False
        if pid and not alive:
            is_stale = True
        elif pid and alive:
            is_stale = (now - hb > 600.0)
        else:
            is_stale = (now - hb > stale_s)

        if is_stale:
            if not (pid and alive):   # a live pid with a silent heartbeat (idle at its prompt, one long tool call) is out of the LIST only: its
                try:                  # entry stays, it is what tells worktree_merge_gate the session is alive (R1 review 14/10: the file was deleted
                    os.remove(file_path)   # here and the next Stop adopted - merged and removed - that session's worktree)
                except OSError:
                    pass
            continue
        if info.get("status") == "idle":
            continue   # finished its turn, waiting for the user (Notification idle_prompt): not a working sibling

        # Another linked worktree of the same repo has its own tree, build dir and gate receipt: its
        # session is not a sibling of this checkout (the registry is shared through the git common dir).
        info_cwd = info.get("cwd")
        if info.get("gitdir") and my_gitdir:
            # Exact: each worktree has its own git dir (also for one nested inside this checkout).
            reg_gdir, my_gdir = os.path.realpath(info["gitdir"]), os.path.realpath(my_gitdir)
            if reg_gdir != my_gdir and not _same_dir(reg_gdir, my_gdir):   # APFS: one git dir, two spellings
                continue
        elif top and info_cwd:
            # Older record without a git dir: compare by path.
            if not _inside(info_cwd, top):
                continue

        sid = info.get("session_id")
        active.append(info)
        if current_sid and sid != current_sid:
            other.append(info)
        elif not current_sid:
            if pid not in (os.getpid(), os.getppid(), holder_pid()):
                other.append(info)

    return active, other, len(other) == 0


def check_last_active(argv):
    """`--check-last-active [--session ID] [--json] [dir]`
    Exit 0 if this session is the only/last active session.
    Exit 1 if other sessions are active."""
    sid = ""
    is_json = False
    if "--session" in argv:
        i = argv.index("--session")
        sid = argv[i + 1] if i + 1 < len(argv) else ""
        argv = argv[:i] + argv[i + 2:]
    if "--json" in argv:
        is_json = True
        argv = [a for a in argv if a != "--json"]
    target = argv[0] if argv else os.getcwd()
    active, other, is_last = get_active_sessions(cwd=target, current_sid=sid)
    if is_json:
        print(json.dumps({
            "is_last_active": is_last,
            "session_id": sid,
            "active_count": len(active),
            "other_count": len(other),
            "other_sessions": [s.get("session_id") for s in other]
        }))
    else:
        if is_last:
            print(f"session_lock: phiên {sid[:12] if sid else 'hiện tại'} là phiên cuối cùng/duy nhất đang hoạt động.")
        else:
            other_ids = ", ".join(str(s.get("session_id", "?"))[:12] for s in other)
            print(f"session_lock: phát hiện {len(other)} phiên khác đang hoạt động ({other_ids}).")
    return 0 if is_last else 1


def spawn_scratch_cleanup(*args):
    """Detached scripts/governance/scratch_cleanup.py (user 2026-10-09: 33 GB of Claude Code temp dirs, disk 99 % full): the
    session hooks never wait for a large rmtree. DEVKIT_SCRATCH_CLEANUP=0 turns it off."""
    if os.environ.get("DEVKIT_SCRATCH_CLEANUP") == "0":
        return
    script = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "governance", "scratch_cleanup.py")
    if not os.path.isfile(script):
        return
    import subprocess  # noqa: PLC0415 - SessionStart / SessionEnd only
    try:
        subprocess.Popen([sys.executable, "-I", script, *args], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
    except OSError as e:
        print(f"session_lock: scratch cleanup not started: {e}", file=sys.stderr)


def log(gdir, line):
    try:
        with open(os.path.join(gdir, LOG), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + line + "\n")
    except OSError as e:
        print(f"session_lock: không ghi được nhật ký: {e}", file=sys.stderr)


def stale_after():
    try:
        return float(os.environ.get("DEVKIT_SESSION_LOCK_STALE_S", "600"))
    except ValueError:
        return 600.0


def is_free_for(lock, sid, now, idle_frees=True, live_pid_holds=False):
    """True when `sid` may hold the checkout: no lock, its own lock, an idle holder, a dead process, or a stale one.
    idle_frees=False: an idle holder still counts as present (it is alive and may come back) — for callers that would
    otherwise act ON that session's tree (worktree_merge_gate merging or removing it), not just write next to it.
    live_pid_holds: those callers only - a holder whose pid answers is present whatever its heartbeat says (idle at its prompt or inside
    one long tool call keeps none): merging and removing its worktree on a 10-minute-old heartbeat took it from under a live session."""
    if not lock or not lock.get("session_id"):
        return True
    if lock.get("session_id") == sid:
        return True
    if idle_frees and lock.get("idle_since"):
        return True   # the holder finished its turn and waits for the user (Notification idle_prompt)
    lock_pid = lock.get("pid")
    if lock_pid and not is_pid_alive(lock_pid, lock.get("pid_start")):
        return True
    if live_pid_holds and lock_pid:
        return False
    return now - _num(lock.get("heartbeat")) > stale_after()   # not a number: missing, i.e. stale (D6)


def describe(lock, now):
    sid = str(lock.get("session_id", "?"))
    try:
        started = time.strftime("%H:%M", time.localtime(_num(lock.get("started"), now) or now))
    except (OverflowError, OSError, ValueError):   # a number past the platform's time range
        started = "?"
    age = int(now - _num(lock.get("heartbeat"), now))
    return f"phiên {sid[:12]} (giữ từ {started}, hoạt động cách đây {age}s)"


def is_self_grant(cmd):
    """True when a Bash command switches the user's approval (`agent-kit allow-shared`, session_lock.py --allow-shared[-off], under any wrapper
    - nice, timeout, uv run, bash -c ...) or WRITES the flag file (a redirect INTO it, `sed -i`, or touch / cp / mv / tee / an interpreter
    naming it). Judged per segment (quotes and heredoc bodies are not segments): a command that only READS (grep, cat, ls, git log, sed -n,
    awk ...) is fine, so is a commit message that talks about the switch.
    ponytail: a python one-liner that builds the file name from pieces is not recognised; upgrade to a signed flag if that is ever seen."""
    if ALLOW_FLAG not in cmd and "allow-shared" not in cmd:
        return False
    import shlex   # noqa: PLC0415 - only commands that mention the switch pay for it
    for seg in _split_segments(cmd)[::2]:
        if ALLOW_FLAG in seg and re.search(r">>?\s*\S*" + ALLOW_FLAG, seg):
            return True
        try:
            words = shlex.split(seg)
        except ValueError:
            words = seg.split()
        while words and re.match(r"^[A-Za-z_]\w*=", words[0]):
            words = words[1:]
        if not words:
            continue
        base = [os.path.basename(w) for w in words]
        w0 = base[0]
        if w0 == "sed" and ALLOW_FLAG in seg and any(w.startswith("-i") or w == "--in-place" for w in words[1:]):
            return True
        if w0 in READERS:
            continue
        if ALLOW_FLAG in seg and (w0 in WRITE_CMDS or any(b in WRITE_CMDS or b.startswith("python") for b in base)):
            return True
        if re.search(r"\bagent-kit\s+allow-shared\b|session_lock\.py\s+(?:\S+\s+)*?--allow-shared", seg):
            return True
    return False


# The USER's trunk-mode switches (W1 R7), kept from an agent like allow-shared: `agent-kit worktree trunk off`, a `git config devkit.trunkMode` that is
# not true (or unsets it), WORKTREE_TRUNK_MODE=0 set inside a command. `trunk on`, a true value and reads only tighten and stay open.
_TRUNK_TRUE = {"true", "yes", "on", "1"}   # git's spellings of true, as hooks/session_worktree.py _TRUE (tests/context_memory/test_session_lock_trunk.sh compares)
_PRINTERS = READERS - {"git", "find", "sed", "awk"}   # print their words and run nothing (find -exec, sed e, awk system() do)
_PREFIX_RUN = {"export", "env", "declare", "typeset", "readonly", "local", "sudo", "nice", "timeout", "command", "exec", "nohup", "time", "builtin"}
_CONFIG_VALUE_OPTS = {"-f", "--file", "--blob", "-t", "--type", "--default", "--comment"}   # the next word is their value, not the key
_CONFIG_READ_OPTS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "-l", "--list"}


def _config_trunk_off(args):
    """The words after `git config`: True when they unset devkit.trunkMode (or its section) or give it a value that is not a true spelling."""
    opts, pos, i = [], [], 0
    while i < len(args):
        a, i = args[i], i + 1
        if a.startswith("-") and a != "-":
            opts.append(a)
            if a in _CONFIG_VALUE_OPTS:
                i += 1
        else:
            pos.append(a)
    if pos and pos[0] in ("get", "list", "edit", "set", "unset", "remove-section", "rename-section"):   # git >= 2.46 spells the action as a word
        opts.append("--" + pos.pop(0))
    if _CONFIG_READ_OPTS & set(opts):
        return False
    if {"--remove-section", "--rename-section"} & set(opts):
        return bool(pos) and pos[0].lower() == "devkit"
    if not pos or pos[0].lower() != "devkit.trunkmode":
        return False
    if {"--unset", "--unset-all"} & set(opts):
        return True
    return len(pos) > 1 and pos[1].lower() not in _TRUNK_TRUE


def _clean(cmd):
    """cmd without the bodies of heredocs that feed data commands and without shell comments (a quote in a comment is no quote)."""
    text = _strip_heredocs(cmd)
    try:
        return _hook_module("shell_writes").strip_comments(text)
    except Exception as e:  # noqa: BLE001 - the text as it is: what the segment walk always read
        print(f"session_lock: comment scan failed: {e!r}", file=sys.stderr)
        return text


def _matching_paren(text, start):
    """Index of the `)` that closes the `(` at `start` (quotes and escapes skipped); len(text) when it never closes."""
    depth, quote, i, n = 0, None, start, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and quote != "'" and i + 1 < n:
            i += 2
            continue
        if quote:
            quote = None if c == quote else quote
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _subst_bodies(text):
    """The bodies of the `$( )`, backtick, `<( )` and `>( )` substitutions of `text`, outermost level only (callers recurse). None inside
    single quotes; `$( )` and backticks inside double quotes run, `<( )` and `>( )` only outside quotes. One that never closes runs to the end."""
    out, quote, i, n = [], None, 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and quote != "'" and i + 1 < n:
            i += 2
            continue
        if quote == "'":
            quote = None if c == "'" else quote
        elif c in "\"'":
            quote = c if quote is None else (None if quote == c else quote)
        elif c == "`":
            j = text.find("`", i + 1)
            out.append(text[i + 1:n if j < 0 else j])
            i = n if j < 0 else j
        elif text[i + 1:i + 2] == "(" and (c == "$" or (c in "<>" and quote is None)):
            j = _matching_paren(text, i + 1)
            out.append(text[i + 2:j])
            i = j
        i += 1
    return out


_STDIN_SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
_STDIN_INTERP = _Re(r"^(?:python[\d.]*|node|deno|ruby|perl|php)$")


# The options of a launcher that take a VALUE as the next word (the same table as hooks/shell_writes.py PREFIX_VALUE_OPTS; the trunk test compares them)
_LAUNCHER_VALUE_OPTS = {"nice": {"-n"}, "env": {"-u", "-C", "-S", "--chdir", "--unset", "--split-string"},
                        "timeout": {"-s", "-k", "--signal", "--kill-after"},
                        "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "--chdir"}}


def _launcher_end(words):
    """(index of the program in `words`, the command lines `env -S` hands over): past assignments, launchers (_PREFIX_RUN), their options WITH
    the value of one that takes a value (`env -u FOO`, `sudo -u root`, `nice -n 5`, `timeout -s KILL`) and timeout's duration. The value used to be
    read as the program, so `env -u FOO git config devkit.trunkMode false` went unseen (OCR2 21). An attached value (`-uFOO`, `--unset=FOO`) is
    one word and consumes nothing more."""
    k, launcher, lines = 0, "", []
    while k < len(words):
        w = words[k]
        if os.path.basename(w) in _PREFIX_RUN:
            launcher = os.path.basename(w)
        elif w.startswith("-"):
            if w in _LAUNCHER_VALUE_OPTS.get(launcher, ()) and k + 1 < len(words):
                k += 1
                if w in ("-S", "--split-string"):
                    lines.append(words[k])
            elif launcher == "env" and (w.startswith("--split-string=") or (w.startswith("-S") and not w.startswith("--"))):
                lines.append(w.split("=", 1)[1] if w.startswith("--") else w[2:])
        elif not (re.fullmatch(r"[A-Za-z_]\w*=.*", w, re.S) or not w or re.fullmatch(r"\d+(?:\.\d+)?[smhd]?", w)):
            break
        k += 1
    return k, lines


def _cmd_words(seg):
    """The words of one segment up to its first redirection, after assignments and launchers (env, sudo, nice ...) and their options."""
    import shlex   # noqa: PLC0415 - only commands with a pipe, a here-string or a heredoc get here
    try:
        words = shlex.split(seg)
    except ValueError:
        words = seg.split()
    words = [w.lstrip("({") for w in words]
    for k, w in enumerate(words):
        if re.match(r"\d*[<>&]", w):
            words = words[:k]
            break
    return words[_launcher_end(words)[0]:]


def _stdin_reader(words):
    """The program (basename) of `words` when it is a shell or an interpreter that reads its SCRIPT from stdin: no `-c` / `-e` code and no
    script file (an operand `-` or `-s` means stdin), else None."""
    if not words:
        return None
    prog = os.path.basename(words[0])
    shell = prog in _STDIN_SHELLS
    if not shell and not _STDIN_INTERP.match(prog):
        return None
    opts = [w for w in words[1:] if w.startswith("-") and w != "-"]
    operands = [w for w in words[1:] if not w.startswith("-") or w == "-"]
    if any(re.fullmatch(r"-[A-Za-z]*[ce][A-Za-z]*", o) for o in opts if not o.startswith("--")):
        return None
    return prog if not operands or operands == ["-"] or (shell and "-s" in opts) else None


def _printf_text(args):
    """What `printf FORMAT ARGS...` prints, approximately: escapes read, each %s / %b / %d replaced by the next argument (the format repeats
    while arguments are left)."""
    fmt = args[0].replace("\\n", "\n").replace("\\t", "\t") if args else ""
    rest = args[1:]
    holes = len(re.findall(r"%[-0-9.]*[sbdiq]", fmt))
    if not holes:
        return fmt + " ".join(rest)
    out = []
    for g in range(0, max(len(rest), 1), holes):
        it = iter(rest[g:g + holes])
        out.append(re.sub(r"%[-0-9.]*[sbdiq]", lambda _m: next(it, ""), fmt))
    return "".join(out)


def _stdin_scripts(cmd):
    """Scripts a shell or an interpreter reads on STDIN that neither the segment walk nor the heredoc rules see: `echo|printf '…' | sh`,
    `cat <<EOF … EOF | bash`, `bash <<< '…'`. Each comes back as the equivalent heredoc command (`bash -s <<'EOF' … EOF`), which those rules judge.
    ponytail: a producer that is not echo / printf / a cat-heredoc (`cat file | sh`, `curl … | sh`) feeds a script no scan can read; upgrade by
    refusing a pipe into a shell when its producer is unknown."""
    import shlex   # noqa: PLC0415
    out = []

    def synth(prog, body):
        out.append(f"{prog} -s <<'__DEVKIT_EOF__'\n{body}\n__DEVKIT_EOF__")
    lines, i = cmd.split("\n"), 0
    while i < len(lines):   # cat <<EOF ... EOF | bash: the body is the producer's text; `_strip_heredocs` drops it before anything else looks
        m = _HEREDOC.search(lines[i])
        i += 1
        if not m:
            continue
        j = i
        while j < len(lines) and lines[j].strip() != m.group(2):
            j += 1
        after = lines[i - 1][m.end():]
        prog = _stdin_reader(_cmd_words(re.split(r"[|;&]", after.split("|", 1)[1])[0])) if "|" in after.replace("||", "") else None
        if prog:
            synth(prog, "\n".join(lines[i:j]))
        i = j + 1
    pieces = _split_segments(_clean(cmd))
    for k in range(0, len(pieces), 2):
        hs = re.search(r"<<<\s*(\"[^\"]*\"|'[^']*'|\S+)", pieces[k])
        prog = _stdin_reader(_cmd_words(pieces[k])) if hs else None
        if prog:   # bash <<< 'cmd'
            try:
                body = shlex.split(hs.group(1))[0]
            except (ValueError, IndexError):
                body = hs.group(1)
            synth(prog, body)
        if k + 2 < len(pieces) and pieces[k + 1] == "|" and _stdin_reader(_cmd_words(pieces[k + 2])):   # echo '…' | sh, printf … | bash
            words = _cmd_words(pieces[k])
            if words and os.path.basename(words[0]) in ("echo", "printf"):
                args = [a for a in words[1:]]
                if words[0] == "echo":
                    while args and re.fullmatch(r"-[neE]+", args[0]):
                        args = args[1:]
                    synth(_stdin_reader(_cmd_words(pieces[k + 2])), " ".join(args))
                else:
                    synth(_stdin_reader(_cmd_words(pieces[k + 2])), _printf_text(args))
    return out


def _nested_scripts(cmd):
    """Every script `cmd` runs that its own segments do not show: command substitutions and the scripts fed on stdin (_stdin_scripts). One
    scan for is_trunk_off and trunk_write; each caller recurses into what this returns (three levels)."""
    return _subst_bodies(_clean(cmd)) + _stdin_scripts(cmd)


def is_trunk_off(cmd, depth=0):
    """True when a Bash command turns trunk mode off (see _TRUNK_TRUE above). Judged per segment as is_self_grant does: a quoted word is text,
    so a commit message or a grep that talks about the switch is fine; heredoc bodies fed to a shell are segments, `bash -c '...'` / eval are read.
    Substitutions ($( ), backticks, <( ), >( )) and scripts fed on stdin (echo / printf / cat-heredoc piped to a shell, a here-string) are read too
    (_nested_scripts). ponytail: a script or one-liner that builds the key or the value from pieces (python -c), and xargs / find -exec, are not
    recognised; upgrade by making the switch a file only the user's command can write (as the allow-shared flag is)."""
    if not re.search(r"trunk|-section", re.sub(r"[\"'\\]", "", cmd).lower()):   # (-section: git config --remove-section devkit)
        return False
    import shlex   # noqa: PLC0415 - only commands that mention the switch pay for it
    if depth < 3 and any(is_trunk_off(body, depth + 1) for body in _nested_scripts(cmd)):   # $( ), backticks, <( ), echo '…' | sh, bash <<< '…'
        return True
    for seg in _split_segments(_clean(cmd))[::2]:
        try:
            words = shlex.split(seg)
        except ValueError:
            words = seg.split()
        if words:
            words[0] = words[0].lstrip("({")
        k, lines = _launcher_end(words)   # what wraps the program (assignments, export / env / sudo ... and their options) comes first
        for w in words[:k]:
            m = re.fullmatch(r"WORKTREE_TRUNK_MODE=(.*)", w, re.S)
            if m and (m.group(1) == "0" or "$" in m.group(1) or "`" in m.group(1)):
                return True
        if depth < 3 and any(is_trunk_off(line, depth + 1) for line in lines):   # env -S 'git config ...': its value is a command line
            return True
        words = words[k:]
        if not words:
            continue
        base = [os.path.basename(w) for w in words]
        if base[0] in _PRINTERS:
            continue
        for j, w in enumerate(base):   # agent-kit worktree trunk off, worktree.py trunk off, under any launcher
            if w in ("worktree", "worktree.py", "wt") and [a for a in words[j + 1:] if not a.startswith("-")][:2] == ["trunk", "off"]:
                return True
        if base[0] == "git":
            j = 1
            while j < len(words) and words[j].startswith("-"):   # git's own options; some take the next word as their value
                j += 2 if words[j] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") else 1
            if j < len(words) and words[j] == "config" and _config_trunk_off(words[j + 1:]):
                return True
        elif depth < 3 and base[0] in ("bash", "sh", "zsh", "dash", "ksh"):
            for j in range(1, len(words) - 1):
                if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", words[j]) and is_trunk_off(words[j + 1], depth + 1):
                    return True
        elif depth < 3 and base[0] == "eval" and is_trunk_off(" ".join(words[1:]), depth + 1):
            return True
    return False


_SETTINGS_FILE = _Re(r"settings[\w.-]*\.json")
_SETTINGS_PATH = _Re(r"(?:^|/)settings[\w.-]*\.json$")
_TRUNK_ENV = _Re(r"WORKTREE_TRUNK_MODE\W{0,12}(?P<v>\w*)")   # JSON `"WORKTREE_TRUNK_MODE": "0"`, shell `WORKTREE_TRUNK_MODE=0`, python `['WORKTREE_TRUNK_MODE']='0'`
_PURE_READERS = frozenset(("grep", "egrep", "fgrep", "rg", "ag", "cat", "bat", "less", "more", "head", "tail", "wc", "nl", "file", "stat", "ls", "diff", "cmp", "jq"))


def _read_text(path, limit=1_000_000):
    """A regular file's text, read without ever blocking (the path is the agent's to plant a FIFO at: this runs in a PreToolUse hook); a symlinked
    dotfile is followed. None when it cannot be read."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
    except (OSError, ValueError):
        return None
    try:
        return os.read(fd, limit).decode("utf-8", "replace") if stat.S_ISREG(os.fstat(fd).st_mode) else None
    except OSError:
        return None
    finally:
        os.close(fd)


def _edited(text, ti):
    """`text` after the Edit / MultiEdit of `ti` is applied (the first occurrence, every one with replace_all); None when an old_string is not in it
    - the tool refuses that edit, so there is no result to judge."""
    for e in [ti] if "old_string" in ti else [e for e in ti.get("edits") or [] if isinstance(e, dict)]:
        old, new = e.get("old_string"), e.get("new_string")
        if not (isinstance(old, str) and isinstance(new, str) and old and old in text):
            return None
        text = text.replace(old, new) if e.get("replace_all") else text.replace(old, new, 1)
    return text


_SED_SUBST = _Re(r"s(?P<d>[^\w\s\\])(?P<pat>.*?)(?P=d)(?P<rep>.*?)(?P=d)")


def _sed_one_to_zero(command):
    """True when a segment of `command` is a `sed -i` on a settings file with a substitution that turns a lone 1 into 0 (`s/"1"/"0"/`,
    `s/MODE": "1"/MODE": "0"/`, `s/1/0/`): the value-only edit of WORKTREE_TRUNK_MODE that names no key. A bounded parse: one `s` word each."""
    for seg in _split_segments(_clean(command))[::2]:
        words = _cmd_words(seg)
        if not (words and os.path.basename(words[0]) == "sed" and any(w.startswith("-i") or w == "--in-place" for w in words[1:])):
            continue
        if not any(_SETTINGS_FILE.search(w) and not re.search(r"\s", w) for w in words[1:]):
            continue
        for w in words[1:]:
            m = _SED_SUBST.match(w)
            if m and re.search(r"(?:^|\W)1\W*$", m.group("pat")) and re.search(r"(?:^|\W)0\W*$", m.group("rep")):
                return True
    return False


def trunk_env_in_settings(tool, tool_input, command):
    """True when a tool call writes WORKTREE_TRUNK_MODE (anything but 1) into a Claude settings file (settings.json, settings.local.json, any
    folder): that file's `env` block is the environment of the hooks of the next session - MEASURED 14/10 with `claude -p` (Claude Code 2.1.299,
    a project .claude/settings.local.json `env` reached a hook as printenv shows it) - so this is the user's switch (R7) by another door, and
    settings.local.json is git-ignored, so no other rule looks at it (principal review R4a). Edit / Write / MultiEdit: the text written into a
    settings file; Bash: the key with a value that is not 1 in a command that redirects into, or runs a program other than a pure reader on, a
    settings file named as a word (a commit message or a grep that talks about it is no write).
    ponytail: a tripwire against an agent flipping the switch by accident or with a plain command, not a lock - a Bash value-only edit other than
    `sed -i`, a two-step copy (write the file elsewhere, then cp / mv it over a settings file) and a name built from pieces are not seen, and
    each review round found one more variant; upgrade: deny agent writes to settings*.json while trunk mode is on."""
    def off(text):
        return any(m.group("v") != "1" for m in _TRUNK_ENV.finditer(text))
    if tool in EDIT_TOOLS:
        ti = tool_input if isinstance(tool_input, dict) else {}
        path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
        if not (isinstance(path, str) and _SETTINGS_PATH.search(path)):
            return False
        texts = [ti.get("content"), ti.get("new_string"), ti.get("new_source")] + [e.get("new_string") for e in ti.get("edits") or [] if isinstance(e, dict)]
        if any(isinstance(t, str) and off(t) for t in texts):
            return True
        if tool in ("Edit", "MultiEdit"):   # a value-only edit (`"1"` -> `"0"`) names no key: judge the file as it becomes (OCR2 8)
            cur = _read_text(path)
            after = _edited(cur, ti) if cur is not None and not off(cur) else None
            return after is not None and off(after)
        return False
    if tool == "Bash" and _SETTINGS_FILE.search(command) and _sed_one_to_zero(command):
        return True
    if tool != "Bash" or "WORKTREE_TRUNK_MODE" not in command or not _SETTINGS_FILE.search(command) or not off(command):
        return False
    if any(t and _SETTINGS_FILE.search(t) for t in _redirect_targets(command)):
        return True
    import shlex   # noqa: PLC0415 - only a command that names the key and a settings file pays for it
    for seg in _split_segments(_clean(command))[::2]:
        try:
            raw = shlex.split(seg)
        except ValueError:
            raw = seg.split()
        if any(_SETTINGS_FILE.search(w) and not re.search(r"\s", w) for w in raw):
            words = _cmd_words(seg)
            base = os.path.basename(words[0]) if words else ""
            if not words or not (base in _PURE_READERS or (base in ("sed", "awk") and not any(w.startswith("-i") or w == "--in-place" for w in words[1:]))):
                return True
    return False


def _unquote(word):
    return word[1:-1] if len(word) >= 2 and word[0] in "\"'" and word[-1] == word[0] else word


def _same_dir(a, b):
    """The same directory by inode (see _inside), False when either is gone."""
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def _inside(path, root):
    """True when `path` is `root` or lies below it. realpath keeps the letter case it was given and a case-insensitive filesystem
    (APFS) spells one directory two ways ("Repo" / "repo"), so a string prefix is not enough: when it fails, `root`'s inode is
    looked for among `path` and its parents (a path that does not exist yet is judged by its nearest existing parent)."""
    r, p = os.path.realpath(root), os.path.realpath(path)
    if p == r or p.startswith(r + os.sep):
        return True
    try:
        rst = os.stat(r)
    except OSError:
        return False
    while True:
        try:
            st = os.stat(p)
            if (st.st_dev, st.st_ino) == (rst.st_dev, rst.st_ino):
                return True
        except OSError:
            pass   # not there (yet): its parent decides
        up = os.path.dirname(p)
        if up == p:
            return False
        p = up


def _target(path):
    """(real toplevel, git dir) of the checkout that holds `path`; (None, None) when that cannot be told (no such directory, not a
    repository, an unexpanded $VAR / ~ / backtick, git timing out)."""
    if not path or "$" in path or "`" in path or path.startswith("~") or not os.path.isdir(path):
        return None, None
    gdir, top = git_dir(path)
    if not gdir or not top:
        return None, None
    return os.path.realpath(top), gdir


def _resolve(base, word):
    """A cd / -C argument as an absolute path from `base` (None when base is unknown)."""
    word = _unquote(word)
    if os.path.isabs(word):
        return word
    return os.path.join(base, word) if base else None


def _git_target(cur, opts):
    """The directory a git command acts on: `cur` moved by each `-C <dir>` in order; None (unknown) with --git-dir / --work-tree."""
    if re.search(r"--(?:git-dir|work-tree)", opts):
        return None
    for d in re.findall(r"-C\s+(\"[^\"]*\"|'[^']*'|\S+)", opts):
        cur = _resolve(cur, d)
    return cur


def write_hits_locked(cmd, top, cwd, sid=""):
    """(hits_top, foreign): hits_top - a git write / gate run in `cmd` can land in the locked checkout `top`, or its target cannot be told
    (fail closed); foreign - (toplevel, git dir, lock) of ANOTHER checkout the command writes to that ANOTHER live session holds (it
    counts even when the session's own checkout is free). The command is walked segment by segment (&&, ||, ;, |, &, newline; not
    inside quotes): a segment that is only `cd <dir>` moves the working directory for the segments after it, but only when it runs in
    the same shell (followed by && ; or a newline); a cd that may not have run (before | & ||) and any directory change the walk cannot
    follow (DIR_CHANGE) make the directory unknown; each write is judged by the toplevel of its `git -C <dir>` / `CLAUDE_PROJECT_DIR=<dir>`
    / working directory."""
    locked = os.path.realpath(top) if top else None
    cur = cwd or top
    pieces = _split_segments(cmd)   # segment, separator, segment, ...
    seen, hits_top, foreign, named = False, False, None, False
    for i in range(0, len(pieces), 2):
        seg = pieces[i]
        sep = pieces[i + 1] if i + 1 < len(pieces) else ""
        cd = CD_ONLY.match(seg)
        if cd:
            cur = _resolve(cur, cd.group(1)) if sep in ("&&", ";", "\n", "") else None
            continue
        if DIR_CHANGE.search(seg):
            cur = None
        named = named or bool(GIT_WRITE.search(seg) or GATE.search(seg))
        targets = [_git_target(cur, m.group("opts")) for m in GIT_WRITE.finditer(seg)]
        if _gate_run(seg):
            pd = PROJECT_DIR.search(seg)
            targets.append(_resolve(cur, pd.group(1)) if pd else cur)
        for target in targets:
            seen = True
            tl, tgdir = _target(target)
            if tl is None or tl == locked or _same_dir(tl, locked):
                hits_top = True
                continue
            lock = read_checkout_lock(tgdir)
            if foreign is None and not is_free_for(lock, sid, time.time()):
                foreign = (tl, tgdir, lock)   # another repository, but a live session holds THAT one
    # the regexes see a write the segment walk did not (e.g. an unterminated quote): judge it by the text, as before. Not when a segment
    # showed it and was judged a read there (`cd X && grep … the gate's name`: the whole line starts with `cd`, no reader, 14/10).
    if not seen and not named:
        stripped = _strip_heredocs(cmd)
        hits_top = bool(GIT_WRITE.search(stripped) or _gate_run(stripped))
    return hits_top, foreign


def edit_hits_locked(tool_input, top, cwd, gdir=None):
    """Edit / Write / MultiEdit / NotebookEdit collide only for a file inside the locked checkout or its git dir (a linked worktree's
    lies OUTSIDE it); no path at all fails closed."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
    if not path or not top or not isinstance(path, str):
        return True
    real = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd or top, path))
    return any(_inside(real, root) for root in (top, gdir) if root)


def allow_shared_until(gdir):
    """Epoch until which the USER allowed a second live session to write here (0 when never / expired / unreadable)."""
    d = read_lock(os.path.join(gdir, ALLOW_FLAG))
    try:
        return float((d or {}).get("until") or 0)
    except (TypeError, ValueError):
        return 0.0


def allow_shared(argv, off=False):
    """`--allow-shared [--minutes N] [dir]` / `--allow-shared-off [dir]`: run by the USER (`! agent-kit allow-shared`), never by an
    agent (main() blocks an agent's Bash call that does). Lets any live session write in the checkout for N minutes
    (default 60, 1..480) without restarting it; the hook reads the flag on every call and logs each use."""
    minutes = 60
    if "--minutes" in argv:
        i = argv.index("--minutes")
        try:
            minutes = int(argv[i + 1])
        except (ValueError, IndexError):
            print("session_lock: --minutes needs a whole number (1..480)")
            return 2
        argv = argv[:i] + argv[i + 2:]
    minutes = max(1, min(480, minutes))
    target = argv[0] if argv else os.getcwd()
    gdir, top = git_dir(target)
    if not gdir:
        print(f"session_lock: {target} không phải git checkout")
        return 1
    path = os.path.join(gdir, ALLOW_FLAG)
    if off:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        except OSError as e:
            print(f"session_lock: không gỡ được {path}: {e}")
            return 1
        log(gdir, "người dùng tắt cho phép ghi song song")
        print(f"session_lock: đã tắt cho phép ghi song song ở {top}")
        return 0
    now = time.time()
    write_lock(path, {"until": now + minutes * 60, "granted": now, "by": "user"})
    until = time.strftime("%H:%M", time.localtime(now + minutes * 60))
    log(gdir, f"người dùng cho phép ghi song song {minutes} phút (tới {until})")
    print(f"session_lock: {top} cho phép phiên khác ghi song song {minutes} phút (tới {until}). Tắt sớm: agent-kit allow-shared off")
    return 0


def _file_write_hits(cmd, top, cwd):
    """A file write of `cmd` lands in the locked checkout `top`: cp / install / rsync / ln destinations, mv / rm / touch / truncate /
    tee / mkdir / rmdir / chmod / unlink operands, dd of=, sed -i / perl -i files, also inside `bash -c` (hooks/shell_writes.py, the
    scanner hooks/worktree_guard.sh uses: issues-bugs.md A.1 #3, 13/10 11:03 a cp/mv into a held checkout went through). Not judged
    here: a target behind $VAR or a backtick, an interpreter's or build tool's own writes (a read-only session runs `python3 x.py`).
    ponytail: those stay open, and so do `xargs rm`, `find -delete`, `eval '…'`, a backtick, a heredoc fed to a shell and a cd inside a
    subshell (review 14/10); tighten when one is seen landing. Scanner missing or line untokenisable: False (the other rules hold)."""
    try:
        found = _hook_module("shell_writes").targets(cmd, cwd or top)
    except Exception as e:   # the git / gate / redirect rules still apply; say why this one could not
        print(f"session_lock: file-write scan failed: {e!r}", file=sys.stderr)
        return False
    for kind, t, here in found or ():
        if kind != "file" or "$" in t or "`" in t:
            continue
        p = os.path.expanduser(t)
        try:
            if _inside(os.path.realpath(p if os.path.isabs(p) else os.path.join(here or cwd or top, p)), top):
                return True
        except ValueError as e:   # a NUL in the path: no file can have it, and the hook must not crash (exit 1 lets the call through)
            print(f"session_lock: target {t!r} skipped: {e}", file=sys.stderr)
    return False


def _hook_module(name):
    """A module of this file's own kit hooks/ (shell_writes, session_worktree), imported after the stdlib on the path."""
    hooks = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "hooks")
    if hooks not in sys.path:
        sys.path.append(hooks)
    return __import__(name)


# ── W1 R1/R2 v6: trunk mode (docs/workflow-improvements.md I.0; hooks/session_worktree.py) ─────────────────────────────────────────
# ON by default (a repo with no `devkit.trunkMode` key; `agent-kit worktree trunk off` or WORKTREE_TRUNK_MODE=0 turn it off): the main checkout is merge-only, nobody holds it, every session works in its own worktree.
TRUNK_STATUS_EXIT = 5   # `--status` on a trunk-mode main checkout (Antigravity and other agents without hooks read the code)
# What may still run against a trunk-mode main checkout: the integrator (agent-kit worktree …, worktree.py …) and syncing main with origin
# (fetch, push, a pull that only fast-forwards). The gate is not among them: it writes the tracked checklist there (v6 item 7).
_TRUNK_ALLOWED = _Re(r"^\s*(?:\S*/)?agent-kit\s+(?:worktree|wt)\s|^\s*(?:python3?\s+(?:-I\s+)?)?\S*worktree\.py\s")
_LOCAL_REMOTE = _Re(r"^(?:\.{1,2}(?:/|$)|/|~|file:)")   # a remote that is a path: `git fetch . x:main`, `git pull . branch` move THIS repo's refs


def _git_verb(seg):
    """(verb, its words) of a segment that is `git [options] <verb> ...`, else (None, [])."""
    import shlex   # noqa: PLC0415 - only a segment that names git pays for it
    try:
        words = shlex.split(seg)
    except ValueError:
        return None, []
    if not words or os.path.basename(words[0]) != "git":
        return None, []
    i = 1
    while i < len(words) and words[i].startswith("-"):   # git's own options; some take the next word as their value
        i += 2 if words[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") else 1
    return (words[i], words[i + 1:]) if i < len(words) else (None, [])


def _updates_checked_out_branch(seg):
    """`git fetch [-u | --update-head-ok] ...` (also through pull): the only way git lets a fetch move the branch a checkout stands on - main's own,
    from any worktree: `git fetch . HEAD:main -u` moved main past the integrator's gate (OCR 9, 14/10). Without the flag git refuses."""
    verb, args = _git_verb(seg)
    return verb in ("fetch", "pull") and any(a == "--update-head-ok" or a.startswith("--update-head-ok=") or re.fullmatch(r"-[A-Za-z]*u[A-Za-z]*", a)
                                              for a in args)


def _trunk_sync(seg):
    """The segment only syncs with a REMOTE, which main may still do: `git [-C dir] fetch|push ...` whose remote is no local path, and `git pull
    --ff-only` with no remote or `origin` and no refspec that names a local ref (`pull --ff-only . branch` fast-forwards main onto any local
    branch, past the integrator's gate; OCR 9, 14/10). ponytail: a remote CONFIGURED to a local path (`remote.origin.url = .`) is not looked up."""
    verb, args = _git_verb(seg)
    pos = [a for a in args if not a.startswith("-")]
    if verb not in ("fetch", "push", "pull") or _updates_checked_out_branch(seg) or (pos and _LOCAL_REMOTE.match(pos[0])):
        return False
    return verb != "pull" or ("--ff-only" in args and pos[:1] in ([], ["origin"]) and not any(":" in a for a in pos[1:]))


_TRUNK_WRAP = _Re(r"^\s*(?:nohup|time(?:\s+-p)?)\s+")
_TRUNK_REDIR = _Re(r"\d*>>?|&>>?|\d*>>?\S+|&>>?\S+|\d*>&\d+")


def _trunk_unwrap(seg):
    """Lệnh bên trong của `nohup …`, `time [-p] …` và `bash|sh|zsh -c '<một lệnh>'` (tối đa 3 lớp), để _TRUNK_ALLOWED / _trunk_sync /
    _updates_checked_out_branch xét nó theo đúng luật cũ (17/10, GeelyEx2 + Goods: `nohup agent-kit worktree finish … &` để chạy nền một lần
    finish 5–10 phút bị chặn). Không gỡ được thì trả nguyên segment: kịch bản `-c` nhiều lệnh, có substitution ($( ), backtick, <( ), >( ) — trong
    nháy đơn _subst_bodies không thấy), heredoc, hay chữ nào sau kịch bản không phải redirect. Redirect của lớp bọc vẫn được quét trên dòng gốc."""
    import shlex   # noqa: PLC0415
    for _ in range(3):
        m = _TRUNK_WRAP.match(seg)
        if m:
            seg = seg[m.end():]
            continue
        try:
            words = shlex.split(seg)
        except ValueError:
            return seg
        if len(words) < 3 or os.path.basename(words[0]) not in ("bash", "sh", "zsh") or words[1] != "-c":
            return seg
        rest, k = words[3:], 0
        while k < len(rest):   # sau kịch bản chỉ được là redirect (`> /tmp/x.log 2>&1`)
            if not _TRUNK_REDIR.fullmatch(rest[k]):
                return seg
            k += 2 if re.fullmatch(r"\d*>>?|&>>?", rest[k]) else 1
        body = words[2]
        if "$(" in body or "`" in body or "<(" in body or ">(" in body or "<<" in body or len(_split_segments(_clean(body))) != 1:
            return seg
        seg = body
    return seg
TRUNK_MSG = ("⛔ [DevKit] Trunk mode: main checkout {main} chỉ để GỘP — không phiên nào sửa ở đây (người dùng 14/10: mọi phiên làm trong "
             "worktree riêng, không ai giữ main). Gọi tool EnterWorktree (không tham số, hoặc name=<việc>): phiên có worktree riêng dưới "
             ".claude/worktrees/, DevKit tự dựng (chép cấu hình, cài DevKit); sửa, test, commit ở đó; hook Stop tự gộp vào main. Agent không "
             "có EnterWorktree (Antigravity, script): `agent-kit worktree add ../<repo>-<việc>`, xong `agent-kit worktree finish <đường dẫn>`. "
             "Ở main chỉ được: `agent-kit worktree …`, `git fetch`, `git push`, `git pull --ff-only`, và state bị git ignore (memory, "
             ".claude/audit-gate). Đích là biến ($X) thì không biết nó ở đâu: dùng đường dẫn thật. Tắt cho mọi repo: WORKTREE_TRUNK_MODE=0 "
             "(công tắc của người dùng).")


def info_alive(info, now=None):
    """A registry entry names a live session: its pid answers - a session idle at its prompt or inside one long tool call keeps no fresh
    heartbeat and is alive all the same, so adopting its worktree (merge, remove) on a heartbeat would take it from under a live session.
    No pid recorded: the heartbeat, 180 s. For the gate's legacy owner checks (session_alive); trunk adoption and reown use owner_gone."""
    if not info:
        return False
    pid = info.get("pid")
    if pid:
        return is_pid_alive(pid, info.get("pid_start"))
    return (time.time() if now is None else now) - _num(info.get("heartbeat")) <= 180.0


RECORD_NO_PID_TAKEOVER_S = 24 * 3600.0   # a worktree record with no pid anywhere is taken over only when it is this old


def owner_gone(cwd, osid, sw, main):
    """(dead, why): True only on a POSITIVE death signal of session `osid`, the owner of a worktree record - the one test for taking that
    worktree over (hooks/worktree_merge_gate.sh adoption: merge, then remove) or its record (reown). Anything unknown reads as ALIVE
    (why "alive" | "unknown"): the old default - unknown is dead - moved the debt to whoever asked, but adoption destroys a worktree.
    Pids known: the one in the session's record (the claude process the EnterWorktree hook ran under) and the one of its registry entry;
    dead when every one of them is gone. SessionEnd deletes the registry entry, so a gone session has none, and a live one whose
    registration failed (or that started before this kit) never had one: the record's pid is what tells them apart. The registry
    heartbeat decides nothing - a session idle at its prompt or inside one long tool call keeps none. No pid anywhere: a record older than
    24 h (`sw` = hooks/session_worktree.py, `main` = the main checkout).
    A pid the OS has reused reads gone when its recorded start time differs (#413); one with no start time recorded, or one that cannot be read
    now, reads alive (fails closed)."""
    if not osid or os.sep in osid:
        return False, "unknown"
    ok = lambda v: isinstance(v, int) and not isinstance(v, bool) and v > 1   # noqa: E731 - a pid, not a flag or a bogus number
    reg = read_session(cwd, osid) or {}
    # (pid, alive?) per source: the registry's pid_start is raw (is_pid_alive), the record's start token has no blank (sw.lock_pid_alive);
    # a live pid whose start time differs was reused by the OS = the session is gone (#413). No start time recorded: the pid alone, as before.
    seen = [(p, alive) for p, alive in ((sw.raw_pid(main, osid), lambda p: sw.lock_pid_alive(p, sw.raw_pid_start(main, osid))),
                                         (reg.get("pid"), lambda p: is_pid_alive(p, reg.get("pid_start")))) if ok(p)]
    if seen:
        return (False, "alive") if any(alive(p) for p, alive in seen) else (True, "pid gone")
    age = sw.record_age(main, osid)
    return (True, "old record, no pid") if age is not None and age > RECORD_NO_PID_TAKEOVER_S else (False, "unknown")


def trunk_main(top):
    """(main checkout, session_worktree module) when the repo holding `top` runs in trunk mode; (None, module or None) otherwise - also
    when hooks/session_worktree.py cannot be imported (the old rules then, said on stderr)."""
    try:
        sw = _hook_module("session_worktree")
    except Exception as e:  # noqa: BLE001 - an unreadable module must not turn the lock off; the old rules hold
        print(f"session_lock: trunk mode unknown ({e!r}): the old rules apply", file=sys.stderr)
        return None, None
    main = sw.main_of(top) if top else None
    return (main, sw) if main and sw.trunk_mode(main) else (None, sw)


def _lands_in_main(path, main, sw):
    """`path` is content of the main checkout ITSELF: inside it, no other checkout in between (a session worktree under .claude/worktrees/,
    a submodule), and not ignored by git (agent memory, .claude/audit-gate and other local state are no merge-only content). A path with a
    NUL (no file can have it) is no write: ValueError -> False."""
    try:
        if not _inside(path, main):
            return False
        t = sw.tree_of(path)
    except ValueError:
        return False
    if t is not None and not _same_dir(t[0], main):
        return False
    import subprocess  # noqa: PLC0415 - only for a write into a trunk-mode main checkout
    try:
        r = subprocess.run(["git", "-C", main, "check-ignore", "-q", "--", os.path.realpath(path)], capture_output=True, timeout=5)
    except (OSError, ValueError, subprocess.SubprocessError):
        return True   # cannot tell: merge-only
    return r.returncode != 0   # 0: git ignores it (and does not track it)


def trunk_write(tool, tool_input, cmd, cwd, main, sw, sid=""):
    """W1 R1 v6: this call writes into the trunk-mode main checkout `main` itself. Edit/Write: its file. Bash, after dropping the segments
    _TRUNK_ALLOWED lets through (a `cd` before them still counts): a git write or gate run aimed at main (write_hits_locked: by the toplevel
    of its target; one that cannot be told counts), or a redirect / file write (hooks/shell_writes.py, cd-aware) landing in it. Builds and
    interpreters run in main are no writes here (their output is ignored build state). A line the scanner cannot tokenise: its redirects
    are read without cd tracking."""
    if tool in EDIT_TOOLS:
        ti = tool_input if isinstance(tool_input, dict) else {}
        path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
        if not isinstance(path, str) or not path:
            return True
        return _lands_in_main(path if os.path.isabs(path) else os.path.join(cwd or main, path), main, sw)
    return _bash_trunk_write(cmd, cwd, main, sw, sid, 0)


_VAR_ASSIGN = re.compile(r"""(?:^|[;&|\n(]|\bexport\s+)\s*([A-Za-z_][A-Za-z0-9_]*)(\+?)=("[^"$`]*"|'[^']*'|[^\s;&|$`"'()]*)""")
_VAR_USE = re.compile(r"\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})")


def _expand_static_vars(target, cmd):
    """`target` with every $VAR / ${VAR} replaced by the literal value `cmd` itself assigns (`VAR=/path`, `export VAR=/path`); None when it
    still holds a variable the line does not assign, a $( ) or a backtick - where such a path lands cannot be told. The last assignment wins."""
    values = {}
    for m in _VAR_ASSIGN.finditer(cmd):
        # `B=$M`, `B="$M"`, `B=$M/x`: the value pattern stops at the `$` and matches "" - the variable is unknown, not empty
        # `M+=/x` appends to the old value: also unknown, never the old value (reviewer R1)
        if m.group(2) or (m.end() < len(cmd) and cmd[m.end()] not in " \t\r\n;&|()"):
            values.pop(m.group(1), None)
        else:
            values[m.group(1)] = m.group(3).strip("\"'")
    unknown = False

    def sub(m):
        nonlocal unknown
        name = m.group(1) or m.group(2)
        if name not in values:
            unknown = True
        return values.get(name, "")

    out = _VAR_USE.sub(sub, target)
    return None if unknown or "$" in out or "`" in out else out


def _bash_trunk_write(cmd, cwd, main, sw, sid, depth):
    """trunk_write for one Bash script: what its segments write, then - three levels deep - the scripts it hides from them (_nested_scripts:
    substitutions, echo / printf / cat-heredoc piped to a shell or interpreter, a here-string). A script that cannot be tokenised counts as a
    write where it runs (hooks/shell_writes.py "unparsed"); after a cd the nested scripts run where that cd led, which is unknown: main's rules."""
    # An allowed segment is excused only as a git write / gate run: its own redirects still count (OCR 14/10: `git fetch > src/a.py`,
    # `agent-kit worktree list > README.md` overwrote tracked files of main), so the redirect / file-write scan reads the ORIGINAL line
    pieces = _split_segments(_clean(cmd))
    inner = [_trunk_unwrap(p) if i % 2 == 0 else p for i, p in enumerate(pieces)]   # nohup / time / bash -c '<một lệnh>' gỡ ra (17/10)
    if any(i % 2 == 0 and _updates_checked_out_branch(p) for i, p in enumerate(inner)):
        return True
    stripped = "".join(":" if i % 2 == 0 and (_TRUNK_ALLOWED.search(q) or _trunk_sync(q)) else p for i, (p, q) in enumerate(zip(pieces, inner)))
    if (GIT_WRITE.search(stripped) or GATE.search(stripped)) and write_hits_locked(stripped, main, cwd, sid)[0]:
        return True
    here = cwd or main
    try:
        found = _hook_module("shell_writes").targets(cmd, here, run_bodies=True)
    except Exception as e:  # noqa: BLE001 - the redirect rule below still applies
        print(f"session_lock: write scan failed: {e!r}", file=sys.stderr)
        found = None
    if found is None:
        found = [("redirect", t, here) for t in _redirect_targets(cmd) if t and not t.startswith("&")]
    cd_unsafe = False   # a `cd "$VAR"` that leads into main or cannot be told: relative targets of the line may land there
    for kind, t, wd in found:
        if kind == "cdvar":
            d = _expand_static_vars(t, cmd)
            cd_unsafe = cd_unsafe or d is None or _lands_in_main(os.path.expanduser(d) if os.path.isabs(os.path.expanduser(d)) else os.path.join(wd or here, d), main, sw)
            continue
        if kind == "unparsed":
            if _lands_in_main(wd or here, main, sw):
                return True
            continue
        if kind not in ("redirect", "file"):
            continue
        if "$" in t or "`" in t:
            t = _expand_static_vars(t, cmd)
            if t is None:   # a variable the line does not assign, or a substitution: where it lands cannot be told - fail closed (issue #13)
                return True
        p = os.path.expanduser(t)
        if not os.path.isabs(p) and cd_unsafe:
            return True
        if _lands_in_main(p if os.path.isabs(p) else os.path.join(wd or here, p), main, sw):
            return True
    if depth < 3:
        moved = bool(DIR_CHANGE.search(_clean(cmd)))
        for body in _nested_scripts(cmd):
            if _bash_trunk_write(body, None if moved else cwd, main, sw, sid, depth + 1):
                return True
    return False


def bash_collides(cmd, top, cwd=None, sid=""):
    """(hits_top, foreign) - see write_hits_locked; a redirect or a file write (_file_write_hits) into the locked checkout also counts
    as hits_top."""
    hits_top, foreign = False, None
    if GIT_WRITE.search(cmd) or GATE.search(cmd):
        hits_top, foreign = write_hits_locked(cmd, top, cwd, sid)
    if not hits_top and ">" in cmd:
        for target in _redirect_targets(cmd):
            if not target or target.startswith("&"):
                continue
            # An absolute target collides only inside the checkout - also one that lives under /tmp (a temp-dir prefix used to be
            # skipped first, and a quoted path into such a checkout passed once quotes were read, 2026-10-09); outside it (/dev/null,
            # a temp dir, another directory) it never does. A relative one, $VAR or ~ lands here or cannot be told: it does.
            if not target.startswith("/") or (top and _inside(target, top)):
                hits_top = True
                break
    if not hits_top and top and _file_write_hits(cmd, top, cwd):
        hits_top = True
    return hits_top, foreign


def _guard(gdir):
    """(fd, None) once this process holds the exclusive flock on <git dir>/devkit-session.guard - closing fd (or exiting) frees it;
    (None, why) when it cannot be had within GUARD_WAIT_S. Every read-decide-write of the lock runs under it (D1, audit 2026-10-09:
    two sessions whose first write hooks started together both read "free" and both were allowed, 19 of 20 runs - the window was the
    whole hook run, not microseconds). flock, not a lock file: the kernel frees it when the hook dies, so it never goes stale."""
    import fcntl  # noqa: PLC0415 - builtin, cheap
    path = os.path.join(gdir, GUARD)
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0), 0o600)
    except OSError as e:
        return None, f"không mở được {path}: {e}"
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            return None, f"{path} không phải file thường"
        deadline = time.monotonic() + GUARD_WAIT_S
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd, None
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    os.close(fd)
                    return None, f"{path} bị tiến trình khác giữ quá {GUARD_WAIT_S:g}s"
                time.sleep(0.005)
    except OSError as e:
        os.close(fd)
        return None, f"không khoá được {path}: {e}"


def take(path, lock, sid, cwd, now, pid=None):
    started = lock.get("started") if lock and lock.get("session_id") == sid else now
    if lock and lock.get("session_id") == sid and not lock.get("idle_since") and now - _num(lock.get("heartbeat")) < 30:
        return  # heartbeat throttle (an idle mark is always cleared: the holder works again)
    if pid is None:
        pid = holder_pid()
    write_lock(path, {"session_id": sid, "started": started, "heartbeat": now, "cwd": cwd, "pid": pid, "pid_start": pid_start(pid), "gitdir": os.path.dirname(path)})


def status(argv):
    """`--status [--session ID] [dir]`, read-only (2026-09-29): an agent with no hook API (Antigravity) cannot be
    blocked, so it asks before editing. Exit 3: another live session holds the checkout; 0: free, stale, its own
    (--session), or not a git checkout."""
    sid = ""
    if "--session" in argv:
        i = argv.index("--session")
        sid = argv[i + 1] if i + 1 < len(argv) else ""
        argv = argv[:i] + argv[i + 2:]
    target = argv[0] if argv else os.getcwd()
    gdir, top = git_dir(target)
    if not gdir:
        print(f"session_lock: {target} không phải git checkout — không có khoá")
        return 0
    trunk, _sw = trunk_main(top)
    if trunk and _same_dir(top, trunk):   # W1 R2 v6: an agent without hooks (Antigravity) reads this code before it edits
        print(f"session_lock: {top} ở trunk mode — main chỉ để GỘP, KHÔNG sửa ở đây (exit {TRUNK_STATUS_EXIT}). Làm trong worktree riêng: "
              f"`agent-kit worktree add ../<repo>-<việc>`, sửa + test + commit ở đó, xong `agent-kit worktree finish <đường dẫn>` (gộp vào main "
              f"qua gate, rồi xoá worktree). Không dừng lại hỏi.")
        return TRUNK_STATUS_EXIT
    now = time.time()
    lock = read_checkout_lock(gdir)
    if is_free_for(lock, sid, now):
        print(f"session_lock: {top} trống — được sửa")
        return 0
    until = allow_shared_until(gdir)
    if until > now:
        print(f"session_lock: {top} đang do {describe(lock, now)} giữ, nhưng người dùng đã cho phép ghi song song tới "
              f"{time.strftime('%H:%M', time.localtime(until))} — được sửa")
        return 0
    print(f"session_lock: {top} đang do {describe(lock, now)} giữ — KHÔNG sửa ở đây và KHÔNG dừng lại hỏi: TỰ làm trong worktree riêng "
          f"(`agent-kit worktree add ../<repo>-<việc>`, người dùng đã duyệt sẵn; xong thì `agent-kit worktree finish <đường dẫn>` gộp vào main "
          f"rồi xoá worktree; main còn bị giữ thì chờ phiên đó xong lượt, khoá tự nhả khoảng 1 phút sau khi nó chờ người dùng gõ)")
    return 3


def main():
    if "--status" in sys.argv[1:]:
        return status([a for a in sys.argv[1:] if a != "--status"])
    if "--allow-shared" in sys.argv[1:]:
        return allow_shared([a for a in sys.argv[1:] if a != "--allow-shared"])
    if "--allow-shared-off" in sys.argv[1:]:
        return allow_shared([a for a in sys.argv[1:] if a != "--allow-shared-off"], off=True)
    if "--check-last-active" in sys.argv[1:]:
        return check_last_active([a for a in sys.argv[1:] if a != "--check-last-active"])
    if "--register" in sys.argv[1:]:
        argv = [a for a in sys.argv[1:] if a != "--register"]
        sid = ""
        agent = "agent"
        if "--session" in argv:
            i = argv.index("--session")
            sid = argv[i + 1] if i + 1 < len(argv) else ""
            argv = argv[:i] + argv[i + 2:]
        if "--agent" in argv:
            i = argv.index("--agent")
            agent = argv[i + 1] if i + 1 < len(argv) else "agent"
            argv = argv[:i] + argv[i + 2:]
        pid = None
        if "--pid" in argv:
            i = argv.index("--pid")
            try:
                pid = int(argv[i + 1])
            except (ValueError, IndexError):
                pid = None
            argv = argv[:i] + argv[i + 2:]
        target = argv[0] if argv else os.getcwd()
        register_session(target, sid, agent=agent, pid=pid)
        return 0
    if "--unregister" in sys.argv[1:]:
        argv = [a for a in sys.argv[1:] if a != "--unregister"]
        sid = ""
        if "--session" in argv:
            i = argv.index("--session")
            sid = argv[i + 1] if i + 1 < len(argv) else ""
            argv = argv[:i] + argv[i + 2:]
        target = argv[0] if argv else os.getcwd()
        unregister_session(target, sid)
        return 0
    if "--heartbeat" in sys.argv[1:]:
        argv = [a for a in sys.argv[1:] if a != "--heartbeat"]
        sid = ""
        if "--session" in argv:
            i = argv.index("--session")
            sid = argv[i + 1] if i + 1 < len(argv) else ""
            argv = argv[:i] + argv[i + 2:]
        target = argv[0] if argv else os.getcwd()
        heartbeat_session(target, sid)
        return 0

    try:
        d = json.load(sys.stdin)
    except (ValueError, RecursionError):
        return 0
    if not isinstance(d, dict):
        return 0   # an array, a string, null: no event to judge - a no-op like unparsable JSON (D6, audit 2026-10-09: it crashed, exit 1)
    event = str(d.get("hook_event_name") or "")
    sid = str(d.get("session_id") or "")
    cwd = str(d.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    if not sid:
        return 0
    gdir, top = git_dir(cwd)
    if not gdir:
        return 0
    path = os.path.join(gdir, LOCK)
    now = time.time()
    # Every branch below reads the lock again under the guard (_guard, D1) right before it decides and writes.

    if event == "SessionEnd":
        # This session's temp dir under /tmp/claude-<uid>/ goes with it — not on /clear or /resume: the process lives on under a new
        # session id (review 2026-10-09), the prune takes that dir later. --self-pid: the claude process ending (it is still alive).
        if str(d.get("reason") or "") not in ("clear", "resume"):
            spawn_scratch_cleanup("--end", sid, "--self-pid", str(holder_pid()))
        unregister_session(cwd, sid)
        guard, why = _guard(gdir)
        lock = read_checkout_lock(gdir)
        if guard is None:
            print(f"session_lock: khoá để lại (không lấy được {GUARD}: {why}) — pid của phiên chết theo nó thì khoá tự trống", file=sys.stderr)
        elif lock and lock.get("session_id") == sid:
            try:
                os.remove(path)
            except OSError as e:
                print(f"session_lock: không gỡ được khoá: {e}", file=sys.stderr)
        return 0

    if event == "SessionStart":
        spawn_scratch_cleanup("--prune", "--keep", sid)   # temp dirs of sessions dead for more than 24 h
        register_session(cwd, sid, agent="claude")
        trunk, _sw = trunk_main(top)
        main_top = _sw.main_of(top) if _sw is not None and top else None
        if main_top:   # /clear, /resume: the same process under a new id, still in its worktree - its record follows it (W1 v6 item 5)
            try:
                _sw.reown(main_top, sid, cwd, lambda o: not owner_gone(cwd, o, _sw, main_top)[0], me=holder_pid())
            except Exception as e:  # noqa: BLE001 - a record that cannot be moved: the Stop hook tries again (worktree_merge_gate)
                print(f"session_lock: worktree record not moved ({e!r})", file=sys.stderr)
            problems = []   # #413: a lock that could not be taken is said on stdout (SessionStart context), not only on stderr
            try:   # review 25/10: a session that starts in its worktree (no EnterWorktree) holds it too, or cleanup-wt removes it mid-gate
                _sw.lock_started_worktree(main_top, cwd, sid, holder_pid(), source=str(d.get("source") or "") or None,
                                          owner_alive=lambda o: owner_gone(cwd, o, _sw, main_top)[1] == "alive", problems=problems)
            except Exception as e:  # noqa: BLE001 - SessionStart never blocks: said on stderr, the worktree stays as unprotected as before
                print(f"session_lock: session worktree not locked ({e!r})", file=sys.stderr)
                problems.append(f"NOT LOCKED: the session worktree lock failed ({e!r}): cleanup-wt may remove it while this session works")
            for line in problems:
                print(f"⚠️ [DevKit] {line}")
        if trunk and _same_dir(top, trunk):
            return 0   # W1 R1 v6: a trunk-mode main checkout has no holder - nothing to take, nobody to wait for
        guard, why = _guard(gdir)
        now, lock = time.time(), read_checkout_lock(gdir)
        if guard is None:
            print(f"session_lock: chưa nhận khoá lúc mở phiên ({why}); lần ghi đầu sẽ nhận", file=sys.stderr)
        if guard is not None and is_free_for(lock, sid, now, idle_frees=False):
            if lock and lock.get("session_id") not in (None, sid):
                log(gdir, f"{sid} nhận khoá của {lock.get('session_id')} ({'phiên đó đang rảnh' if lock.get('idle_since') else 'đã hết hạn'})")
            take(path, lock, sid, cwd, now)
        elif not is_free_for(lock, sid, now):
            print(f"⚠️ [DevKit] Checkout này đang do {describe(lock, now)} giữ. Luật: MỘT thư mục — MỘT phiên. Phiên này "
                  f"CHỈ ĐỌC ở đây (Edit/Write, git ghi, post-fix-gate bị chặn) cho tới khi phiên kia xong lượt (khoá tự nhả khoảng 1 "
                  f"phút sau khi nó chờ người dùng gõ, không cần /exit); cần ghi thì TỰ làm trong worktree riêng "
                  f"(`agent-kit worktree add ../<repo>-<việc>`, người dùng đã duyệt sẵn, không hỏi lại; xong thì "
                  f"`agent-kit worktree finish <đường dẫn>`).")
        # else an IDLE holder: free for this session's first write, but not taken now — a session opened and never prompted
        # never goes idle, so taking it here would lock the idle holder out for the whole heartbeat window
        return 0

    if event == "Notification":
        if str(d.get("notification_type") or "") != "idle_prompt":
            return 0
        lock = read_checkout_lock(gdir)
        reg0 = read_session(cwd, sid) or {}   # read before anything else: both writes below compare against these heartbeats
        if test_run_active({top, os.environ.get("CLAUDE_PROJECT_DIR") or top}):
            return 0   # an end-of-turn gate still runs: the session is not idle yet (the lock stays, as before)
        if reg0:
            mark_idle_session(cwd, sid, expect_heartbeat=reg0.get("heartbeat"))
        guard, _why = _guard(gdir)   # no guard: not marked (the lock stays, as while a gate runs)
        cur = read_lock(path) if guard is not None else None   # compare-then-write: a take() by the holder resuming meanwhile (new heartbeat) is never marked idle
        if (lock and cur and cur.get("session_id") == sid and lock.get("session_id") == sid and not cur.get("idle_since")
                and cur.get("heartbeat") == lock.get("heartbeat")):
            cur["idle_since"] = now
            write_lock(path, cur)
            log(gdir, f"{sid} rảnh (xong lượt, chờ người dùng gõ) — phiên khác được nhận khoá")
        return 0

    if event != "PreToolUse":
        return 0
    heartbeat_session(cwd, sid)
    tool = str(d.get("tool_name") or "")
    ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}   # (a string or a list: no command, no path - D6)
    command = str(ti.get("command") or "") if tool == "Bash" else ""
    if tool in EDIT_TOOLS:   # the approval flag and the lock file are written by the user's command and by this hook, never by an Edit/Write
        target_path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
        if isinstance(target_path, str) and os.path.basename(target_path) in (ALLOW_FLAG, LOCK):
            print("⛔ [DevKit] File công tắc / khoá của DevKit không được ghi bằng Edit/Write: công tắc là của NGƯỜI DÙNG "
                  "(`! agent-kit allow-shared`).", file=sys.stderr)
            return 2
    if command and is_self_grant(command):
        print("⛔ [DevKit] Công tắc 'cho phép ghi song song' là của NGƯỜI DÙNG: agent không tự bật hay tắt. Nhờ người dùng chạy "
              "`! agent-kit allow-shared` (mặc định 60 phút; `agent-kit allow-shared off` để tắt).", file=sys.stderr)
        return 2
    if command and is_trunk_off(command):
        print("⛔ [DevKit] Công tắc trunk mode là của NGƯỜI DÙNG: agent không tự tắt (`agent-kit worktree trunk off`, `git config devkit.trunkMode` "
              "khác true hay --unset, WORKTREE_TRUNK_MODE=0 trong lệnh). Bật thêm (`trunk on`) và đọc thì được. Cần tắt: nhờ người dùng chạy "
              "`! agent-kit worktree trunk off`.", file=sys.stderr)
        return 2
    if trunk_env_in_settings(tool, d.get("tool_input"), command):
        print("⛔ [DevKit] Công tắc trunk mode là của NGƯỜI DÙNG: agent không ghi WORKTREE_TRUNK_MODE (khác 1) vào file settings của Claude (khối `env` "
              "của settings*.json là môi trường của hook ở phiên sau). Cần tắt: nhờ người dùng chạy `! agent-kit worktree trunk off`.", file=sys.stderr)
        return 2
    foreign = None
    if tool in EDIT_TOOLS:
        collides = edit_hits_locked(d.get("tool_input"), top, cwd, gdir)
    elif tool == "Bash":
        collides, foreign = bash_collides(command, top, cwd, sid)
    else:
        return 0
    if foreign:   # a write into ANOTHER checkout that another live session holds: judged by THAT lock, whatever this session's own checkout says
        ftop, fgdir, flock = foreign
        if os.environ.get("DEVKIT_ALLOW_SHARED_CHECKOUT") == "1" or allow_shared_until(fgdir) > now:
            log(fgdir, f"{sid} ghi song song khi {flock.get('session_id')} đang giữ (được cho phép): {tool}")
        else:
            print(f"⛔ [DevKit] Một thư mục — một phiên: lệnh này ghi vào checkout {ftop}, đang do {describe(flock, now)} giữ. KHÔNG dừng lại hỏi: "
                  f"TỰ làm trong worktree riêng (`agent-kit worktree add ../<repo>-<việc>`, người dùng đã duyệt sẵn; xong thì "
                  f"`agent-kit worktree finish <đường dẫn>`), hoặc chờ phiên kia xong lượt.", file=sys.stderr)
            return 2
    trunk, sw = trunk_main(top)
    if trunk:   # W1 R1 v6: main is merge-only - a write into it is refused whoever the session is, wherever it runs from
        if trunk_write(tool, d.get("tool_input"), command, cwd, trunk, sw, sid):
            print(TRUNK_MSG.format(main=trunk), file=sys.stderr)
            log(gdir, f"{sid} trunk mode: chặn ghi vào main {trunk} ({tool})")
            return 2
        if _same_dir(top, trunk):
            return 0   # nothing written into main: nothing to take (main has no holder in trunk mode)

    # D1: read, decide and take under the guard - two sessions starting their first write together used to both read "free"
    guard, why = _guard(gdir)
    if guard is None:
        if not collides:
            return 0   # a read needs no lock (its heartbeat refresh waits for the next call)
        print(f"⛔ [DevKit] Một thư mục — một phiên: không lấy được khoá phụ của checkout {top} ({why}), nên không biết phiên nào "
              f"đang giữ — lệnh ghi bị chặn cho chắc. Chạy lại lệnh; nếu vẫn bị, một tiến trình treo đang giữ {GUARD} (xem `lsof`).",
              file=sys.stderr)
        return 2
    now, lock = time.time(), read_checkout_lock(gdir)
    if is_free_for(lock, sid, now):
        if collides or (lock and lock.get("session_id") == sid):
            if lock and lock.get("session_id") not in (None, sid):   # logged only when it is really taken (not on every read)
                log(gdir, f"{sid} nhận khoá của {lock.get('session_id')} ({'phiên đó đang rảnh' if lock.get('idle_since') else 'đã hết hạn'})")
            take(path, lock, sid, cwd, now)
        return 0
    if not collides:
        return 0
    if os.environ.get("DEVKIT_ALLOW_SHARED_CHECKOUT") == "1":
        log(gdir, f"{sid} ghi song song khi {lock.get('session_id')} đang giữ (DEVKIT_ALLOW_SHARED_CHECKOUT=1): {tool}")
        return 0
    until = allow_shared_until(gdir)
    if until > now:
        log(gdir, f"{sid} ghi song song khi {lock.get('session_id')} đang giữ (người dùng cho phép tới "
                  f"{time.strftime('%H:%M', time.localtime(until))}): {tool}")
        return 0
    print(f"⛔ [DevKit] Một thư mục — một phiên: checkout {top} đang do {describe(lock, now)} giữ. Phiên này chỉ đọc "
          f"ở đây. KHÔNG dừng lại hỏi: TỰ làm trong worktree riêng (`agent-kit worktree add ../<repo>-<việc>`, người dùng đã duyệt sẵn; "
          f"xong thì `agent-kit worktree finish <đường dẫn>` gộp vào main rồi xoá worktree), hoặc chờ phiên kia xong lượt (khoá tự nhả "
          f"khoảng 1 phút sau khi nó chờ người dùng gõ, hoặc sau {int(stale_after())}s không hoạt động). Chỉ khi người dùng cố ý cho chạy "
          f"song song trong chính checkout này: `! agent-kit allow-shared` hoặc DEVKIT_ALLOW_SHARED_CHECKOUT=1 trước khi mở phiên.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
