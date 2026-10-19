#!/usr/bin/env python3
"""super_board_all tạo 2 slot và nhét thư mục đó vào lệnh khởi động từng runner."""
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "universal-agent-devkit" / "scripts" / "governance" / "super_board_all.py"


def load():
    spec = importlib.util.spec_from_file_location("super_board_all_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    fails = 0

    def check(cond, label, detail=""):
        nonlocal fails
        if cond:
            print("✔", label)
        else:
            print("✖", label, detail)
            fails += 1

    board = load()
    with tempfile.TemporaryDirectory() as raw:
        slot_dir = board.ensure_heavy_slots(raw)
        names = sorted(p.name for p in Path(slot_dir).glob("heavy-gate-*.lock"))
        check(names == ["heavy-gate-1.lock", "heavy-gate-2.lock"], "start creates exactly two heavy slots", str(names))
        cmd = board.runner_launch("/repo", "agent-workbench", "/bin/run.sh", "/repo/runner.log", slot_dir)
        check("SB_HEAVY_SLOT_DIR='%s'" % slot_dir in cmd, "runner command pins the shared slot directory")
        check(cmd.startswith("cd '/repo' && SB_DAEMON=1 "), "runner command keeps the per-repo daemon")
        check("nohup '/bin/run.sh' agent-workbench > '/repo/runner.log'" in cmd, "the launch line names the repo slug and its log")
    if fails:
        print("test_super_board_all_slots: FAIL (%s)" % fails)
        return 1
    print("test_super_board_all_slots: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
