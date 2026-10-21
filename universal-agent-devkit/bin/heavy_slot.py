#!/usr/bin/env python3
"""Cho việc nặng chạy theo TẢI MÁY (người dùng 20/10: bỏ giới hạn 2 slot --full): tải 1 phút dưới DEVKIT_SLOT_LOAD_MAX (mặc định
100, như merge_load_max của merge gate) thì chạy ngay, cao hơn thì chờ tải xuống tối đa DEVKIT_SLOT_LOAD_WAIT_S (600 s) rồi VẪN chạy —
tải không bao giờ làm một suite thành UNTESTED. Chỉ tài nguyên độc quyền còn khoá (P1, 20/10): Unity (1 Editor một lúc), có hàng
đợi vé: ưu tiên merge > push > interactive > stop > nightly, cùng mức thì việc ngắn trước, chờ lâu được bù 1:1 (không đói). Không còn
khoá thiết bị (review 20/10): suite thiết bị nhận bằng regex chữ (`bash -n scripts/qa/adb/x.sh` cũng khớp), khoá đó không khớp khoá
của proof-capture, và suite thiết bị gọi proof-capture trên chính serial của nó thì tự chờ chính nó."""

from __future__ import annotations

import fcntl
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from typing import IO, Optional, Sequence

DEFAULT_WAIT_S = 3600.0   # SB_HEAVY_SLOT_WAIT_S: chờ khoá độc quyền (Unity) tối đa chừng này
# Mức ưu tiên của hàng đợi (DEVKIT_SLOT_PRIORITY): số nhỏ đứng trước. Việc chặn merge/push đi trước việc của Stop hook hay nightly.
PRIORITY = {"merge": 0, "push": 1, "interactive": 2, "stop": 3, "nightly": 4}
DEFAULT_EST_S = 600.0     # suite chưa có thời lượng ghi nhận
CPU_HEAVY_S = 300.0       # thời lượng ghi nhận dài nhất vượt mức này: suite nặng CPU (DEVKIT_SLOT_CPU_S)
LOAD_MAX = 100.0          # DEVKIT_SLOT_LOAD_MAX: tải 1 phút (os.getloadavg) dưới mức này thì chạy ngay (người dùng 20/10)
LOAD_WAIT_S = 600.0       # DEVKIT_SLOT_LOAD_WAIT_S: tải cao thì chờ tối đa chừng này rồi vẫn chạy; 0 = không chờ
ADVISORY_BUDGET_S = 600.0  # DEVKIT_SLOT_ADVISORY_BUDGET_S: tổng giây ĐỒNG HỒ một tiến trình được chờ tải (chờ chồng nhau tính một lần)
# Sổ chờ tải của tiến trình: giây đồng hồ đã chờ (các khoảng có ít nhất một suite đang chờ, hợp lại), số suite đang chờ, lúc khoảng
# hiện tại bắt đầu, đã báo hết ngân sách chưa.
_LOAD_WAIT = {"spent": 0.0, "active": 0, "since": 0.0, "noted": False}
_ADVISORY_LOCK = threading.Lock()


def _load_wait_spent(now: float) -> float:
    """Giây đồng hồ tiến trình đã chờ tải tới `now` (gọi trong _ADVISORY_LOCK)."""
    return _LOAD_WAIT["spent"] + (now - _LOAD_WAIT["since"] if _LOAD_WAIT["active"] else 0.0)


@dataclass
class SlotHandle:
    """Thông tin slot đang giữ của tiến trình hiện tại."""

    fh: Optional[IO[str]]
    slot: Optional[int]
    prev_held: bool
    timed_out: bool = False


def admitted(handle: Optional[SlotHandle]) -> bool:
    """Được chạy việc nặng. Hết giờ chờ thì không. Thiếu thư mục khoá vẫn được (không chặn gate)."""
    if handle is None or handle.prev_held:
        return True
    return not handle.timed_out


def slot_dir() -> str:
    """Trả về thư mục chứa file khoá heavy-gate, cho phép ghi đè qua SB_HEAVY_SLOT_DIR."""
    custom = os.environ.get("SB_HEAVY_SLOT_DIR", "").strip()
    if custom:
        return custom
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks")


