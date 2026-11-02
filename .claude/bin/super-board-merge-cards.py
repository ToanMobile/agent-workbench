#!/usr/bin/env python3
"""Gộp thẻ chưa chạy vào một thẻ giữ: chép dòng AC nguyên văn, đóng thẻ nguồn.

    python3 super-board-merge-cards.py --repo <owner/name> --into N --absorb M[,K]

Exit 0: đã gộp, hoặc marker `<!-- sb:gom #M -->` đã có (đóng nốt thẻ nguồn nếu còn mở).
Exit 3: một thẻ nguồn có PR mở head `issue-<M>-` — không ghi gì.
Exit 1: gh lỗi. Exit 64: sai cách gọi.

Stdout một dòng JSON: {"into": N, "folded": [...], "already": [...], "closed": [...]}.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

MARKER = "<!-- sb:gom #{n} -->"
HEAD_RE = re.compile(r"issue-(\d+)-")


def gh(args, timeout=60):
    try:
        return subprocess.run(["gh", *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(["gh", *args], 124, "", "quá hạn")


def section(body, name):
    lines = (body or "").splitlines()
    heads = [i for i, line in enumerate(lines) if re.match(rf"^##\s+{re.escape(name)}\s*$", line, re.I)]
    if not heads:
        return []
    tail = lines[heads[-1] + 1:]
    end = next((i for i, line in enumerate(tail) if line.startswith("## ")), len(tail))
    return tail[:end]


def issue_view(repo, number):
    res = gh(["issue", "view", str(number), "--repo", repo, "--json", "title,body,state"])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip()[:200] or f"issue view #{number} thoát {res.returncode}")
    try:
        data = json.loads(res.stdout)
    except ValueError as e:
        raise RuntimeError(f"issue view #{number} không phải JSON") from e
    if not isinstance(data, dict):
        raise RuntimeError(f"issue view #{number} không phải object")
    return data


def started(repo, numbers):
    res = gh(["pr", "list", "--repo", repo, "--state", "open", "--json", "headRefName", "--limit", "100"])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip()[:200] or f"pr list thoát {res.returncode}")
    try:
        prs = json.loads(res.stdout or "[]")
    except ValueError as e:
        raise RuntimeError("pr list không phải JSON") from e
    if not isinstance(prs, list):
        raise RuntimeError("pr list không trả một mảng")
    want = {str(n) for n in numbers}
    hit = []
    for pr in prs:
        m = HEAD_RE.match(str((pr or {}).get("headRefName") or ""))
        if m and m.group(1) in want:
            hit.append(int(m.group(1)))
    return sorted(set(hit))


def fold_body(keeper, sources):
    """sources: [(number, title, body)]. Trả body mới. Bỏ thẻ đã có marker."""
    lines = keeper.rstrip().splitlines()
    pending = []
    already = []
    text = "\n".join(lines)
    for number, title, body in sources:
        mark = MARKER.format(n=number)
        if mark in text:
            already.append(number)
            continue
        pending.append((number, title, body, mark))
    if not pending:
        return keeper if keeper.endswith("\n") else keeper + "\n", [], already
    new_ac = []
    for number, _title, body, _mark in pending:
        for line in section(body, "Acceptance Criteria"):
            if line.strip():
                new_ac.append(line)
    heads = [i for i, line in enumerate(lines) if re.match(r"^##\s+Acceptance Criteria\s*$", line, re.I)]
    if heads and new_ac:
        end = next((i for i in range(heads[-1] + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        while end > heads[-1] + 1 and not lines[end - 1].strip():
            end -= 1
        lines[end:end] = new_ac
    elif new_ac:
        lines += ["", "## Acceptance Criteria", *new_ac]
    for number, title, body, mark in pending:
        problem = "\n".join(section(body, "Problem")).strip()
        fix = "\n".join(section(body, "Fix")).strip()
        lines += ["", f"## Gộp thêm: {title}", "", mark]
        if problem:
            lines += ["", problem]
        if fix:
            lines += ["", fix]
    folded = [number for number, _title, _body, _mark in pending]
    return "\n".join(lines).rstrip() + "\n", folded, already


def close_source(repo, into, number):
    comment = f"Gộp vào #{into}. AC đã chép nguyên văn sang thẻ đó."
    commented = gh(["issue", "comment", str(number), "--repo", repo, "--body", comment])
    if commented.returncode != 0:
        raise RuntimeError(commented.stderr.strip()[:200] or f"comment #{number} thoát {commented.returncode}")
    closed = gh(["issue", "close", str(number), "--repo", repo, "--reason", "not planned"])
    if closed.returncode != 0:
        raise RuntimeError(closed.stderr.strip()[:200] or f"close #{number} thoát {closed.returncode}")


def main():
    ap = argparse.ArgumentParser(description="Gộp thẻ chưa chạy vào một thẻ giữ")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--into", required=True)
    ap.add_argument("--absorb", required=True, help="số issue, cách nhau bởi dấu phẩy")
    args = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        print("repo phải là owner/name", file=sys.stderr)
        return 64
    if not re.fullmatch(r"[0-9]+", args.into):
        print("--into phải là số", file=sys.stderr)
        return 64
    parts = [p.strip() for p in args.absorb.split(",") if p.strip()]
    if not parts or any(not re.fullmatch(r"[0-9]+", p) for p in parts):
        print("--absorb phải là số, cách nhau bởi dấu phẩy", file=sys.stderr)
        return 64
    numbers = []
    for p in parts:
        n = int(p)
        if n == int(args.into) or n in numbers:
            continue
        numbers.append(n)
    if not numbers:
        print("--absorb không có số khác --into", file=sys.stderr)
        return 64
    try:
        busy = started(args.repo, numbers)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    if busy:
        print(json.dumps({"into": int(args.into), "started": busy, "folded": [], "already": [], "closed": []}))
        return 3
    try:
        keeper = issue_view(args.repo, args.into)
        if keeper.get("state") != "OPEN":
            raise RuntimeError(f"#{args.into} không còn mở")
        sources = []
        for n in numbers:
            src = issue_view(args.repo, n)
            sources.append((n, src.get("title") or f"#{n}", src.get("body") or ""))
        new_body, folded, already = fold_body(keeper.get("body") or "", sources)
        if folded:
            edited = gh(["issue", "edit", args.into, "--repo", args.repo, "--body", new_body])
            if edited.returncode != 0:
                raise RuntimeError(edited.stderr.strip()[:200] or f"issue edit thoát {edited.returncode}")
        closed = []
        for n, _title, _body in sources:
            src = issue_view(args.repo, n)
            if src.get("state") == "OPEN":
                close_source(args.repo, args.into, n)
                closed.append(n)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    print(json.dumps({"into": int(args.into), "folded": folded, "already": already, "closed": closed}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
