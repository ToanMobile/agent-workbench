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
"""
import json
import os
import re
import stat
import subprocess
import sys
import time

LOCK = "devkit-session.lock"
LOG = "devkit-session.log"
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
# (?![\w-]) ends the verb: `git merge-base`, `merge-tree` and `commit-tree` are read-only plumbing, not `merge` / `commit` (the old
# `\b` matched before the hyphen and blocked them). `opts` are git's global options before the verb (-C <dir>, -c k=v, --git-dir ...).
GIT_WRITE = re.compile(
    r"(^|[\s;&|(/])git\s+(?P<opts>(?:(?:-C\s+(?:\"[^\"]*\"|'[^']*'|\S+)|-c\s+(?:[^\s\"']|\"[^\"]*\"|'[^']*')+|--(?:git-dir|work-tree)\s+\S+|--[\w-]+(?:=\S+)?|-[pP])\s+)*)"
    r"(commit|push|pull|add|rm|mv|reset|checkout|restore|switch|stash|merge|rebase|cherry-pick|revert|am|apply|tag|clean)(?![\w-])")
GATE = re.compile(r"post-fix-gate(\.py)?\b|\bpostfix-gate\b|\bagent-kit\s+(?:worktree|wt)\s+(?:finish|automerge)\b|worktree\.py\s+(?:finish|automerge)\b")
SEPARATOR = re.compile(r"(&&|\|\||[;|&\n])")
CD_ONLY = re.compile(r"^\s*(?:builtin\s+)?cd\s+(?:--\s+)?(\"[^\"]*\"|'[^']*'|[^\s;&|()<>$`\\]+)\s*$")
PROJECT_DIR = re.compile(r"\bCLAUDE_PROJECT_DIR=(\"[^\"]*\"|'[^']*'|\S+)")
ALLOW_FLAG = "devkit-allow-shared"
# A directory change the segment walk cannot follow (subshell, `bash -c`, eval, pushd, a cd with a redirect, GIT_DIR=...): the directory
# is UNKNOWN from there on, so every later write fails closed (review 2026-10-08: `cd B && (cd A && git commit)` slipped through).
DIR_CHANGE = re.compile(r"(?:^|[\s;&|(`])(?:cd|pushd|popd)\b|\beval\b|\b(?:ba|z|da)?sh\s+-\w*c\b|\bGIT_DIR=|\bGIT_WORK_TREE=|--git-dir|--work-tree|\benv\s+(?:-\S+\s+)*-C\b|--chdir|^\s*\(")
WRAPPERS = {"env", "command", "exec", "xargs", "nohup", "time", "sudo", "bash", "sh", "zsh", "dash", "eval"}
WRITE_CMDS = {"touch", "cp", "mv", "ln", "install", "tee", "dd", "rsync", "truncate", "perl", "ruby", "node"}
READERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "cat", "bat", "less", "more", "head", "tail", "wc", "file", "stat", "ls", "echo",
           "printf", "diff", "cmp", "git", "man", "type", "which", "find", "sed", "awk"}   # (sed writes only with -i: see is_self_grant)
_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
RUNS_BODY = {"bash", "sh", "zsh", "dash", "ksh", "python", "python3", "perl", "ruby", "node", "eval", "source", "."}   # a heredoc fed to these is CODE


def _strip_heredocs(cmd):
    """Drop the body of every heredoc that feeds a data command (cat, a commit message, a patch): its lines are text, not commands. A
    heredoc fed to a shell or an interpreter keeps its body - those lines run."""
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
        runs = word in RUNS_BODY or word.startswith("python")
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
REDIRECT = re.compile(r"\d*>>?\|?\s*([^\s;&|<>()]+)")
TEMP_PREFIXES = ("/dev/", "/tmp", "/private/tmp", "/var/folders", "/private/var/folders")


def git_dir(cwd):
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
    except (OSError, ValueError):
        return None


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
            pid = os.getppid()
        data = {
            "session_id": sid,
            "agent": agent,
            "pid": pid,
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
        if data.get("status") != "idle" and now - float(data.get("heartbeat") or 0) < 15:
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


def is_pid_alive(pid):
    if not pid or not isinstance(pid, int) or pid <= 1:
        return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
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
            if lock and lock.get("session_id") and not lock.get("idle_since") and (now - float(lock.get("heartbeat") or 0) <= stale_s):
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

        hb = float(info.get("heartbeat") or 0)
        pid = info.get("pid")
        alive = is_pid_alive(pid)
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
            try:
                os.remove(file_path)
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
            if os.path.realpath(info["gitdir"]) != os.path.realpath(my_gitdir):
                continue
        elif top and info_cwd:
            # Older record without a git dir: compare by path.
            real_top, real_cwd = os.path.realpath(top), os.path.realpath(info_cwd)
            if real_cwd != real_top and not real_cwd.startswith(real_top + os.sep):
                continue

        sid = info.get("session_id")
        active.append(info)
        if current_sid and sid != current_sid:
            other.append(info)
        elif not current_sid:
            if pid != os.getpid() and pid != os.getppid():
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
            other_ids = ", ".join(s.get("session_id", "?")[:12] for s in other)
            print(f"session_lock: phát hiện {len(other)} phiên khác đang hoạt động ({other_ids}).")
    return 0 if is_last else 1


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


def is_free_for(lock, sid, now, idle_frees=True):
    """True when `sid` may hold the checkout: no lock, its own lock, an idle holder, a dead process, or a stale one.
    idle_frees=False: an idle holder still counts as present (it is alive and may come back) — for callers that would
    otherwise act ON that session's tree (worktree_merge_gate merging or removing it), not just write next to it."""
    if not lock or not lock.get("session_id"):
        return True
    if lock.get("session_id") == sid:
        return True
    if idle_frees and lock.get("idle_since"):
        return True   # the holder finished its turn and waits for the user (Notification idle_prompt)
    lock_pid = lock.get("pid")
    if lock_pid and not is_pid_alive(lock_pid):
        return True
    return now - float(lock.get("heartbeat") or 0) > stale_after()