def _env_float(name: str, default: float) -> float:
    """Số thực từ biến môi trường; rỗng, rác, NaN, vô cực hay âm thì lấy mặc định."""
    try:
        value = float(os.environ.get(name, "") or default)
    except ValueError:
        return float(default)
    return value if value == value and 0 <= value != float("inf") else float(default)


def _poll_s() -> float:
    return max(0.02, _env_float("SB_HEAVY_SLOT_POLL_S", 2.0))


def load_now() -> Optional[float]:
    """Tải 1 phút của máy; None khi không đọc được. DEVKIT_SLOT_LOAD_FILE: móc test, đọc tải từ file (như SB_MERGE_LOAD_FILE của
    merge gate)."""
    path = os.environ.get("DEVKIT_SLOT_LOAD_FILE", "").strip()
    try:
        if path:
            with open(path, encoding="utf-8") as f:
                value = float(f.read().strip())
        else:
            value = os.getloadavg()[0]
    except (OSError, ValueError):
        return None
    return value if value == value and 0 <= value != float("inf") else None


def load_max() -> float:
    """Ngưỡng tải (DEVKIT_SLOT_LOAD_MAX); rỗng, rác hay không dương thì 100."""
    value = _env_float("DEVKIT_SLOT_LOAD_MAX", LOAD_MAX)
    return value if value > 0 else LOAD_MAX


def wait_load(wait_s: float, label: str = "") -> tuple:
    """Chờ tải máy xuống dưới load_max(), tối đa wait_s giây; (giây đã chờ, ghi chú hoặc None). Không bao giờ từ chối: hết giờ,
    hay không đọc được tải, thì vẫn chạy. wait_s <= 0: không đọc tải, không chờ.
    ponytail: tải 1 phút trễ ~1 phút nên nhiều lượt cùng thấy tải thấp có thể vào cùng lúc; thêm khoá đếm nếu đo thấy máy quá tải vì vậy."""
    if wait_s <= 0:
        return 0.0, None
    limit = load_max()
    load = load_now()
    if load is None or load < limit:
        return 0.0, None
    t0 = time.monotonic()
    deadline = t0 + wait_s
    print(f"[heavy-slot] tải máy {load:.0f} ≥ {limit:g}{f' — {label}' if label else ''}; chờ tải xuống (tối đa {wait_s:g}s)...",
          file=sys.stderr, flush=True)
    poll_s = _poll_s()
    while True:
        now = time.monotonic()
        if now >= deadline:
            return now - t0, f"tải máy vẫn {load:.0f} ≥ {limit:g} sau {now - t0:.0f}s — vẫn chạy (tải không chặn suite)"
        time.sleep(min(poll_s + random.uniform(0.0, min(0.5, poll_s * 0.25)), deadline - now))
        load = load_now()
        if load is None or load < limit:
            waited = time.monotonic() - t0
            return waited, f"chờ tải máy xuống dưới {limit:g}: {waited:.0f}s"


def priority_name() -> str:
    """Mức ưu tiên của tiến trình này (DEVKIT_SLOT_PRIORITY); tên lạ thì là interactive."""
    name = (os.environ.get("DEVKIT_SLOT_PRIORITY") or "interactive").strip().lower()
    return name if name in PRIORITY else "interactive"


# ── Hàng đợi vé (một thư mục mỗi pool) ─────────────────────────────────────────────────────────────────────────
def queue_order(tickets: list, now: float) -> list:
    """Thứ tự phục vụ: (mức ưu tiên, thời lượng ước tính − thời gian đã chờ, lúc đến). Việc dài chờ lâu dần lên đầu."""
    def key(t):
        try:
            est = float(t.get("est_s"))
        except (TypeError, ValueError):
            est = DEFAULT_EST_S
        try:
            t0 = float(t.get("t0"))
        except (TypeError, ValueError):
            t0 = now
        return (PRIORITY.get(t.get("prio"), PRIORITY["interactive"]), est - max(0.0, now - t0), t0, str(t.get("name") or ""))
    return sorted(tickets, key=key)


