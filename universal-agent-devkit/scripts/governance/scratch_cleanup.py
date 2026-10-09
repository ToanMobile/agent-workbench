#!/usr/bin/env python3
"""scratch_cleanup.py — remove the temp dirs Claude Code leaves behind per session.

User 2026-10-09: "thư mục tạm của Claude Code chiếm tới 33 GB … mày phải có cơ chế dùng xong xoá đi". Claude Code keeps
/tmp/claude-<uid>/<project-slug>/<session-uuid>/ (scratchpad, background task output) and never removes it; one session's
two CoW repo copies (29 GB) filled the boot disk to 99 %.

  --end SESSION_ID [--self-pid PID]     remove that session's dirs (under every project slug) — run at SessionEnd; kept while
                                        another live Claude process (not PID) holds the same session id
  --prune [--keep ID] [--ttl-hours N]   remove the dirs of sessions idle for more than N hours (default 168): the session's
                                        transcript (~/.claude/projects/<slug>/<id>.jsonl) and the newest entry in the top two
                                        levels of its dir are all older — run at SessionStart, keeping the session itself

Only <root>/<slug>/<uuid>/ real directories are ever touched: the root must be a real directory owned by this user (not a
symlink), slug and session entries must be real directories (a symlink is never followed or removed), the name a UUID.
DEVKIT_SCRATCH_ROOT and DEVKIT_CLAUDE_PROJECTS override the two roots (tests). Every removal is logged to
<root>/devkit-scratch-cleanup.log. Exit 0 (nothing to do included), 2 = bad usage.
Removal is fd-based (audit T0023, TOCTOU): root and project dir are opened with O_NOFOLLOW and the session dir is removed with
rmtree(dir_fd=…), so a project dir swapped for a symlink after the listing is never followed; a Python without that support skips.
ponytail: liveness is the transcript and the top two levels (no running process maps to its session id); a session left open
and idle for over the TTL (7 days, audit T0023: 24 h could hit a session left open overnight) loses its scratchpad — SessionEnd
already removes every normally closed session, so the prune only catches crashed ones; raise --ttl-hours if that ever bites.
"""
import json
import os
import re
import shutil
import stat
import sys
import time

UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
DEFAULT_TTL_H = 168.0


def scratch_root():
    r = os.environ.get("DEVKIT_SCRATCH_ROOT") or os.path.join("/tmp", "claude-%d" % os.getuid())
    try:
        st = os.lstat(r)
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        return None   # a symlink, a file, or another user's directory: not ours to clean
    return r


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def projects_root():
    return os.environ.get("DEVKIT_CLAUDE_PROJECTS") or os.path.join(claude_home(), "projects")


def live_sessions(exclude_pid=None):
    """{session id: pid} of running Claude Code processes: <claude home>/sessions/<pid>.json holds {pid, sessionId} (review
    2026-10-09: the only signal that a session idle at the prompt for days is alive). A stale file of a dead pid counts for
    nothing; a pid this user may not signal (EPERM) counts as alive; a reused pid only keeps a dir (the safe side)."""
    d = os.environ.get("DEVKIT_CLAUDE_SESSIONS") or os.path.join(claude_home(), "sessions")
    live = {}
    try:
        names = os.listdir(d)
    except OSError:
        return live
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, n), encoding="utf-8") as f:
                info = json.load(f)
            pid, sid = int(info.get("pid")), str(info.get("sessionId") or "")
        except (OSError, ValueError, TypeError, AttributeError):
            continue
        if pid <= 1 or pid == exclude_pid or not UUID.match(sid):
            continue
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        except OSError:
            pass   # EPERM and the like: alive
        live[sid] = pid
    return live


def real_dir(p):
    try:
        return stat.S_ISDIR(os.lstat(p).st_mode)
    except OSError:
        return False


