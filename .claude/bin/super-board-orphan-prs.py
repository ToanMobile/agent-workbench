#!/usr/bin/env python3
"""Dry-run: liệt kê PR mở có issue Closes/Fixes/Resolves đã ĐÓNG (PR mồ côi) — #560.

  super-board-orphan-prs.py --repo O/R [--json]

In số PR, issue đã đóng, ngày cập nhật, lý do. Chỉ đọc (`gh pr list`, `gh issue view`); đóng PR là bước sau, người duyệt danh sách.
Exit: 0 xong · 79 không đọc được trạng thái (không đoán, không in danh sách thiếu).
"""
import argparse
import json
import re
import subprocess
import sys

HALTED = 79
# GitHub chỉ coi từ khoá + số ngay sau; "Closes #1, #2" chỉ đóng #1, nên bắt từng cặp từ khoá-số cũng như danh sách sau dấu phẩy.
CLOSING = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+((?:#\d+)(?:\s*,\s*#\d+)*)", re.IGNORECASE)


def closing_issues(body: str) -> list:
    found = []
    for m in CLOSING.finditer(body or ""):
        found += [int(n) for n in re.findall(r"#(\d+)", m.group(1))]
    return sorted(set(found))


def list_open_prs(repo: str) -> list:
    result = subprocess.run(
        ["gh", "pr", "list", "--repo", repo, "--state", "open", "--limit", "200",
         "--json", "number,title,body,headRefName,updatedAt,isDraft"],
        capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise OSError(f"gh pr list exited {result.returncode}: {result.stderr.strip()[:200]}")
    return json.loads(result.stdout)


def read_state(repo: str, number: int) -> str:
    result = subprocess.run(
        ["gh", "issue", "view", str(number), "--repo", repo, "--json", "state", "--jq", ".state"],
        capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise OSError(f"gh issue view #{number} exited {result.returncode}: {result.stderr.strip()[:200]}")
    return result.stdout.strip()


def find_orphans(repo: str, lister=list_open_prs, reader=read_state) -> list:
    states = {}  # một lần đọc mỗi issue, dù nhiều PR cùng nhắc
    orphans = []
    for pr in sorted(lister(repo), key=lambda p: p["number"]):
        closed = []
        for n in closing_issues(pr.get("body", "")):
            if n not in states:
                states[n] = reader(repo, n).upper()
            if states[n] == "CLOSED":
                closed.append(n)
        if closed:
            refs = ", ".join(f"#{n}" for n in closed)
            orphans.append({
                "pr": pr["number"], "issues": closed, "updatedAt": pr["updatedAt"], "draft": pr.get("isDraft", False),
                "branch": pr.get("headRefName", ""), "title": pr.get("title", ""),
                "reason": f"issue {refs} đã đóng nhưng PR vẫn mở",
            })
    return orphans


def main(argv=None, lister=list_open_prs, reader=read_state) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--repo", required=True)
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)
    try:
        orphans = find_orphans(args.repo, lister, reader)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"cannot read PR/issue state: {exc}", file=sys.stderr)
        return HALTED
    if args.json:
        print(json.dumps(orphans, ensure_ascii=False, indent=2))
        return 0
    print(f"dry-run: {len(orphans)} PR mở có issue đã đóng trong {args.repo} (không đóng PR, không xoá nhánh)")
    for o in orphans:
        kind = "draft" if o["draft"] else "ready"
        print(f"#{o['pr']} [{kind}] cập nhật {o['updatedAt'][:10]} · {o['reason']} · {o['branch']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
