#!/usr/bin/env python3
"""Semaphore toàn máy giới hạn tối đa 2 tiến trình chạy post-fix-gate --full / verify nặng cùng lúc."""

from __future__ import annotations

import fcntl
import os
import random
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import IO, Optional, Sequence

SLOT_COUNT = 2
DEFAULT_WAIT_S = 3600.0


@dataclass
class SlotHandle:
    """Thông tin slot đang giữ của tiến trình hiện tại."""

    fh: Optional[IO[str]]
    slot: Optional[int]
    prev_held: bool
    timed_out: bool = False


def admitted(handle: Optional[SlotHandle]) -> bool:
    """Được chạy việc nặng. Hết giờ chờ thì không. Thiếu thư mục khoá vẫn được (không chặn gate)."""
    if handle is None or handle.prev_held or handle.fh is not None:
        return True
    return not handle.timed_out


def slot_dir() -> str:
    """Trả về thư mục chứa file khoá heavy-gate, cho phép ghi đè qua SB_HEAVY_SLOT_DIR."""
    custom = os.environ.get("SB_HEAVY_SLOT_DIR", "").strip()
    if custom:
        return custom
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks")


def _try_lock_slot(lock_dir: str, slot_num: int) -> Optional[IO[str]]:
    """Thử lấy flock độc quyền không chặn (LOCK_NB) trên một slot cụ thể."""
    path = os.path.join(lock_dir, f"heavy-gate-{slot_num}.lock")
    fh: Optional[IO[str]] = None
    try:
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        fh = os.fdopen(fd, "r+", encoding="utf-8")
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            fh.seek(0)
            fh.truncate()
            fh.write(f"{os.getpid()}\n")
            fh.flush()
        except OSError:
            pass
        return fh
    except OSError:
        if fh is not None:
            try:
                fh.close()
            except OSError:
                pass
        return None


def acquire(wait_s: Optional[float] = None, nonblocking: bool = False) -> SlotHandle:
    """Lấy một trong 2 slot toàn máy; trả ngay nếu tiến trình cha đã giữ (SB_HEAVY_SLOT_HELD=1)."""
    if os.environ.get("SB_HEAVY_SLOT_HELD") == "1":
        return SlotHandle(fh=None, slot=0, prev_held=True)

    if wait_s is None:
        try:
            wait_s = float(os.environ.get("SB_HEAVY_SLOT_WAIT_S", str(DEFAULT_WAIT_S)))
        except ValueError:
            wait_s = DEFAULT_WAIT_S

    try:
        poll_s = float(os.environ.get("SB_HEAVY_SLOT_POLL_S", "2.0"))
    except ValueError:
        poll_s = 2.0
    poll_s = max(0.02, poll_s)
    jitter_max = min(0.5, poll_s * 0.25)

    lock_dir = slot_dir()
    try:
        os.makedirs(lock_dir, mode=0o700, exist_ok=True)
        try:
            os.chmod(lock_dir, 0o700)
        except OSError:
            pass
    except OSError as exc:
        print(f"[heavy-slot] không tạo được thư mục khoá {lock_dir}: {exc}; chạy tiếp không khoá", file=sys.stderr, flush=True)
        return SlotHandle(fh=None, slot=None, prev_held=False)

    deadline = time.monotonic() + max(0.0, wait_s)
    logged_wait = False

    while True:
        for slot_num in range(1, SLOT_COUNT + 1):
            fh = _try_lock_slot(lock_dir, slot_num)
            if fh is not None:
                os.environ["SB_HEAVY_SLOT_HELD"] = "1"
                return SlotHandle(fh=fh, slot=slot_num, prev_held=False)

        now = time.monotonic()
        if nonblocking or now >= deadline:
            return SlotHandle(fh=None, slot=None, prev_held=False, timed_out=True)

        if not logged_wait:
            print(
                f"[heavy-slot] cả {SLOT_COUNT} slot --full đang bận ({lock_dir}); đang chờ slot trống (tối đa {wait_s:g}s)...",
                file=sys.stderr,
                flush=True,
            )
            logged_wait = True

        sleep_for = min(poll_s + random.uniform(0.0, jitter_max), max(0.0, deadline - now))
        time.sleep(sleep_for)


def release(handle: Optional[SlotHandle]) -> None:
    """Nhả flock của slot và khôi phục biến môi trường SB_HEAVY_SLOT_HELD."""
    if handle is None:
        return
    try:
        if handle.fh is not None:
            try:
                fcntl.flock(handle.fh.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                handle.fh.close()
            except OSError:
                pass
    finally:
        if not handle.prev_held:
            os.environ.pop("SB_HEAVY_SLOT_HELD", None)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI bọc một lệnh dưới heavy slot: heavy_slot.py [--nonblock] [--] <command...>."""
    args = list(sys.argv[1:] if argv is None else argv)
    nonblocking = False
    while args and args[0] in ("--nonblock", "--nb"):
        nonblocking = True
        args.pop(0)
    if args and args[0] == "--":
        args.pop(0)

    handle = acquire(nonblocking=nonblocking)
    try:
        if not admitted(handle):
            if not nonblocking:
                print("[heavy-slot] hết thời gian chờ 2 slot --full; không chạy lệnh", file=sys.stderr, flush=True)
            return 1
        if not args:
            return 0
        proc = subprocess.run(args)
        return proc.returncode
    finally:
        release(handle)


if __name__ == "__main__":
    sys.exit(main())
