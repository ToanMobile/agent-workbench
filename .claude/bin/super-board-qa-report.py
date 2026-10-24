"""Đối chiếu report QA mới nhất và AC trong thân PR trước khi merge (#364). Không mạng, không tác dụng phụ.

    super-board-qa-report.py --meta <pr.json>

`--meta` là `gh pr view --json body,comments,author`. Thoát 0 khi sạch; thoát 1 và in từng dòng `qa-report: <lý do>` khi:
  - comment `[qa] [report]` MỚI NHẤT của người đáng tin còn mục `❌ Not done:` NÊU TÊN một AC của PR: mã AC (`AC1`, `AC 7`) hoặc
    nguyên văn một mục trong khối AC của thân PR. Ghi chú phạm vi ("thuộc #358", "đã tách sang #352", "không có ảnh (không có UI)")
    không nêu AC nên không bị từ chối. Mục có thể nhiều dòng: các dòng thụt lề / gạch đầu dòng ngay dưới nó thuộc cùng mục;
  - mục AC `- [x]` trong "## Acceptance criteria" của thân PR không có dòng bằng chứng `↳ <nội dung>` ở các dòng liền sau nó
    (dừng ở dòng trống, mục AC kế hay tiêu đề). Khối "## AC + proof" (agents-md-block.md) chỉ dùng để nhận diện AC cho mục Not done:
    bằng chứng của nó nằm ngay trên dòng mục, các PR #345/#374 đã merge không có `↳`.
Người đáng tin = tác giả PR hoặc authorAssociation OWNER/MEMBER/COLLABORATOR. Dòng trích dẫn `> ` và khối ``` bị bỏ qua.
Không có comment QA hay không có mục AC thì không có gì để từ chối (cổng khác lo việc QA vắng mặt).
Thoát 2 khi metadata không đọc được hay lỗi bất ngờ: cổng merge coi là "không quyết định được", không phải lỗi build.
ponytail: authorAssociation COLLABORATOR gồm cả quyền read (gh pr view không cho quyền cụ thể); nâng lên tra
`collaborators/<login>/permission` như super-board-approval.py khi có repo nhiều cộng tác viên chỉ-đọc.
"""
import argparse
import json
import re
import sys

QA_HEADER = re.compile(r"^\s*\[qa\]\s*\[report\]", re.I)
NOT_DONE = re.compile(r"^\s*❌\s*Not done:[ \t]*(.*)$")
EMPTY_VALUES = {"", "none", "n/a", "na", "-", "—", "–", "không", "khong", "nothing"}
AC_HEADING = re.compile(r"^#{1,6}\s*(Acceptance criteria|AC\s*\+\s*proof)\b", re.I)
PROOF_HEADING = re.compile(r"^#{1,6}\s*Acceptance criteria\b", re.I)  # "## AC + proof" mang bằng chứng ngay trên dòng mục, không cần ↳
AC_ITEM = re.compile(r"^\s*-\s*\[([ xX])\]\s*(.*)$")
PROOF = re.compile(r"^\s*↳\s*(\S.*)$")
AC_ID = re.compile(r"\bAC\s*-?\s*#?\d+", re.I)
BULLET = re.compile(r"^\s*(?:[-*•]|\d+[.)])\s+\S")
TRUSTED_ASSOC = {"OWNER", "MEMBER", "COLLABORATOR"}
MIN_AC_TEXT = 12  # AC ngắn hơn thế quá dễ trùng chữ thường trong ghi chú phạm vi


def visible_lines(body):
    """Các dòng của comment sau khi bỏ dòng trích dẫn `> ` và nội dung trong khối ``` (không ai coi đó là lời khai của QA)."""
    out, fenced = [], False
    for line in (body or "").splitlines():
        if re.match(r"^\s*(```|~~~)", line):
            fenced = not fenced
            continue
        if fenced or line.lstrip().startswith(">"):
            continue
        out.append(line)
    return out


