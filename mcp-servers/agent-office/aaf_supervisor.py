#!/usr/bin/env python3
"""Multi-repo AAF Supervisor: manages `aaf run --auto` per repo, flock single-instance, caffeinate -w, backoff."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time

import aaf_hub

LOCK_PATH = os.path.join(aaf_hub.AGENT_OFFICE_DIR, "aaf-supervisor.lock")
POLL_SEC = 5.0


def compute_backoff(failures: int) -> int:
    """Exponential backoff 15s -> 30s -> 60s -> 120s -> 240s -> capped 300s."""
    return min(300, 15 * (2 ** max(0, int(failures))))


def acquire_instance_lock(lock_path: str = LOCK_PATH) -> int | None:
    """Acquire non-blocking exclusive flock; returns open fd or None if another instance is live."""
    os.makedirs(os.path.dirname(lock_path), mode=0o700, exist_ok=True)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    os.ftruncate(fd, 0)
    os.write(fd, f"{os.getpid()}\n".encode("ascii"))
    return fd


def build_caffeinate_cmd(parent_pid: int) -> list[str]:
    """Bind caffeinate to parent_pid (-w) so macOS auto-reaps it even on SIGKILL."""
    return ["caffeinate", "-s", "-w", str(int(parent_pid))]


def should_spawn_repo(*, enabled: bool, has_ready: bool, frozen: bool) -> bool:
    return bool(enabled and has_ready and not frozen)


def _terminate_child(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except OSError:
        try:
            proc.terminate()
        except OSError as exc:
            aaf_hub.log_warn("supervisor_terminate", exc)
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except OSError as exc:
            aaf_hub.log_warn("supervisor_sigkill", exc)


def run_supervisor(cfg_path: str) -> int:
    lock_fd = acquire_instance_lock()
    if lock_fd is None:
        print("[aaf-supervisor] Another instance already holds lock, exiting.", flush=True)
        return 0

    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    repo_paths = aaf_hub._build_repo_paths(cfg)
    aaf_bin = aaf_hub.find_aaf_bin()

    workers: dict[str, subprocess.Popen] = {}
    failures: dict[str, int] = {}
    next_try: dict[str, float] = {}
    caff: subprocess.Popen | None = None
    stopping = False

    def _on_sig(signum, _frame):
        nonlocal stopping
        stopping = True
        print(f"[aaf-supervisor] Signal {signum}, shutting down cleanly...", flush=True)

    signal.signal(signal.SIGTERM, _on_sig)
    signal.signal(signal.SIGINT, _on_sig)

    try:
        while not stopping:
            now = time.monotonic()
            sup = aaf_hub.read_supervisor_state()
            enabled = bool(sup.get("enabled", False))
            studio = aaf_hub.read_studio_state(repo_paths=repo_paths, include_manual=False)

            ready_repos: set[str] = set()
            frozen_repos: set[str] = set()
            for t in studio.get("tasks") or []:
                rname = t.get("repo") or ""
                if t.get("frozen"):
                    frozen_repos.add(rname)
                if t.get("state") in ("ready", "running", "building", "gating"):
                    ready_repos.add(rname)

            # Reap finished workers
            for rname, proc in list(workers.items()):
                rc = proc.poll()
                if rc is not None:
                    workers.pop(rname, None)
                    if rc != 0:
                        f_cnt = failures.get(rname, 0) + 1
                        failures[rname] = f_cnt
                        delay = compute_backoff(f_cnt - 1)
                        next_try[rname] = now + delay
                        print(f"[aaf-supervisor] {rname} exited rc={rc}; backoff {delay}s", flush=True)
                    else:
                        failures[rname] = 0

            # Stop workers if supervisor toggled OFF or repo frozen
            for rname, proc in list(workers.items()):
                if not enabled or rname in frozen_repos:
                    print(f"[aaf-supervisor] Stopping worker {rname} (enabled={enabled}, frozen={rname in frozen_repos})", flush=True)
                    _terminate_child(proc)
                    workers.pop(rname, None)

            # Spawn workers for eligible repos
            if enabled:
                for rname, rpath in repo_paths.items():
                    if rname in workers or not os.path.isdir(rpath):
                        continue
                    if not os.path.isfile(os.path.join(rpath, ".autofactory", "config.toml")):
                        continue
                    if now < next_try.get(rname, 0.0):
                        continue
                    if should_spawn_repo(
                        enabled=enabled,
                        has_ready=(rname in ready_repos),
                        frozen=(rname in frozen_repos),
                    ):
                        print(f"[aaf-supervisor] Starting `aaf run --auto` for {rname}", flush=True)
                        workers[rname] = subprocess.Popen(
                            [aaf_bin, "run", "--auto"],
                            cwd=rpath,
                            stdin=subprocess.DEVNULL,
                            start_new_session=True,
                        )

            # Manage caffeinate -s -w <pid> only while work is active
            if workers and (caff is None or caff.poll() is not None):
                try:
                    caff = subprocess.Popen(build_caffeinate_cmd(os.getpid()), stdin=subprocess.DEVNULL)
                except OSError:
                    caff = None
            elif not workers and caff is not None:
                if caff.poll() is None:
                    caff.terminate()
                caff = None

            time.sleep(POLL_SEC)
    finally:
        for proc in workers.values():
            _terminate_child(proc)
        if caff is not None and caff.poll() is None:
            caff.terminate()
        os.close(lock_fd)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="AAF Multi-Repo Supervisor")
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json"))
    args = ap.parse_args()
    return run_supervisor(args.config)


if __name__ == "__main__":
    sys.exit(main())
