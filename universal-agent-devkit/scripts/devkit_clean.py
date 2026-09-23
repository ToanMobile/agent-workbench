#!/usr/bin/env python3
"""devkit_clean.py — remove the DevKit's own runtime leftovers from a project.

Usage: devkit_clean.py [project_dir] [--days=N] [--apply] [--old-installs]
       (normally `agent-kit clean [path] [--days=N] [--apply] [--old-installs]`)

Dry-run unless --apply. Only the hooks' working area is touched:
  <project>/.claude/audit-gate/
    * files and folders older than --days (default 14): hook logs and per-session
      state, restore-backup/<time>/ copies, adb-safe-exec/ evidence (logs, tombstones)
    * a log newer than that but over 5 MB is trimmed to its last 2000 lines
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
KEEP_LINES = 2000


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


def plan(project, days, old_installs):
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
            if name in ("restore-backup", "adb-safe-exec") and os.path.isdir(path) and not os.path.islink(path):
                candidates += [os.path.join(path, n) for n in sorted(os.listdir(path))]
            else:
                candidates.append(path)
        for path in candidates:
            if newest_mtime(path) < cutoff:
                out.append(("remove", path, size_of(path)))
            elif path.endswith(".log") and os.path.isfile(path) and os.path.getsize(path) > MAX_LOG:
                out.append(("trim", path, os.path.getsize(path)))
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
    days = 14
    rest = []
    for a in argv[1:]:
        if a.startswith("--days="):
            try:
                days = max(0, int(a.split("=", 1)[1]))
            except ValueError:
                sys.stderr.write("clean: --days needs a whole number\n")
                return 2
        elif a in ("--apply", "--old-installs"):
            continue
        elif a.startswith("-"):
            sys.stderr.write(f"clean: unknown option '{a}' (--days=N, --apply, --old-installs)\n")
            return 2
        else:
            rest.append(a)
    project = os.path.abspath(rest[0] if rest else os.getcwd())
    set_lang(resolve_lang(None, project))
    items = plan(project, days, old_installs)
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
