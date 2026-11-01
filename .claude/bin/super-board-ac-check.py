#!/usr/bin/env python3
"""super-board-ac-check.py — đối chiếu AC của thẻ với khối sb:ac của PR, trước khi merge gate merge (T0054, 24/10).

Vì sao: #315 có AC "lượt 2 dùng lại REG-DK-ALL-01" chưa ai làm mà thẻ vẫn đóng — #318 chỉ ghi "AC của thẻ #315 (xem thẻ
đó)", PR #343 nén 7 AC của #318 thành 3 dòng tóm tắt đã tick, và `Closes #N` đóng thẻ dù AC chưa chứng minh. Script chỉ
ĐỌC file (body issue, body PR, message squash) và in một JSON; merge gate quyết định:
  foreign_closes Closes/Fixes/Resolves thẻ khác thẻ của nhánh issue-<N>, hoặc owner/repo#N của repo khác (#731)
                                                                              → exit 11 (kiểm cả khi PR không có sb:ac)
  collapsed      khối sb:ac ít dòng hơn số AC của thẻ (+ AC của thẻ tham chiếu) → exit 11, builder viết lại mỗi AC một dòng
  unticked       dòng AC chưa tick (đo số sau merge, thiết bị, người)          → vẫn merge, thẻ ở lại (nhãn ac-open)
  indirect       số thẻ mà AC ghi "AC của thẻ #X": merge gate đọc #X rồi chạy lại với --extra-issue-body
  batch          (#724) thẻ Closes khác thẻ của nhánh mà body (--batch-member-body) mang `<!-- sb:batch-of #<thẻ nhánh> -->`:
                 thành viên đợt, không phải thẻ lạ; AC của nó cộng vào issue_ac. Body thiếu/không đọc được → vẫn là thẻ lạ.
Nhánh không mang số thẻ: {"skip": true}. PR không có sb:ac: chỉ có foreign_closes ("ac": false).

  --rewrite-closes <file> --card N : đổi từ khoá đóng #N (mọi dạng GitHub nhận) thành `Refs #N` tại chỗ.
"""
import argparse
import json
import re
import subprocess
import sys

# Mục AC cấp 1 (không thụt lề) — cùng dạng super-board-preflight.sh nhận (#283): `-`, `*`, `1.`, `1)`; năm (2026.) không phải mục.
AC_ITEM = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]+\S")
CHECKBOX = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]*\[([ xX])\][ \t]*(.*)$")
# "## AC" viết tắt cũng là mục AC (#616, #618), cùng luật với has_acs của super-board-preflight.sh.
AC_HEADING = re.compile(r"^##[ \t]+(?:Acceptance Criteria|AC)(?!\w)", re.I)
AC_BLOCK = re.compile(r"<!--\s*sb:ac\s*-->(.*?)<!--\s*/sb:ac\s*-->", re.S)
CARD_FROM_BRANCH = re.compile(r"(?:^|/)issue-(\d+)(?:\D|$)")
# GitHub's closing keywords, the same expression as super-board-approval.py: KEYWORD[:] #N or KEYWORD[:] owner/repo#N.
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+([\w.-]+/[\w.-]+)?#(\d+)\b", re.I)
# "AC của thẻ #315", "AC của #344, #338", "AC of cards #12 and #13": chỉ các số thẻ đứng liền sau cụm đó
# ("AC của thẻ #315 đạt (xem PR #343)": #343 không phải thẻ được tham chiếu).
INDIRECT = re.compile(r"\bAC\s+(?:của|of)\s+(?:(?:các\s+)?(?:thẻ|cards?|issues?)\s+)?(#\d+(?:\s*(?:,|và|and|&)\s*#\d+)*)", re.I)
CARD_REF = re.compile(r"#(\d+)")
# #724: marker create_task.py ghi vào body thẻ thành viên đợt (cùng regex với create_task.BATCH_OF_RE).
BATCH_OF = re.compile(r"<!--\s*sb:batch-of\s+#(\d+)\s*-->")
# #731: `owner/repo` của origin (cùng regex với create_task.detect_repo).
GITHUB_SLUG = re.compile(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$")


FENCE_BLOCK = re.compile(r"^[ \t]*```.*?^[ \t]*```[^\n]*$", re.S | re.M)
CODE_SPAN = re.compile(r"`[^`\n]*`")


def prose(text):
    """Văn bản không có code fence và code span: GitHub không đóng issue theo từ khoá nằm trong code."""
    return CODE_SPAN.sub("", FENCE_BLOCK.sub("", text or ""))


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


def card_ac(items, card, by_card, skip=()):
    """(số AC phải chứng minh, thẻ gián tiếp) của một thẻ: dòng "AC của thẻ #X" là chỗ đứng của mọi AC của #X (ít nhất 1 mỗi
    thẻ, kể cả khi body #X không đọc được hay viết văn xuôi), nên mở rộng không bao giờ làm giảm số AC phải chứng minh."""
    indirect = [x for x in indirect_cards(items, card) if x not in skip]
    direct = [it for it in items if not INDIRECT.search(it)]
    return max(len(items), len(direct) + sum(max(1, len(ac_items(by_card.get(x, "")))) for x in indirect)), indirect


def batch_lead(body):
    """Số thẻ trưởng mà body thẻ đánh dấu là đợt của nó; marker trong code fence/span không tính."""
    m = BATCH_OF.search(prose(body))
    return int(m.group(1)) if m else None


def own_repo():
    """`owner/repo` (chữ thường) của origin nơi đang đứng (merge gate chạy trong checkout của repo); không đọc được → ""
    (mọi `owner/repo#N` là repo khác: fail-closed)."""
    try:
        r = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"ac-check: cannot read origin ({e}); every owner/repo#N counts as another repo", file=sys.stderr)
        return ""
    m = GITHUB_SLUG.search(r.stdout.strip()) if r.returncode == 0 else None
    return m.group(1).lower() if m else ""


