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
MONITOR_SCRIPT = ROOT / "universal-agent-devkit" / "scripts" / "governance" / "super_board_monitor.py"


def load():
    spec = importlib.util.spec_from_file_location("super_board_all_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_monitor():
    spec = importlib.util.spec_from_file_location("super_board_monitor_under_test", MONITOR_SCRIPT)
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
    slugs = [r["slug"] for r in board.REPOS]
    check(len(slugs) == 6 and "humans-vs-ufos" in slugs, "REPOS includes all 6 boards including humans-vs-ufos", str(slugs))
    check("idle-plaza-3d" in slugs and "neighbours-from-hell" not in slugs, "REPOS replaces neighbours-from-hell with idle-plaza-3d on Project #5", str(slugs))
    plaza = next((r for r in board.REPOS if r["slug"] == "idle-plaza-3d"), {})
    check(plaza.get("dir") == "/Volumes/Data/Toan/Game/Idle-Plaza-3D" and "/projects/5/" in plaza.get("url", ""), "idle-plaza-3d points to /Volumes/Data/Toan/Game/Idle-Plaza-3D and Project #5", str(plaza))
    with tempfile.TemporaryDirectory() as raw:
        slot_dir = board.ensure_heavy_slots(raw)
        names = sorted(p.name for p in Path(slot_dir).glob("heavy-gate-*.lock"))
        check(names == ["heavy-gate-1.lock", "heavy-gate-2.lock"], "start creates exactly two heavy slots", str(names))
        cmd = board.runner_launch("/repo", "agent-workbench", "/bin/run.sh", "/repo/runner.log", slot_dir)
        check("SB_HEAVY_SLOT_DIR='%s'" % slot_dir in cmd, "runner command pins the shared slot directory")
        check(cmd.startswith("cd '/repo' && SB_DAEMON=1 "), "runner command keeps the per-repo daemon")
        check("nohup '/bin/run.sh' agent-workbench > '/repo/runner.log'" in cmd, "the launch line names the repo slug and its log")

        # T0052: dòng báo ngưỡng tải in hold_load thật của bin/capacity.py (8 × lõi), không phải số 100 viết cứng; thiếu capacity thì
        # câu dự phòng không có số. Nút hệ số DEVKIT_CAPACITY của người gọi (suite_env của gate giữ nó) và tải giả không được lái
        # số kỳ vọng (review 23/10: DEVKIT_CAPACITY=2 làm hai ca này đỏ): gỡ ra, trả lại trong finally
        saved_env = {k: os.environ.pop(k) for k in ("DEVKIT_CAPACITY", "DEVKIT_CAPACITY_LOAD") if k in os.environ}
        old_cores = os.environ.get("DEVKIT_CAPACITY_CORES")
        os.environ["DEVKIT_CAPACITY_CORES"] = "12"
        try:
            text = board.hold_load_text()
            check("dưới 96 thì chạy" in text, "the start line prints capacity hold_load (96 on 12 cores)", text)
            os.environ["DEVKIT_CAPACITY_CORES"] = "4"
            check("dưới 32 thì chạy" in board.hold_load_text(), "  … and follows the core count (32 on 4 cores)", board.hold_load_text())
            saved_path = board.CAPACITY_PY
            board.CAPACITY_PY = Path(raw) / "missing" / "capacity.py"
            try:
                text = board.hold_load_text()
            finally:
                board.CAPACITY_PY = saved_path
            check("hold_load" in text and "100" not in text, "  … without capacity.py: a fallback text, no hard-coded number", text)
        finally:
            if old_cores is None:
                os.environ.pop("DEVKIT_CAPACITY_CORES", None)
            else:
                os.environ["DEVKIT_CAPACITY_CORES"] = old_cores
            os.environ.update(saved_env)

        mon = load_monitor()
        fake_home = Path(raw) / "home"
        root_proj = fake_home / ".claude" / "projects" / "-Volumes-X-Repo"
        wt_proj = fake_home / ".claude-finos" / "projects" / "-Volumes-X-Repo--claude-worktrees-issue-19-build"
        other_proj = fake_home / ".claude" / "projects" / "-Volumes-X-Repo-other"
        root_proj.mkdir(parents=True)
        wt_proj.mkdir(parents=True)
        other_proj.mkdir(parents=True)
        f_root = root_proj / "old.jsonl"
        f_wt = wt_proj / "live-wt.jsonl"
        f_other = other_proj / "other.jsonl"
        f_root.write_text("{}\n")
        f_wt.write_text("{}\n")
        f_other.write_text("{}\n")
        os.utime(f_root, (1000, 1000))
        os.utime(f_wt, (2000, 2000))
        os.utime(f_other, (3000, 3000))
        old_home = os.environ.get("HOME")
        try:
            os.environ["HOME"] = str(fake_home)
            found = mon.find_latest_jsonl("/Volumes/X/Repo")
        finally:
            if old_home is not None:
                os.environ["HOME"] = old_home
        check(found == str(f_wt), "monitor finds newer worktree transcript and ignores prefix-sibling repo", str(found))
    if fails:
        print("test_super_board_all_slots: FAIL (%s)" % fails)
        return 1
    print("test_super_board_all_slots: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
