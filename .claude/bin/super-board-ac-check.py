#!/usr/bin/env python3
"""super-board-ac-check.py — đối chiếu AC của thẻ với khối sb:ac của PR, trước khi merge gate merge (T0054, 24/10).

Vì sao: #315 có AC "lượt 2 dùng lại REG-DK-ALL-01" chưa ai làm mà thẻ vẫn đóng — PR #343 nén 10+ AC thành 3 dòng tóm tắt
đã tick, và `Closes #N` đóng thẻ dù AC chưa chứng minh. Script này chỉ ĐỌC (file body issue, body PR, message squash) và
in một JSON; merge gate quyết định:
  collapsed      khối sb:ac có ít dòng hơn số AC của thẻ (AC bị nén/thiếu)        → exit 11, builder viết lại
  foreign_closes Closes/Fixes/Resolves #X với X khác thẻ của nhánh issue-<N>      → exit 11
  unticked       dòng AC chưa tick (đo số sau merge, thiết bị, người)           → vẫn merge, thẻ ở lại (ac-open)
PR không có khối sb:ac, hoặc nhánh không mang số thẻ: {"skip": true} — PR làm tay giữ hành vi cũ.

  --rewrite-closes <file> --card N : đổi `Closes #N` (và Fixes/Resolves) thành `Refs #N` tại chỗ, để GitHub không tự đóng.
"""
import argparse
import json
import re
import sys

CHECKBOX = re.compile(r"^\s*[-*]\s*\[([ xX])\]\s*(.*)$")
AC_BLOCK = re.compile(r"<!--\s*sb:ac\s*-->(.*?)<!--\s*/sb:ac\s*-->", re.S)
CARD_FROM_BRANCH = re.compile(r"(?:^|/)issue-(\d+)(?:\D|$)")
# GitHub's closing keywords; `owner/repo#N` closes too, so the number after any repo prefix counts.
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+(?:[\w.-]+/[\w.-]+)?#(\d+)\b", re.I)


def read(path):
    if not path:
        return ""
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def check(issue_body, pr_body, msg, branch):
    m = AC_BLOCK.search(pr_body or "")
    card = CARD_FROM_BRANCH.search(branch or "")
    if not m or not card:
        return {"skip": True, "reason": "no sb:ac block" if not m else "branch carries no issue-<N>"}
    card = int(card.group(1))
    issue_ac = [c.group(2).strip() for c in map(CHECKBOX.match, (issue_body or "").splitlines()) if c]
    pr_ac = [c for c in map(CHECKBOX.match, m.group(1).splitlines()) if c]
    closes = {int(n) for n in CLOSES.findall((pr_body or "") + "\n" + (msg or ""))}
    return {
        "skip": False,
        "card": card,
        "issue_ac": len(issue_ac),
        "pr_ac": len(pr_ac),
        "collapsed": len(pr_ac) < len(issue_ac),
        "unticked": [c.group(2).rstrip("\\ \t") for c in pr_ac if c.group(1) == " "],   # trailing `\` = markdown line break
        "foreign_closes": sorted(closes - {card}),
    }


def rewrite_closes(path, card):
    text = read(path)
    new = re.sub(rf"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)(\s*:?\s+(?:[\w.-]+/[\w.-]+)?#{card})\b",
                 r"Refs\1", text, flags=re.I)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    return new != text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--issue-body")
    ap.add_argument("--pr-body")
    ap.add_argument("--msg")
    ap.add_argument("--branch", default="")
    ap.add_argument("--rewrite-closes")
    ap.add_argument("--card", type=int)
    a = ap.parse_args()
    if a.rewrite_closes:
        if a.card is None:
            ap.error("--rewrite-closes needs --card")
        print("rewritten" if rewrite_closes(a.rewrite_closes, a.card) else "unchanged")
        return 0
    print(json.dumps(check(read(a.issue_body), read(a.pr_body), read(a.msg), a.branch), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