def _pid_alive(pid) -> bool:
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:   # tiến trình của user khác vẫn sống
        return True
    except OSError:
        return False
    return True


def ticket_alive(ticket: dict, now: float, wait_s: Optional[float] = None) -> bool:
    """Vé còn hiệu lực: PID còn sống và chưa quá thời gian chờ của chính vé (+60 s). Vé của tiến trình chết không chặn ai."""
    try:
        t0 = float(ticket.get("t0"))
        limit = float(ticket.get("wait_s") if wait_s is None else wait_s)
    except (TypeError, ValueError):
        return False
    return _pid_alive(ticket.get("pid")) and now - t0 <= max(0.0, limit) + 60.0


def _read_tickets(qdir: str, now: float) -> list:
    """Vé còn sống trong qdir; vé chết (PID đã thoát, quá hạn, hỏng) bị xoá để không chặn hàng."""
    out = []
    try:
        names = os.listdir(qdir)
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(qdir, name)
        try:
            with open(path, encoding="utf-8") as f:
                ticket = json.load(f)
        except (OSError, ValueError):
            ticket = None
        if isinstance(ticket, dict) and ticket_alive(ticket, now):
            ticket["name"] = name
            out.append(ticket)
            continue
        try:
            if ticket is not None or now - os.stat(path).st_mtime > 60:   # file đang ghi dở thì để yên một phút
                os.remove(path)
        except OSError:
            pass
    return out


def _write_ticket(qdir: str, prio: str, est_s: float, wait_s: float, label: str) -> Optional[str]:
    """Ghi vé của tiến trình này; None khi không ghi được (khi đó không xếp hàng, chỉ tranh khoá như trước)."""
    try:
        os.makedirs(qdir, mode=0o700, exist_ok=True)
        name = f"{os.getpid()}-{random.getrandbits(48):012x}.json"
        tmp = os.path.join(qdir, "." + name + ".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"pid": os.getpid(), "prio": prio, "est_s": float(est_s), "t0": time.time(), "wait_s": float(wait_s),
                       "label": str(label)[:120]}, f)
        os.replace(tmp, os.path.join(qdir, name))
        return name
    except OSError as exc:
        print(f"[heavy-slot] không ghi được vé hàng đợi ({qdir}): {exc}; tranh khoá không xếp hàng", file=sys.stderr, flush=True)
        return None


def _rank(qdir: str, name: Optional[str]) -> int:
    if not name:
        return 0
    order = [t.get("name") for t in queue_order(_read_tickets(qdir, time.time()), time.time())]
    return order.index(name) if name in order else 0


def _try_lock_path(path: str) -> Optional[IO[str]]:
    """flock LOCK_NB trên một file khoá; ghi PID khi lấy được."""
    fh: Optional[IO[str]] = None
    try:
        fd = os.open(path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0), 0o600)
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


def _unlock(fh: Optional[IO[str]]) -> None:
    if fh is None:
        return
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        fh.close()
    except OSError:
        pass


@dataclass
class PoolHandle:
    """Slot đã lấy của một pool. fh None + prev_held: tiến trình cha giữ hộ; fh None + timed_out: hết giờ chờ."""

    pool: str
    fh: Optional[IO[str]] = None
    path: str = ""
    prev_held: bool = False
    timed_out: bool = False
    waited_s: float = 0.0


def pool_paths(pool: str, capacity: int, lock_dir: Optional[str] = None) -> list:
    """File khoá của pool độc quyền (unity-1.lock …) trong slot_dir()."""
    lock_dir = lock_dir or slot_dir()
    return [os.path.join(lock_dir, f"{pool}-{i}.lock") for i in range(1, max(0, capacity) + 1)]


