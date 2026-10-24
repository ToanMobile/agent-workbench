#!/usr/bin/env python3
"""super-board-ac-check.py — đối chiếu AC của thẻ với khối sb:ac của PR, trước khi merge gate merge (T0054, 24/10).

Vì sao: #315 có AC "lượt 2 dùng lại REG-DK-ALL-01" chưa ai làm mà thẻ vẫn đóng — #318 chỉ ghi "AC của thẻ #315 (xem thẻ
đó)", PR #343 nén 7 AC của #318 thành 3 dòng tóm tắt đã tick, và `Closes #N` đóng thẻ dù AC chưa chứng minh. Script chỉ
ĐỌC file (body issue, body PR, message squash) và in một JSON; merge gate quyết định:
  foreign_closes Closes/Fixes/Resolves thẻ khác thẻ của nhánh issue-<N>       → exit 11 (kiểm cả khi PR không có sb:ac)
  collapsed      khối sb:ac ít dòng hơn số AC của thẻ (+ AC của thẻ tham chiếu) → exit 11, builder viết lại mỗi AC một dòng
  unticked       dòng AC chưa tick (đo số sau merge, thiết bị, người)          → vẫn merge, thẻ ở lại (nhãn ac-open)
  indirect       số thẻ mà AC ghi "AC của thẻ #X": merge gate đọc #X rồi chạy lại với --extra-issue-body
Nhánh không mang số thẻ: {"skip": true}. PR không có sb:ac: chỉ có foreign_closes ("ac": false).

  --rewrite-closes <file> --card N : đổi từ khoá đóng #N (mọi dạng GitHub nhận) thành `Refs #N` tại chỗ.
"""
import argparse
import json
import re
import sys

# Mục AC cấp 1 (không thụt lề) — cùng dạng super-board-preflight.sh nhận (#283): `-`, `*`, `1.`, `1)`; năm (2026.) không phải mục.
AC_ITEM = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]+\S")
CHECKBOX = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]*\[([ xX])\][ \t]*(.*)$")
AC_HEADING = re.compile(r"^##[ \t]+Acceptance Criteria(?!\w)", re.I)
AC_BLOCK = re.compile(r"<!--\s*sb:ac\s*-->(.*?)<!--\s*/sb:ac\s*-->", re.S)
CARD_FROM_BRANCH = re.compile(r"(?:^|/)issue-(\d+)(?:\D|$)")
# GitHub's closing keywords, the same expression as super-board-approval.py: KEYWORD[:] #N or KEYWORD[:] owner/repo#N.
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+([\w.-]+/[\w.-]+)?#(\d+)\b", re.I)
# "AC của thẻ #315", "AC của #344, #338", "AC of cards #12 and #13": chỉ các số thẻ đứng liền sau cụm đó
# ("AC của thẻ #315 đạt (xem PR #343)": #343 không phải thẻ được tham chiếu).
INDIRECT = re.compile(r"\bAC\s+(?:của|of)\s+(?:(?:các\s+)?(?:thẻ|cards?|issues?)\s+)?(#\d+(?:\s*(?:,|và|and|&)\s*#\d+)*)", re.I)
CARD_REF = re.compile(r"#(\d+)")


def read(path):
    if not path:
        return ""
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def ac_items(body):
    """Mục AC cấp 1 dưới heading `## Acceptance Criteria` CUỐI CÙNG tới `## ` kế tiếp; bỏ code fence."""
    lines = (body or "").splitlines()
    heads = [i for i, line in enumerate(lines) if AC_HEADING.match(line)]
    if not heads:
        return []
    items, fence = [], False
    for line in lines[heads[-1] + 1:]:
        if line.lstrip().startswith("```"):   # fence trước: "## …" trong code fence không kết thúc mục AC
            fence = not fence
            continue
        if fence:
            continue
        if line.startswith("## "):
            break
        if AC_ITEM.match(line):
            items.append(line.strip())
    return items


def indirect_cards(items, card):
    return sorted({int(n) for it in items for m in INDIRECT.finditer(it) for n in CARD_REF.findall(m.group(1))} - {card})


def check(issue_body, pr_body, msg, branch, extra_bodies=()):
    card = CARD_FROM_BRANCH.search(branch or "")
    if not card:
        return {"skip": True, "reason": "branch carries no issue-<N>"}
    card = int(card.group(1))
    closes = {int(n) for _, n in CLOSES.findall((pr_body or "") + "\n" + (msg or ""))}
    out = {"skip": False, "card": card, "foreign_closes": sorted(closes - {card}), "closes_own": card in closes}
    m = AC_BLOCK.search(pr_body or "")
    out["ac"] = bool(m)
    items = ac_items(issue_body)
    if not m:
        # Không có khối sb:ac mà vẫn đóng thẻ (merge gate chỉ đưa body issue khi closes_own): nén về 0 dòng.
        if issue_body:
            out.update({"issue_ac": len(items), "pr_ac": 0, "collapsed": bool(items), "unticked": [], "indirect": []})
        return out
    indirect = indirect_cards(items, card)
    # Dòng "AC của thẻ #X" là chỗ đứng của mọi AC của #X: thay nó bằng số AC của từng thẻ được nhắc (ít nhất 1 mỗi thẻ,
    # kể cả khi body #X không đọc được hay viết văn xuôi), nên mở rộng không bao giờ làm giảm số AC phải chứng minh.
    by_card = dict(extra_bodies or {})
    direct = [it for it in items if not INDIRECT.search(it)]
    issue_ac = max(len(items), len(direct) + sum(max(1, len(ac_items(by_card.get(x, "")))) for x in indirect))
    pr_ac = [c for c in map(CHECKBOX.match, m.group(1).splitlines()) if c]
    out.update({
        "issue_ac": issue_ac,
        "pr_ac": len(pr_ac),
        "collapsed": len(pr_ac) < issue_ac,
        "unticked": [c.group(2).rstrip("\\ \t") for c in pr_ac if c.group(1) == " "],   # trailing `\` = markdown break
        "indirect": indirect,
    })
    return out


def rewrite_closes(path, card):
    text = read(path)
    new = CLOSES.sub(lambda m: f"Refs {m.group(1) or ''}#{m.group(2)}" if int(m.group(2)) == card else m.group(0), text)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    return new != text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--issue-body")
    ap.add_argument("--extra-issue-body", action="append", default=[], metavar="N=FILE",
                    help="body of card #N that the AC refers to (repeat)")
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
    extra = {}
    for spec in a.extra_issue_body:
        n, sep, path = spec.partition("=")
        if not sep or not n.isdigit():
            ap.error(f"--extra-issue-body wants N=FILE, got {spec!r}")
        extra[int(n)] = read(path)
    print(json.dumps(check(read(a.issue_body), read(a.pr_body), read(a.msg), a.branch, extra), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
