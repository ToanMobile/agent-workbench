#!/usr/bin/env python3
"""scratch_cleanup.py — remove the temp dirs Claude Code leaves behind per session.

User 2026-10-09: "thư mục tạm của Claude Code chiếm tới 33 GB … mày phải có cơ chế dùng xong xoá đi". Claude Code keeps
/tmp/claude-<uid>/<project-slug>/<session-uuid>/ (scratchpad, background task output) and never removes it; one session's
two CoW repo copies (29 GB) filled the boot disk to 99 %.

  --end SESSION_ID                      remove that session's dirs (under every project slug) — run at SessionEnd
  --prune [--keep ID] [--ttl-hours N]   remove the dirs of sessions idle for more than N hours (default 24): the session's
                                        transcript (~/.claude/projects/<slug>/<id>.jsonl) and the newest entry in the top two
                                        levels of its dir are all older — run at SessionStart, keeping the session itself

Only <root>/<slug>/<uuid>/ real directories are ever touched: the root must be a real directory owned by this user (not a
symlink), slug and session entries must be real directories (a symlink is never followed or removed), the name a UUID.
DEVKIT_SCRATCH_ROOT and DEVKIT_CLAUDE_PROJECTS override the two roots (tests). Every removal is logged to
<root>/devkit-scratch-cleanup.log. Exit 0 (nothing to do included), 2 = bad usage.
ponytail: idleness is read from the transcript and the top two levels only (a deep walk of a 14 GB copy is slow); a session
idle longer than the TTL loses its scratchpad, which it may recreate — raise --ttl-hours if that ever bites.
"""
import os
import re
import shutil
import stat
import sys
import time

UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
DEFAULT_TTL_H = 24.0


def scratch_root():
    r = os.environ.get("DEVKIT_SCRATCH_ROOT") or os.path.join("/tmp", "claude-%d" % os.getuid())
    try:
        st = os.lstat(r)
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        return None   # a symlink, a file, or another user's directory: not ours to clean
    return r


def projects_root():
    return os.environ.get("DEVKIT_CLAUDE_PROJECTS") or os.path.join(os.path.expanduser("~"), ".claude", "projects")


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


def remove(root, path, why):
    errors = []
    shutil.rmtree(path, onerror=lambda fn, p, exc: errors.append("%s: %s" % (p, exc[1])))
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

    end, keep, ttl = opt("--end"), opt("--keep", ""), opt("--ttl-hours")
    prune = "--prune" in args
    if (end is None) == (not prune) or (end is not None and not UUID.match(end)):
        print(__doc__.strip().splitlines()[6].strip(), file=sys.stderr)
        return 2
    try:
        ttl_h = float(ttl) if ttl is not None else DEFAULT_TTL_H
    except ValueError:
        return 2
    root = scratch_root()
    if root is None:
        return 0
    if end is not None:
        for slug, sid, path in list(session_dirs(root)):
            if sid == end:
                remove(root, path, "session ended")
        return 0
    cutoff = time.time() - ttl_h * 3600
    for slug, sid, path in list(session_dirs(root)):
        if sid != keep and last_activity(slug, sid, path) < cutoff:
            remove(root, path, "idle > %g h" % ttl_h)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