def acquire_pool(pool: str, paths: list, *, wait_s: float, prio: Optional[str] = None, est_s: Optional[float] = None,
                 label: str = "") -> PoolHandle:
    """Lấy một khoá trong `paths` theo hàng đợi vé của pool. Không bao giờ đụng os.environ (gọi được từ nhiều luồng).
    SB_HEAVY_SLOT_HELD=1: tiến trình cha đã giữ slot cho cả cây tiến trình — trả ngay, không lấy thêm (gate lồng trong suite)."""
    if os.environ.get("SB_HEAVY_SLOT_HELD") == "1":
        return PoolHandle(pool, prev_held=True)
    if not paths:
        return PoolHandle(pool)
    lock_dir = os.path.dirname(paths[0])
    try:
        os.makedirs(lock_dir, mode=0o700, exist_ok=True)
    except OSError as exc:
        print(f"[heavy-slot] không tạo được thư mục khoá {lock_dir}: {exc}; chạy tiếp không khoá", file=sys.stderr, flush=True)
        return PoolHandle(pool)
    qdir = os.path.join(slot_dir(), "queue", pool)
    poll_s = _poll_s()
    jitter_max = min(0.5, poll_s * 0.25)
    t_start = time.monotonic()
    deadline = t_start + max(0.0, wait_s)
    ticket = _write_ticket(qdir, prio or priority_name(), DEFAULT_EST_S if est_s is None else est_s, wait_s, label)
    logged = False
    try:
        while True:
            # Vé đứng đầu hàng (hạng 0, hoặc không xếp hàng): lấy slot trống đầu tiên rồi thôi — không thăm mọi khoá (luồng khác cùng
            # tiến trình đang thăm sẽ thấy 0 slot trống và mất một vòng chờ). Vé đứng sau: thăm mọi khoá, số khoá lấy được = số slot
            # trống; chỉ giữ một khi hạng nhỏ hơn số đó, còn lại nhả ngay để vé đứng trước lấy ở vòng thăm của nó.
            first = _rank(qdir, ticket) == 0
            got = []
            for path in paths:
                fh = _try_lock_path(path)
                if fh is not None:
                    got.append((fh, path))
                    if first:
                        break
            if got and _rank(qdir, ticket) < len(got):
                for fh, _ in got[1:]:
                    _unlock(fh)
                return PoolHandle(pool, fh=got[0][0], path=got[0][1], waited_s=time.monotonic() - t_start)
            for fh, _ in got:
                _unlock(fh)
            now = time.monotonic()
            if now >= deadline:
                return PoolHandle(pool, timed_out=True, waited_s=now - t_start)
            if not logged:
                print(f"[heavy-slot] pool {pool} ({len(paths)} slot) đang bận{f' — {label}' if label else ''}; "
                      f"đang chờ (tối đa {wait_s:g}s, ưu tiên {prio or priority_name()})...", file=sys.stderr, flush=True)
                logged = True
            time.sleep(min(poll_s + random.uniform(0.0, jitter_max), max(0.0, deadline - now)))
    finally:
        if ticket:
            try:
                os.remove(os.path.join(qdir, ticket))
            except OSError:
                pass


def release_pool(handle: Optional[PoolHandle]) -> None:
    if handle is not None:
        _unlock(handle.fh)
        handle.fh = None


def acquire(wait_s: Optional[float] = None, nonblocking: bool = False) -> SlotHandle:
    """Đường cũ của CLI và wrapper super-board, theo TẢI MÁY (không còn 2 slot, người dùng 20/10): tải dưới load_max() thì chạy ngay,
    cao hơn thì chờ tải xuống tối đa wait_s (DEVKIT_SLOT_LOAD_WAIT_S đặt rõ thì thắng — merge gate đặt 0 sau lần chờ của chính nó, OCR
    20/10; không đặt thì SB_HEAVY_SLOT_WAIT_S, giữ cho tương thích ngược; không cả hai thì 600 s) rồi vẫn chạy. --nonblock:
    tải cao thì không chạy. Trả ngay nếu tiến trình cha đã giữ khoá độc quyền (SB_HEAVY_SLOT_HELD=1) hoặc đã được cho chạy theo tải
    (DEVKIT_SLOT_ADVISORY_HELD=1). Được chạy thì đặt DEVKIT_SLOT_ADVISORY_HELD=1 cho cả cây tiến trình: gate lồng không chờ tải lại
    nhưng VẪN xin khoá Unity (không giữ khoá nào thì không được đặt SB_HEAVY_SLOT_HELD — OCR 20/10)."""
    if os.environ.get("SB_HEAVY_SLOT_HELD") == "1" or os.environ.get("DEVKIT_SLOT_ADVISORY_HELD") == "1":
        return SlotHandle(fh=None, slot=0, prev_held=True)
    if nonblocking:
        load = load_now()
        if load is not None and load >= load_max():
            return SlotHandle(fh=None, slot=None, prev_held=False, timed_out=True)
    else:
        if wait_s is None:
            wait_s = _env_float("DEVKIT_SLOT_LOAD_WAIT_S", _env_float("SB_HEAVY_SLOT_WAIT_S", LOAD_WAIT_S))
        _, note = wait_load(wait_s)
        if note:
            print(f"[heavy-slot] {note}", file=sys.stderr, flush=True)
    os.environ["DEVKIT_SLOT_ADVISORY_HELD"] = "1"
    return SlotHandle(fh=None, slot=None, prev_held=False)


