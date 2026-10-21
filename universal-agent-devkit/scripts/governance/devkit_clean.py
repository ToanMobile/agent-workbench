#!/usr/bin/env python3
"""devkit_clean.py — remove the DevKit's own runtime leftovers from a project.

Usage: devkit_clean.py [project_dir] [--days=N] [--apply] [--old-installs] [--keep-state]
       (normally `agent-kit clean [path] [--days=N] [--apply] [--old-installs]`)

Dry-run unless --apply. Only the hooks' working area is touched:
  <project>/.claude/audit-gate/
    * files and folders older than --days (default 14): hook logs and per-session
      state, restore-backup/<time>/ copies, adb-safe-exec/ evidence (logs, tombstones),
      wg_scan/ cache files
    * a log newer than that but over 5 MB is trimmed to its last 1000 lines
    * size cap: if what is left is still over 3 MB, the biggest .log/.jsonl/.tsv files over
      1000 lines are trimmed to their last 1000 lines, then per-session marker files idle for 6 hours are
      removed oldest first (plus idle wg_scan/ cache files), until it fits (backups, locks, state
      *.json, session dirs are never touched)
    * --keep-state: top-level *.json (gate state, approvals) is exempt from the age pass
    * .gitignore is always kept
  --old-installs: also ~/.universal-agent-devkit.old-* (copies quick-install moved
  aside) older than --days.
Never touched: source code, .agents/ (project tier, instincts, regression checklist),
.claude/settings.json, hooks, commands, git data.
"""

import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402

MAX_LOG = 5 * 1024 * 1024
AUDIT_CAP = 3 * 1024 * 1024   # file blocks only, after the age pass: `du` also counts directory blocks, so 2 MB of headroom under the 5 MB acceptance line
LOG_EXTS = (".log", ".jsonl", ".tsv")
KEEP_LINES = 1000


def size_of(path):
    if os.path.isfile(path) or os.path.islink(path):
        return os.lstat(path).st_size
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def newest_mtime(path):
    """A folder is as old as the newest file inside it."""
    if not os.path.isdir(path) or os.path.islink(path):
        return os.lstat(path).st_mtime
    newest = None
    for root, _, files in os.walk(path):
        for f in files:
            try:
                m = os.lstat(os.path.join(root, f)).st_mtime
                newest = m if newest is None else max(newest, m)
            except OSError:
                pass
    return newest if newest is not None else os.lstat(path).st_mtime  # empty folder


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def tail_bytes(path):
    """(lines, bytes of the last KEEP_LINES lines) of a log."""
    with open(path, "rb") as f:
        lines = f.read().splitlines(keepends=True)
    return len(lines), sum(len(x) for x in lines[-KEEP_LINES:])


def disk_size(path):
    """Allocated bytes (what `du` reports): 1400 small state files count 4 KB each, not their few bytes."""
    if not os.path.isdir(path) or os.path.islink(path):
        return os.lstat(path).st_blocks * 512
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_blocks * 512
            except OSError:
                pass
    return total


def cap_plan(audit, planned):
    """Extra trims that bring audit-gate under AUDIT_CAP after `planned` ran: fresh logs have no age to clean by.

    Log tails are cut first, then per-session marker files idle for 6 hours, oldest first (every size is
    allocated bytes, as `du` counts). Backups, flock files, session dirs and state *.json are live data:
    never removed here, so a folder they fill alone stays over the cap.
    """
    gone = {p: a for a, p, _ in planned}
    entries = [os.path.join(audit, n) for n in sorted(os.listdir(audit)) if n != ".gitignore"]
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
    markers = [p for p in entries if os.path.isfile(p) and not os.path.islink(p) and not p.endswith(LOG_EXTS + (".json", ".lock"))
               and os.lstat(p).st_mtime < stale and gone.get(p) != "trim"]
    wg = os.path.join(audit, "wg_scan")   # worktree_guard's incremental scan cache: a miss only rescans
    if os.path.isdir(wg) and not os.path.islink(wg):
        markers += [q for q in (os.path.join(wg, n) for n in os.listdir(wg))
                    if os.path.isfile(q) and not os.path.islink(q) and os.lstat(q).st_mtime < stale and gone.get(q) != "remove"]
    for path in sorted(markers, key=lambda p: os.lstat(p).st_mtime):
        if total <= AUDIT_CAP:
            break
        size = disk_size(path)
        out.append(("remove", path, size)); total -= size
    return out


def plan(project, days, old_installs, keep_state=False):
    """[(action, path, bytes)] with action "remove" or "trim"."""
    cutoff = time.time() - days * 86400
    out = []
    audit = os.path.join(project, ".claude", "audit-gate")
    if os.path.isdir(audit) and not os.path.islink(audit):
        candidates = []
        for name in sorted(os.listdir(audit)):
            if name == ".gitignore":
                continue
            path = os.path.join(audit, name)
            if name in ("restore-backup", "adb-safe-exec", "wg_scan") and os.path.isdir(path) and not os.path.islink(path):
                candidates += [os.path.join(path, n) for n in sorted(os.listdir(path))]
            else:
                candidates.append(path)
        if keep_state:   # the gates' own memory (verified_head, approvals) is not a log: no age limit
            candidates = [p for p in candidates if not (p.endswith(".json") and os.path.isfile(p))]
        for path in candidates:
            if newest_mtime(path) < cutoff:
                out.append(("remove", path, size_of(path)))
            elif path.endswith(".log") and os.path.isfile(path) and os.path.getsize(path) > MAX_LOG:
                out.append(("trim", path, os.path.getsize(path)))
        out += cap_plan(audit, out)
    if old_installs:
        home = os.path.expanduser("~")
        for name in sorted(os.listdir(home)):
            path = os.path.join(home, name)
            if name.startswith(".universal-agent-devkit.old-") and newest_mtime(path) < cutoff:
                out.append(("remove", path, size_of(path)))
    return out


def trim(path):
    with open(path, "rb") as f:
        lines = f.read().splitlines(keepends=True)
    with open(path, "wb") as f:
        f.writelines(lines[-KEEP_LINES:])


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
                before = os.path.getsize(path); trim(path); freed += before - os.path.getsize(path)
            continue
        verb = tr("đã xoá", "removed") if apply else tr("sẽ xoá", "would remove")
        print(f"  {verb:<10} {shown} ({human(nbytes)})")
        if apply:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
            freed += nbytes
        else:
            freed += nbytes
    if apply:  # containers left empty by the clean-up go too
        for sub in ("restore-backup", "adb-safe-exec"):
            d = os.path.join(project, ".claude", "audit-gate", sub)
            if os.path.isdir(d) and not os.path.islink(d) and not os.listdir(d):
                os.rmdir(d)
    if not items:
        print("  " + tr("không có gì để dọn", "nothing to clean"))
    print(f"clean: {len(items)} {tr('mục', 'items')}, {human(freed)} "
          + (tr("đã giải phóng", "freed") if apply else tr("sẽ được giải phóng", "would be freed")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
