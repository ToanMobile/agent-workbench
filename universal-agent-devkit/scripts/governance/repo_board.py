#!/usr/bin/env python3
"""repo_board.py — đọc thông tin GitHub Project board từ cấu hình super-board của repo hiện tại.

Dùng chung cho `agent-kit board`, `context_sync.py` (ghi dòng board vào `AGENTS.md`),
`create_task.py`, `enrich_context.py`, `session_context.sh`, hook và wrapper `gh`.
Chỉ dùng thư viện chuẩn Python.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

_REPO_SLUG_RE = re.compile(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$")


def _parse_repo_slug(url: str | None) -> str:
    m = _REPO_SLUG_RE.search((url or "").strip())
    return m.group(1) if m else ""


def _git_toplevel(path: str) -> str | None:
    try:
        r = subprocess.run(
            ["git", "-C", path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0 and r.stdout.strip():
            return os.path.realpath(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def _origin_slug(root: str) -> str:
    try:
        r = subprocess.run(
            ["git", "-C", root, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            return _parse_repo_slug(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return ""


def _resolve_candidate_root(cand: str) -> str:
    if not os.path.isdir(cand):
        cand = os.path.dirname(cand) or os.getcwd()
    # Nếu thư mục truyền vào đã có cấu hình super-board thì dùng ngay, tránh thoát ra repo cha nếu lồng nhau.
    if os.path.isdir(os.path.join(cand, ".claude", "super-board", "configs")):
        return os.path.realpath(cand)
    top = _git_toplevel(cand)
    return top or os.path.realpath(cand)


def _repo_root(project_dir: str | None = None) -> str:
    if project_dir:
        return _resolve_candidate_root(project_dir)
    # Ưu tiên CWD nếu đang đứng trong repo có cấu hình super-board; chỉ rơi về CLAUDE_PROJECT_DIR khi CWD không có.
    cwd_root = _resolve_candidate_root(os.getcwd())
    if os.path.isdir(os.path.join(cwd_root, ".claude", "super-board", "configs")):
        return cwd_root
    env_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_dir:
        return _resolve_candidate_root(env_dir)
    return cwd_root


def _read_config(cfg_path: Path, root: str, origin: str) -> dict | None:
    try:
        data = json.loads(cfg_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    proj = data.get("project")
    if not isinstance(proj, dict):
        return None
    num = proj.get("number")
    if not isinstance(num, int) or isinstance(num, bool) or num <= 0:
        return None

    remote_url = str((data.get("repo") or {}).get("remote") or "").strip() if isinstance(data.get("repo"), dict) else ""
    repo_slug = _parse_repo_slug(remote_url) or origin
    owner = str(proj.get("owner") or "").strip()
    if not owner:
        owner = repo_slug.split("/", 1)[0] if "/" in repo_slug else "ToanMobile"
    title = str(proj.get("title") or cfg_path.stem).strip()
    is_kit = (
        repo_slug.lower() == "toanmobile/agent-workbench"
        or cfg_path.stem.lower() == "agent-workbench"
        or (num == 1 and os.path.isdir(os.path.join(root, "universal-agent-devkit")))
    )
    board_url = f"https://github.com/users/{owner}/projects/{num}"
    return {
        "owner": owner,
        "number": num,
        "title": title,
        "url": f"{board_url}/views/2",
        "board_url": board_url,
        "slug": cfg_path.stem,
        "repo": repo_slug,
        "config": str(cfg_path),
        "is_kit": is_kit,
    }


def resolve_board(project_dir: str | None = None) -> dict | None:
    """Trả dict thông tin board của repo hiện tại từ `.claude/super-board/configs/*.json`, hoặc None nếu không có."""
    root = _repo_root(project_dir)
    cfg_dir = Path(root) / ".claude" / "super-board" / "configs"
    if not cfg_dir.is_dir():
        return None
    configs = sorted(cfg_dir.glob("*.json"))
    if not configs:
        return None

    origin = _origin_slug(root)
    active_file = Path(root) / ".claude" / "super-board" / "active"
    if active_file.is_file():
        try:
            active_slug = active_file.read_text(encoding="utf-8").strip()
            if active_slug:
                cand = cfg_dir / f"{active_slug}.json"
                if cand.is_file():
                    res = _read_config(cand, root, origin)
                    if res is not None:
                        return res
        except OSError:
            pass

    parsed = [res for p in configs if (res := _read_config(p, root, origin)) is not None]
    if not parsed:
        return None
    if len(parsed) == 1:
        return parsed[0]
    if origin:
        for res in parsed:
            if res["repo"].lower() == origin.lower():
                return res
    return parsed[0]


def board_banner(project_dir: str | None = None) -> str:
    """Dòng đánh dấu board để `context_sync.py` chèn vào khối DevKit của `AGENTS.md`."""
    b = resolve_board(project_dir)
    if not b:
        return ""
    head = f"> Board của repo này: {b['owner']}/projects/{b['number']} ({b['title']})"
    if b["is_kit"]:
        return f"{head} — board #1 chỉ chứa việc của kit (`agent-workbench`), không dùng cho 5 repo app.\n\n"
    return f"{head} — mọi lệnh `gh project` / `super-board` / `createTask` trong repo này dùng #{b['number']}, KHÔNG dùng #1.\n\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="In thông tin GitHub Project board của repo hiện tại")
    ap.add_argument("path", nargs="?", help="Đường dẫn repo (mặc định: repo hiện tại)")
    ap.add_argument("--json", action="store_true", help="In JSON đầy đủ")
    ap.add_argument("--field", choices=["owner", "number", "title", "url", "board_url", "slug", "repo", "config", "is_kit"],
                    help="Chỉ in đúng một trường")
    args = ap.parse_args(argv)

    info = resolve_board(args.path)
    if not info:
        where = args.path or os.getcwd()
        print(f"agent-kit board: không tìm thấy config super-board hợp lệ trong {where}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(info, ensure_ascii=False))
        return 0
    if args.field:
        val = info[args.field]
        print(json.dumps(val) if isinstance(val, bool) else val)
        return 0

    print(f"owner:  {info['owner']}")
    print(f"number: {info['number']}")
    print(f"title:  {info['title']}")
    print(f"url:    {info['url']}")
    if info["is_kit"]:
        print("note:   board #1 chỉ chứa việc của kit (agent-workbench)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
