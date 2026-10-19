#!/usr/bin/env python3
"""scratch_cleanup.py — remove the temp dirs Claude Code leaves behind per session.

User 2026-10-09: "thư mục tạm của Claude Code chiếm tới 33 GB … mày phải có cơ chế dùng xong xoá đi". Claude Code keeps
/tmp/claude-<uid>/<project-slug>/<session-uuid>/ (scratchpad, background task output) and never removes it; one session's
two CoW repo copies (29 GB) filled the boot disk to 99 %.

  --end SESSION_ID [--self-pid PID]     remove that session's dirs (under every project slug) — run at SessionEnd; kept while
                                        another live Claude process (not PID) holds the same session id
  --prune [--keep ID] [--ttl-hours N]   remove the dirs of sessions idle for more than N hours (default 168): the session's
                                        transcript (~/.claude/projects/<slug>/<id>.jsonl) and the newest entry in the top two
                                        levels of its dir are all older — run at SessionStart, keeping the session itself;
                                        it also runs the test temp sweep below
  --sweep-tmp [--tmp-ttl-hours N]       only the test temp sweep: in $TMPDIR, remove the dirs a test of this repo leaves
                                        when it is killed before its EXIT trap (2026-10-19: ~8 GiB, disk 99 %) — a name
                                        from TEST_TMP_PREFIXES, a real dir of this user, nothing in its tree newer than N
                                        hours (default 6), no process holding a file or cwd in it (one lsof snapshot; no
                                        lsof answer = nothing removed); a worktree in it whose admin repo is elsewhere
                                        loses that one registration there after the removal

Only <root>/<slug>/<uuid>/ real directories are ever touched by --end / --prune's session part: the root must be a real directory owned by this user (not a
symlink), slug and session entries must be real directories (a symlink is never followed or removed), the name a UUID.
DEVKIT_SCRATCH_ROOT and DEVKIT_CLAUDE_PROJECTS override the two roots (tests). Every removal is logged to
<root>/devkit-scratch-cleanup.log. Exit 0 (nothing to do included), 2 = bad usage.
Removal is fd-based (audit T0023, TOCTOU): root and project dir are opened with O_NOFOLLOW and the session dir is removed with
rmtree(dir_fd=…), so a project dir swapped for a symlink after the listing is never followed; a Python without that support skips.
ponytail: liveness is the transcript and the top two levels (no running process maps to its session id); a session left open
and idle for over the TTL (7 days, audit T0023: 24 h could hit a session left open overnight) loses its scratchpad — SessionEnd
already removes every normally closed session, so the prune only catches crashed ones; raise --ttl-hours if that ever bites.
"""
import contextlib
import fcntl
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
DEFAULT_TTL_H = 168.0
DEFAULT_TMP_TTL_H = 6.0
# Temp dir names that only this repo's tests create (mktemp / mkdtemp templates; test_scratch_cleanup.sh checks every one
# against the repo). Never a generic name (tmp.*, Python's tmpXXXX) and never a production prefix (agpm-run-, agpm-oracle-).
TEST_TMP_PREFIXES = (
    "agpm-test-", "agpm-s-", "agpm-shot-", "agpm-src-", "agpm-home-", "agpm-state-home-", "agpm-agy-", "agpm-r2-", "agpm-ev-",
    "agpm-reg-", "agpm-space-",
    "hookharness.", "hookgr.", "hookgrok.", "hookgradle.", "hookrestore.", "hookctx.", "hookte.", "hooktef.", "hookteo.",
    "hooketr.", "hookrgweb.", "hooknode.", "hookwg.",
    "devkit-reinit-", "devkit-idem-", "devkit-gi-hooks-", "install-alias.", "install-user-data.", "install-claude-only.",
    "install-cli-test.", "uninstall-test.", "uninstall-leftovers.", "proofbefore.", "proofturn.", "gitguard.", "gitguardnest.",
    "sb-ghread-test.", "sb-runner-test.", "sb-mergegate-test.", "sb-postmerge-test.", "sb-scratchclean-test.",
)


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


