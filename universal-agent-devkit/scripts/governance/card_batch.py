#!/usr/bin/env python3
"""
card_batch.py — đợt thẻ (#724): nhiều thẻ, MỘT nhánh, MỘT PR, MỘT lần gate.

create_task.py đưa thẻ mới không gom được (khác chủ đề, thẻ đủ trần AC) vào đợt của một thẻ trưởng chưa chạy: thẻ thành viên
mang `<!-- sb:batch-of #<trưởng> -->` và Blocked by thẻ trưởng. Builder thẻ trưởng build cả đợt trên nhánh issue-<trưởng>-…:

  python3 card_batch.py plan --lead N [--repo R]
      In JSON: {lead, cards, members:[{number,title,ac}], ac_total, branch_prefix, closes, ac_prefix}. Thành viên đã đóng bị bỏ.
      Mỗi thẻ một (vài) commit, subject kết thúc `(#m)`; PR body một dòng `Closes #x` mỗi thẻ (GitHub chỉ đóng thẻ đầu với
      `Closes #1, #2`); dòng sb:ac của thành viên mở đầu `[#m]`.

  python3 card_batch.py split --lead N --card M --reason "<lý do>" [--pr P] [--base origin/main] [--repo R]
      Thẻ M bị chặn (review, xung đột, AC không đạt): chạy trong worktree của nhánh issue-N-…. Revert commit `(#M)` chưa revert
      (mới → cũ), bỏ marker + đặt `## Blocked by` của M về `- None.` (thẻ riêng, board build được), comment lý do; --pr: body PR
      `Closes #M` → `Refs #M` và bỏ dòng sb:ac `[#M]`. Không push: cây đổi thì chạy lại gate một lần rồi push.

Mã thoát: 0 xong · 1 gh lỗi · 2 M không mang marker đợt #N (không phải thành viên, hoặc đã tách) · 3 không có commit `(#M)` nào
          trong <base>..HEAD · 4 không đứng trên nhánh issue-N-… hoặc cây bẩn · 5 revert xung đột (đã abort, HEAD như cũ) · 64 sai cách gọi
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_task as ct  # noqa: E402  (cùng thư mục: dùng chung gh có hạn, đọc board, đếm AC, marker đợt)

# Cùng dạng từ khoá đóng GitHub nhận với .claude/bin/super-board-ac-check.py CLOSES.
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+([\w.-]+/[\w.-]+)?#(\d+)\b", re.I)
AC_BLOCK = re.compile(r"(<!--\s*sb:ac\s*-->)(.*?)(<!--\s*/sb:ac\s*-->)", re.S)


def git(*args, check=False):
    return subprocess.run(["git", *args], capture_output=True, text=True, timeout=120, check=check)


def issue(repo, n):
    """{body, state, title} của issue #n; gh lỗi → RuntimeError."""
    res = ct.run_cmd(["gh", "issue", "view", str(n), "--repo", repo, "--json", "body,state,title"], check=False)
    if res.returncode != 0:
        raise RuntimeError(f"gh issue view #{n}: {res.stderr.strip()[:200] or res.returncode}")
    return json.loads(res.stdout)


def plan(repo, lead):
    head = issue(repo, lead)
    if head.get("state") != "OPEN":
        raise RuntimeError(f"thẻ trưởng #{lead} không còn mở")
    members = []
    for c in sorted(ct.batch_members(ct.board_items(ct.resolve_project_config(repo)), lead, repo), key=lambda c: c["number"]):
        cur = issue(repo, c["number"])
        if cur.get("state") == "OPEN" and ct.batch_of(cur.get("body")) == lead:   # đã đóng / đã tách thì không thuộc đợt
            members.append({"number": c["number"], "title": cur.get("title") or c.get("title", ""), "ac": ct.ac_count(cur.get("body"))})
    cards = [lead] + [m["number"] for m in members]
    return {"lead": lead, "title": head.get("title", ""), "cards": cards, "members": members,
            "ac_total": ct.ac_count(head.get("body")) + sum(m["ac"] for m in members),
            "branch_prefix": f"issue-{lead}-", "closes": "\n".join(f"Closes #{n}" for n in cards), "ac_prefix": "[#<thẻ>]"}


def standalone_body(body):
    """Body thẻ sau khi tách: bỏ marker, `## Blocked by` chỉ còn `- None.`."""
    lines = [l for l in (body or "").rstrip().splitlines() if not ct.BATCH_OF_RE.search(l)]
    heads = [i for i, l in enumerate(lines) if re.match(r"^##\s+Blocked by\s*$", l, re.I)]
    start = heads[-1] if heads else len(lines)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[:start] + ["## Blocked by", "- None."] + lines[end:]) + "\n"


def pr_without(body, card):
    """Body PR: từ khoá đóng #card → Refs; dòng sb:ac mở đầu `[#card]` cùng các dòng thụt lề theo sau (↳ bằng chứng) bị bỏ."""
    body = CLOSES.sub(lambda m: f"Refs {m.group(1) or ''}#{m.group(2)}" if int(m.group(2)) == card else m.group(0), body)
    item = re.compile(rf"^(?:[-*]|[0-9]{{1,2}}[.)])[ \t]*\[[ xX]\][ \t]*\[#{card}\]")

    def strip(m):
        out, skip = [], False
        for line in m.group(2).split("\n"):
            if item.match(line):
                skip = True
                continue
            if skip and line[:1] in (" ", "\t"):
                continue
            skip = False
            out.append(line)
        return m.group(1) + "\n".join(out) + m.group(3)
    return AC_BLOCK.sub(strip, body)


