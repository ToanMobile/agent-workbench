#!/usr/bin/env python3
"""Nguồn sức chứa DUY NHẤT của máy (T0052): mọi giới hạn song song của DevKit và super-board (ngưỡng tải, số job test, nhóm suite
của gate, suite nặng, gate cùng lúc, worker board, lane song song) suy từ số lõi × hệ số DEVKIT_CAPACITY (nhóm suite của gate còn co
lại khi tải cao), thay cho các hằng số rải rác (100, 6, 3, 10, 16, 4) chỉ đúng trên máy 12 lõi.

Hai ngưỡng tải:
  hold_load (8 × lõi, 12 lõi: 96)  việc BẮT BUỘC (suite của gate trong heavy_slot, verify của merge gate) chỉ chờ khi tải trên mức này
                                   (người dùng 20/10: "dưới 100 thì cho chạy" — máy này tải 45–100 cả ngày);
  busy_load (3 × lõi, 12 lõi: 36)  chỉ để mở thêm việc TÙY CHỌN (worker build / QA / review thêm của super-board).
Nhóm suite của gate co dần từ tải = lõi tới hold_load (free_fraction).

  capacity.py <khoá>    in một số (khoá: xem KEYS, thêm cores / scale / load / free_fraction / gate_busy)
  capacity.py load      in tải 1 phút, hoặc chuỗi rỗng khi không đọc được (exit 0)
  capacity.py --json    in mọi khoá ("load": số thực | null)
  khoá lạ / sai số đối số: exit 2

Biến: DEVKIT_CAPACITY (nút người dùng, số thực kẹp [0.25, 4]; rỗng/rác/≤ 0 = 1), DEVKIT_CAPACITY_CORES, DEVKIT_CAPACITY_LOAD và
DEVKIT_TEST_JOBS_BUSY (móc test / ghi đè số slot pool gate đang bận). Biến cũ cụ thể hơn (DEVKIT_SLOT_LOAD_MAX, DEVKIT_TEST_JOBS, …)
vẫn do chỗ gọi xét trước. Stdlib thuần (không import heavy_slot); không hàm nào ném lỗi ra chỗ gọi."""

from __future__ import annotations

import errno
import json
import math
import os
import stat
import sys

FALLBACK_CORES = 4          # os.cpu_count() không trả lời
MAX_CORES = 1_000_000       # DEVKIT_CAPACITY_CORES lớn hơn là gõ nhầm (và tràn float khi nhân)
MAX_GATE_SLOTS = 256        # trần an toàn khi quét file gate-<i>.lock tránh DEVKIT_GATE_SLOTS khổng lồ
MAX_PID = 2_147_483_647     # trần PID hợp lệ POSIX 32-bit tránh OverflowError trong os.kill
DEFAULT_LOCK_DIR = "~/.claude/super-board/locks"   # đồng bộ quy ước thư mục khoá với bin/heavy_slot.py
SCALE_MIN, SCALE_MAX = 0.25, 4.0
_EPS = 1e-9                 # 12 × (1/3) = 3.9999999… không được làm tròn xuống 3
_READ = object()            # "chưa truyền tải": đọc tải thật


def _floor(x: float) -> int:
    return int(math.floor(x + _EPS))


def cores() -> int:
    """Số lõi: DEVKIT_CAPACITY_CORES (số nguyên 1..MAX_CORES) → số CPU tiến trình được dùng → 4. Rác thì bỏ nguồn đó."""
    raw = os.environ.get("DEVKIT_CAPACITY_CORES", "").strip()
    try:
        v = int(raw)
        if 1 <= v <= MAX_CORES:
            return v
    except ValueError:
        pass   # rỗng hoặc rác: sang nguồn kế
    # CPU tiến trình này được dùng (affinity / cgroup), không phải cả máy: process_cpu_count (3.13+) → sched_getaffinity (Linux)
    # → cpu_count. Nguồn trả None, 0 hay lỗi thì sang nguồn kế.
    probes = []
    if hasattr(os, "process_cpu_count"):
        probes.append(os.process_cpu_count)
    if hasattr(os, "sched_getaffinity"):
        probes.append(lambda: len(os.sched_getaffinity(0)))
    probes.append(os.cpu_count)
    for probe in probes:
        try:
            c = probe()
        except (OSError, ValueError, TypeError):
            continue
        if isinstance(c, int) and c >= 1:
            return c
    return FALLBACK_CORES


