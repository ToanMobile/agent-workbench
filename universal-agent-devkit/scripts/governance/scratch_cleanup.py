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
    "dk-",
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


_UNSET = object()


def _owned_real_dir(p):
    """Kiểm tra đường dẫn là thư mục thật (không phải symlink) và thuộc đúng uid hiện tại."""
    if not p:
        return False
    try:
        st = os.lstat(p)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid()


def _safe_log_root(scratch, root=None):
    """Chọn thư mục ghi log/stamp thuộc riêng uid hiện tại; tuyệt đối không dùng thư mục /private/tmp dùng chung."""
    for cand in (scratch, root, claude_home()):
        if _owned_real_dir(cand):
            return cand
    return None


def _append_log(log_root, line):
    """Ghi nối an toàn một dòng vào devkit-scratch-cleanup.log với O_NOFOLLOW và kiểm tra chủ sở hữu."""
    if not log_root:
        return
    log_path = os.path.join(log_root, "devkit-scratch-cleanup.log")
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(log_path, flags, 0o600)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                return
            os.write(fd, (line + "\n").encode("utf-8", "replace"))
        finally:
            os.close(fd)
    except OSError as e:
        print("scratch_cleanup: cannot write the log: %s" % e, file=sys.stderr)


def remove(root, slug, name, why, log_root=_UNSET, expected_stat=None):
    """rmtree <root>/<slug>/<name> without following a symlink anywhere on the way, even one swapped in after the listing.
    The line goes to <log_root or root>/devkit-scratch-cleanup.log."""
    path, errors, fds = os.path.join(root, slug, name), [], []
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW
    try:
        fds.append(os.open(root, flags))
        fds.append(os.open(slug, flags, dir_fd=fds[0]))
        st = os.fstat(fds[1])
        entry_st = os.lstat(name, dir_fd=fds[1])
        # Cho phép thư mục cha thuộc user hiện tại hoặc là thư mục tạm hệ thống có sticky bit (như /private/tmp trên macOS),
        # nhưng mục con bị xoá BẮT BUỘC phải là thư mục thật thuộc đúng uid hiện tại (và khớp đúng inode đã kiểm định nếu có).
        parent_ok = st.st_uid == os.getuid() or (st.st_uid == 0 and bool(st.st_mode & stat.S_ISVTX))
        if not parent_ok or entry_st.st_uid != os.getuid() or not stat.S_ISDIR(entry_st.st_mode):
            return
        if expected_stat is not None and not os.path.samestat(expected_stat, entry_st):
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
    target_log = _safe_log_root(root) if log_root is _UNSET else log_root
    _append_log(target_log, line)
    if errors:
        print("scratch_cleanup: " + line, file=sys.stderr)


def test_tmp_root():
    """Trả về $TMPDIR (hoặc DEVKIT_TEST_TMP_ROOT trong test) khi là thư mục hợp lệ để quét tiền tố tạm của test."""
    explicit = os.environ.get("DEVKIT_TEST_TMP_ROOT")
    r = (explicit or os.environ.get("TMPDIR") or tempfile.gettempdir()).rstrip("/")
    if not explicit and r in ("/tmp", "/var/tmp"):
        r = os.path.realpath(r).rstrip("/")
    try:
        st = os.lstat(r)
    except OSError:
        return None
    owner_ok = st.st_uid == os.getuid() or (not explicit and st.st_uid == 0 and bool(st.st_mode & stat.S_ISVTX))
    return r if stat.S_ISDIR(st.st_mode) and owner_ok else None


def dk_tmp_root(primary_root):
    """Trả về thư mục /private/tmp (hoặc DEVKIT_DK_TMP_ROOT trong test) để quét riêng tiền tố dk-* khi khác với TMPDIR chính."""
    if "DEVKIT_DK_TMP_ROOT" in os.environ:
        cand = os.environ["DEVKIT_DK_TMP_ROOT"].strip().rstrip("/")
        if cand in ("/tmp", "/var/tmp"):
            cand = os.path.realpath(cand).rstrip("/")
    elif "DEVKIT_TEST_TMP_ROOT" in os.environ:
        return None
    else:
        cand = os.path.realpath("/tmp").rstrip("/")
    if not cand:
        return None
    try:
        st = os.lstat(cand)
    except OSError:
        return None
    owner_ok = st.st_uid == os.getuid() or (st.st_uid == 0 and bool(st.st_mode & stat.S_ISVTX))
    if not (stat.S_ISDIR(st.st_mode) and owner_ok):
        return None
    if primary_root and os.path.realpath(cand) == os.path.realpath(primary_root):
        return None
    return cand


