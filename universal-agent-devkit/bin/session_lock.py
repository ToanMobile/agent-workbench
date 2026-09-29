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

Escape hatch: DEVKIT_ALLOW_SHARED_CHECKOUT=1 (logged to <git dir>/devkit-session.log).
ponytail: Bash writes are recognised by pattern (git writes, post-fix-gate, `>`/`>>` into the checkout) — cp/mv/rm/
sed -i by a second session still pass; upgrade to hooks/worktree_guard.sh's write classifier if that happens.
"""
import json
import os
import re
import subprocess
import sys
import time

LOCK = "devkit-session.lock"
LOG = "devkit-session.log"
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
GIT_WRITE = re.compile(
    r"(^|[\s;&|(])git\s+(-C\s+\S+\s+)?(commit|push|pull|add|rm|mv|reset|checkout|restore|switch|stash|merge|rebase|"
    r"cherry-pick|revert|am|apply|tag|clean)\b")
GATE = re.compile(r"post-fix-gate(\.py)?\b|\bpostfix-gate\b")
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
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def write_lock(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)


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


def is_free_for(lock, sid, now):
    """True when `sid` may hold the checkout: no lock, its own lock, or a stale one."""
    if not lock or not lock.get("session_id"):
        return True
    if lock.get("session_id") == sid:
        return True
    return now - float(lock.get("heartbeat") or 0) > stale_after()


def describe(lock, now):
    sid = str(lock.get("session_id", "?"))
    started = time.strftime("%H:%M", time.localtime(float(lock.get("started") or now)))
    age = int(now - float(lock.get("heartbeat") or now))
    return f"phiên {sid[:12]} (giữ từ {started}, hoạt động cách đây {age}s)"


def bash_collides(cmd, top):
    if GIT_WRITE.search(cmd) or GATE.search(cmd):
        return True
    for m in REDIRECT.finditer(cmd):
        target = m.group(1)
        if target.startswith("&") or target.startswith(TEMP_PREFIXES):
            continue
        tmpdir = os.environ.get("TMPDIR", "")
        if tmpdir and target.startswith(tmpdir):
            continue
        if not target.startswith("/") or (top and os.path.realpath(target).startswith(os.path.realpath(top) + os.sep)):
            return True
    return False


def take(path, lock, sid, cwd, now):
    started = lock.get("started") if lock and lock.get("session_id") == sid else now
    if lock and lock.get("session_id") == sid and now - float(lock.get("heartbeat") or 0) < 30:
        return  # heartbeat throttle
    write_lock(path, {"session_id": sid, "started": started, "heartbeat": now, "cwd": cwd})


def main():
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
    lock = read_lock(path)

    if event == "SessionEnd":
        if lock and lock.get("session_id") == sid:
            try:
                os.remove(path)
            except OSError as e:
                print(f"session_lock: không gỡ được khoá: {e}", file=sys.stderr)
        return 0

    if event == "SessionStart":
        if is_free_for(lock, sid, now):
            if lock and lock.get("session_id") not in (None, sid):
                log(gdir, f"{sid} nhận khoá cũ đã hết hạn của {lock.get('session_id')}")
            take(path, lock, sid, cwd, now)
        else:
            print(f"⚠️ [DevKit] Checkout này đang do {describe(lock, now)} giữ. Luật: MỘT thư mục — MỘT phiên. Phiên này "
                  f"CHỈ ĐỌC ở đây (Edit/Write, git ghi, post-fix-gate bị chặn) cho tới khi phiên kia xong; muốn làm song "
                  f"song thì xin người dùng tạo worktree riêng.")
        return 0

    if event != "PreToolUse":
        return 0
    tool = str(d.get("tool_name") or "")
    if tool in EDIT_TOOLS:
        collides = True
    elif tool == "Bash":
        collides = bash_collides(str((d.get("tool_input") or {}).get("command") or ""), top)
    else:
        return 0

    if is_free_for(lock, sid, now):
        if lock and lock.get("session_id") not in (None, sid):
            log(gdir, f"{sid} nhận khoá cũ đã hết hạn của {lock.get('session_id')}")
        if collides or (lock and lock.get("session_id") == sid):
            take(path, lock, sid, cwd, now)
        return 0
    if not collides:
        return 0
    if os.environ.get("DEVKIT_ALLOW_SHARED_CHECKOUT") == "1":
        log(gdir, f"{sid} ghi song song khi {lock.get('session_id')} đang giữ (DEVKIT_ALLOW_SHARED_CHECKOUT=1): {tool}")
        return 0
    print(f"⛔ [DevKit] Một thư mục — một phiên: checkout {top} đang do {describe(lock, now)} giữ. Phiên này chỉ đọc "
          f"ở đây: chờ phiên kia xong (khoá tự hết hạn sau {int(stale_after())}s không hoạt động), hoặc xin người dùng tạo "
          f"worktree riêng. Người dùng cố ý cho chạy song song: DEVKIT_ALLOW_SHARED_CHECKOUT=1.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