def load():
    """Tải 1 phút: DEVKIT_CAPACITY_LOAD (số thực ≥ 0) → os.getloadavg()[0]; không đọc được thì None."""
    raw = os.environ.get("DEVKIT_CAPACITY_LOAD", "").strip()
    if raw:
        try:
            v = float(raw)
            if math.isfinite(v) and v >= 0:
                return v
        except ValueError:
            pass   # rác: đọc tải thật
    try:
        v = float(os.getloadavg()[0])
    except (OSError, AttributeError, IndexError, TypeError, ValueError):   # Windows không có getloadavg
        return None
    return v if math.isfinite(v) and v >= 0 else None


def scale() -> float:
    """Hệ số người dùng DEVKIT_CAPACITY kẹp [0.25, 4]; rỗng, rác, nan/inf hay ≤ 0 thì 1."""
    try:
        v = float(os.environ.get("DEVKIT_CAPACITY", "").strip())
    except ValueError:
        return 1.0
    if not math.isfinite(v) or v <= 0:
        return 1.0
    return min(SCALE_MAX, max(SCALE_MIN, v))


def _resolve(c, s):
    return (cores() if c is None else c), (scale() if s is None else s)


def _resolve_load(l):
    return load() if l is _READ else l


def busy_load(cores=None, scale=None, load=None) -> int:
    """Ngưỡng tải coi là bận, cho việc TÙY CHỌN (mở thêm worker super-board): 3 × lõi × hệ số (12 lõi: 36). Tham số `load` để
    snapshot() gọi mọi khoá theo một dạng fn(c, s, l)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(3 * c * s))


def hold_load(cores=None, scale=None, load=None) -> int:
    """Ngưỡng tải mà việc BẮT BUỘC (suite của gate, verify của merge gate) chờ ở trên: 8 × lõi × hệ số (12 lõi: 96 — người dùng 20/10:
    "dưới 100 thì cho chạy"). Tham số `load` để snapshot() gọi mọi khoá theo một dạng fn(c, s, l)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(8 * c * s))


def free_fraction(cores=None, scale=None, load=_READ) -> float:
    """Phần máy còn rảnh trong [0.25, 1]: tải ≤ lõi × min(1, hệ số) → 1; tải ≥ hold_load → 0.25; giữa hai mức giảm tuyến tính.
    Trần là hold_load chứ không phải busy_load: gate_parallel (người dùng duy nhất) phục vụ việc BẮT BUỘC, máy này tải 45–100 cả
    ngày, co hết ở 36 thì gate luôn chạy 2 suite (12 lõi: tải 24 → 5, 36 → 4, 60 → 3, 90 → 2)."""
    c, s = _resolve(cores, scale)
    l = _resolve_load(load)
    low = c * min(1.0, s)
    hold = hold_load(c, s)
    if l is None or l <= low:
        return 1.0
    if l >= hold or hold <= low:
        return 0.25
    return 1.0 - 0.75 * (l - low) / (hold - low)


def _has_valid_cores_env() -> bool:
    """True khi người gọi chủ động ghim số lõi qua DEVKIT_CAPACITY_CORES hợp lệ."""
    raw = os.environ.get("DEVKIT_CAPACITY_CORES", "").strip()
    if not raw:
        return False
    try:
        v = int(raw, 10)
    except ValueError:
        return False
    return 1 <= v <= MAX_CORES


def _parse_busy_env():
    """Đọc DEVKIT_TEST_JOBS_BUSY: rỗng -> None; số nguyên 0..MAX_CORES -> max(1, v); rác -> cảnh báo stderr, trả None."""
    raw = os.environ.get("DEVKIT_TEST_JOBS_BUSY", "").strip()
    if not raw:
        return None
    try:
        v = int(raw, 10)
        if 0 <= v <= MAX_CORES:
            return max(1, v)
    except ValueError:
        pass
    print("[capacity] DEVKIT_TEST_JOBS_BUSY=%r không hợp lệ (cần số nguyên 0..%d); bỏ qua" % (raw[:40], MAX_CORES), file=sys.stderr)
    return None


def _pid_alive(pid) -> bool:
    """Kiểm tra PID còn sống mà không import heavy_slot (giữ capacity.py chạy độc lập trong mk_kit / super-board-capacity)."""
    if not isinstance(pid, int) or isinstance(pid, bool) or not (0 < pid <= MAX_PID):
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except (OSError, OverflowError, ValueError, TypeError):
        return False
    return True