def trusted(comment, pr_author):
    login = (comment.get("author") or {}).get("login")
    return (comment.get("authorAssociation") in TRUSTED_ASSOC) or bool(login and login == pr_author)


def ac_texts(body):
    """Nguyên văn các mục AC (mọi trạng thái tích) trong khối AC của thân PR."""
    in_ac, texts = False, []
    for line in (body or "").splitlines():
        if re.match(r"^#{1,6}\s", line):
            in_ac = bool(AC_HEADING.match(line))
            continue
        m = AC_ITEM.match(line) if in_ac else None
        if m:
            t = m.group(2).rstrip("\\").strip().lower()
            if len(t) >= MIN_AC_TEXT:
                texts.append(t)
    return texts


def names_ac(text, acs):
    low = text.lower()
    return bool(AC_ID.search(text)) or any(a in low for a in acs)


def latest_qa_unfinished(comments, pr_author=None, body=""):
    latest = None
    for c in comments or []:
        if not isinstance(c, dict) or not isinstance(c.get("body"), str) or not trusted(c, pr_author):
            continue
        lines = visible_lines(c["body"])
        if any(QA_HEADER.match(l) for l in lines):
            latest = lines          # thứ tự API = thứ tự thời gian: comment đáng tin cuối thắng
    if latest is None:
        return []
    acs = ac_texts(body)
    items = []
    for i, line in enumerate(latest):
        m = NOT_DONE.match(line)
        if not m:
            continue
        parts = [m.group(1).strip().rstrip("\\").strip()]
        for nxt in latest[i + 1:]:      # mục nhiều dòng: dòng thụt lề / gạch đầu dòng ngay dưới, dừng ở dòng trống hay trường mới
            if not nxt.strip() or not (nxt[:1].isspace() or BULLET.match(nxt)):
                break
            parts.append(nxt.strip())
        text = " ".join(p for p in parts if p).strip()
        if text.strip(" .").lower() not in EMPTY_VALUES and names_ac(text, acs):
            items.append(text)
    return items


def ac_without_proof(body):
    lines = (body or "").splitlines()
    in_ac, bad = False, []
    for i, line in enumerate(lines):
        if re.match(r"^#{1,6}\s", line):
            in_ac = bool(PROOF_HEADING.match(line))
            continue
        m = AC_ITEM.match(line) if in_ac else None
        if not m or m.group(1) == " ":
            continue
        # Bằng chứng nằm ở các dòng liền sau mục AC, dừng ở dòng trống, mục AC kế hay tiêu đề.
        proof = False
        for nxt in lines[i + 1:]:
            if not nxt.strip() or AC_ITEM.match(nxt) or re.match(r"^#{1,6}\s", nxt):
                break
            if PROOF.match(nxt):
                proof = True
                break
        if not proof:
            bad.append(m.group(2).rstrip("\\").strip())
    return bad


def run(meta_path):
    try:
        with open(meta_path, encoding="utf-8") as fh:
            meta = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"qa-report: không đọc được metadata PR ({exc})", file=sys.stderr)
        return 2
    if not isinstance(meta, dict):
        print("qa-report: metadata PR không phải object", file=sys.stderr)
        return 2
    author = meta.get("author")
    pr_author = author.get("login") if isinstance(author, dict) else None
    body = meta.get("body") if isinstance(meta.get("body"), str) else ""
    problems = [f"qa-report: report QA mới nhất còn việc chưa xong: {t[:200]}"
                for t in latest_qa_unfinished(meta.get("comments"), pr_author, body)]
    problems += [f"qa-report: AC đã tích [x] nhưng không có dòng bằng chứng '↳': {t[:200]}" for t in ac_without_proof(body)]
    for p in problems:
        print(p)
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meta", required=True)
    args = ap.parse_args()
    try:
        return run(args.meta)
    except Exception as exc:  # noqa: BLE001 — lỗi bất ngờ phải thành "không quyết định được" (2), không thành lỗi build
        print(f"qa-report: lỗi bất ngờ khi đối chiếu ({type(exc).__name__}: {exc})", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
