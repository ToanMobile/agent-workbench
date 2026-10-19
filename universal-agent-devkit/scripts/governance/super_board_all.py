#!/usr/bin/env python3
"""
super_board_all.py — Quản lý đồng thời toàn bộ 5 Super-Board Runners cho 5 Repositories:
  1. agent-workbench             ➔ Project #1
  2. officereader                ➔ Project #2
  3. goods-triple-shelf-match-3d ➔ Project #3
  4. geelyex2                    ➔ Project #4
  5. neighbours-from-hell        ➔ Project #5

Cách dùng:
  python3 super_board_all.py start   # Khởi động cả 5 runners chạy ngầm cùng lúc
  python3 super_board_all.py status  # Xem trạng thái cả 5 bảng và runners
  python3 super_board_all.py stop    # Dừng an toàn cả 5 runners
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

REPOS = [
    {
        "slug": "agent-workbench",
        "name": "Agent Workbench (#1)",
        "dir": "/Volumes/Data/Toan/agent-workbench",
        "tuios_window": "agent-workbench",
        "url": "https://github.com/users/ToanMobile/projects/1/views/2"
    },
    {
        "slug": "officereader",
        "name": "OfficeReader (#2)",
        "dir": "/Volumes/Data/Toan/OfficeReader/OfficeReader",
        "tuios_window": "OfficeReader",
        "url": "https://github.com/users/ToanMobile/projects/2/views/2"
    },
    {
        "slug": "goods-triple-shelf-match-3d",
        "name": "Goods 3D (#3)",
        "dir": "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D",
        "tuios_window": "Goods-Triple",
        "url": "https://github.com/users/ToanMobile/projects/3/views/2"
    },
    {
        "slug": "geelyex2",
        "name": "GeelyEx2 (#4)",
        "dir": "/Volumes/Data/Toan/GeelyEx2",
        "tuios_window": "GeelyEx2",
        "url": "https://github.com/users/ToanMobile/projects/4/views/2"
    },
    {
        "slug": "neighbours-from-hell",
        "name": "Neighbours From Hell (#5)",
        "dir": "/Volumes/Data/Toan/Game/Neighbours-From-Hell",
        "tuios_window": "Neighbours",
        "url": "https://github.com/users/ToanMobile/projects/5/views/2"
    },
]

SLOT_COUNT = 2


def heavy_slot_dir():
    """Thư mục flock dùng chung cho mọi repo. SB_HEAVY_SLOT_DIR ghi đè đường mặc định."""
    custom = os.environ.get("SB_HEAVY_SLOT_DIR", "").strip()
    if custom:
        return custom
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks")


def ensure_heavy_slots(directory=None):
    """Tạo đúng 2 file slot. post-fix-gate --full của mọi runner lấy flock trên các file này."""
    directory = directory or heavy_slot_dir()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    for number in range(1, SLOT_COUNT + 1):
        path = os.path.join(directory, "heavy-gate-%s.lock" % number)
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
    return directory


def runner_launch(rdir, slug, run_script, log_path, slot_dir):
    """Một runner vẫn là một vòng lặp, nhưng verify nặng dùng đúng thư mục slot của process này."""
    return (
        "cd '%s' && SB_DAEMON=1 SB_HEAVY_SLOT_DIR='%s' nohup '%s' %s > '%s' 2>&1 &"
        % (rdir, slot_dir, run_script, slug, log_path)
    )


def get_running_pids(slug):
    cmd = f"ps aux | grep -i 'super-board-run.sh {slug}' | grep -v grep | awk '{{print $2}}'"
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return [p.strip() for p in r.stdout.strip().splitlines() if p.strip()]

def attach_tuios_log(tuios_win, rdir):
    tuios_bin = "/Users/alex/.local/bin/tuios"
    monitor_py = "/Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_monitor.py"
    if not os.path.isfile(tuios_bin):
        return
    subprocess.run([tuios_bin, "send-keys", "-s", "factory", "-w", tuios_win, "ctrl+c"], capture_output=True)
    mon_cmd = f"python3 '{monitor_py}' '{rdir}'\n"
    subprocess.run([tuios_bin, "send-text", "-s", "factory", "-w", tuios_win, mon_cmd], capture_output=True)

def start_all():
    print("=================================================================")
    print("  🚀 KHỞI ĐỘNG ĐỒNG THỜI 5 SUPER-BOARD RUNNERS (TỰ HÀNH 24/7)")
    print("=================================================================\n")
    locks_dir = ensure_heavy_slots()
    print(f"🔒 Heavy-gate slots (--full toàn máy, tối đa {SLOT_COUNT}): {locks_dir}/heavy-gate-{{1,2}}.lock\n")
    for repo in REPOS:
        rdir = repo["dir"]
        slug = repo["slug"]
        name = repo["name"]
        tuios_win = repo["tuios_window"]
        
        if not os.path.isdir(rdir):
            print(f"⚠️  Bỏ qua {name}: không tìm thấy thư mục {rdir}")
            continue

        # Đảm bảo thư mục log tồn tại
        os.makedirs(os.path.join(rdir, "docs", "super-board", "runs"), exist_ok=True)
        os.makedirs(os.path.join(rdir, "docs", "super-board", "inflight"), exist_ok=True)

        log_path = os.path.join(rdir, "docs", "super-board", "runner.log")
        worker_log_path = os.path.join(rdir, "docs", "super-board", "current-worker.log")
        Path(log_path).touch(exist_ok=True)
        Path(worker_log_path).touch(exist_ok=True)

        pids = get_running_pids(slug)
        if pids:
            attach_tuios_log(tuios_win, rdir)
            print(f"✅ {name:<30} : Đang chạy sẵn (PID: {', '.join(pids)})")
            continue

        run_script = os.path.join(rdir, ".claude", "bin", "super-board-run.sh")
        if not os.path.isfile(run_script):
            run_script = "/Volumes/Data/Toan/agent-workbench/.claude/bin/super-board-run.sh"

        cmd = runner_launch(rdir, slug, run_script, log_path, locks_dir)
        subprocess.run(cmd, shell=True)
        attach_tuios_log(tuios_win, rdir)
        
        # Lấy PID mới khởi động
        new_pids = get_running_pids(slug)
        pid_str = ', '.join(new_pids) if new_pids else "đã gửi lệnh nền"
        print(f"🚀 {name:<30} : Đã khởi động ngầm (PID: {pid_str})")
        print(f"   Log: {log_path}")

    print("\n🎉 Toàn bộ 5 Runners đã được kích hoạt & hiển thị trên TUIOS (tuios attach factory)!")
    print("💡 Bây giờ bạn vào BẤT KỲ Project Board nào kéo thẻ sang Ready là máy tự động làm!")

def stop_all():
    print("=================================================================")
    print("  🛑 DỪNG TOÀN BỘ 5 SUPER-BOARD RUNNERS")
    print("=================================================================\n")
    for repo in REPOS:
        slug = repo["slug"]
        name = repo["name"]
        rdir = repo["dir"]
        pids = get_running_pids(slug)
        if not pids:
            print(f"⚪ {name:<30} : Không hoạt động")
            continue

        stop_sh = os.path.join(rdir, ".claude", "bin", "super-board-stop.sh")
        if os.path.exists(stop_sh):
            subprocess.run(["bash", stop_sh, slug], cwd=rdir, capture_output=True)
        for p in pids:
            try:
                os.kill(int(p), 15)  # SIGTERM
            except Exception:
                pass
        print(f"🛑 {name:<30} : Đã dừng an toàn (PIDs: {', '.join(pids)})")
    print("\n✅ Đã dừng toàn bộ các runner.")

def status_all():
    print("=================================================================")
    print("  📊 TRẠNG THÁI 5 SUPER-BOARD RUNNERS & GITHUB BOARDS")
    print("=================================================================\n")
    for repo in REPOS:
        rdir = repo["dir"]
        slug = repo["slug"]
        name = repo["name"]
        url = repo["url"]
        pids = get_running_pids(slug)

        status_icon = "🟢 Đang chạy" if pids else "⚪ Đã tắt"
        pid_info = f"(PID: {', '.join(pids)})" if pids else ""
        print(f"{status_icon:<14} {name:<32} {pid_info}")
        print(f"   Board: {url}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Quản lý đồng thời cả 5 Super-Board Runners")
    parser.add_argument("action", choices=["start", "stop", "status"], default="status", nargs="?", help="Hành động: start | stop | status")
    args = parser.parse_args()

    if args.action == "start":
        start_all()
    elif args.action == "stop":
        stop_all()
    else:
        status_all()
