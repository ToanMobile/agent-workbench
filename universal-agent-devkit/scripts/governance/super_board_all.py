#!/usr/bin/env python3
"""
super_board_all.py — Quản lý đồng thời toàn bộ 6 Super-Board Runners cho 6 Repositories:
  1. agent-workbench             ➔ Project #1
  2. officereader                ➔ Project #2
  3. goods-triple-shelf-match-3d ➔ Project #3
  4. geelyex2                    ➔ Project #4
  5. neighbours-from-hell        ➔ Project #5
  6. humans-vs-ufos              ➔ Project #6

Cách dùng:
  python3 super_board_all.py start   # Khởi động cả 6 runners chạy ngầm cùng lúc
  python3 super_board_all.py status  # Xem trạng thái cả 6 bảng và runners
  python3 super_board_all.py stop    # Dừng an toàn cả 6 runners
"""

import os
import sys
import glob
import json
import subprocess
import time
import argparse
from pathlib import Path

REPOS = [
    {
        "slug": "agent-workbench",
        "name": "Agent Workbench (#1)",
        "dir": "/Volumes/Data/Toan/agent-workbench",
        "url": "https://github.com/users/ToanMobile/projects/1/views/2"
    },
    {
        "slug": "officereader",
        "name": "OfficeReader (#2)",
        "dir": "/Volumes/Data/Toan/OfficeReader/OfficeReader",
        "url": "https://github.com/users/ToanMobile/projects/2/views/2"
    },
    {
        "slug": "goods-triple-shelf-match-3d",
        "name": "Goods 3D (#3)",
        "dir": "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D",
        "url": "https://github.com/users/ToanMobile/projects/3/views/2"
    },
    {
        "slug": "geelyex2",
        "name": "GeelyEx2 (#4)",
        "dir": "/Volumes/Data/Toan/GeelyEx2",
        "url": "https://github.com/users/ToanMobile/projects/4/views/2"
    },
    {
        "slug": "neighbours-from-hell",
        "name": "Neighbours From Hell (#5)",
        "dir": "/Volumes/Data/Toan/Game/Neighbours-From-Hell",
        "url": "https://github.com/users/ToanMobile/projects/5/views/2"
    },
    {
        "slug": "humans-vs-ufos",
        "name": "Humans vs. UFOs (#6)",
        "dir": "/Volumes/Data/Toan/Game/Humans-vs.-UFOs",
        "url": "https://github.com/users/ToanMobile/projects/6/views/2"
    },
]

SLOT_COUNT = 2


def heavy_slot_dir():
    """Thư mục flock dùng chung cho mọi repo. SB_HEAVY_SLOT_DIR ghi đè đường mặc định."""
    custom = os.environ.get("SB_HEAVY_SLOT_DIR", "").strip()
    if custom:
        return custom
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks")


CAPACITY_PY = Path(__file__).resolve().parents[2] / "bin" / "capacity.py"   # nguồn sức chứa chung (T0052)


def hold_load_text():
    """Câu báo ngưỡng tải của suite: hold_load thật của bin/capacity.py (8 × lõi, cùng ngưỡng heavy_slot.load_max); không nạp được
    capacity thì câu dự phòng không có số."""
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("devkit_capacity", str(CAPACITY_PY))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return "dưới %d thì chạy" % mod.hold_load()
    except Exception as exc:   # noqa: BLE001 - chỉ là dòng báo, capacity hỏng kiểu gì cũng không được chặn khởi động runner
        print("⚠ không nạp được %s: %r" % (CAPACITY_PY, exc), file=sys.stderr)
        return "dưới ngưỡng hold_load của bin/capacity.py thì chạy"


def ensure_heavy_slots(directory=None):
    """Tạo đúng 2 file slot cho các bản DevKit cũ còn khoá chúng. DevKit hiện tại không khoá: suite chạy theo tải máy
    (bin/heavy_slot.py, DEVKIT_SLOT_LOAD_MAX, mặc định capacity hold_load = 8 × lõi; người dùng 20/10: bỏ giới hạn 2 slot)."""
    directory = directory or heavy_slot_dir()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    for number in range(1, SLOT_COUNT + 1):
        path = os.path.join(directory, "heavy-gate-%s.lock" % number)
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
    return directory


def ensure_claude_workspace_trust(home_dir=None, repo_dirs=None):
    """Đảm bảo mọi thư mục repo (và worktree hiện có) đã có hasTrustDialogAccepted=True trong các file .claude.json."""
    home = home_dir or os.path.expanduser("~")
    dirs = list(repo_dirs) if repo_dirs is not None else [r["dir"] for r in REPOS]
    for rdir in list(dirs):
        wt_root = os.path.join(rdir, ".claude", "worktrees")
        if os.path.isdir(wt_root):
            for name in os.listdir(wt_root):
                wt_path = os.path.join(wt_root, name)
                if os.path.isdir(wt_path):
                    dirs.append(wt_path)
    cfg_files = [os.path.join(home, ".claude.json")] + glob.glob(os.path.join(home, ".claude*", ".claude.json"))
    for cfg in cfg_files:
        if not os.path.isfile(cfg):
            continue
        try:
            with open(cfg, "r", encoding="utf-8") as f:
                data = json.load(f)
            projects = data.setdefault("projects", {})
            changed = False
            for d in dirs:
                entry = projects.setdefault(d, {})
                if entry.get("hasTrustDialogAccepted") is not True:
                    entry["hasTrustDialogAccepted"] = True
                    changed = True
            if changed:
                tmp = f"{cfg}.{os.getpid()}"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                os.replace(tmp, cfg)
        except (OSError, ValueError) as e:
            print(f"⚠️  Không thể cập nhật workspace trust trong {cfg}: {e}", file=sys.stderr)


