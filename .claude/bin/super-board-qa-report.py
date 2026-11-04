"""Đối chiếu report QA mới nhất và AC trong thân PR trước khi merge (#364). Không mạng, không tác dụng phụ.

    super-board-qa-report.py --meta <pr.json> [--head <sha40> --repo <path> --base <ref>]

`--meta` là `gh pr view --json body,comments,author`. Thoát 0 khi sạch; thoát 1 và in từng dòng `qa-report: <lý do>` khi:
  - comment `[qa] [report]` MỚI NHẤT của người đáng tin còn mục `❌ Not done:` NÊU TÊN một AC của PR: mã AC (`AC1`, `AC 7`) hoặc
    nguyên văn một mục trong khối AC của thân PR. Ghi chú phạm vi ("thuộc #358", "đã tách sang #352", "không có ảnh (không có UI)")
    không nêu AC nên không bị từ chối. Mục có thể nhiều dòng: các dòng thụt lề / gạch đầu dòng ngay dưới nó thuộc cùng mục;
  - mục AC `- [x]` trong "## Acceptance criteria" của thân PR không có dòng bằng chứng `↳ <nội dung>` ở các dòng liền sau nó
    (dừng ở dòng trống, mục AC kế hay tiêu đề). Khối "## AC + proof" (agents-md-block.md) chỉ dùng để nhận diện AC cho mục Not done:
    bằng chứng của nó nằm ngay trên dòng mục, các PR #345/#374 đã merge không có `↳`;
  - (T0255, khi có `--head` và `--base`) report QA mới nhất nêu sha một commit của nhánh PR mà head còn commit code sau sha đó
    (không tính commit merge và commit chỉ chạm docs/super-board/runs): QA chưa chạy lại trên code cuối.
Người đáng tin = tác giả PR hoặc authorAssociation OWNER/MEMBER/COLLABORATOR. Dòng trích dẫn `> ` và khối ``` bị bỏ qua.
Không có comment QA hay không có mục AC thì không có gì để từ chối (cổng khác lo việc QA vắng mặt).
Thoát 2 khi metadata không đọc được hay lỗi bất ngờ: cổng merge coi là "không quyết định được", không phải lỗi build.
ponytail: authorAssociation COLLABORATOR gồm cả quyền read (gh pr view không cho quyền cụ thể); nâng lên tra
`collaborators/<login>/permission` như super-board-approval.py khi có repo nhiều cộng tác viên chỉ-đọc.
"""
import argparse
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path
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
_CONFIG = os.environ.get("SB_CONFIG") or None  # decision_policy.enabled=false của config tắt luật này
MIN_AC_TEXT = 12  # AC ngắn hơn thế quá dễ trùng chữ thường trong ghi chú phạm vi
SHA_TOKEN = re.compile(r"\b[0-9a-f]{7,40}\b")
EVIDENCE_DIR = "docs/super-board/runs"  # commit bằng chứng QA (bin/tree_fp.py cũng bỏ thư mục này khỏi dấu vân tay cây)


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


# #516: bộ đọc [decision] dùng chung; tên file có gạch ngang nên nạp bằng importlib.
_spec = importlib.util.spec_from_file_location("sb_decision", Path(__file__).with_name("super-board-decision.py"))
_DEC = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_DEC)


def latest_qa(comments, pr_author=None):
    """(các dòng hiển thị, chỉ số) của report `[qa] [report]` mới nhất của người đáng tin; (None, -1) khi không có."""
    latest, latest_at = None, -1
    for i, c in enumerate(comments or []):
        if not isinstance(c, dict) or not isinstance(c.get("body"), str) or not trusted(c, pr_author):
            continue
        lines = visible_lines(c["body"])
        if any(QA_HEADER.match(l) for l in lines):
            latest, latest_at = lines, i    # thứ tự API = thứ tự thời gian: comment đáng tin cuối thắng
    return latest, latest_at


def _git(repo, *args):
    """stdout của git (đã strip), None khi git lỗi / quá 10 s."""
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def _is_ancestor(repo, a, b):
    """True/False theo `merge-base --is-ancestor` (exit 0/1); None khi git lỗi (exit khác, quá 10 s) — không đoán là 'không'."""
    try:
        r = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", a, b], capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return {0: True, 1: False}.get(r.returncode)


