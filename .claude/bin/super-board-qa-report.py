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
    (không tính merge sạch và commit chỉ chạm docs/super-board/runs; #1000: merge sửa tay / giải conflict tay có tính), hay nêu
    commit đã bị amend / force-push khỏi lịch sử head mà code khác head: QA chưa chạy lại trên code cuối (chi tiết: stale_qa).
    Lỗi git khi kiểm (base không đọc được…) = thoát 2, không bỏ ghim.
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


class GitError(RuntimeError):
    """git lỗi / quá giờ khi kiểm ghim sha QA (#1000): không quyết định được (main -> exit 2, merge gate -> exit 7), không lặng lẽ bỏ ghim."""


def _git(repo, *args, ok=(0,)):
    """(mã thoát, stdout đã strip) của git; mã ngoài `ok` hay quá 60 s -> GitError. Subject không phải UTF-8 thay bằng U+FFFD.
    60 s (như audit-check): merge-tree / diff trên repo Unity lúc 6 board chạy; lỗi ở đây thành cổng người (exit 7), không lặng lẽ qua."""
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, errors="replace", timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GitError(f"git {args[0]}: {type(exc).__name__}") from exc
    if r.returncode not in ok:
        raise GitError(f"git {args[0]} exit {r.returncode}")
    return r.returncode, r.stdout.strip()


def _commit(repo, token):
    """sha40 của commit `token` trỏ tới, None khi không phải commit (hash file, sha chưa fetch, tiền tố mơ hồ)."""
    rc, out = _git(repo, "rev-parse", "--verify", "-q", f"{token}^{{commit}}", ok=(0, 1, 128))
    return out if rc == 0 and out else None


def _is_ancestor(repo, a, b):
    """True/False theo `merge-base --is-ancestor` (exit 0/1); mã khác -> GitError (không đoán là 'không')."""
    return _git(repo, "merge-base", "--is-ancestor", a, b, ok=(0, 1))[0] == 0


def _same_code(repo, a, b):
    """True khi hai tree-ish giống nhau ngoài EVIDENCE_DIR."""
    return _git(repo, "diff", "--quiet", a, b, "--", ".", f":(exclude){EVIDENCE_DIR}", ok=(0, 1))[0] == 0


def _code_after(repo, sha, head, base):
    """Thay đổi code của nhánh sau `sha` tới `head` (không tính base, không tính EVIDENCE_DIR): commit thường, và commit merge có nội
    dung khác bản gộp tự động của hai cha — sửa tay, giải conflict bằng tay — hay không đúng hai cha (#1000 mục 1: --no-merges bỏ sót)."""
    _, out = _git(repo, "log", "--no-merges", "--format=%h %s", head, f"^{sha}", f"^{base}", "--", ".", f":(exclude){EVIDENCE_DIR}")
    found = out.splitlines() if out else []
    _, merges = _git(repo, "rev-list", "--merges", head, f"^{sha}", f"^{base}")
    for m in merges.split():
        parents = _git(repo, "rev-list", "--parents", "-n", "1", m)[1].split()[1:]
        if len(parents) == 2:
            # merge-tree (trong chính repo: driver gộp của .gitattributes áp dụng) in tree gộp ở dòng đầu, kể cả khi conflict (exit 1;
            # tree có dấu conflict nên khác commit đã giải tay). Không có tree = lỗi git.
            _, mt = _git(repo, "merge-tree", "--write-tree", "--no-messages", parents[0], parents[1], ok=(0, 1))
            tree = mt.splitlines()[0].strip() if mt else ""
            if not tree:
                raise GitError(f"git merge-tree {m[:12]}: no tree")
            if _same_code(repo, tree, m):
                continue
        found.append(f"{m[:9]} merge commit có thay đổi code ngoài bản gộp tự động")
    return found


def stale_qa(comments, pr_author, head, repo, base):
    """T0255: report QA mới nhất kiểm một commit mà head còn code chưa QA ⇒ mô tả lỗi; còn lại None. Lỗi git ⇒ GitError.
    Lời khai: sha ở dòng tiêu đề `[qa] [report]` khi nó là commit; không thì mọi sha trong các dòng hiển thị (#1000: head chỉ được nhắc
    ở thân không thay lời khai ở tiêu đề). Một sha lời khai == head ⇒ None.
    Commit của nhánh (own) = tổ tiên của head, không là tổ tiên của base (sha của main mà QA nêu để so ĐỎ thì bỏ qua). Base phải vừa
    fetch (merge gate lo): base cũ làm commit main đã gộp trông như commit của nhánh (Grok T0255 P1). Không đi theo first-parent:
    builder commit tại chỗ rồi `pull --no-rebase` đẩy commit QA sang cha thứ hai (review T0255 P2). Commit chỉ chạm EVIDENCE_DIR và
    merge sạch không tính là code; merge sửa tay / giải conflict tay thì tính (_code_after). #1000: MỌI sha own còn code sau ⇒ từ chối
    (không lấy sha "tốt nhất"): report mới nhất nêu sha vòng cũ thì exit 11 là chấp nhận được, QA ghi lại report trên head.
    Không có sha own: sha lời khai không thuộc lịch sử head lẫn base (amend / force-push) mà code khác head ⇒ từ chối."""
    lines, _ = latest_qa(comments, pr_author)
    if lines is None or not head:
        return None
    # head/base trước: repo hỏng (rev-parse 128) không được làm mọi token thành "không phải commit" rồi lặng lẽ qua.
    head_sha, base_sha = _commit(repo, head), _commit(repo, base)
    if not head_sha or not base_sha:
        raise GitError(f"không đọc được {'head ' + head if not head_sha else 'base ' + base}")
    header = next((l for l in lines if QA_HEADER.match(l)), "")
    claims = [s for s in (_commit(repo, t) for t in sorted(set(SHA_TOKEN.findall(header)))) if s]
    # Tiêu đề chỉ là lời khai khi nó nêu ít nhất một commit KHÔNG thuộc base (sha main ở tiêu đề không thay sha nhánh ở thân).
    if not any(not _is_ancestor(repo, s, base_sha) for s in claims):
        claims = [s for s in (_commit(repo, t) for t in sorted(set(SHA_TOKEN.findall("\n".join(lines))))) if s]
    if not claims:
        return None
    if head_sha in claims:
        return None
    own, foreign = [], []
    for sha in dict.fromkeys(claims):
        if _is_ancestor(repo, sha, base_sha):
            continue
        (own if _is_ancestor(repo, sha, head_sha) else foreign).append(sha)
    for sha in own:
        commits = _code_after(repo, sha, head_sha, base_sha)
        if commits:
            return (f"report QA mới nhất kiểm {sha[:12]}, head {head_sha[:12]} còn {len(commits)} commit code sau đó "
                    f"({'; '.join(c[:80] for c in commits[:3])}): QA phải chạy lại trên head")
    if own:
        return None
    for sha in foreign:
        if not _same_code(repo, sha, head_sha):
            return (f"report QA mới nhất kiểm {sha[:12]}, commit không còn trong lịch sử head {head_sha[:12]} (amend / force-push) "
                    f"và code khác head: QA phải chạy lại trên head")
    return None


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
