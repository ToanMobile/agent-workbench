#!/usr/bin/env python3
"""Bậc review S/M/L của một PR, tính bằng lệnh từ `git diff --numstat <base>...HEAD` (#858, luật chủ repo 02/11, core-rules §18).

    review_tier.py [--base REF] [--numstat FILE|-] [--deletes-data]

In một dòng `<S|M|L> product_lines=<N> reasons=<…>`; token đầu là bậc, để board và lane đọc cùng một kết quả.
Dòng code sản phẩm = tổng thêm+xoá của numstat, trừ đường dẫn bắt đầu bằng `tests/` hoặc chứa `/tests/`,
`.agents/regression_matrix`, `test_durations`, đuôi `.md` (rename: xét đường dẫn mới).
L: > 400 dòng, HOẶC đường dẫn sản phẩm (cũ hoặc mới) khớp L_PATHS, HOẶC --deletes-data (thẻ xoá dữ liệu).
M: 51–400 dòng, HOẶC đường dẫn sản phẩm khớp M_PATHS. Còn lại S.
Chỗ mơ hồ nghiêng về bậc cao: L_PATHS/M_PATHS không phân biệt hoa thường (AuthRepository.kt ở repo app là auth), phần loại trừ
thì có phân biệt. File nhị phân (`-`) tính 0 dòng. Lỗi git, dòng numstat sai, base dạng cờ ⇒ exit 2, không in bậc (không rơi về S).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys

L_PATHS = re.compile(r"hardware_safety_gate|block-dangerous-git|guard-review|bin/review|review_sign|merge-gate|merge_gate"
                     r"|auth|billing|payment|migration", re.I)
M_PATHS = re.compile(r"universal-agent-devkit/hooks/|universal-agent-devkit/bin/|post-fix-gate|\.claude/bin/", re.I)
EXCLUDED = re.compile(r"(^|/)tests/|\.agents/regression_matrix|test_durations|\.md$")
_RENAME_BRACE = re.compile(r"(.*)\{(.*) => (.*)\}(.*)")


class TierError(Exception):
    pass


def _paths(field: str) -> tuple[str, str]:
    """Trường đường dẫn của numstat → (cũ, mới); rename in `a/{x => y}/b` hoặc `x => y`."""
    m = _RENAME_BRACE.fullmatch(field)
    if m:
        pre, old, new, post = m.groups()
        return (pre + old + post).replace("//", "/"), (pre + new + post).replace("//", "/")
    if " => " in field:
        old, new = field.split(" => ", 1)
        return old, new
    return field, field


def parse_numstat(text: str) -> list[tuple[int, str, str]]:
    rows = []
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        parts = line.split("\t", 2)
        if len(parts) != 3 or not parts[2] or not all(p == "-" or p.isdigit() for p in parts[:2]):
            raise TierError(f"dòng numstat {n} sai: {line[:120]!r}")
        old, new = _paths(parts[2])
        rows.append((sum(int(p) for p in parts[:2] if p != "-"), old, new))
    return rows


def classify(rows: list[tuple[int, str, str]], deletes_data: bool = False) -> tuple[str, int, list[str]]:
    lines, l_hits, m_hits = 0, [], []
    for count, old, new in rows:
        if EXCLUDED.search(new):
            continue
        lines += count
        if L_PATHS.search(old) or L_PATHS.search(new):
            l_hits.append(new)
        elif M_PATHS.search(old) or M_PATHS.search(new):
            m_hits.append(new)
    l_why = (["deletes-data"] if deletes_data else []) + (["lines>400"] if lines > 400 else []) + [f"path:{p}" for p in l_hits]
    if l_why:
        return "L", lines, l_why
    m_why = (["lines>50"] if lines > 50 else []) + [f"path:{p}" for p in m_hits]
    return ("M", lines, m_why) if m_why else ("S", lines, [])


def git_numstat(base: str) -> str:
    if not base or base.startswith("-"):
        raise TierError(f"base không hợp lệ: {base!r}")
    try:
        proc = subprocess.run(["git", "-c", "core.quotePath=false", "diff", "--numstat", f"{base}...HEAD"],
                              capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TierError(f"git diff --numstat {base}...HEAD không chạy được: {exc}") from exc
    if proc.returncode != 0:
        raise TierError(f"git diff --numstat {base}...HEAD exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    return proc.stdout


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="In bậc review S/M/L của PR (core-rules §18).")
    ap.add_argument("--base", default="origin/main", help="nhánh gốc của diff, mặc định origin/main")
    ap.add_argument("--numstat", metavar="FILE", help="đọc numstat từ FILE ('-' = stdin) thay vì chạy git")
    ap.add_argument("--deletes-data", action="store_true", help="thẻ xoá dữ liệu ⇒ bậc L")
    args = ap.parse_args(argv)
    try:
        if args.numstat == "-":
            text = sys.stdin.read()
        elif args.numstat:
            with open(args.numstat, encoding="utf-8") as fh:
                text = fh.read()
        else:
            text = git_numstat(args.base)
        tier, lines, why = classify(parse_numstat(text), args.deletes_data)
    except (TierError, OSError, UnicodeDecodeError) as exc:
        print(f"review_tier: {exc}", file=sys.stderr)
        return 2
    shown = ",".join(why[:5]) + (f",+{len(why) - 5}" if len(why) > 5 else "")
    print(f"{tier} product_lines={lines} reasons={shown or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
