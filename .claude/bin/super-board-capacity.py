#!/usr/bin/env python3
"""Wrapper mỏng: tìm universal-agent-devkit/bin/capacity.py (nguồn sức chứa chung, T0052) và in một khoá của nó.

  super-board-capacity.py <khoá>    in số (busy_load, build_workers, lane_workers, gate_max, …)
  super-board-capacity.py --json    in mọi khoá

Thứ tự dò: repo hiện tại (SB_REPO_PATH hoặc cwd; universal-agent-devkit rồi .agents/devkit) → main worktree → repo chứa chính script
này. Repo hiện tại đứng trước main worktree để worktree đang sửa capacity.py dùng bản của nó (INSTINCT-057: wrapper heavy-slot dò main
trước nên test trong worktree chạy code cũ). Không thấy: exit 3, chỗ gọi tự dùng số cũ."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence


def _git_lines(args: List[str]) -> List[str]:
    try:
        proc = subprocess.run(["git"] + args, capture_output=True, text=True, check=False, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    return proc.stdout.splitlines() if proc.returncode == 0 else []


def _find_capacity() -> Optional[Path]:
    repo_path = Path(os.environ.get("SB_REPO_PATH") or os.getcwd()).resolve()
    top = _git_lines(["-C", str(repo_path), "rev-parse", "--show-toplevel"])
    current = Path(top[0]) if top and top[0].strip() else repo_path
    main_wt = current
    for line in _git_lines(["-C", str(repo_path), "worktree", "list", "--porcelain"]):
        if line.startswith("worktree "):
            cand = line[len("worktree "):].strip()
            if cand:
                main_wt = Path(cand)
            break
    self_root = Path(__file__).resolve().parents[2]
    for root in (current, main_wt, self_root):
        for base in (root / "universal-agent-devkit", root / ".agents" / "devkit"):
            target = base / "bin" / "capacity.py"
            if target.is_file():
                return target
    return None


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    target = _find_capacity()
    if target is None:
        print("[capacity] không tìm thấy bin/capacity.py trong DevKit; chỗ gọi dùng số mặc định cũ", file=sys.stderr, flush=True)
        return 3
    spec = importlib.util.spec_from_file_location("devkit_capacity", str(target))
    if spec is None or spec.loader is None:
        print(f"[capacity] không nạp được {target}", file=sys.stderr, flush=True)
        return 3
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except (OSError, SyntaxError, ImportError) as exc:   # bản capacity.py hỏng: chỗ gọi dùng số cũ, không chết theo
        print(f"[capacity] nạp {target} lỗi: {exc!r}", file=sys.stderr, flush=True)
        return 3
    return int(mod.main(args))


if __name__ == "__main__":
    sys.exit(main())