def held_names_multi(roots):
    """Lấy tập tên mục con đang được tiến trình của user mở (file, cwd hoặc AF_UNIX socket) trong `roots` bằng MỘT lần gọi lsof."""
    lsof = os.environ.get("DEVKIT_LSOF") or shutil.which("lsof") or "/usr/sbin/lsof"
    try:
        r = subprocess.run([lsof, "-nPw", "-u", str(os.getuid()), "-Fn"], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode not in (0, 1) or not r.stdout.strip():
        return None
    lines = r.stdout.splitlines()
    if not any(line.startswith("p") for line in lines):
        return None
    out = {}
    for root in roots:
        real = os.path.realpath(root).rstrip("/")
        prefixes = {root.rstrip("/") + "/", real + "/"}
        # Trên macOS XNU, lsof báo đường dẫn AF_UNIX socket theo chuỗi bind gốc (/tmp/dk-...) thay vì /private/tmp/dk-...
        if real.startswith("/private/"):
            alias = real[len("/private"):]
            if alias and os.path.realpath(alias).rstrip("/") == real:
                prefixes.add(alias + "/")
        held = set()
        for line in lines:
            for pre in prefixes:
                if line.startswith("n" + pre):
                    name = line[1 + len(pre):].split("/", 1)[0]
                    if name:
                        held.add(name)
        out[root] = held
    return out


def held_names(root):
    """Trả về tập tên mục con trực tiếp trong `root` đang được tiến trình của user hiện tại giữ (file mở, cwd hoặc socket)
    từ một ảnh chụp lsof; trả về None khi lsof không phản hồi hợp lệ (khi đó không xoá gì để an toàn)."""
    res = held_names_multi([root])
    return None if res is None else res[root]


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
        if ".git" in fns:   # worktree liên kết: .git là file thường chứa dòng "gitdir: <admin>/.git/worktrees/<name>"
            git_p = os.path.join(dp, ".git")
            with contextlib.suppress(OSError, UnicodeDecodeError):
                git_st = os.lstat(git_p)
                if stat.S_ISREG(git_st.st_mode) and git_st.st_size <= 4096:
                    gfd = os.open(git_p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
                    try:
                        raw = os.read(gfd, 4096).decode("utf-8", "replace")
                    finally:
                        os.close(gfd)
                    line = raw.splitlines()[0].strip() if raw else ""
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
    """Gỡ cờ bất biến uchg (INSTINCT-038) và cấp lại quyền rwx cho thư mục thật của user hiện tại để rmtree dọn sạch thư mục chỉ đọc.
    Không bao giờ đi theo symlink; mở quyền thư mục trước và sau khi gỡ chflags để xử lý cả thư mục con 000/555 chứa file uchg.
    ponytail: hoán đổi cùng uid giữa lúc kiểm tra và lúc duyệt cây chỉ có thể chạm cây khác của cùng user (remove() kiểm tra samestat),
    nâng cấp sang os.fwalk hoàn toàn theo fd khi os.chflags hỗ trợ dir_fd."""
    def unlock(p, is_dir):
        if is_dir and _owned_real_dir(p):
            with contextlib.suppress(OSError):
                os.chmod(p, stat.S_IRWXU)
        with contextlib.suppress(OSError, NotImplementedError, AttributeError):
            os.chflags(p, 0, follow_symlinks=False)
        if is_dir and _owned_real_dir(p):
            with contextlib.suppress(OSError):
                os.chmod(p, stat.S_IRWXU)

    if not _owned_real_dir(path):
        return
    unlock(path, True)
    for dp, dns, fns in os.walk(path):
        for n in dns:
            unlock(os.path.join(dp, n), True)
        for n in fns:
            unlock(os.path.join(dp, n), False)


def claim_hour(stamp, window_s=3600):
    """Trả về True khi tiến trình hiện tại giành được lượt chạy trong cửa sổ `window_s` giây (mặc định 1 giờ).
    File `stamp` lưu mốc thời gian dưới khoá flock TRƯỚC khi tác vụ nặng chạy để một loạt SessionStart đồng thời chỉ chạy một lượt.
    Mở bằng O_NOFOLLOW và kiểm tra thuộc đúng uid hiện tại; nếu không mở/ghi được thì chỉ bỏ giới hạn tần suất (trả về True).
    ponytail: nếu tác vụ dọn bị giết giữa chừng thì lượt kế tiếp chờ hết cửa sổ `window_s` giây (--sweep-tmp thủ công vẫn quét ngay),
    chuyển sang ghi stamp sau khi hoàn tất kèm khoá riêng nếu thực tế gặp vấn đề."""
    if not stamp:
        return True
    try:
        fd = os.open(stamp, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    except OSError as e:
        print("scratch_cleanup: sweep stamp unusable (%s), sweeping without the hourly limit" % e, file=sys.stderr)
        return True
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
            print("scratch_cleanup: sweep stamp not an owned regular file, sweeping without the hourly limit", file=sys.stderr)
            return True
        fcntl.flock(fd, fcntl.LOCK_EX)   # chỉ giữ khoá trong lúc đọc và ghi mốc thời gian ngắn
        try:
            last = float(os.read(fd, 64).decode("ascii", "replace").strip())
        except ValueError:
            last = 0.0   # file rỗng từ phiên bản đầu hoặc dữ liệu hỏng: coi như chưa có lượt nhận trước đó
        now = time.time()
        if 0 <= now - last < window_s:
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
    """Xoá các thư mục tạm quá hạn do test bỏ sót trong $TMPDIR (mọi TEST_TMP_PREFIXES) và trong /private/tmp (riêng dk-*)."""
    root = test_tmp_root()
    dk_root = dk_tmp_root(root)
    targets = []
    if root is not None:
        targets.append((root, TEST_TMP_PREFIXES))
    if dk_root is not None:
        targets.append((dk_root, ("dk-",)))
    if not targets:
        return
    log_root = _safe_log_root(scratch, root)
    candidates = []
    for scan_root, prefixes in targets:
        try:
            names = [n for n in os.listdir(scan_root) if n.startswith(prefixes)]
        except OSError:
            continue
        if names:
            candidates.append((scan_root, names))
    if not candidates:
        return
    # SessionStart: nhiều phiên cùng khởi động (worker super-board), chỉ cần quét tối đa 1 lần (1 lsof) mỗi giờ.
    if rate_limited and log_root and not claim_hour(os.path.join(log_root, ".devkit-test-tmp-sweep")):
        return
    held_map = held_names_multi([scan_root for scan_root, _ in candidates])
    if held_map is None:
        print("scratch_cleanup: lsof gave no answer, test temp sweep skipped", file=sys.stderr)
        return
    cutoff, swept, freed = time.time() - ttl_h * 3600, 0, 0
    for scan_root, names in candidates:
        held = held_map.get(scan_root, set())
        # Giải quyết symlink hệ thống ở thư mục cha (ví dụ /tmp -> /private/tmp trên macOS) mà vẫn giữ kiểm tra O_NOFOLLOW trên chính scan_root.
        parent_dir = os.path.realpath(os.path.dirname(scan_root) or "/")
        scan_name = os.path.basename(scan_root)
        for name in names:
            path = os.path.join(scan_root, name)
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
            remove(parent_dir, scan_name, name, "stale test temp > %g h" % ttl_h,
                   log_root=log_root, expected_stat=st)
            if os.path.lexists(path):
                continue
            swept, freed = swept + 1, freed + info[1]
            for gd in info[2]:   # đăng ký worktree trong kho quản trị khác: thư mục đã xoá nên gỡ mục đăng ký tương ứng
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