def clear_early_deaths(rdir):
    """Xoá các file early-deaths cũ khi khởi động lại bảng để các thẻ vừa gỡ lỗi môi trường được chạy lại."""
    ed_dir = os.path.join(rdir, ".claude", "super-board", "inflight", "early-deaths")
    if not os.path.isdir(ed_dir):
        return
    for name in os.listdir(ed_dir):
        fpath = os.path.join(ed_dir, name)
        if os.path.isfile(fpath):
            try:
                os.remove(fpath)
            except OSError as e:
                print(f"⚠️  Không thể xoá {fpath}: {e}", file=sys.stderr)


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

def start_all():
    print("=================================================================")
    print("  🚀 KHỞI ĐỘNG ĐỒNG THỜI 5 SUPER-BOARD RUNNERS (TỰ HÀNH 24/7)")
    print("=================================================================\n")
    locks_dir = ensure_heavy_slots()
    ensure_claude_workspace_trust()
    print(f"🔒 Suite nặng chạy theo tải máy ({hold_load_text()}; khoá riêng chỉ cho Unity): {locks_dir}\n")
    for repo in REPOS:
        rdir = repo["dir"]
        slug = repo["slug"]
        name = repo["name"]
        
        if not os.path.isdir(rdir):
            print(f"⚠️  Bỏ qua {name}: không tìm thấy thư mục {rdir}")
            continue

        clear_early_deaths(rdir)

        # Đảm bảo thư mục log tồn tại
        os.makedirs(os.path.join(rdir, "docs", "super-board", "runs"), exist_ok=True)
        os.makedirs(os.path.join(rdir, "docs", "super-board", "inflight"), exist_ok=True)

        log_path = os.path.join(rdir, "docs", "super-board", "runner.log")
        worker_log_path = os.path.join(rdir, "docs", "super-board", "current-worker.log")
        Path(log_path).touch(exist_ok=True)
        Path(worker_log_path).touch(exist_ok=True)

        pids = get_running_pids(slug)
        if pids:
            print(f"✅ {name:<30} : Đang chạy sẵn (PID: {', '.join(pids)})")
            continue

        run_script = os.path.join(rdir, ".claude", "bin", "super-board-run.sh")
        if not os.path.isfile(run_script):
            run_script = "/Volumes/Data/Toan/agent-workbench/.claude/bin/super-board-run.sh"

        cmd = runner_launch(rdir, slug, run_script, log_path, locks_dir)
        subprocess.run(cmd, shell=True)
        
        # Lấy PID mới khởi động
        new_pids = get_running_pids(slug)
        pid_str = ', '.join(new_pids) if new_pids else "đã gửi lệnh nền"
        print(f"🚀 {name:<30} : Đã khởi động ngầm (PID: {pid_str})")
        print(f"   Log: {log_path}")

    print("\n🎉 Toàn bộ Runners đã được kích hoạt! Theo dõi: python3 universal-agent-devkit/scripts/governance/super_board_monitor.py <repo>")
    print("💡 Bây giờ bạn vào BẤT KỲ Project Board nào kéo thẻ sang Ready là máy tự động làm!")

def write_stop_marker(marker):
    """Cùng định dạng super-board-stop.sh: watchdog không khởi động lại board có marker."""
    try:
        os.makedirs(os.path.dirname(marker), exist_ok=True)
        with open(marker, "w") as f:
            f.write("STOPPED_AT=%s\nBY=%s via super_board_all.py\nPID=%d\n" % (
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), os.environ.get("USER", "unknown"), os.getpid()))
    except OSError as e:
        print(f"⚠️  không ghi được stop marker {marker}: {e}")


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
        if not os.path.exists(stop_sh):
            # Repo không có stop.sh riêng: stop.sh của agent-workbench tự chuyển về repo của nó nên không ghi marker ở đây.
            write_stop_marker(marker)
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
        print(drift_line(rdir))


def drift_line(rdir, source=None):
    # #368: bản sao super-board ở repo app lệch bản nguồn (repo đầu của REPOS) thì in tên file, không để trôi âm thầm.
    source = source or REPOS[0]["dir"]
    script = os.path.join(source, ".claude", "bin", "super-board-drift.py")
    if os.path.realpath(rdir) == os.path.realpath(source) or not os.path.isfile(script):
        return "   Drift: -"
    try:
        r = subprocess.run([sys.executable, script, "--source", source, "--target", rdir],
                           capture_output=True, text=True, timeout=30)
        res = json.loads(r.stdout)["targets"][rdir]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as exc:
        return f"   Drift: không đọc được ({type(exc).__name__})"
    names = res["changed"] + res["missing"]
    return "   Drift: khớp bản nguồn" if not names else \
        f"   Drift: ⚠️ {len(names)} file lệch bản nguồn ({', '.join(os.path.basename(n) for n in names[:3])}{'…' if len(names) > 3 else ''})"


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
