#!/usr/bin/env python3
"""
super_board_monitor.py — Hiển thị trực tiếp (Real-time Live Stream) tiến trình Super-Board Runner
và từng bước suy nghĩ / gõ lệnh (🔧 Tool / 💬 Text) của Worker Agent bên trong cửa sổ TUIOS.
"""
import glob
import json
import os
import sys
import time


def find_latest_jsonl(repo_dir: str):
    slug_path = repo_dir.replace("/", "-")
    candidates = []
    for base in glob.glob(os.path.expanduser("~/.claude*")):
        proj_dir = os.path.join(base, "projects", slug_path)
        if os.path.isdir(proj_dir):
            for f in glob.glob(os.path.join(proj_dir, "*.jsonl")):
                try:
                    candidates.append((os.path.getmtime(f), f))
                except OSError:
                    pass
    if not candidates:
        return None
    candidates.sort(reverse=True)
    return candidates[0][1]


def format_jsonl_line(line: str):
    try:
        obj = json.loads(line)
    except Exception:
        return []
    msg = obj.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        return []
    out = []
    for item in content:
        if not isinstance(item, dict):
            continue
        t = item.get("type")
        if t == "text":
            txt = (item.get("text") or "").strip()
            if txt:
                first_line = txt.splitlines()[0][:120]
                out.append(f"\033[1;36m💬 {first_line}\033[0m")
        elif t == "tool_use":
            name = item.get("name", "Tool")
            inp = item.get("input") or {}
            detail = (
                inp.get("command")
                or inp.get("file_path")
                or inp.get("pattern")
                or inp.get("description")
                or ""
            )
            detail_one = str(detail).strip().splitlines()[0][:100] if detail else ""
            out.append(f"\033[1;33m🔧 {name}\033[0m: {detail_one}")
    return out


def main():
    repo_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    runner_log = os.path.join(repo_dir, "docs", "super-board", "runner.log")
    os.makedirs(os.path.dirname(runner_log), exist_ok=True)
    if not os.path.exists(runner_log):
        open(runner_log, "a").close()

    print(f"\033[1;32m═══ 🛰  SUPER-BOARD LIVE MONITOR: {os.path.basename(repo_dir)} ═══\033[0m", flush=True)

    # In các dòng cuối của runner.log
    try:
        with open(runner_log, "r", encoding="utf-8", errors="replace") as rf:
            lines = rf.readlines()
            for l in lines[-15:]:
                print(f"\033[1;32m[RUNNER]\033[0m {l.rstrip()}", flush=True)
            runner_pos = rf.tell()
    except Exception:
        runner_pos = 0

    cur_jsonl = find_latest_jsonl(repo_dir)
    jsonl_pos = 0
    if cur_jsonl and os.path.exists(cur_jsonl):
        try:
            with open(cur_jsonl, "r", encoding="utf-8", errors="replace") as jf:
                jlines = jf.readlines()
                for jl in jlines[-12:]:
                    for formatted in format_jsonl_line(jl):
                        print(formatted, flush=True)
                jsonl_pos = jf.tell()
        except Exception:
            jsonl_pos = 0

    while True:
        try:
            if os.path.exists(runner_log):
                size = os.path.getsize(runner_log)
                if size < runner_pos:
                    runner_pos = 0
                if size > runner_pos:
                    with open(runner_log, "r", encoding="utf-8", errors="replace") as rf:
                        rf.seek(runner_pos)
                        for l in rf:
                            print(f"\033[1;32m[RUNNER]\033[0m {l.rstrip()}", flush=True)
                        runner_pos = rf.tell()

            newest = find_latest_jsonl(repo_dir)
            if newest != cur_jsonl:
                cur_jsonl = newest
                jsonl_pos = 0

            if cur_jsonl and os.path.exists(cur_jsonl):
                jsize = os.path.getsize(cur_jsonl)
                if jsize < jsonl_pos:
                    jsonl_pos = 0
                if jsize > jsonl_pos:
                    with open(cur_jsonl, "r", encoding="utf-8", errors="replace") as jf:
                        jf.seek(jsonl_pos)
                        for jl in jf:
                            for formatted in format_jsonl_line(jl):
                                print(formatted, flush=True)
                        jsonl_pos = jf.tell()
        except KeyboardInterrupt:
            break
        except Exception:
            pass
        time.sleep(1.0)


if __name__ == "__main__":
    main()