def check(issue_body, pr_body, msg, branch, extra_bodies=(), batch_bodies=()):
    card = CARD_FROM_BRANCH.search(branch or "")
    if not card:
        return {"skip": True, "reason": "branch carries no issue-<N>"}
    card = int(card.group(1))
    # Body PR là Markdown: từ khoá trong code không đóng issue. Message commit là văn bản thô: mọi từ khoá đều tính.
    found = CLOSES.findall(prose(pr_body) + "\n" + (msg or ""))
    closes = {int(n) for _, n in found}
    # #724: thẻ Closes mà body mang marker đợt của chính thẻ nhánh là thành viên đợt (một nhánh, một PR, một gate). Chỉ Closes
    # của repo này (`#32`, hoặc `<origin>#32`): `Closes x/y#32` đóng issue của repo khác, body thẻ #32 ở đây không nói gì về nó.
    members = dict(batch_bodies or {})
    own = own_repo() if any(repo for repo, _ in found) else ""
    local = {int(n) for repo, n in found if not repo or repo.lower() == own}
    # #731: Closes repo khác luôn là thẻ lạ — trước đây tính trên tập số đã bỏ tiền tố repo, nên `Closes #32` (thành viên) hay
    # thẻ của nhánh trùng số che mất `Closes x/y#32`.
    cross_repo = {int(n) for repo, n in found if repo and repo.lower() != own}
    batch = sorted(n for n in local - {card} if n in members and batch_lead(members[n]) == card)
    # AC của thành viên phải chứng minh trong cùng khối sb:ac: ít nhất 1 mỗi thẻ, như AC gián tiếp.
    batch_ac = sum(max(1, len(ac_items(members[n]))) for n in batch)
    out = {"skip": False, "card": card, "foreign_closes": sorted((local - {card} - set(batch)) | cross_repo),
           "closes_own": card in closes, "batch": batch}
    m = AC_BLOCK.search(pr_body or "")
    out["ac"] = bool(m)
    items = ac_items(issue_body)
    if not m:
        # Không có khối sb:ac mà vẫn đóng thẻ (merge gate chỉ đưa body issue khi closes_own): nén về 0 dòng.
        if issue_body or batch:
            out.update({"issue_ac": len(items) + batch_ac, "pr_ac": 0, "collapsed": bool(items) or bool(batch),
                        "unticked": [], "indirect": []})
        return out
    by_card = dict(extra_bodies or {})
    issue_ac, indirect = card_ac(items, card, by_card)
    # #724: mỗi thành viên đếm như khi nó đứng riêng — "AC của thẻ #X" của thành viên cũng mở rộng (lỗ #315/#343), #X vào
    # `indirect` để merge gate đọc. "AC của thẻ <trưởng/thành viên khác>" đã được đếm ở thẻ đó, không đếm hai lần.
    for n in batch:
        m_ac, m_indirect = card_ac(ac_items(members[n]), n, by_card, skip={card, *batch})
        issue_ac += max(1, m_ac)
        indirect = sorted(set(indirect) | set(m_indirect))
    pr_ac = [c for c in map(CHECKBOX.match, FENCE_BLOCK.sub("", m.group(1)).splitlines()) if c]
    out.update({
        "issue_ac": issue_ac,
        "pr_ac": len(pr_ac),
        "collapsed": len(pr_ac) < issue_ac,
        "unticked": [c.group(2).rstrip("\\ \t") for c in pr_ac if c.group(1) == " "],   # trailing `\` = markdown break
        "indirect": indirect,
    })
    return out


def rewrite_closes(path, card, foreign=False):
    """Đổi từ khoá đóng #card thành `Refs` (foreign=True: đổi mọi thẻ KHÁC #card, giữ Closes của chính thẻ)."""
    text = read(path)
    new = CLOSES.sub(lambda m: f"Refs {m.group(1) or ''}#{m.group(2)}" if (int(m.group(2)) != card) == foreign else m.group(0),
                     text)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    return new != text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--issue-body")
    ap.add_argument("--extra-issue-body", action="append", default=[], metavar="N=FILE",
                    help="body of card #N that the AC refers to (repeat)")
    ap.add_argument("--batch-member-body", action="append", default=[], metavar="N=FILE",
                    help="body of card #N that the PR closes besides the branch card (#724 batch member check; repeat)")
    ap.add_argument("--pr-body")
    ap.add_argument("--msg")
    ap.add_argument("--branch", default="")
    ap.add_argument("--rewrite-closes")
    ap.add_argument("--card", type=int)
    ap.add_argument("--foreign", action="store_true", help="with --rewrite-closes: rewrite every card but --card")
    a = ap.parse_args()
    if a.rewrite_closes:
        if a.card is None:
            ap.error("--rewrite-closes needs --card")
        print("rewritten" if rewrite_closes(a.rewrite_closes, a.card, a.foreign) else "unchanged")
        return 0
    extra, batch = {}, {}
    for flag, specs, into in (("--extra-issue-body", a.extra_issue_body, extra), ("--batch-member-body", a.batch_member_body, batch)):
        for spec in specs:
            n, sep, path = spec.partition("=")
            if not sep or not n.isdigit():
                ap.error(f"{flag} wants N=FILE, got {spec!r}")
            into[int(n)] = read(path)
    print(json.dumps(check(read(a.issue_body), read(a.pr_body), read(a.msg), a.branch, extra, batch), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