def session_dirs(root):
    """(slug, session id, path) for every real <root>/<slug>/<uuid>/ directory."""
    try:
        slugs = os.listdir(root)
    except OSError:
        return
    for slug in slugs:
        sp = os.path.join(root, slug)
        if not real_dir(sp):
            continue
        try:
            names = os.listdir(sp)
        except OSError:
            continue
        for name in names:
            p = os.path.join(sp, name)
            if UUID.match(name) and real_dir(p):
                yield slug, name, p


def last_activity(slug, sid, path):
    """Newest mtime of the session's transcript and of the entries in the top two levels of its temp dir."""
    times = []
    for p in [os.path.join(projects_root(), slug, sid + ".jsonl"), path]:
        try:
            times.append(os.lstat(p).st_mtime)
        except OSError:
            pass
    try:
        for e in os.scandir(path):
            times.append(e.stat(follow_symlinks=False).st_mtime)
            if e.is_dir(follow_symlinks=False):
                with os.scandir(e.path) as inner:
                    for f in inner:
                        times.append(f.stat(follow_symlinks=False).st_mtime)
    except OSError:
        return time.time()   # cannot read it: treat as active (never remove what cannot be judged)
    return max(times) if times else time.time()


def remove(root, slug, name, why):
    """rmtree <root>/<slug>/<name> without following a symlink anywhere on the way, even one swapped in after the listing."""
    path, errors, fds = os.path.join(root, slug, name), [], []
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW
    try:
        fds.append(os.open(root, flags))
        fds.append(os.open(slug, flags, dir_fd=fds[0]))
        st = os.fstat(fds[1])
        if st.st_uid != os.getuid() or not stat.S_ISDIR(os.lstat(name, dir_fd=fds[1]).st_mode):
            return
        if not getattr(shutil.rmtree, "avoids_symlink_attacks", False):
            errors.append("this Python cannot remove a tree without following symlinks: skipped")
        else:
            shutil.rmtree(name, dir_fd=fds[1], onerror=lambda fn, p, exc: errors.append("%s: %s" % (p, exc[1])))
    except (OSError, TypeError) as e:   # a symlink swapped in (ELOOP / ENOTDIR), or rmtree without dir_fd (Python < 3.11)
        errors.append("not removed: %s" % e)
    finally:
        for fd in fds:
            os.close(fd)
    line = "%s removed %s (%s)%s" % (time.strftime("%Y-%m-%d %H:%M:%S"), path, why,
                                    " — errors: " + "; ".join(errors[:3]) if errors else "")
    try:
        with open(os.path.join(root, "devkit-scratch-cleanup.log"), "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError as e:
        print("scratch_cleanup: cannot write the log: %s" % e, file=sys.stderr)
    if errors:
        print("scratch_cleanup: " + line, file=sys.stderr)


def main(argv):
    args = list(argv)

    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            val = args[i + 1] if i + 1 < len(args) else ""
            del args[i:i + 2]
            return val
        return default

    end, keep, ttl, self_pid = opt("--end"), opt("--keep", ""), opt("--ttl-hours"), opt("--self-pid")
    prune = "--prune" in args
    if (end is None) == (not prune) or (end is not None and not UUID.match(end)):
        print(__doc__.strip().splitlines()[6].strip(), file=sys.stderr)
        return 2
    try:
        ttl_h = float(ttl) if ttl is not None else DEFAULT_TTL_H
        self_pid = int(self_pid) if self_pid else None
    except ValueError:
        return 2
    root = scratch_root()
    if root is None:
        return 0
    if end is not None:
        if end in live_sessions(exclude_pid=self_pid):
            return 0   # another live process holds this session id (a --resume elsewhere): not ours to remove
        for slug, sid, path in list(session_dirs(root)):
            if sid == end:
                remove(root, slug, sid, "session ended")
        return 0
    cutoff, live = time.time() - ttl_h * 3600, live_sessions()
    for slug, sid, path in list(session_dirs(root)):
        if sid != keep and sid not in live and last_activity(slug, sid, path) < cutoff:
            remove(root, slug, sid, "idle > %g h" % ttl_h)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
