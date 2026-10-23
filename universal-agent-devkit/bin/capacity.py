#!/usr/bin/env python3
"""Nguồn sức chứa DUY NHẤT của máy (T0052): mọi giới hạn song song của DevKit và super-board (ngưỡng tải, số job test, nhóm suite
của gate, suite nặng, gate cùng lúc, worker board, lane song song) suy từ số lõi × hệ số DEVKIT_CAPACITY (nhóm suite của gate còn co
lại khi tải cao; máy bận thì các nơi gọi chờ dưới busy_load trước khi chạy), thay
cho các hằng số rải rác (100, 6, 3, 10, 16, 4) chỉ đúng trên máy 12 lõi.

  capacity.py <khoá>    in một số (khoá: xem KEYS, thêm cores / scale / load / free_fraction)
  capacity.py load      in tải 1 phút, hoặc chuỗi rỗng khi không đọc được (exit 0)
  capacity.py --json    in mọi khoá ("load": số thực | null)
  khoá lạ / sai số đối số: exit 2

Biến: DEVKIT_CAPACITY (nút người dùng, số thực kẹp [0.25, 4]; rỗng/rác/≤ 0 = 1), DEVKIT_CAPACITY_CORES và DEVKIT_CAPACITY_LOAD (móc
test: giả số lõi / tải). Biến cũ cụ thể hơn (DEVKIT_SLOT_LOAD_MAX, DEVKIT_TEST_JOBS, …) vẫn do chỗ gọi xét trước. Stdlib; không hàm nào
ném lỗi ra chỗ gọi."""

from __future__ import annotations

import json
import math
import os
import sys

FALLBACK_CORES = 4          # os.cpu_count() không trả lời
MAX_CORES = 1_000_000       # DEVKIT_CAPACITY_CORES lớn hơn là gõ nhầm (và tràn float khi nhân)
SCALE_MIN, SCALE_MAX = 0.25, 4.0
_EPS = 1e-9                 # 12 × (1/3) = 3.9999999… không được làm tròn xuống 3
_READ = object()            # "chưa truyền tải": đọc tải thật


def _floor(x: float) -> int:
    return int(math.floor(x + _EPS))


def cores() -> int:
    """Số lõi: DEVKIT_CAPACITY_CORES (số nguyên 1..MAX_CORES) → os.cpu_count() → 4. Rác thì bỏ nguồn đó."""
    raw = os.environ.get("DEVKIT_CAPACITY_CORES", "").strip()
    try:
        v = int(raw)
        if 1 <= v <= MAX_CORES:
            return v
    except ValueError:
        pass   # rỗng hoặc rác: sang nguồn kế
    c = os.cpu_count()
    return c if isinstance(c, int) and c >= 1 else FALLBACK_CORES


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
    """Ngưỡng tải coi là bận: 3 × lõi × hệ số (12 lõi: 36). Tham số `load` để snapshot() gọi mọi khoá theo một dạng fn(c, s, l)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(3 * c * s))


def free_fraction(cores=None, scale=None, load=_READ) -> float:
    """Phần máy còn rảnh trong [0.25, 1]: tải ≤ lõi × min(1, hệ số) → 1; tải ≥ busy_load → 0.25; giữa hai mức giảm tuyến tính."""
    c, s = _resolve(cores, scale)
    l = _resolve_load(load)
    low = c * min(1.0, s)
    busy = busy_load(c, s)
    if l is None or l <= low:
        return 1.0
    if l >= busy or busy <= low:
        return 0.25
    return 1.0 - 0.75 * (l - low) / (busy - low)


def test_jobs(cores=None, scale=None, load=None) -> int:
    """Số test run_impacted.sh chạy cùng lúc: lõi × 4/3 × hệ số, sàn 4 (12 lõi: 16). KHÔNG co theo tải (người dùng 23/10): máy bận thì
    gate chờ trước khi chạy (heavy_slot); pool nhỏ đi chỉ giành ít CPU hơn các phiên khác và đẩy REG-DK-ALL-01 tới 900 s. Tham số
    `load` giữ để snapshot() gọi mọi khoá theo một dạng fn(c, s, l)."""
    c, s = _resolve(cores, scale)
    return max(4, _floor(c * 4 * s / 3))


def gate_parallel(cores=None, scale=None, load=_READ) -> int:
    """Số suite parallel_safe post-fix-gate chạy cùng nhóm: lõi/2 × hệ số × phần rảnh, sàn 2 (12 lõi rảnh: 6)."""
    c, s = _resolve(cores, scale)
    return max(2, _floor(c * s * free_fraction(c, s, load) / 2))


def heavy_max(cores=None, scale=None, load=None) -> int:
    """Số suite nặng (cpu/gradle/xcode) cùng lúc trên cả máy: lõi/4 × hệ số (12 lõi: 3)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 4))


def gate_max(cores=None, scale=None, load=None) -> int:
    """Số post-fix-gate chạy cùng lúc trên máy (super-board gate_max): lõi/2 × hệ số (12 lõi: 6)."""
    c, s = _resolve(cores, scale)
    return max(1, _floor(c * s / 2))


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
    "busy_load": busy_load, "test_jobs": test_jobs, "gate_parallel": gate_parallel, "heavy_max": heavy_max,
    "gate_max": gate_max, "build_workers": build_workers, "lane_workers": lane_workers, "lane_slots_max": lane_slots_max,
}


def snapshot() -> dict:
    """Mọi khoá trên MỘT lần đọc lõi / hệ số / tải (các khoá khớp nhau)."""
    c, s, l = cores(), scale(), load()
    out = {"cores": c, "scale": s, "load": l, "free_fraction": free_fraction(c, s, l)}
    for name, fn in KEYS.items():
        out[name] = fn(c, s, l)
    return out


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print("usage: capacity.py <key> | --json   (keys: %s, cores, scale, load, free_fraction)" % ", ".join(KEYS), file=sys.stderr)
        return 2
    key = args[0]
    if key == "--json":
        print(json.dumps(snapshot(), sort_keys=True))
        return 0
    if key == "load":
        l = load()
        print("" if l is None else l)
        return 0
    if key == "cores":
        print(cores())
        return 0
    if key == "scale":
        print(scale())
        return 0
    if key == "free_fraction":
        print(free_fraction())
        return 0
    if key in KEYS:
        print(KEYS[key]())
        return 0
    print("capacity.py: unknown key %r (keys: %s, cores, scale, load, free_fraction)" % (key, ", ".join(KEYS)), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