def describe(lock, now):
    sid = str(lock.get("session_id", "?"))
    started = time.strftime("%H:%M", time.localtime(float(lock.get("started") or now)))
    age = int(now - float(lock.get("heartbeat") or now))
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


def _unquote(word):
    return word[1:-1] if len(word) >= 2 and word[0] in "\"'" and word[-1] == word[0] else word


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
    seen, hits_top, foreign = False, False, None
    for i in range(0, len(pieces), 2):
        seg = pieces[i]
        sep = pieces[i + 1] if i + 1 < len(pieces) else ""
        cd = CD_ONLY.match(seg)
        if cd:
            cur = _resolve(cur, cd.group(1)) if sep in ("&&", ";", "\n", "") else None
            continue
        if DIR_CHANGE.search(seg):
            cur = None
        targets = [_git_target(cur, m.group("opts")) for m in GIT_WRITE.finditer(seg)]
        if GATE.search(seg):
            pd = PROJECT_DIR.search(seg)
            targets.append(_resolve(cur, pd.group(1)) if pd else cur)
        for target in targets:
            seen = True
            tl, tgdir = _target(target)
            if tl is None or tl == locked:
                hits_top = True
                continue
            lock = read_checkout_lock(tgdir)
            if foreign is None and not is_free_for(lock, sid, time.time()):
                foreign = (tl, tgdir, lock)   # another repository, but a live session holds THAT one
    # the regexes see a write the segment walk did not (e.g. an unterminated quote): judge it by the text, as before
    if not seen:
        stripped = _strip_heredocs(cmd)
        hits_top = bool(GIT_WRITE.search(stripped) or GATE.search(stripped))
    return hits_top, foreign


