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

        cmd = f"cd '{rdir}' && SB_DAEMON=1 nohup '{run_script}' {slug} > '{log_path}' 2>&1 &"
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
        # stop.sh chạy cả khi runner đã chết: nó ghi stop marker, thiếu marker thì watchdog khởi động lại board.
        stop_sh = os.path.join(rdir, ".claude", "bin", "super-board-stop.sh")
        marker = os.path.join(rdir, ".claude", "super-board", "runner", f"{slug}.stopped")
        if os.path.exists(stop_sh):
            r = subprocess.run(["bash", stop_sh, slug], cwd=rdir, capture_output=True, text=True)
            if r.returncode != 0:
                print(f"⚠️  {name:<30} : super-board-stop.sh exit {r.returncode}: {r.stderr.strip()[:200]}")
        if not os.path.exists(marker):
            print(f"⚠️  {name:<30} : CHƯA có stop marker {marker} — watchdog có thể khởi động lại board này")
        if not pids:
            print(f"⚪ {name:<30} : Không hoạt động")
            continue

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
        print(watchdog_line(rdir, slug))


def watchdog_line(rdir, slug):
    # Board watchdog đã bỏ cuộc (gave-up, spawn-died, missing-tools, github-halt) không được trông giống board người dùng
    # dừng: in marker, STATE cuối của runner và kết luận gần nhất của watchdog (.claude/super-board/runner/).
    d = os.path.join(rdir, ".claude", "super-board", "runner")

    def kv(path):
        try:
            with open(path, encoding="utf-8") as f:
                return dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
        except OSError:
            return {}

    st, wd = kv(os.path.join(d, f"{slug}.state")), kv(os.path.join(d, f"{slug}.watchdog"))
    mark = "stop marker" if os.path.exists(os.path.join(d, f"{slug}.stopped")) else "no stop marker"
    return (f"   Watchdog: {mark} · runner STATE={st.get('STATE', '-')} rc={st.get('RC', '-')}"
            f" · verdict={wd.get('VERDICT') or '-'} · restarts={wd.get('RESTARTS', '0')}")

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
