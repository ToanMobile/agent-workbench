#!/usr/bin/env python3
"""In dòng máy đọc `blocked-by:` chỉ với issue còn MỞ (block-template.md → "The blocked-by: line").

  super-board-blocked-by.py line --repo O/R 160,161

Builder #200 (22/10) ghi `blocked-by:` có #160 đã merge: wave sweep thả thẻ về Ready ngay, builder build lại, 6 lượt.
Số đã đóng bị bỏ và lý do ra stderr (đưa vào comment của Block); không còn số nào mở thì in `blocked-by: -`.
Exit: 0 xong · 64 danh sách sai hoặc số không thuộc repo · 79 không đọc được trạng thái (không đoán, không in dòng nào).
Đọc bằng `gh` trực tiếp, không qua file halt của board: số gõ nhầm (404) là exit 64 của lệnh này, không dừng board.
"""
import argparse
import re
import subprocess
import sys
HALTED = 79


class NotFound(ValueError):
    """Số không phải issue của repo (gõ nhầm, hoặc là PR đang mở): lỗi của người gọi, không phải sự cố."""


def read_state(repo: str, number: int) -> str:
    # Gọi `gh` trực tiếp, không qua super-board-github-read.py: file halt của nó dừng cả board khi gặp lỗi vĩnh viễn
    # (404 trên số gõ nhầm, #253 review F1). PR đã merge/đóng trả MERGED/CLOSED nên tính là đã đóng; PR đang mở trả OPEN
    # nhưng không nằm trong tập issue mở của super-board-deps.sh (sweep coi là đã đóng, thả thẻ ngay), nên bị từ chối.
    result = subprocess.run(
        ["gh", "issue", "view", str(number), "--repo", repo, "--json", "state,url", "--jq", '.state + " " + .url'],
        capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        if "could not resolve" in result.stderr.lower():
            raise NotFound(f"#{number} không phải issue hay PR của {repo}")
        raise OSError(f"gh exited {result.returncode}: {result.stderr.strip()[:200]}")
    state, _, url = result.stdout.strip().partition(" ")
    if state.upper() == "OPEN" and "/pull/" in url:
        raise NotFound(f"#{number} là PR đang mở, không phải issue: ghi số issue mà PR đó đóng")
    return state


def main(argv=None, reader=read_state) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("cmd", choices=["line"])
    p.add_argument("--repo", required=True)
    p.add_argument("issues", help="comma-separated issue numbers, e.g. 160,161")
    args = p.parse_args(argv)
    if not re.fullmatch(r"[0-9]+(?:\s*,\s*[0-9]+)*", args.issues):
        print(f"issues must be numbers separated by commas: {args.issues!r}", file=sys.stderr)
        return 64
    numbers = sorted({int(n) for n in args.issues.split(",")})
    open_numbers = []
    dropped = []
    for n in numbers:
        try:
            state = reader(args.repo, n).upper()
        except NotFound as exc:
            print(str(exc), file=sys.stderr)
            return 64
        except (OSError, subprocess.SubprocessError) as exc:
            print(f"cannot read the state of #{n}: {exc}", file=sys.stderr)
            return HALTED
        if state == "OPEN":
            open_numbers.append(n)
        else:
            dropped.append(n)
    for n in dropped:
        print(f"#{n} đã đóng (closed) — không ghi vào blocked-by; không còn gì để chờ ở #{n}", file=sys.stderr)
    print("blocked-by: " + (", ".join(str(n) for n in open_numbers) if open_numbers else "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
