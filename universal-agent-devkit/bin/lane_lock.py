#!/usr/bin/env python3
"""Khoá lane cho việc nặng của phiên điều phối (gate, test suite, build, đo A/B), số slot theo tải máy (#716).

    lane_lock.py <tên> [--] <lệnh…>

Luật người dùng (18:03 30/10): load1 < 12 ⇒ tối đa 2 việc nặng cùng lúc; 12 ≤ load1 < 24 ⇒ 1 (KHÔNG còn ai khác giữ slot nào);
load1 ≥ 24 ⇒ không bắt đầu, chờ tải xuống. Đọc tải lỗi ⇒ coi như tải cao (1 slot). Chờ không giới hạn (như khoá mkdir cũ ở
.claude/audit-gate/handoff/work-1644/with_lane_lock.sh), log lại mỗi 60 s.

Khoá là flock trên <thư mục>/lane-<k>.lock (dùng lại heavy_slot._try_lock_path / _unlock): kernel nhả khi wrapper chết, kể cả
kill -9, nên không có khoá mồ côi. Con KHÔNG thừa hưởng fd khoá (close_fds): tiến trình cháu sống sót không giữ slot (#697). TERM/INT/HUP
gửi cho wrapper được chuyển cho con; wrapper chờ con rồi nhả. Exit = exit của lệnh (127 khi không chạy được, 128+sig khi con bị tín hiệu).

Biến: LANE_LOCK_DIR (mặc định <git common dir>/lane-lock, chung cho main và mọi worktree), LANE_LOCK_SLOTS (2), LANE_LOCK_LOAD_TWO (12),
LANE_LOCK_LOAD_MAX (24), LANE_LOCK_POLL_S (5), LANE_LOCK_LOG_S (60); tải giả cho test: DEVKIT_SLOT_LOAD_FILE (của heavy_slot.load_now).
ponytail: không có hàng vé/ưu tiên (2–3 người chờ, jitter tránh đồng pha); ≥ 4 lane chờ thường xuyên thì chuyển sang hàng vé của
heavy_slot.acquire_pool.
"""
from __future__ import annotations

import os
import random
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heavy_slot  # noqa: E402  dùng lại flock và đọc tải của kit, không sửa heavy_slot.py


def _env_num(name: str, default: float) -> float:
    try:
        value = float(os.environ.get(name, "") or default)
    except ValueError:
        return float(default)
    return value if value == value and 0 <= value != float("inf") else float(default)


def _git_common(cwd: str) -> str:
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True,
                           text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    out = r.stdout.strip()
    return os.path.abspath(out) if r.returncode == 0 and out else ""


def lock_dir() -> str:
    """LANE_LOCK_DIR; không đặt thì <git common dir của CWD>/lane-lock, rồi của repo chứa file này, rồi ~/.claude/super-board/locks/lane-lock."""
    custom = os.environ.get("LANE_LOCK_DIR", "").strip()
    if custom:
        return os.path.abspath(custom)
    common = _git_common(os.getcwd()) or _git_common(os.path.dirname(os.path.abspath(__file__)))
    if common:
        return os.path.join(common, "lane-lock")
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks", "lane-lock")


def _say(msg: str, err: bool = False) -> None:
    """In log [lock]; pipe đầu ra đã đóng (BrokenPipeError) không được làm hỏng việc nhả khoá."""
    try:
        print(msg, file=sys.stderr if err else sys.stdout, flush=True)
    except OSError:
        pass


def _owners(paths: list) -> str:
    """Chủ của các slot đang bị giữ (thăm flock; file .owner chỉ để đọc, có thể cũ sau kill -9 nên chỉ đọc khi thăm thất bại)."""
    out = []
    for p in paths:
        probe = heavy_slot._try_lock_path(p)
        if probe is not None:
            heavy_slot._unlock(probe)
            continue
        try:
            with open(p[:-5] + ".owner", encoding="utf-8") as f:
                out.append(f.read().strip())
        except OSError:
            out.append(os.path.basename(p))
    return "; ".join(out) or "không ai"


