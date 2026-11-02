"""Chạy gate --full THEO YÊU CẦU từ xưởng (nút "Chạy gate full"), cạnh lượt đêm 00:00 của LaunchAgent.

Dùng lại đúng lượt đêm, không tự chế lệnh:
- lệnh, môi trường, thư mục chạy lấy từ plist com.toanmobile.devkit.gate-full.<slug> mà universal-agent-devkit/bin/gate-full-schedule.sh
  đã cài cho MAIN checkout của repo (ProgramArguments = /usr/bin/nice -n 10 <python3> <main>/…/gate_full.py run --repo <main>,
  EnvironmentVariables có DEVKIT_GATE_FULL_LOG_DIR = ~/Library/Logs/devkit-gate-full/<slug>). Repo chưa cài lịch thì không chạy được
  (nút báo cách cài) — không đoán đường gate_full.py;
- kết quả đọc từ summary-latest.md trong thư mục log đó (gate_full.py ghi), log chạy tay của xưởng: <log dir>/manual-<stamp>.out.log;
- KHÔNG BAO GIỜ hai lượt cùng lúc trên cả máy: gate_full.py giữ khoá toàn máy (flock, DEVKIT_GATE_FULL_GLOBAL_LOCK, mặc định
  ~/Library/Caches/devkit-gate-full/global.lock) suốt lượt, lượt đến sau CHỜ (lượt đêm của repo khác cũng chờ). Ở đây thêm hàng đợi FIFO
  (bỏ trùng repo) để chỉ một tiến trình gate_full.py do xưởng mở tồn tại mỗi lúc và chỉ mở khi khoá toàn máy rảnh.
- Hàng đợi lưu ra file (queueFile, mặc định ~/.agent-office/gate-full-queue.json): server khởi động lại vẫn còn. Lượt đang chạy là
  tiến trình tách rời (start_new_session) nên server tắt nó vẫn chạy tiếp; server mới nhận ra qua khoá của gate_full.py.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import plistlib
import re
import subprocess
import threading
import time

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows
    fcntl = None

LABEL_PREFIX = "com.toanmobile.devkit.gate-full."
DEFAULT_GLOBAL_LOCK = "~/Library/Caches/devkit-gate-full/global.lock"   # cùng mặc định với gate_full.py
RESULT_RE = re.compile(r"^- Kết quả: \*\*(.+?)\*\*", re.M)
LOG_RE = re.compile(r"^- Log: (.+)$", re.M)
VERDICT = {"XANH": "PASS", "ĐỎ": "FAIL", "CHƯA KẾT LUẬN": "INCONCLUSIVE", "LỖI": "ERROR", "BỊ DỪNG (aborted)": "ABORTED"}


def expand(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p))


def global_lock_path() -> str:
    return expand(os.environ.get("DEVKIT_GATE_FULL_GLOBAL_LOCK") or DEFAULT_GLOBAL_LOCK)


def lock_holder(path: str):
    """None khi khoá rảnh (hoặc chưa có file); dict nội dung khoá (pid, repo, started — có thể rỗng) khi đang có lượt giữ flock."""
    if fcntl is None:
        return None
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return None
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except OSError:
            try:
                data = json.loads(os.read(fd, 4096) or b"{}")
            except ValueError:
                data = {}
            return data if isinstance(data, dict) else {}
        fcntl.flock(fd, fcntl.LOCK_UN)
        return None
    finally:
        os.close(fd)


def repo_lock(repo_path: str):
    """Nội dung khoá theo repo của gate_full.py (<main>/.git/postfix-gate/gate-full.lock) khi pid trong đó còn sống, ngược lại None.
    CHỈ ĐỌC, không flock: gate_full.py lấy khoá này kiểu không chờ (LOCK_NB) rồi skip, nên một lần thử flock của xưởng trùng lúc
    lượt đêm khởi động sẽ làm lượt đêm bỏ lượt. gate_full.py gỡ file khi nhả khoá; file còn mà pid chết là khoá mồ côi."""
    try:
        with open(os.path.join(repo_path, ".git", "postfix-gate", "gate-full.lock"), encoding="utf-8") as f:
            data = json.loads(f.read() or "{}")
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and _alive(data.get("pid")) else None


def _alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
    except (ProcessLookupError, ValueError, TypeError):
        return False
    except PermissionError:
        return True
    return True


def next_run(hour: int, minute: int, now: dt.datetime | None = None) -> float:
    now = now or dt.datetime.now()
    t = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if t <= now:
        t += dt.timedelta(days=1)
    return t.timestamp()


class GateFull:
    POLL = 5.0

    def __init__(self, cfg: dict):
        g = cfg.get("gateFull") or {}
        self.la_dir = expand(g.get("launchAgentsDir") or "~/Library/LaunchAgents")
        self.queue_file = expand(g.get("queueFile") or "~/.agent-office/gate-full-queue.json")
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self._plists = {}          # path -> (mtime, info)
        self.proc = None           # Popen của lượt xưởng đang mở
        self.running = None        # {"repo", "pid", "started", "log"}
        self.queue = self._load()

    # ---- hàng đợi bền
    def _load(self) -> list:
        try:
            with open(self.queue_file, encoding="utf-8") as f:
                q = json.load(f)
            return [str(x) for x in q if isinstance(x, str)] if isinstance(q, list) else []
        except (OSError, ValueError):
            return []

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self.queue_file), exist_ok=True)
        tmp = self.queue_file + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.queue, f, ensure_ascii=False)
        os.replace(tmp, self.queue_file)

    # ---- lịch đã cài (plist)
    def schedules(self) -> dict:
        """realpath của repo -> {label, argv, env, cwd, hour, minute, logDir} từ các plist gate-full đã cài."""
        out, seen = {}, set()
        try:
            names = [n for n in os.listdir(self.la_dir) if n.startswith(LABEL_PREFIX) and n.endswith(".plist")]
        except OSError:
            names = []
        for n in names:
            p = os.path.join(self.la_dir, n)
            seen.add(p)
            try:
                m = os.stat(p).st_mtime
            except OSError:
                continue
            hit = self._plists.get(p)
            if not hit or hit[0] != m:
                try:
                    with open(p, "rb") as f:
                        d = plistlib.load(f)
                    argv = [str(x) for x in d.get("ProgramArguments") or []]
                    repo = argv[argv.index("--repo") + 1] if "--repo" in argv[:-1] else d.get("WorkingDirectory")
                    cal = d.get("StartCalendarInterval") or {}
                    env = {str(k): str(v) for k, v in (d.get("EnvironmentVariables") or {}).items()}
                    info = {"label": d.get("Label") or n[:-6], "argv": argv, "env": env, "cwd": d.get("WorkingDirectory") or repo,
                            "repo": repo, "hour": int(cal.get("Hour", 0)), "minute": int(cal.get("Minute", 0)),
                            "logDir": env.get("DEVKIT_GATE_FULL_LOG_DIR") or ""}
                    ok = bool(repo) and any(a.endswith("gate_full.py") for a in argv) and "run" in argv
                except (OSError, ValueError, plistlib.InvalidFileException, IndexError, TypeError):
                    ok, info = False, None
                hit = self._plists[p] = (m, info if ok else None)
            if hit[1]:
                out[os.path.realpath(hit[1]["repo"])] = hit[1]
        for p in list(self._plists):
            if p not in seen:
                self._plists.pop(p, None)
        return out

    # ---- thao tác
    def enqueue(self, repo: str, repo_paths: dict) -> dict:
        path = repo_paths.get(repo)
        if not path:
            raise ValueError("Không có repo " + repo)
        if os.path.realpath(path) not in self.schedules():
            raise ValueError("Repo %s chưa cài lịch gate-full: chạy universal-agent-devkit/bin/gate-full-schedule.sh install --repo %s" % (repo, path))
        with self.lock:
            if self.running and self.running["repo"] == repo:
                return {"ok": True, "state": "running", "already": True}
            if repo in self.queue:
                return {"ok": True, "state": "queued", "position": self.queue.index(repo) + 1, "already": True}
            self.queue.append(repo)
            self._save()
            pos = len(self.queue)
        self.wake.set()
        return {"ok": True, "state": "queued", "position": pos}

    def cancel(self, repo: str) -> dict:
        with self.lock:
            if repo not in self.queue:
                raise ValueError("Repo %s không ở hàng chờ (lượt đang chạy thì không huỷ ở đây)" % repo)
            self.queue.remove(repo)
            self._save()
        return {"ok": True}

    def _spawn(self, info: dict, repo: str):
        log_dir = info["logDir"] or os.path.dirname(self.queue_file)
        os.makedirs(log_dir, exist_ok=True)
        log = os.path.join(log_dir, "manual-%s.out.log" % dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
        env = dict(os.environ, **info["env"])
        with open(log, "ab") as f:
            p = subprocess.Popen(info["argv"], cwd=info["cwd"] or None, env=env, stdin=subprocess.DEVNULL, stdout=f,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        return p, log

    def tick(self, repo_paths: dict) -> None:
        """Một vòng: lượt xưởng đang mở xong chưa; hàng chờ có việc và khoá toàn máy rảnh thì mở lượt kế (đúng một)."""
        with self.lock:
            if self.proc is not None:
                if self.proc.poll() is None:
                    return
                self.proc, self.running = None, None
            if not self.queue or lock_holder(global_lock_path()) is not None:
                return  # lượt khác (đêm, hoặc mở trước khi server khởi động lại) đang chạy: chờ
            sched = self.schedules()
            while self.queue:
                repo = self.queue[0]
                path = repo_paths.get(repo)
                info = sched.get(os.path.realpath(path)) if path else None
                if info:
                    break
                self.queue.pop(0)  # repo đã gỡ lịch / khỏi cấu hình: bỏ
            else:
                self._save()
                return
            self.queue.pop(0)
            self._save()
            try:
                self.proc, log = self._spawn(info, repo)
            except OSError as e:
                self.running = {"repo": repo, "error": str(e)}
                return
            self.running = {"repo": repo, "pid": self.proc.pid, "started": time.time(), "log": log}

    def loop(self, repo_paths_fn) -> None:
        while True:
            try:
                self.tick(repo_paths_fn())
            except Exception as e:  # noqa: BLE001
                print(f"[gate-full] lỗi: {e}", flush=True)
            self.wake.wait(self.POLL)
            self.wake.clear()

    # ---- trạng thái cho trang
    @staticmethod
    def _summary(log_dir: str):
        p = os.path.join(log_dir, "summary-latest.md") if log_dir else ""
        try:
            with open(p, encoding="utf-8") as f:
                text = f.read(20000)
            m = os.path.getmtime(p)
        except OSError:
            return None
        r, lg = RESULT_RE.search(text), LOG_RE.search(text)
        label = r.group(1) if r else "?"
        verdict = next((v for k, v in VERDICT.items() if label == k), "FAIL" if label.startswith("ĐỎ") else label)
        return {"verdict": verdict, "label": label, "at": m, "log": lg.group(1).strip() if lg else p, "summary": p}

    def status(self, repo_paths: dict) -> dict:
        sched = self.schedules()
        g = lock_holder(global_lock_path())
        with self.lock:
            queue, running = list(self.queue), dict(self.running) if self.running else None
        repos = {}
        for name, path in repo_paths.items():
            rp = os.path.realpath(path)
            info = sched.get(rp)
            st = {"installed": bool(info)}
            if info:
                st["next"] = next_run(info["hour"], info["minute"])
                st["logDir"] = info["logDir"]
                st["last"] = self._summary(info["logDir"])
            held = repo_lock(path)
            if held is not None or (running and running.get("repo") == name and running.get("pid")):
                st["state"] = "running"
                st["since"] = (running or {}).get("started") if running and running.get("repo") == name else None
                if not st["since"] and held and held.get("started"):
                    try:
                        st["since"] = dt.datetime.fromisoformat(held["started"]).timestamp()
                    except ValueError:
                        st["since"] = None
                if held is None:
                    st["waiting"] = True  # tiến trình đã mở, đang chờ khoá (tải máy / khoá toàn máy)
                if running and running.get("repo") == name:
                    st["log"] = running.get("log")
            elif name in queue:
                st["state"] = "queued"
                st["position"] = queue.index(name) + 1
            else:
                st["state"] = "idle"
            repos[name] = st
        return {"repos": repos, "queue": queue, "busy": g is not None, "busyRepo": (g or {}).get("repo")}