def release(handle: Optional[SlotHandle]) -> None:
    """Gỡ DEVKIT_SLOT_ADVISORY_HELD mà acquire() đã đặt (acquire không giữ flock nào)."""
    if handle is not None and not handle.prev_held:
        os.environ.pop("DEVKIT_SLOT_ADVISORY_HELD", None)


# ── Lớp tài nguyên của một suite (P1, 20/10) ──────────────────────────────────────────────────────────────────────
# Đọc TỪ LỆNH CHẠY của từng đoạn lệnh (sau gán biến / từ khoá shell), không đọc chữ trong chuỗi: test của DevKit nhắc
# "./gradlew" hay "unity-batch.sh" trong fixture mà không chạy chúng (đo 20/10: 0/34 suite workbench là engine theo cách đọc
# này; mọi suite Gradle/Unity của 5 repo app đều nhận ra).
_KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}", "(", ")", "exec", "env",
             "command", "time", "nohup"}
# Trình bọc chạy chương trình thật đứng sau nó (review 20/10: `timeout 600 unity-batch.sh` từng là suite nhẹ): tên → (tuỳ chọn có
# đối số tách rời, có từ thời lượng sau tuỳ chọn không). Mỗi trình một bộ: `caffeinate -s` không có đối số, `xvfb-run -s` có.
_WRAPPERS = {
    "timeout": ({"-k", "-s", "--kill-after", "--signal"}, True),
    "gtimeout": ({"-k", "-s", "--kill-after", "--signal"}, True),
    "xvfb-run": ({"-e", "-f", "-n", "-p", "-s", "-w", "--error-file", "--auth-file", "--server-num", "--xauth-protocol",
                  "--server-args", "--wait"}, False),
    "caffeinate": ({"-t", "-w"}, False),
    "nice": ({"-n", "--adjustment"}, False),
}
_ENGINE = {"gradlew": "gradle", "gradle": "gradle", "xcodebuild": "xcode", "unity-batch.sh": "unity", "unity-batch": "unity",
           "unity": "unity"}
_UNITY_FLAGS = {"-runTests", "-batchmode"}
_CPU = {"go": {"test", "build", "vet"}, "cargo": {"test", "build"}, "mvn": None, "mvnw": None, "dotnet": {"test", "build"},
        "swift": {"test", "build"}}
_FAN_OUT = {"run_impacted.sh"}   # tự mở tới 10 job song song
_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "source", "."}
_ASSIGN = re.compile(r"^[A-Za-z_]\w*=")
_SHELL_C = re.compile(r"-[A-Za-z]*c[A-Za-z]*")   # -c, -lc, -euc …: cờ chạy mã trên dòng lệnh


def _past(words: list, i: int) -> int:
    """Chỉ số ngay sau từ words[i]; từ mở nháy chưa đóng (đối số có khoảng trắng: -s '-screen 0 640x480x24') kéo tới từ đóng nháy."""
    for q in "'\"":
        if words[i].count(q) % 2:
            i += 1
            while i < len(words) and words[i].count(q) % 2 == 0:
                i += 1
            break
    return i + 1


