#!/usr/bin/env python3
"""tests/lib/watchdog_env.py — phân loại một lần watchdog 7 s của hook (#685), gọi từ tests/lib/case_runner.sh (shell cha).

Hook production (block-dangerous-git.sh, hardware_safety_gate.sh) KHÔNG đổi: watchdog bắn thì hook chặn (exit 2, fail-closed). Test chỉ
quyết định ca đó là ENVB (đói tải, không có phán quyết) hay FAIL; KHÔNG BAO GIỜ PASS. In đúng một dòng: "ENVB <lý do>" hoặc "FAIL <lý do>".

ENVB khi đủ cả ba: (1) CPU cây hook < 50 % cửa sổ (HOOK_WATCHDOG_WINDOW_S, mặc định 7 s) — hook tự đốt CPU là lỗi thật, không phải đói tải;
(2) tải ≥ capacity.hold_load(lõi, hệ số) (tải không đọc được ⇒ coi là không bận ⇒ FAIL); (3) tổng số watchdog trong lượt ≤ 10.
Núm đã lưu trước khi clean_git_env.sh unset DEVKIT_CAPACITY*: --cap-saved (DEVKIT_CAPACITY của người chạy) và móc test
--test-load / --test-cores (HOOK_WATCHDOG_TEST_LOAD / _CORES). Mọi phép parse/kẹp đi qua bin/capacity.py (scale(), cores(), load(), hold_load()).
ponytail: chưa tách treo I/O (CPU ≈ 0: git/adb chặn) khỏi đói CPU do tải; hai lớp chặn còn lại là hold_load và trần 10 lần. Nâng khi
gate-full vẫn đỏ oan hoặc xanh oan vì điều kiện này.
"""
import argparse
import os
import sys

MAX_ENV_BLOCKED = 10


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--kit", required=True)
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--cpu-file", default="")
    ap.add_argument("--cap-saved", default="")
    ap.add_argument("--test-load", default="")
    ap.add_argument("--test-cores", default="")
    a = ap.parse_args(argv)

    wd_file = os.path.join(a.state_dir, "wd")
    with open(wd_file, "a", encoding="utf-8") as f:
        f.write("wd\n")
    with open(wd_file, encoding="utf-8") as f:
        count = sum(1 for _ in f)

    cpu_ms = None
    try:
        with open(a.cpu_file, encoding="utf-8") as f:
            cpu_ms = int(f.read().strip())
    except (OSError, ValueError):
        pass
    try:
        window = float(os.environ.get("HOOK_WATCHDOG_WINDOW_S", "7"))
    except ValueError:
        window = 7.0
    if window <= 0:
        window = 7.0

    if cpu_ms is None:
        print("FAIL không đo được CPU của hook")
        return 0
    if cpu_ms >= 0.5 * window * 1000:
        print("FAIL hook tự tốn CPU %d ms (>= 50%% cửa sổ %.2f s): không phải đói tải" % (cpu_ms, window))
        return 0
    if count > MAX_ENV_BLOCKED:
        print("FAIL watchdog bắn lần thứ %d (> %d): coi là hook hỏng" % (count, MAX_ENV_BLOCKED))
        return 0

    sys.path.insert(0, os.path.join(a.kit, "bin"))
    try:
        import capacity  # noqa: PLC0415
    except Exception as e:  # noqa: BLE001
        print("FAIL không nạp được bin/capacity.py (%s)" % str(e)[:80])
        return 0
    if a.test_cores:
        os.environ["DEVKIT_CAPACITY_CORES"] = a.test_cores
    if a.test_load:
        os.environ["DEVKIT_CAPACITY_LOAD"] = a.test_load
    if a.cap_saved:
        os.environ["DEVKIT_CAPACITY"] = a.cap_saved
    cores, scale, load = capacity.cores(), capacity.scale(), capacity.load()
    if load is None:
        print("FAIL không đọc được tải: coi là không bận")
        return 0
    hold = capacity.hold_load(cores, scale)
    if load >= hold:
        print("ENVB tải %.1f >= hold_load %d, CPU hook %d ms, watchdog lần %d" % (load, hold, cpu_ms, count))
    else:
        print("FAIL tải %.1f < hold_load %d: máy không bận, không có lý do đói tải" % (load, hold))
    return 0


if __name__ == "__main__":
    sys.exit(main())