def _gate_slots_count(c: int, s: float) -> int:
    """Số slot của pool 'gate': DEVKIT_GATE_SLOTS nguyên ≥ 0 nếu có (0 = tắt hàng đợi), không thì gate_max(c, s), kẹp MAX_GATE_SLOTS."""
    raw = os.environ.get("DEVKIT_GATE_SLOTS", "").strip()
    if raw:
        try:
            n = int(raw, 10)
            if n >= 0:
                return 0 if n == 0 else min(n, MAX_GATE_SLOTS)
        except ValueError:
            pass
    return min(gate_max(c, s), MAX_GATE_SLOTS)


def _read_gate_locks(c: int, s: float, slot_dir=None) -> int:
    """Đếm PID sống trong thư mục khoá pool 'gate' (trả tối thiểu 1)."""
    d = (slot_dir.strip() if isinstance(slot_dir, str) else "") or os.environ.get("SB_HEAVY_SLOT_DIR", "").strip()
    if not d:
        d = os.path.expanduser(DEFAULT_LOCK_DIR)
    try:
        lst = os.lstat(d)
    except FileNotFoundError:
        return 1   # thư mục khoá chưa từng tạo: rảnh, không in cảnh báo
    except OSError as exc:
        print("[capacity] không đọc được thư mục khoá %s: %s; dùng busy=1" % (d, exc), file=sys.stderr)
        return 1
    if stat.S_ISLNK(lst.st_mode) or not stat.S_ISDIR(lst.st_mode):
        print("[capacity] đường dẫn khoá %s không phải thư mục thực (symlink hoặc file); dùng busy=1" % d, file=sys.stderr)
        return 1
    n = _gate_slots_count(c, s)
    if n <= 0:
        return 1
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    live_pids = set()
    for i in range(1, n + 1):
        p = os.path.join(d, "gate-%d.lock" % i)
        try:
            fd = os.open(p, flags)
        except FileNotFoundError:
            continue
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                continue
            print("[capacity] không mở được file khoá %s: %s; dùng busy=1" % (p, exc), file=sys.stderr)
            return 1
        try:
            fst = os.fstat(fd)
            if not stat.S_ISREG(fst.st_mode):
                continue
            raw = os.read(fd, 64)
        except OSError as exc:
            print("[capacity] lỗi đọc file khoá %s: %s; dùng busy=1" % (p, exc), file=sys.stderr)
            return 1
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        txt = raw.decode("utf-8", errors="replace").strip()
        if not txt:
            continue
        try:
            pid = int(txt, 10)
        except ValueError:
            print("[capacity] nội dung PID không hợp lệ trong %s; bỏ qua" % p, file=sys.stderr)
            continue
        if _pid_alive(pid):
            live_pids.add(pid)
    return max(1, len(live_pids))


def gate_busy(cores=None, scale=None, slot_dir=None) -> int:
    """Số slot pool 'gate' đang có tiến trình sống giữ khoá (tối thiểu 1 để chia mẫu số an toàn, #787).
    Tuyệt đối KHÔNG dùng flock dưới mọi dạng (kể cả LOCK_SH|LOCK_NB) để không bao giờ làm hụt acquire_pool(wait_s=0)
    của _gate_pool_has_room; mở O_RDONLY|O_NOFOLLOW|O_NONBLOCK chống treo FIFO và khử trùng tập PID sống."""
    c, s = _resolve(cores, scale)
    if slot_dir is None:
        if os.environ.get("SB_HEAVY_SLOT_HELD") == "1" or os.environ.get("_DEVKIT_CHILD_TEST") == "1":
            return 1
        eb = _parse_busy_env()
        if eb is not None:
            return eb
    return _read_gate_locks(c, s, slot_dir=slot_dir)


def _effective_busy(c: int, s: float, cores_arg=None, busy=None) -> int:
    """Xác định mẫu số slot bận cho test_jobs() và snapshot():
    1) busy truyền tường minh (int ≥ 0, không phải bool);
    2) cô lập tuyệt đối các bài test có sẵn qua SB_HEAVY_SLOT_HELD=1 (clean_git_env.sh) / _DEVKIT_CHILD_TEST=1;
    3) DEVKIT_TEST_JOBS_BUSY hợp lệ hoặc SB_HEAVY_SLOT_DIR đặt tường minh;
    4) truy vấn giả lập số lõi (cores_arg / DEVKIT_CAPACITY_CORES) trả 1 tất định; còn lại thăm thư mục khoá thật."""
    if busy is not None:
        if isinstance(busy, int) and not isinstance(busy, bool) and busy >= 0:
            return max(1, busy)
        return 1
    if os.environ.get("SB_HEAVY_SLOT_HELD") == "1" or os.environ.get("_DEVKIT_CHILD_TEST") == "1":
        return 1
    eb = _parse_busy_env()
    if eb is not None:
        return eb
    if os.environ.get("SB_HEAVY_SLOT_DIR", "").strip():
        return _read_gate_locks(c, s)
    if cores_arg is not None or _has_valid_cores_env():
        return 1
    return _read_gate_locks(c, s)