def _skip_wrapper(words: list, i: int) -> int:
    """words[i] là một trình bọc (_WRAPPERS): chỉ số từ chương trình thật — bỏ tuỳ chọn, đối số của chúng, `--` và thời lượng của
    timeout. `$VAR` làm từ chương trình thì để nguyên (unity-batch.sh có khoá máy riêng)."""
    arg_opts, has_duration = _WRAPPERS[os.path.basename(words[i])]
    i += 1
    while i < len(words) and words[i].startswith("-") and words[i] != "--":
        opt = words[i]
        i = _past(words, i)
        if opt in arg_opts and i < len(words):
            i = _past(words, i)
    if i < len(words) and words[i] == "--":
        i += 1
    if has_duration and i < len(words):
        i += 1
    return i


def _rc():
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:   # một lần: classify gọi hàm này cho mọi đoạn lệnh của mọi suite
        sys.path.insert(0, here)
    import regression_checklist  # noqa: PLC0415 - module anh em trong bin/
    return regression_checklist


def _scan_programs(text: str, project_dir: str, top: bool, cwd0: str, found: dict) -> None:
    """Ghi vào found: engine (unity > gradle > xcode), cpu. top: dòng lệnh của ma trận (đi theo script nó chạy, một cấp);
    không top: nội dung một script shell (bỏ comment, heredoc, chuỗi có khoảng trắng — rc._command_lines)."""
    rc = _rc()
    for line in ([text] if top else rc._command_lines(text)):
        for cwd, seg in rc._segments(line, cwd0):
            words = seg.split()
            i = 0
            while i < len(words):
                if words[i] in _KEYWORDS or _ASSIGN.match(words[i]):
                    i += 1
                elif os.path.basename(words[i]) in _WRAPPERS:
                    i = _skip_wrapper(words, i)
                else:
                    break
            words = words[i:]
            if not words:
                continue
            base = os.path.basename(words[0].strip("'\"()"))
            if any(w in _UNITY_FLAGS for w in words):
                found["engine"].add("unity")
            if base in _ENGINE:
                found["engine"].add(_ENGINE[base])
            sub = _CPU.get(base, False)
            if base in _FAN_OUT or sub is None or (sub and len(words) > 1 and words[1] in sub):
                found["cpu"] = True
            script = None
            if base in _SHELLS and len(words) > 1:
                j, cflag = 1, False
                while j < len(words) and words[j].startswith("-") and words[j] != "--":
                    if words[j] in ("-o", "-O"):
                        j += 1   # tuỳ chọn có đối số (bash -o pipefail -c …)
                    elif _SHELL_C.fullmatch(words[j]):
                        cflag = True
                    j += 1
                if cflag and top:
                    code = " ".join(words[j:]).strip()
                    if len(code) > 1 and code[0] == code[-1] and code[0] in "'\"":
                        code = code[1:-1]
                    _scan_programs(code, project_dir, True, cwd, found)
                    continue
                script = next((w for w in words[1:] if not w.startswith("-")), None)
            elif "/" in words[0]:
                script = words[0]
            if not script:
                continue
            script = script.strip("'\"")
            sbase = os.path.basename(script)
            if sbase in _ENGINE:
                found["engine"].add(_ENGINE[sbase])
            if sbase in _FAN_OUT:
                found["cpu"] = True
            if not top or "$" in script or "`" in script:
                continue   # một cấp: script trong script không được theo
            path = script if os.path.isabs(script) else os.path.join(project_dir, cwd, script)
            try:
                if os.path.splitext(path)[1] not in ("", ".sh", ".bash", ".zsh") or not os.path.isfile(path) \
                        or os.path.getsize(path) > 1_000_000:
                    continue
                with open(path, encoding="utf-8", errors="replace") as f:
                    body = f.read()
            except OSError:
                # script không đọc được: không biết bên trong có Unity không — coi là unity (khoá Unity), không phải cpu (cpu không
                # còn khoá nào: suite Unity thật đọc lỗi từng chạy không khoá, OCR 20/10)
                found["engine"].add("unity")
                found["cpu"] = True
                continue
            if "\0" not in body[:4096]:
                _scan_programs(body, project_dir, False, "", found)


