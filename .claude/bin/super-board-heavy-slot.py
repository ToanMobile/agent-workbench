#!/usr/bin/env python3
"""Wrapper mỏng tìm và gọi universal-agent-devkit/bin/heavy_slot.py theo thứ tự của super-board-scratch-config.sh."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional, Sequence


def _find_devkit_heavy_slot() -> Optional[Path]:
    """Tìm bin/heavy_slot.py theo đúng thứ tự thư mục như super-board-scratch-config.sh:19."""
    repo_path = Path(os.environ.get("SB_REPO_PATH") or os.getcwd()).resolve()
    self_root = Path(__file__).resolve().parents[2]
    main_wt = repo_path
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_path), "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            check=False,
        )
        for line in proc.stdout.splitlines():
            if line.startswith("worktree "):
                cand = line[len("worktree ") :].strip()
                if cand:
                    main_wt = Path(cand)
                break
    except OSError:
        pass

    candidates = (
        main_wt / "universal-agent-devkit",
        main_wt / ".agents" / "devkit",
        self_root / "universal-agent-devkit",
        self_root / ".agents" / "devkit",
    )
    for base in candidates:
        target = base / "bin" / "heavy_slot.py"
        if target.is_file():
            return target
    return None


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Chạy heavy_slot.py nếu tìm thấy; nếu không thấy thì log một dòng và chạy tiếp lệnh không chặn."""
    args = list(sys.argv[1:] if argv is None else argv)
    target = _find_devkit_heavy_slot()
    if target is not None:
        spec = importlib.util.spec_from_file_location("devkit_heavy_slot", str(target))
        if spec is not None and spec.loader is not None:
            mod = importlib.util.module_from_spec(spec)
            sys.modules["devkit_heavy_slot"] = mod
            spec.loader.exec_module(mod)
            return int(mod.main(args))

    print("[heavy-slot] không tìm thấy heavy_slot.py trong DevKit; bỏ qua giới hạn slot và chạy tiếp", file=sys.stderr, flush=True)
    cmd = list(args)
    while cmd and cmd[0] in ("--nonblock", "--nb"):
        cmd.pop(0)
    if cmd and cmd[0] == "--":
        cmd.pop(0)
    if not cmd:
        return 0
    return subprocess.run(cmd).returncode


if __name__ == "__main__":
    sys.exit(main())