def test_jobs(cores=None, scale=None, load=None, busy=None) -> int:
    """Số test run_impacted.sh chạy cùng lúc trên mỗi lượt gate (#787): max(4, ⌊lõi × 4 × hệ số / (3 × busy)⌋)
    (12 lõi: busy=1 → 16, busy=2 → 8, busy=3 → 5; tổng toàn máy ~15–16 job thay vì 48; busy chụp lúc khởi chạy shard).
    KHÔNG co theo tải 1 phút (người dùng 23/10): máy bận thì gate chờ trước khi chạy (heavy_slot). Tham số `load` giữ để
    snapshot() và caller 3 đối số vị trí tương thích ngược 100%."""
    c, s = _resolve(cores, scale)
    b = _effective_busy(c, s, cores_arg=cores, busy=busy)
    return max(4, _floor(c * 4 * s / (3 * b)))


def gate_parallel(cores=None, scale=None, load=_READ) -> int:
    """Số suite parallel_safe post-fix-gate chạy cùng nhóm: lõi/2 × hệ số × phần rảnh, sàn 2 (12 lõi rảnh: 6)."""
    c, s = _resolve(cores, scale)
    return max(2, _floor(c * s * free_fraction(c, s, load) / 2))


def heavy_max(cores=None, scale=None, load=None) -> int:
    """Số suite nặng (cpu/gradle/xcode) cùng lúc trên cả máy: lõi/4 × hệ số (12 lõi: 3)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 4))


def gate_max(cores=None, scale=None, load=None) -> int:
    """Số post-fix-gate chạy suite cùng lúc trên cả máy (pool gate): lõi/4 × hệ số (12 lõi: 3)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 4))


def build_workers(cores=None, scale=None, load=None) -> int:
    """Trần worker lane build của super-board: lõi × 5/6 × hệ số (12 lõi: 10)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * 5 * s / 6))


def lane_workers(cores=None, scale=None, load=None) -> int:
    """Trần worker mỗi lane QA / Review của super-board: lõi/4 × hệ số (12 lõi: 3)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 4))


def lane_slots_max(cores=None, scale=None, load=None) -> int:
    """Trần lane agent song song của lane_plan.py: lõi/3 × hệ số (12 lõi: 4)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 3))


# khoá đếm (int ≥ 1) mà CLI in; jobs_per_lane không ở đây (lane_plan giữ 4 cố định: chi phí một lane, không phải sức máy)
KEYS = {
    "busy_load": busy_load, "hold_load": hold_load, "test_jobs": test_jobs, "gate_parallel": gate_parallel, "heavy_max": heavy_max,
    "gate_max": gate_max, "build_workers": build_workers, "lane_workers": lane_workers, "lane_slots_max": lane_slots_max,
}


def snapshot() -> dict:
    """Mọi khoá trên MỘT lần đọc lõi / hệ số / tải / slot bận (các khoá khớp nhau)."""
    c, s, l = cores(), scale(), load()
    b = _effective_busy(c, s, cores_arg=None, busy=None)
    out = {"cores": c, "scale": s, "load": l, "free_fraction": free_fraction(c, s, l)}
    for name, fn in KEYS.items():
        out[name] = test_jobs(c, s, l, busy=b) if name == "test_jobs" else fn(c, s, l)
    return out


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print("usage: capacity.py <key> | --json   (keys: %s, cores, scale, load, free_fraction, gate_busy)" % ", ".join(KEYS), file=sys.stderr)
        return 2
    key = args[0]
    if key == "--json":
        print(json.dumps(snapshot(), sort_keys=True))
        return 0
    if key == "load":
        l = load()
        print("" if l is None else l)
        return 0
    fn = KEYS.get(key) or {"cores": cores, "scale": scale, "free_fraction": free_fraction, "gate_busy": gate_busy}.get(key)
    if fn is not None:
        print(fn())
        return 0
    print("capacity.py: unknown key %r (keys: %s, cores, scale, load, free_fraction, gate_busy)" % (key, ", ".join(KEYS)), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
