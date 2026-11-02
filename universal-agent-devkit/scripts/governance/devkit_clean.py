#!/usr/bin/env python3
"""devkit_clean.py — dọn các file và thư mục runtime quá hạn do DevKit và super-board sinh ra trong dự án.

Cách dùng: devkit_clean.py [project_dir] [--days=N] [--apply] [--old-installs] [--keep-state]
           (thường gọi qua `agent-kit clean [path] [--days=N] [--apply] [--old-installs]`)

Mặc định chạy thử (dry-run) trừ khi có `--apply`. Các vùng runtime được dọn:
  <project>/.claude/audit-gate/
    * file và thư mục cũ hơn `--days` (mặc định 14): log của hook, trạng thái theo phiên,
      bản sao restore-backup/<time>/, bằng chứng adb-safe-exec/ (log, tombstone), file cache wg_scan/
    * file log mới hơn ngưỡng nhưng vượt 5 MB sẽ được cắt gọn giữ lại 1000 dòng cuối
    * trần dung lượng: nếu phần còn lại vẫn trên 3 MB, các file .log/.jsonl/.tsv lớn nhất trên
      1000 dòng được cắt còn 1000 dòng cuối, sau đó xoá dần file marker phiên nhàn rỗi quá 6 giờ
      từ cũ nhất (cùng cache wg_scan/ nhàn rỗi) cho tới khi dưới trần (backup, lock, file state
      và thư mục phiên không bao giờ bị xoá ở bước trần)
    * `--keep-state`: giữ nguyên *.json, *.state và .testsourceset_attempts* ở cấp trên cùng (bộ nhớ gate, `owed`)
    * `.gitignore` luôn được giữ lại
  `--old-installs`: dọn thêm `~/.universal-agent-devkit.old-*` cũ hơn `--days`.
  File rác runtime của super-board cũ hơn `--days`:
    * `<git-common-dir>/super-board/last-merge-verify-pr-*.log`
    * `<project>/.claude/super-board/last-merge-verify-pr-*.log` (khi đã gitignore và untracked)
    * `<project>/docs/super-board/runs/*-workers/` (khi đã gitignore và untracked, trừ các thư mục `YYYY-MM-DD-*-workers` của hôm nay)
Không bao giờ chạm tới: mã nguồn, `.agents/` (profile, instincts, regression checklist),
`.claude/settings.json`, hooks, commands, bất kỳ file tracked nào, hoặc `git objects/refs/index`.
"""

import contextlib
import errno
import fnmatch
import os
import shutil
import stat
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402

MAX_LOG = 5 * 1024 * 1024
AUDIT_CAP = 3 * 1024 * 1024   # file blocks only, after the age pass: `du` also counts directory blocks, so 2 MB of headroom under the 5 MB acceptance line
LOG_EXTS = (".log", ".jsonl", ".tsv")
KEEP_LINES = 1000
# Per-session markers the hooks drop (<prefix><session id>): safe to remove once idle. Matched by NAME, never "everything
# that is not .json/.lock": worktree_merge_gate.state (holds `owed`), proof_gate.state and .testsourceset_attempts* are gate memory.
MARKER_PATTERNS = ("prompt_seen_*", "untracked_edit.*", "*_stopchain_*", "*_shown_*", "context_note_*",
                   "lesson_reminded_*", "buglink_reminded_*", "review_attempts_*", "security_gate_attempts_*")


def is_marker(path):
    return any(fnmatch.fnmatch(os.path.basename(path), pat) for pat in MARKER_PATTERNS)


def is_state(path):
    """Gate memory exempt from --keep-state: *.json, *.state, .testsourceset_attempts*."""
    name = os.path.basename(path)
    return os.path.isfile(path) and (name.endswith((".json", ".state")) or name.startswith(".testsourceset_attempts"))


def size_of(path):
    try:
        if os.path.isfile(path) or os.path.islink(path):
            return os.lstat(path).st_size
    except OSError:
        return 0
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def newest_mtime(path):
    """Tuổi của thư mục tính theo file mới nhất (và thư mục con rỗng mới tạo) bên trong; trả inf nếu đường dẫn biến mất."""
    try:
        if not os.path.isdir(path) or os.path.islink(path):
            return os.lstat(path).st_mtime
    except OSError:
        return float("inf")
    newest = None
    for root, dirs, files in os.walk(path):
        for f in files:
            try:
                m = os.lstat(os.path.join(root, f)).st_mtime
                newest = m if newest is None else max(newest, m)
            except OSError:
                pass
        for d in dirs:
            dp = os.path.join(root, d)
            try:
                st = os.lstat(dp)
                if stat.S_ISDIR(st.st_mode) and not os.listdir(dp):
                    newest = st.st_mtime if newest is None else max(newest, st.st_mtime)
            except OSError:
                pass
    if newest is not None:
        return newest
    try:
        return os.lstat(path).st_mtime
    except OSError:
        return float("inf")


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def tail_bytes(path):
    """(lines, bytes of the last KEEP_LINES lines) of a log."""
    try:
        with open(path, "rb") as f:
            lines = f.read().splitlines(keepends=True)
    except OSError:
        return 0, 0
    return len(lines), sum(len(x) for x in lines[-KEEP_LINES:])