# Bản sao của post-fix-gate.py HARD_DEVICE_SUITE (giữ hai bản đồng bộ): classify tự nhận suite thiết bị khi người gọi không nói.
# Lớp "device" chỉ để ghi nhãn: không còn khoá thiết bị (review 20/10).
HARD_DEVICE = re.compile(r"\badb\b|connected\w*(?:Test|Check)|\bemulator\b|\bsimctl\b|"
                         r"\bxcodebuild\b[^\n]*\btest\b|replicant|-testPlatform[ =]+(?!EditMode\b|PlayMode\b)\w+", re.I)


def classify(command: str, project_dir: str = ".", recorded_s: Optional[float] = None, device: Optional[bool] = None) -> dict:
    """{"cls": unity|gradle|xcode|device|cpu|light, "engine": unity|gradle|xcode|None, "serial": serial|None}.
    device None: tự nhận theo HARD_DEVICE (stale_rerun.run_one); gate truyền kết quả HARD_DEVICE_SUITE của nó."""
    if device is None:
        device = bool(HARD_DEVICE.search(command or ""))
    found = {"engine": set(), "cpu": False}
    try:
        _scan_programs(command or "", project_dir, True, "", found)
    except Exception as exc:   # noqa: BLE001 - không đọc được lệnh: coi là unity (khoá độc quyền), không bao giờ nhẹ hơn thực tế
        # cpu không còn khoá nào (P1b), nên "cpu" ở đây cho một suite Unity thật chạy không khoá Unity (OCR 20/10)
        print(f"[heavy-slot] không phân lớp được lệnh ({exc}); coi là unity", file=sys.stderr, flush=True)
        found["engine"].add("unity")
        found["cpu"] = True
    engine = next((e for e in ("unity", "gradle", "xcode") if e in found["engine"]), None)
    serial = None
    if device:
        m = re.search(r"(?:\badb\s+-s\s+|\bANDROID_SERIAL=)['\"]?([\w.:-]+)", command or "")
        serial = m.group(1) if m else (os.environ.get("ANDROID_SERIAL") or "default")
        cls = "device"
    elif engine:
        cls = engine
    elif found["cpu"] or (recorded_s is not None and recorded_s > _env_float("DEVKIT_SLOT_CPU_S", CPU_HEAVY_S)):
        cls = "cpu"
    else:
        cls = "light"
    return {"cls": cls, "engine": engine, "serial": serial}


@dataclass
class SuiteSlots:
    """Suite được chạy chưa và nó giữ gì. admitted False: khoá ĐỘC QUYỀN (Unity) hết giờ chờ — không chạy suite.
    held: suite giữ khoá Unity, hoặc tiến trình cha giữ hộ — môi trường của nó đặt SB_HEAVY_SLOT_HELD=1 (gate lồng không xin gì
    nữa). advisory: suite được chạy theo tải máy mà không giữ khoá Unity — môi trường đặt DEVKIT_SLOT_ADVISORY_HELD=1: gate lồng
    không chờ tải lại nhưng VẪN xin khoá Unity (một unity-batch.sh nằm sâu hai cấp script không lách được khoá Unity)."""

    handles: list
    admitted: bool = True
    held: bool = False
    notes: tuple = ()
    advisory: bool = False