def edit_hits_locked(tool_input, top, cwd, gdir=None):
    """Edit / Write / MultiEdit / NotebookEdit collide only for a file inside the locked checkout or its git dir (a linked worktree's
    lies OUTSIDE it); no path at all fails closed."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
    if not path or not top or not isinstance(path, str):
        return True
    real = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd or top, path))
    for root in (top, gdir):
        if root:
            r = os.path.realpath(root)
            if real == r or real.startswith(r + os.sep):
                return True
    return False


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


def bash_collides(cmd, top, cwd=None, sid=""):
    """(hits_top, foreign) - see write_hits_locked; a redirect into the locked checkout also counts as hits_top."""
    hits_top, foreign = False, None
    if GIT_WRITE.search(cmd) or GATE.search(cmd):
        hits_top, foreign = write_hits_locked(cmd, top, cwd, sid)
    if not hits_top:
        for m in REDIRECT.finditer(cmd):
            target = m.group(1)
            if target.startswith("&") or target.startswith(TEMP_PREFIXES):
                continue
            tmpdir = os.environ.get("TMPDIR", "")
            if tmpdir and target.startswith(tmpdir):
                continue
            if not target.startswith("/") or (top and os.path.realpath(target).startswith(os.path.realpath(top) + os.sep)):
                hits_top = True
                break
    return hits_top, foreign


def take(path, lock, sid, cwd, now, pid=None):
    started = lock.get("started") if lock and lock.get("session_id") == sid else now
    if lock and lock.get("session_id") == sid and not lock.get("idle_since") and now - float(lock.get("heartbeat") or 0) < 30:
        return  # heartbeat throttle (an idle mark is always cleared: the holder works again)
    if pid is None:
        pid = os.getppid()
    write_lock(path, {"session_id": sid, "started": started, "heartbeat": now, "cwd": cwd, "pid": pid, "gitdir": os.path.dirname(path)})


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
    print(f"session_lock: {top} đang do {describe(lock, now)} giữ — KHÔNG sửa ở đây: chờ phiên đó xong lượt (khoá tự nhả khoảng 1 phút sau khi nó chờ người dùng gõ), "
          f"hoặc làm trong worktree riêng (`agent-kit worktree add`), hoặc nhờ người dùng chạy `! agent-kit allow-shared`")
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
    except ValueError:
        return 0
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
    lock = read_checkout_lock(gdir)

    if event == "SessionEnd":
        unregister_session(cwd, sid)
        if lock and lock.get("session_id") == sid:
            try:
                os.remove(path)
            except OSError as e:
                print(f"session_lock: không gỡ được khoá: {e}", file=sys.stderr)
        return 0

    if event == "SessionStart":
        register_session(cwd, sid, agent="claude")
        if is_free_for(lock, sid, now, idle_frees=False):
            if lock and lock.get("session_id") not in (None, sid):
                log(gdir, f"{sid} nhận khoá của {lock.get('session_id')} ({'phiên đó đang rảnh' if lock.get('idle_since') else 'đã hết hạn'})")
            take(path, lock, sid, cwd, now)
        elif not is_free_for(lock, sid, now):
            print(f"⚠️ [DevKit] Checkout này đang do {describe(lock, now)} giữ. Luật: MỘT thư mục — MỘT phiên. Phiên này "
                  f"CHỈ ĐỌC ở đây (Edit/Write, git ghi, post-fix-gate bị chặn) cho tới khi phiên kia xong lượt (khoá tự nhả khoảng 1 "
                  f"phút sau khi nó chờ người dùng gõ, không cần /exit); muốn làm song "
                  f"song thì xin người dùng tạo worktree riêng.")
        # else an IDLE holder: free for this session's first write, but not taken now — a session opened and never prompted
        # never goes idle, so taking it here would lock the idle holder out for the whole heartbeat window
        return 0

    if event == "Notification":
        if str(d.get("notification_type") or "") != "idle_prompt":
            return 0
        reg0 = read_session(cwd, sid) or {}   # read before anything else: both writes below compare against these heartbeats
        if test_run_active({top, os.environ.get("CLAUDE_PROJECT_DIR") or top}):
            return 0   # an end-of-turn gate still runs: the session is not idle yet (the lock stays, as before)
        if reg0:
            mark_idle_session(cwd, sid, expect_heartbeat=reg0.get("heartbeat"))
        cur = read_lock(path)   # compare-then-write: a take() by the holder resuming meanwhile (new heartbeat) is never marked idle
        if (lock and cur and cur.get("session_id") == sid and lock.get("session_id") == sid and not cur.get("idle_since")
                and cur.get("heartbeat") == lock.get("heartbeat")):
            cur["idle_since"] = now
            write_lock(path, cur)   # ponytail: not atomic (no O_EXCL), a microsecond window remains; take() has the same shape
            log(gdir, f"{sid} rảnh (xong lượt, chờ người dùng gõ) — phiên khác được nhận khoá")
        return 0

    if event != "PreToolUse":
        return 0
    heartbeat_session(cwd, sid)
    tool = str(d.get("tool_name") or "")
    command = str((d.get("tool_input") or {}).get("command") or "") if tool == "Bash" else ""
    if tool in EDIT_TOOLS:   # the approval flag and the lock file are written by the user's command and by this hook, never by an Edit/Write
        ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
        target_path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
        if isinstance(target_path, str) and os.path.basename(target_path) in (ALLOW_FLAG, LOCK):
            print("⛔ [DevKit] File công tắc / khoá của DevKit không được ghi bằng Edit/Write: công tắc là của NGƯỜI DÙNG "
                  "(`! agent-kit allow-shared`).", file=sys.stderr)
            return 2
    if command and is_self_grant(command):
        print("⛔ [DevKit] Công tắc 'cho phép ghi song song' là của NGƯỜI DÙNG: agent không tự bật hay tắt. Nhờ người dùng chạy "
              "`! agent-kit allow-shared` (mặc định 60 phút; `agent-kit allow-shared off` để tắt).", file=sys.stderr)
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
            print(f"⛔ [DevKit] Một thư mục — một phiên: lệnh này ghi vào checkout {ftop}, đang do {describe(flock, now)} giữ. Chờ phiên kia xong, "
                  f"làm trong worktree riêng, hoặc người dùng gõ `! agent-kit allow-shared` (trong chính checkout đó).", file=sys.stderr)
            return 2

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
          f"ở đây: chờ phiên kia xong lượt (khoá tự nhả khoảng 1 phút sau khi nó chờ người dùng gõ, hoặc sau {int(stale_after())}s không hoạt động), hoặc xin người dùng tạo "
          f"worktree riêng. Người dùng cố ý cho chạy song song: gõ `! agent-kit allow-shared` (không cần khởi động lại "
          f"phiên) hoặc đặt DEVKIT_ALLOW_SHARED_CHECKOUT=1 trước khi mở phiên.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