def disk_size(path):
    """Allocated bytes (what `du` reports): 1400 small state files count 4 KB each, not their few bytes."""
    try:
        if not os.path.isdir(path) or os.path.islink(path):
            return os.lstat(path).st_blocks * 512
    except OSError:
        return 0
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_blocks * 512
            except OSError:
                pass
    return total


def _listdir_safe(path, *, sort_names=True):
    """Đọc mục con của thư mục; bỏ qua im lặng FileNotFoundError đua tranh và ghi lỗi đọc khác ra stderr."""
    try:
        names = os.listdir(path)
    except FileNotFoundError:
        return []
    except OSError as e:
        print(f"clean: cannot read {path}: {e}", file=sys.stderr)
        return []
    return sorted(names) if sort_names else names


def cap_plan(audit, planned):
    """Extra trims that bring audit-gate under AUDIT_CAP after `planned` ran: fresh logs have no age to clean by.

    Log tails are cut first, then per-session marker files idle for 6 hours, oldest first (every size is
    allocated bytes, as `du` counts). Backups, flock files, session dirs and state *.json are live data:
    never removed here, so a folder they fill alone stays over the cap. Markers are matched by name (MARKER_PATTERNS).
    """
    gone = {p: a for a, p, _ in planned}
    raw_names = _listdir_safe(audit)
    if not raw_names:
        return []
    entries = [os.path.join(audit, n) for n in raw_names if n != ".gitignore"]
    entries = [p for p in entries if gone.get(p) != "remove"]
    logs = {}   # path -> (allocated bytes now, allocated bytes after a trim)
    total = 0
    for p in entries:
        size = disk_size(p)
        if p.endswith(LOG_EXTS) and os.path.isfile(p) and not os.path.islink(p):
            lines, tail = tail_bytes(p)
            if gone.get(p) == "trim":
                size = -(-tail // 4096) * 4096   # the age pass trims it first
            elif lines > KEEP_LINES:
                logs[p] = (size, -(-tail // 4096) * 4096)
        total += size
    out = []
    for path in sorted(logs, key=lambda p: -logs[p][0]):
        if total <= AUDIT_CAP:
            break
        out.append(("trim", path, logs[path][0])); total -= logs[path][0] - logs[path][1]
    stale = time.time() - 6 * 3600   # per-session markers (prompt_seen_<sid>, untracked_edit.<sid>): 6 h idle = the session is over
    markers = []
    for p in entries:
        if os.path.isfile(p) and not os.path.islink(p) and is_marker(p) and not p.endswith(LOG_EXTS) and gone.get(p) != "trim":
            with contextlib.suppress(OSError):
                m = os.lstat(p).st_mtime
                if m < stale:
                    markers.append((m, p))
    wg = os.path.join(audit, "wg_scan")   # worktree_guard's incremental scan cache: a miss only rescans
    if os.path.isdir(wg) and not os.path.islink(wg):
        for n in _listdir_safe(wg, sort_names=False):
            q = os.path.join(wg, n)
            if os.path.isfile(q) and not os.path.islink(q) and gone.get(q) != "remove":
                with contextlib.suppress(OSError):
                    m = os.lstat(q).st_mtime
                    if m < stale:
                        markers.append((m, q))
    for _, path in sorted(markers, key=lambda item: item[0]):
        if total <= AUDIT_CAP:
            break
        size = disk_size(path)
        out.append(("remove", path, size)); total -= size
    return out


def _clean_git_env():
    """Tạo môi trường sạch không chứa biến GIT_* ngoại lai và khoá cấu hình global/system để lệnh git chỉ đọc đúng repo đích."""
    env = {k: v for k, v in os.environ.items() if not (k.startswith("GIT_") and k != "GIT_EXEC_PATH")}
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_OPTIONAL_LOCKS"] = "0"
    return env


def _git_common_dir(project):
    """Xác định thư mục git chung (.git trực tiếp hoặc commondir của worktree liên kết) để tìm log runtime của super-board."""
    dot_git = os.path.join(project, ".git")
    if os.path.isdir(dot_git) and not os.path.islink(dot_git):
        return dot_git
    if os.path.isfile(dot_git) and not os.path.islink(dot_git):
        try:
            r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", project, "rev-parse", "--git-common-dir"],
                               env=_clean_git_env(), capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=10)
            if r.returncode == 0 and r.stdout.strip():
                gd = os.path.abspath(os.path.join(os.path.realpath(project), r.stdout.strip()))
                if os.path.isdir(gd) and not os.path.islink(gd):
                    return gd
        except (OSError, subprocess.SubprocessError) as e:
            print(f"clean: cannot resolve git-common-dir for {project}: {e}", file=sys.stderr)
    return None


def _git_ignored_untracked(project, relpath):
    """Chỉ cho phép xoá đường dẫn trong cây làm việc khi git của chính repo xác nhận vừa nằm trong .gitignore vừa không chứa file tracked/unignored."""
    git_env = _clean_git_env()
    try:
        ig = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", project, "check-ignore", "--no-index", "-q", "--", relpath],
                            env=git_env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10)
        if ig.returncode != 0:
            return False
        tr_files = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", project, "ls-files", "--cached", "--others", "--exclude-standard", "--", relpath],
                                  env=git_env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10)
        return tr_files.returncode == 0 and tr_files.stdout.strip() == ""
    except (OSError, subprocess.SubprocessError):
        return False