def try_take(paths: list, load) -> tuple:
    """Một lượt xin slot theo tải. Trả (fh, chỉ số slot, cap) khi lấy được, (None, None, cap) khi phải chờ."""
    two = _env_num("LANE_LOCK_LOAD_TWO", 12.0)
    cap_max = _env_num("LANE_LOCK_LOAD_MAX", 24.0)
    if load is not None and load >= cap_max:
        return None, None, 0
    if load is not None and load < two:
        for i, path in enumerate(paths):
            fh = heavy_slot._try_lock_path(path)
            if fh is not None:
                return fh, i, len(paths)
        return None, None, len(paths)
    # tải cao (hoặc đọc lỗi): 1 slot = phải lấy được slot đầu VÀ mọi slot khác đang trống (không ai khác giữ)
    fh = heavy_slot._try_lock_path(paths[0])
    if fh is None:
        return None, None, 1
    for path in paths[1:]:
        probe = heavy_slot._try_lock_path(path)
        if probe is None:
            heavy_slot._unlock(fh)
            return None, None, 1
        heavy_slot._unlock(probe)
    return fh, 0, 1


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print("dùng: lane_lock.py <tên> [--] <lệnh…>", file=sys.stderr)
        return 2
    name = args.pop(0)
    if args and args[0] == "--":
        args.pop(0)
    if not args:
        print("dùng: lane_lock.py <tên> [--] <lệnh…>", file=sys.stderr)
        return 2
    d = lock_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    slots = max(1, int(_env_num("LANE_LOCK_SLOTS", 2)))
    paths = [os.path.join(d, f"lane-{k}.lock") for k in range(1, slots + 1)]
    poll = max(0.02, _env_num("LANE_LOCK_POLL_S", 5.0))
    log_every = _env_num("LANE_LOCK_LOG_S", 60.0)
    t0 = time.monotonic()
    last_log = None
    while True:
        load = heavy_slot.load_now()
        fh, idx, cap = try_take(paths, load)
        if fh is not None:
            break
        now = time.monotonic()
        if last_log is None or now - last_log >= log_every:
            why = f"load {load:.1f} ≥ {_env_num('LANE_LOCK_LOAD_MAX', 24.0):g}" if cap == 0 else f"đủ {cap} slot"
            if load is None:
                why += " (không đọc được tải: coi là tải cao)"
            _say(f"[lock] {name} chờ ({why}; đang giữ: {_owners(paths)}) {time.strftime('%T')}")
            last_log = now
        time.sleep(poll + random.uniform(0.0, min(1.0, poll * 0.25)))
    waited = time.monotonic() - t0
    owner = paths[idx][:-5] + ".owner"
    t1 = time.monotonic()
    rc = 127
    proc = None
    forwarded = {}

    def _signal_group(sig) -> bool:
        """Gửi sig cho cả nhóm của con; False khi nhóm không còn (macOS: nhóm chỉ còn zombie trả PermissionError)."""
        try:
            os.killpg(proc.pid, sig)
            return True
        except (ProcessLookupError, PermissionError):
            return False
        except OSError:
            return False

    def _forward(sig, _frame):
        forwarded["sig"] = sig
        if proc is not None:
            _signal_group(sig)

    old = {s: signal.signal(s, _forward) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    try:   # mọi bước sau khi giữ slot nằm trong try: lỗi ở đâu cũng nhả slot
        try:
            with open(owner, "w", encoding="utf-8") as f:
                f.write(f"{name} pid {os.getpid()} từ {time.strftime('%T')}\n")
        except OSError:
            pass
        ltxt = "?" if load is None else f"{load:.1f}"
        _say(f"[lock] {name} giữ khoá {time.strftime('%T')} (slot {idx + 1}/{len(paths)}, cho phép {cap}, chờ {waited:.0f} s, load {ltxt})")
        try:
            proc = subprocess.Popen(args, close_fds=True, start_new_session=True)
        except OSError as exc:
            _say(f"[lock] {name}: không chạy được {args[0]}: {exc}", err=True)
        else:
            if forwarded:   # tín hiệu tới trước khi con kịp chạy: gửi lại cho nhóm của con
                _signal_group(forwarded["sig"])
            while True:
                try:
                    status = proc.wait()
                    break
                except InterruptedError:
                    continue
            rc = status if status >= 0 else 128 - status
            # cháu cùng nhóm còn sống: chờ ân hạn LANE_LOCK_GRACE_S rồi mới nhả slot; nhận tín hiệu thì giết nốt nhóm sau ân hạn
            grace_end = time.monotonic() + _env_num("LANE_LOCK_GRACE_S", 5.0)
            while _signal_group(0) and time.monotonic() < grace_end:
                time.sleep(0.1)
            if _signal_group(0):
                if forwarded:
                    _signal_group(signal.SIGKILL)
                _say(f"[lock] {name}: nhóm tiến trình của lệnh vẫn còn sau ân hạn"
                     f"{' (đã KILL vì nhận tín hiệu)' if forwarded else ''}", err=True)
    finally:
        for s, h in old.items():
            signal.signal(s, h)
        try:
            os.remove(owner)
        except OSError:
            pass
        heavy_slot._unlock(fh)
        _say(f"[lock] {name} nhả khoá rc={rc} {time.strftime('%T')} (giữ {time.monotonic() - t1:.0f} s)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