def remove(root, slug, name, why, log_root=None):
    """rmtree <root>/<slug>/<name> without following a symlink anywhere on the way, even one swapped in after the listing.
    The line goes to <log_root or root>/devkit-scratch-cleanup.log."""
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
        with open(os.path.join(log_root or root, "devkit-scratch-cleanup.log"), "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError as e:
        print("scratch_cleanup: cannot write the log: %s" % e, file=sys.stderr)
    if errors:
        print("scratch_cleanup: " + line, file=sys.stderr)


def test_tmp_root():
    """$TMPDIR (DEVKIT_TEST_TMP_ROOT in tests) when it is a real directory of this user, else None."""
    r = (os.environ.get("DEVKIT_TEST_TMP_ROOT") or os.environ.get("TMPDIR") or tempfile.gettempdir()).rstrip("/")
    try:
        st = os.lstat(r)
    except OSError:
        return None
    return r if stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() else None


def held_names(root):
    """Names of the entries of root that a process of this user holds (an open file or its cwd somewhere inside), from one
    lsof snapshot; None when lsof gives no answer (then nothing can be proven free)."""
    lsof = os.environ.get("DEVKIT_LSOF") or shutil.which("lsof") or "/usr/sbin/lsof"
    try:
        r = subprocess.run([lsof, "-nPw", "-u", str(os.getuid()), "-Fn"], capture_output=True, text=True,
                           errors="replace", timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode not in (0, 1) or not r.stdout.strip():
        return None
    pre = os.path.realpath(root) + "/"
    return {line[1 + len(pre):].split("/", 1)[0] for line in r.stdout.splitlines() if line.startswith("n" + pre)}


def inspect_tree(path):
    """(newest mtime in the whole tree, bytes, worktree registrations <admin>/worktrees/<name> outside it for a worktree
    inside it), or None when it is gone or a level cannot be read (never remove what cannot be judged)."""
    try:
        newest = os.lstat(path).st_mtime
    except OSError:
        return None
    size, admins, base, unreadable = 0, set(), os.path.realpath(path) + "/", []
    for dp, dns, fns in os.walk(path, onerror=unreadable.append):
        for n in dns + fns:
            with contextlib.suppress(OSError):
                st = os.lstat(os.path.join(dp, n))
                newest, size = max(newest, st.st_mtime), size + st.st_blocks * 512
        if ".git" in fns:   # a linked worktree: .git is a file "gitdir: <admin>/.git/worktrees/<name>"
            with contextlib.suppress(OSError, UnicodeDecodeError):
                with open(os.path.join(dp, ".git"), encoding="utf-8") as f:
                    line = f.readline().strip()
                if line.startswith("gitdir: "):
                    gd = os.path.realpath(os.path.join(dp, line[8:]))
                    if os.path.basename(os.path.dirname(gd)) == "worktrees" and not (gd + "/").startswith(base):
                        admins.add(gd)
    return None if unreadable else (newest, size, admins)


def drop_registration(gd, removed):
    """After `removed` is gone, delete the one registration <admin>/worktrees/<name> whose gitdir file points into it — what
    `git worktree prune` does for that entry alone, never for the admin repo's other worktrees; a locked one is kept."""
    try:
        with open(os.path.join(gd, "gitdir"), encoding="utf-8") as f:
            target = os.path.realpath(os.path.join(gd, f.readline().strip()))   # git writes it absolute; relative: to gd
    except (OSError, UnicodeDecodeError):
        return
    if os.path.exists(os.path.join(gd, "locked")) or os.path.lexists(target):
        return
    if (target + "/").startswith(os.path.realpath(removed) + "/"):
        shutil.rmtree(gd, ignore_errors=True)


def make_removable(path):
    """Clear the immutable flags (INSTINCT-038) and give this user rwx on the dirs of a proven leftover, itself included,
    so rmtree can empty read-only fixture dirs. Symlinks inside are not followed; a leftover found a symlink is skipped.
    ponytail: a same-uid swap between that check and the walk could chmod another tree of this user (remove() still
    refuses it), move to os.fwalk on an O_NOFOLLOW fd if TMPDIR is ever shared."""
    def unlock(p, is_dir):
        with contextlib.suppress(OSError, NotImplementedError, AttributeError):   # no chflags on Linux: nothing to clear
            os.chflags(p, 0, follow_symlinks=False)
        if is_dir and real_dir(p):   # a real dir (never a symlink): plain chmod, Linux has no lchmod
            with contextlib.suppress(OSError):
                os.chmod(p, stat.S_IRWXU)

    if not real_dir(path):
        return
    unlock(path, True)
    for dp, dns, fns in os.walk(path):
        for n in dns + fns:
            unlock(os.path.join(dp, n), n in dns)


def claim_hour(stamp):
    """True when this process takes the hourly sweep slot. The stamp holds the time of the last claimed sweep and is read
    and rewritten under flock BEFORE lsof runs, so a burst of SessionStarts (super-board workers) runs one lsof, not one
    each. A stamp that cannot be opened or written (full disk, read-only root) loses the throttle, never the sweep: True.
    ponytail: a sweep whose lsof then fails still used its hour, fine while SessionStart is the only trigger."""
    try:
        fd = os.open(stamp, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as e:
        print("scratch_cleanup: sweep stamp unusable (%s), sweeping without the hourly limit" % e, file=sys.stderr)
        return True
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)   # held for a read and a write only: never long
        try:
            last = float(os.read(fd, 64).decode("ascii", "replace").strip())
        except ValueError:
            last = 0.0   # the empty stamp of the first version, or junk: no claim on record
        now = time.time()
        if 0 <= now - last < 3600:
            return False
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, ("%f" % now).encode("ascii"))
        return True
    except OSError as e:
        print("scratch_cleanup: sweep stamp unusable (%s), sweeping without the hourly limit" % e, file=sys.stderr)
        return True
    finally:
        os.close(fd)


def sweep_test_tmp(ttl_h, scratch, rate_limited=False):
    """Remove the stale temp dirs this repo's tests leave in $TMPDIR when they are killed before their EXIT trap."""
    root = test_tmp_root()
    if root is None:
        return
    log_root = scratch or root
    try:
        names = [n for n in os.listdir(root) if n.startswith(TEST_TMP_PREFIXES)]
    except OSError:
        return
    if not names:
        return
    # SessionStart: many sessions start (super-board workers), one sweep (one lsof) an hour is enough
    if rate_limited and not claim_hour(os.path.join(log_root, ".devkit-test-tmp-sweep")):
        return
    held = held_names(root)
    if held is None:
        print("scratch_cleanup: lsof gave no answer, test temp sweep skipped", file=sys.stderr)
        return
    cutoff, swept, freed = time.time() - ttl_h * 3600, 0, 0
    for name in names:
        path = os.path.join(root, name)
        try:
            st = os.lstat(path)
        except OSError:
            continue
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or name in held:
            continue
        info = inspect_tree(path)
        if info is None or info[0] >= cutoff:
            continue
        make_removable(path)
        remove(os.path.dirname(root), os.path.basename(root), name, "stale test temp > %g h" % ttl_h, log_root)
        if os.path.lexists(path):
            continue
        swept, freed = swept + 1, freed + info[1]
        for gd in info[2]:   # its registration in an admin repo elsewhere: the folder is gone, drop that entry
            drop_registration(gd, path)
    if swept:
        print("scratch_cleanup: swept %d stale test temp dir(s), %.2f GiB" % (swept, freed / 2 ** 30))


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
    tmp_ttl = opt("--tmp-ttl-hours")
    prune, sweep_only = "--prune" in args, "--sweep-tmp" in args
    if [end is not None, prune, sweep_only].count(True) != 1 or (end is not None and not UUID.match(end)):
        print(__doc__.strip().splitlines()[6].strip(), file=sys.stderr)
        return 2
    try:
        ttl_h = float(ttl) if ttl is not None else DEFAULT_TTL_H
        tmp_ttl_h = float(tmp_ttl) if tmp_ttl is not None else DEFAULT_TMP_TTL_H
        self_pid = int(self_pid) if self_pid else None
    except ValueError:
        return 2
    if not 0 <= tmp_ttl_h < float("inf"):   # nan / negative would make every unheld prefixed dir "stale"
        return 2
    root = scratch_root()
    if prune or sweep_only:
        sweep_test_tmp(tmp_ttl_h, root, rate_limited=prune)
    if root is None or sweep_only:
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