def super_board_plan(project, cutoff):
    # #547: dọn các file log verify và thư mục *-workers đã gitignore của super-board quá hạn --days, giữ nguyên ngày hôm nay và file tracked.
    out = []
    gdir = _git_common_dir(project)
    if gdir:
        gsb = os.path.join(gdir, "super-board")
        if os.path.isdir(gsb) and not os.path.islink(gsb):
            for name in _listdir_safe(gsb):
                if fnmatch.fnmatch(name, "last-merge-verify-pr-*.log"):
                    p = os.path.join(gsb, name)
                    if os.path.isfile(p) and not os.path.islink(p) and newest_mtime(p) < cutoff:
                        out.append(("remove", p, size_of(p)))
    csb = os.path.join(project, ".claude", "super-board")
    if os.path.isdir(csb) and not os.path.islink(csb):
        for name in _listdir_safe(csb):
            if fnmatch.fnmatch(name, "last-merge-verify-pr-*.log"):
                p = os.path.join(csb, name)
                rel = os.path.relpath(p, project)
                if os.path.isfile(p) and not os.path.islink(p) and newest_mtime(p) < cutoff and _git_ignored_untracked(project, rel):
                    out.append(("remove", p, size_of(p)))
    runs = os.path.join(project, "docs", "super-board", "runs")
    # super-board-run.sh đặt tên YYYY-MM-DD-<slug>-workers (hoặc YYYY-MM-DD-workers): giữ mọi thư mục *-workers của ngày hôm nay.
    today_prefix = time.strftime("%Y-%m-%d") + "-"
    if os.path.isdir(runs) and not os.path.islink(runs):
        for name in _listdir_safe(runs):
            if not name.endswith("-workers") or name.startswith(today_prefix):
                continue
            p = os.path.join(runs, name)
            rel = os.path.relpath(p, project)
            if os.path.isdir(p) and not os.path.islink(p) and newest_mtime(p) < cutoff and _git_ignored_untracked(project, rel):
                out.append(("remove", p, size_of(p)))
    return out


def plan(project, days, old_installs, keep_state=False):
    """[(action, path, bytes)] with action "remove" or "trim"."""
    cutoff = time.time() - days * 86400
    out = []
    audit = os.path.join(project, ".claude", "audit-gate")
    if os.path.isdir(audit) and not os.path.islink(audit):
        candidates = []
        for name in _listdir_safe(audit):
            if name == ".gitignore":
                continue
            path = os.path.join(audit, name)
            if name in ("restore-backup", "adb-safe-exec", "wg_scan") and os.path.isdir(path) and not os.path.islink(path):
                candidates += [os.path.join(path, n) for n in _listdir_safe(path)]
            else:
                candidates.append(path)
        if keep_state:   # the gates' own memory (verified_head, approvals) is not a log: no age limit
            candidates = [p for p in candidates if not is_state(p)]
        for path in candidates:
            if newest_mtime(path) < cutoff:
                out.append(("remove", path, size_of(path)))
            elif path.endswith(".log") and os.path.isfile(path) and not os.path.islink(path):
                with contextlib.suppress(OSError):
                    sz = os.path.getsize(path)
                    if sz > MAX_LOG:
                        out.append(("trim", path, sz))
        out += cap_plan(audit, out)
    out += super_board_plan(project, cutoff)
    if old_installs:
        home = os.path.expanduser("~")
        for name in _listdir_safe(home):
            path = os.path.join(home, name)
            if name.startswith(".universal-agent-devkit.old-") and newest_mtime(path) < cutoff:
                out.append(("remove", path, size_of(path)))
    return out