def split(repo, lead, card, reason, pr, base):
    branch = git("branch", "--show-current").stdout.strip()
    if not branch.startswith(f"issue-{lead}-"):
        print(f"❌ Đang ở nhánh {branch or '(detached)'}: split chạy trong worktree của nhánh issue-{lead}-….", file=sys.stderr)
        return 4
    if git("status", "--porcelain").stdout.strip():
        print("❌ Cây bẩn: commit hoặc bỏ thay đổi trước khi tách thẻ (revert cần cây sạch).", file=sys.stderr)
        return 4
    cur = issue(repo, card)
    if ct.batch_of(cur.get("body")) != lead:
        print(f"❌ #{card} không còn là thành viên đợt #{lead} (không có marker sb:batch-of #{lead}; đã tách?).", file=sys.stderr)
        return 2
    log = git("log", "--no-merges", "--format=%H%x09%s%x09%b%x1e", f"{base}..HEAD")
    if log.returncode != 0:
        print(f"❌ git log {base}..HEAD: {log.stderr.strip()[:200]}", file=sys.stderr)
        return 4
    mine, reverted = [], set()
    for rec in filter(None, (r.strip("\n") for r in log.stdout.split("\x1e"))):
        sha, subject, rest = (rec.split("\t", 2) + ["", ""])[:3]
        if re.search(rf"\(#{card}\)\s*$", subject):
            mine.append(sha)
        reverted.update(re.findall(r"This reverts commit ([0-9a-f]{40})", rest))
    if not mine:
        print(f"❌ Không có commit nào kết thúc `(#{card})` trong {base}..HEAD: không có gì để revert, thẻ giữ nguyên.", file=sys.stderr)
        return 3
    todo = [sha for sha in mine if sha not in reverted]   # git log: mới → cũ, đúng thứ tự revert
    if todo:
        orig = git("rev-parse", "HEAD").stdout.strip()
        res = git("revert", "--no-edit", *todo)   # MỘT chuỗi revert: --abort trả về đúng trạng thái trước cả chuỗi
        if res.returncode != 0:
            git("revert", "--abort")
            if git("rev-parse", "HEAD").stdout.strip() != orig:   # cây sạch lúc đầu (đã kiểm) nên về orig không mất gì
                git("reset", "--hard", orig)
            print(f"❌ Revert commit của #{card} xung đột (đã abort, HEAD như cũ): {res.stdout.strip()[-300:]} {res.stderr.strip()[-300:]}\n"
                  f"   Commit sau của đợt sửa cùng chỗ: gỡ tay, hoặc giữ #{card} trong đợt.", file=sys.stderr)
            return 5
        print(f"   ↩️  Đã revert {len(todo)} commit của #{card}: {', '.join(s[:8] for s in todo)}")
    new_body = standalone_body(cur.get("body"))
    ct.run_cmd(["gh", "issue", "edit", str(card), "--repo", repo, "--body", new_body])
    # Nhãn waiting-on:#lead giữ thẻ ở Ready (runner không giao); thẻ đã riêng thì gỡ để board build nó.
    res = ct.run_cmd(["gh", "issue", "edit", str(card), "--repo", repo, "--remove-label", f"waiting-on:#{lead}"], check=False)
    if res.returncode != 0:
        print(f"   ⚠️  Chưa gỡ được nhãn waiting-on:#{lead} của #{card} ({res.stderr.strip()[:200]}): gỡ tay, hoặc sweep gỡ khi #{lead} đóng.",
              file=sys.stderr)
    if ct.batch_of(issue(repo, card).get("body")) is not None:
        raise RuntimeError(f"ghi lại body #{card} chưa ăn (còn marker)")
    ct.run_cmd(["gh", "issue", "comment", str(card), "--repo", repo, "--body",
                f"[builder] [report] ✂️ tách khỏi đợt #{lead} · {reason}\nDid: revert commit `(#{card})` trên nhánh {branch}; "
                f"`## Blocked by` về `- None.`, thẻ thành thẻ riêng (board build nó trên nhánh issue-{card}-…)."])
    if pr:
        res = ct.run_cmd(["gh", "pr", "view", str(pr), "--repo", repo, "--json", "body"])
        old = json.loads(res.stdout).get("body") or ""
        new = pr_without(old, card)
        if new != old:
            ct.run_cmd(["gh", "pr", "edit", str(pr), "--repo", repo, "--body", new])
    print(f"✂️  #{card} đã tách khỏi đợt #{lead}. Cây đổi: chạy lại gate một lần trên nhánh {branch} rồi push (không force).")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Đợt thẻ #724: plan (một nhánh/PR/gate) và split (tách thẻ bị chặn)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--lead", type=int, required=True)
    p.add_argument("--repo")
    s = sub.add_parser("split")
    s.add_argument("--lead", type=int, required=True)
    s.add_argument("--card", type=int, required=True)
    s.add_argument("--reason", required=True)
    s.add_argument("--pr", type=int)
    s.add_argument("--base", default="origin/main")
    s.add_argument("--repo")
    a = ap.parse_args()
    repo = a.repo or ct.detect_repo()
    if a.cmd == "split" and (a.card == a.lead or not a.reason.strip()):
        print("❌ --card phải khác --lead và --reason không rỗng.", file=sys.stderr)
        return 64
    try:
        if a.cmd == "plan":
            print(json.dumps(plan(repo, a.lead), ensure_ascii=False, indent=1))
            return 0
        return split(repo, a.lead, a.card, a.reason.strip(), a.pr, a.base)
    except (RuntimeError, ValueError, OSError) as e:
        print(f"❌ {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