def acquire_for_suite(info: dict, *, est_s: Optional[float] = None, label: str = "", prio: Optional[str] = None,
                      max_wait: Optional[float] = None) -> SuiteSlots:
    """Cho suite chạy theo TẢI MÁY (người dùng 20/10: bỏ 2 slot): tải dưới load_max() thì chạy ngay, cao hơn thì chờ tải xuống tối đa
    DEVKIT_SLOT_LOAD_WAIT_S rồi vẫn chạy (cả tiến trình chờ tải tổng cộng tối đa DEVKIT_SLOT_ADVISORY_BUDGET_S). Rồi suite Unity xin
    khoá độc quyền Unity: hết SB_HEAVY_SLOT_WAIT_S (tính sau lần chờ tải) thì không chạy, như trước. Suite thiết bị không khoá gì.
    max_wait: trần TỔNG cho mọi lần chờ của suite này (ngân sách còn lại của gate, timeout của run_one đang giữ test_run.lock)."""
    if os.environ.get("SB_HEAVY_SLOT_HELD") == "1":
        return SuiteSlots([], admitted=True, held=True)
    t_start = time.monotonic()
    engine = info.get("engine")
    lock_wait = _env_float("SB_HEAVY_SLOT_WAIT_S", DEFAULT_WAIT_S)
    notes = []
    # tiến trình cha đã được cho chạy theo tải (gate lồng trong suite, wrapper CLI): không chờ lại. Merge gate super-board đã bật chờ tải
    # (merge_load_wait_s > 0) thì chờ một lần trước verify rồi đặt DEVKIT_SLOT_LOAD_WAIT_S=0; không bật (mặc định của hầu hết board) hay
    # worktree finish (không tự chờ trước) thì chờ ở đây như mọi lượt.
    if os.environ.get("DEVKIT_SLOT_ADVISORY_HELD") != "1":
        wait_s = _env_float("DEVKIT_SLOT_LOAD_WAIT_S", LOAD_WAIT_S)
        # Ngân sách là giây ĐỒNG HỒ tiến trình chờ tải (OCR 20/10 + 21/10): suite vào lúc khác đang chờ thì chờ tới cùng mốc hết ngân sách
        # (chờ chồng nhau tính một lần, suite nào cũng chờ), không phải mỗi suite một ngân sách trọn, cũng không phải suite đầu giữ hết.
        with _ADVISORY_LOCK:
            now = time.monotonic()
            left = _env_float("DEVKIT_SLOT_ADVISORY_BUDGET_S", ADVISORY_BUDGET_S) - _load_wait_spent(now)
            if left <= 0 < wait_s and not _LOAD_WAIT["noted"]:
                _LOAD_WAIT["noted"] = True
                notes.append("ngân sách chờ tải máy của lượt này đã hết — các suite sau chạy không chờ")
            wait_s = min(wait_s, max(0.0, left))
            if max_wait is not None:
                wait_s = min(wait_s, max(0.0, max_wait))
            if wait_s > 0:
                if not _LOAD_WAIT["active"]:
                    _LOAD_WAIT["since"] = now
                _LOAD_WAIT["active"] += 1
        if wait_s > 0:
            try:
                _, note = wait_load(wait_s, label)
            finally:
                with _ADVISORY_LOCK:
                    _LOAD_WAIT["active"] -= 1
                    if not _LOAD_WAIT["active"]:
                        _LOAD_WAIT["spent"] += time.monotonic() - _LOAD_WAIT["since"]
            if note:
                notes.append(note)
    got = []
    if engine == "unity":
        # Hạn chờ khoá tính SAU lần chờ tải (Antigravity audit 20/10: t_start + min(SB_HEAVY_SLOT_WAIT_S, max_wait) để lần chờ tải ăn
        # mất SB_HEAVY_SLOT_WAIT_S); max_wait vẫn là trần TỔNG tính từ lúc vào.
        lock_start = time.monotonic()
        deadline = lock_start + lock_wait
        if max_wait is not None:
            deadline = min(deadline, t_start + max(0.0, max_wait))
        h = acquire_pool("unity", pool_paths("unity", 1), wait_s=max(0.0, deadline - lock_start), prio=prio, est_s=est_s,
                         label=label)
        if h.timed_out:
            return SuiteSlots([], admitted=False, held=False,
                              notes=tuple(notes) + (f"khoá unity bận hết {h.waited_s:.1f}s — suite không chạy",))
        got.append(h)
    held = any(h.fh is not None for h in got)
    return SuiteSlots(got, admitted=True, held=held, advisory=not held, notes=tuple(notes))


def release_suite(slots: Optional[SuiteSlots]) -> None:
    if slots is not None:
        for h in reversed(slots.handles):
            release_pool(h)
        slots.handles = []


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
            print(f"[heavy-slot] tải máy ≥ {load_max():g} (--nonblock): không chạy lệnh", file=sys.stderr, flush=True)
            return 1
        if not args:
            return 0
        proc = subprocess.run(args)
        return proc.returncode
    finally:
        release(handle)


if __name__ == "__main__":
    sys.exit(main())