def trim(path):
    with open(path, "rb") as f:
        lines = f.read().splitlines(keepends=True)
    with open(path, "wb") as f:
        f.writelines(lines[-KEEP_LINES:])


def _rmtree_runtime_dir(path):
    """Xoá thư mục runtime quá hạn, mở quyền rwx trên thư mục con thật thuộc cùng uid nếu chỉ đọc và bỏ qua FileNotFoundError đua tranh."""
    uid = os.getuid()
    with contextlib.suppress(OSError):
        st = os.lstat(path)
        if stat.S_ISDIR(st.st_mode) and st.st_uid == uid:
            os.chmod(path, stat.S_IRWXU)
    for dp, dns, _ in os.walk(path):
        for n in dns:
            sub = os.path.join(dp, n)
            with contextlib.suppress(OSError):
                st = os.lstat(sub)
                if stat.S_ISDIR(st.st_mode) and st.st_uid == uid:
                    os.chmod(sub, stat.S_IRWXU)

    def _handle_err(fn, p, exc_val):
        if isinstance(exc_val, FileNotFoundError):
            return
        raise exc_val

    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=_handle_err)
    else:
        shutil.rmtree(path, onerror=lambda fn, p, exc_info: _handle_err(fn, p, exc_info[1]))


def main(argv):
    apply = "--apply" in argv
    old_installs = "--old-installs" in argv
    keep_state = "--keep-state" in argv
    days = 14
    rest = []
    for a in argv[1:]:
        if a.startswith("--days="):
            try:
                days = max(0, int(a.split("=", 1)[1]))
            except ValueError:
                sys.stderr.write("clean: --days needs a whole number\n")
                return 2
        elif a in ("--apply", "--old-installs", "--keep-state"):
            continue
        elif a.startswith("-"):
            sys.stderr.write(f"clean: unknown option '{a}' (--days=N, --apply, --old-installs, --keep-state)\n")
            return 2
        else:
            rest.append(a)
    project = os.path.abspath(rest[0] if rest else os.getcwd())
    set_lang(resolve_lang(None, project))
    items = plan(project, days, old_installs, keep_state)
    mode = tr("xoá thật", "apply") if apply else tr("chạy thử — thêm --apply để xoá", "dry-run — add --apply to delete")
    print(f"clean: {project} ({tr('cũ hơn', 'older than')} {days} {tr('ngày', 'days')}, {mode})")
    freed = 0
    for action, path, nbytes in items:
        shown = os.path.relpath(path, project) if path.startswith(project + os.sep) else path
        if action == "trim":
            verb = tr("đã cắt", "trimmed") if apply else tr("sẽ cắt", "would trim")
            print(f"  {verb:<10} {shown} ({human(nbytes)} → {tr('giữ', 'keep')} {KEEP_LINES} {tr('dòng cuối', 'last lines')})")
            if apply:
                with contextlib.suppress(FileNotFoundError):
                    try:
                        before = os.path.getsize(path)
                        trim(path)
                        freed += before - os.path.getsize(path)
                    except OSError as e:
                        print(f"clean: cannot trim {shown}: {e}", file=sys.stderr)
            continue
        verb = tr("đã xoá", "removed") if apply else tr("sẽ xoá", "would remove")
        print(f"  {verb:<10} {shown} ({human(nbytes)})")
        if apply:
            # Bỏ qua FileNotFoundError khi hai worktree/phiên cùng dọn đồng thời một mục runtime chung; ghi nhận lỗi lẻ mà không ngắt vòng lặp.
            try:
                if os.path.isdir(path) and not os.path.islink(path):
                    _rmtree_runtime_dir(path)
                else:
                    os.unlink(path)
                freed += nbytes
            except FileNotFoundError:
                pass
            except OSError as e:
                print(f"clean: cannot remove {shown}: {e}", file=sys.stderr)
        else:
            freed += nbytes
    if apply:  # xoá luôn thư mục vỏ rỗng sau khi dọn; chỉ im lặng với FileNotFoundError và ENOTEMPTY
        for sub in ("restore-backup", "adb-safe-exec"):
            d = os.path.join(project, ".claude", "audit-gate", sub)
            if os.path.isdir(d) and not os.path.islink(d):
                try:
                    os.rmdir(d)
                except FileNotFoundError:
                    pass
                except OSError as e:
                    if e.errno != errno.ENOTEMPTY:
                        print(f"clean: cannot remove {d}: {e}", file=sys.stderr)
    if not items:
        print("  " + tr("không có gì để dọn", "nothing to clean"))
    print(f"clean: {len(items)} {tr('mục', 'items')}, {human(freed)} "
          + (tr("đã giải phóng", "freed") if apply else tr("sẽ được giải phóng", "would be freed")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