def stale_qa(comments, pr_author, head, repo, base):
    """T0255: report QA mới nhất nêu commit của nhánh PR mà head còn commit code sau đó ⇒ mô tả lỗi; còn lại None.
    Commit của nhánh = tổ tiên của head, không là tổ tiên của base (sha của main mà QA nêu để so ĐỎ thì bỏ qua). Base phải vừa
    fetch (merge gate lo): base cũ làm commit main đã gộp trông như commit của nhánh (Grok T0255 P1). Không đi theo first-parent:
    builder commit tại chỗ rồi `pull --no-rebase` đẩy commit QA sang cha thứ hai (review T0255 P2). Commit merge và commit chỉ chạm
    EVIDENCE_DIR không tính là code. Report không nêu commit nào của nhánh, hay git/base không đọc được: không chặn (giữ hành vi
    cũ). ponytail: commit merge có sửa tay khi giải conflict, và sha QA bị amend/force-push khỏi lịch sử head, không bị tính; so cây
    của phần nhánh khi gặp ca lọt như vậy."""
    lines, _ = latest_qa(comments, pr_author)
    if lines is None or not head:
        return None
    tokens = set(SHA_TOKEN.findall("\n".join(lines)))
    if any(head.startswith(t) for t in tokens):
        return None
    if _git(repo, "rev-parse", "--verify", "-q", f"{base}^{{commit}}") is None:
        print(f"qa-report-note: bỏ qua ghim sha QA — không đọc được base {base}", file=sys.stderr)
        return None
    own = []
    for t in sorted(tokens):
        sha = _git(repo, "rev-parse", "--verify", "-q", f"{t}^{{commit}}")
        if not sha:
            continue                      # hash file, sha chưa fetch: không phải lời khai về commit
        in_head, in_base = _is_ancestor(repo, sha, head), _is_ancestor(repo, sha, base)
        if in_head is None or in_base is None:
            print(f"qa-report-note: bỏ qua ghim sha QA — git merge-base lỗi trên {sha[:12]}", file=sys.stderr)
            return None
        if in_head and not in_base:
            own.append(sha)
    if not own:
        return None
    after = []
    for sha in own:
        out = _git(repo, "log", "--no-merges", "--format=%h %s", head, f"^{sha}", f"^{base}", "--", ".", f":(exclude){EVIDENCE_DIR}")
        if out is None:
            print(f"qa-report-note: bỏ qua ghim sha QA — git log lỗi trên {sha[:12]}", file=sys.stderr)
            return None
        if not out:
            return None
        after.append((sha, out.splitlines()))
    sha, commits = min(after, key=lambda a: len(a[1]))
    return (f"report QA mới nhất kiểm {sha[:12]}, head {head[:12]} còn {len(commits)} commit code sau đó "
            f"({'; '.join(c[:80] for c in commits[:3])}): QA phải chạy lại trên head")


def latest_qa_unfinished(comments, pr_author=None, body=""):
    latest, latest_at = latest_qa(comments, pr_author)
    if latest is None:
        return []
    # #516: [decision] hợp lệ mới hơn report QA đã xử lý các mục còn mở của nó (luật 1–5 của chủ), nên không chặn merge.
    # ponytail: một decision gỡ MỌI mục Not done của report cũ hơn nó (không đối chiếu từng AC); đối chiếu theo mã AC
    # khi thấy một decision gỡ nhầm mục nó không nhắc.
    decided = _DEC.newest_valid_index(comments, _DEC.load_policy(_CONFIG)) > latest_at
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
            # DANH SÁCH DỪNG (lái xe, secret…) trong chữ của mục (cả dòng nối tiếp) thì decision không gỡ mục đó.
            if not decided or _DEC.is_stop(text):
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


def run(meta_path, head=None, repo=".", base=None):
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
    stale = stale_qa(meta.get("comments"), pr_author, head, repo, base) if head and base else None
    if stale:
        problems.append(f"qa-report: {stale}")
    for p in problems:
        print(p)
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meta", required=True)
    ap.add_argument("--head", help="sha40 head PR: bật ghim sha QA (T0255); thiếu thì bỏ qua")
    ap.add_argument("--repo", default=".", help="repo git chứa head và base")
    ap.add_argument("--base", help="ref base, ví dụ origin/main")
    args = ap.parse_args()
    try:
        return run(args.meta, args.head, args.repo, args.base)
    except Exception as exc:  # noqa: BLE001 — lỗi bất ngờ phải thành "không quyết định được" (2), không thành lỗi build
        print(f"qa-report: lỗi bất ngờ khi đối chiếu ({type(exc).__name__}: {exc})", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
