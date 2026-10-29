#!/usr/bin/env python3
"""Đánh dấu thẻ super-board "cần người", hiện ngay trên thẻ, bằng một lệnh idempotent.

  mark   --repo O/R --issue N --action "<ĐÚNG việc người phải làm>" [--next "<xong thì làm gì>"] [--dry-run]
  unmark --repo O/R --issue N [--dry-run]
  label  --repo O/R [--dry-run]              nhãn `needs-you`, một màu trên mọi repo
  board  --owner O --project N [--dry-run]   bật trường Labels trên mọi view của board

`mark` gắn nhãn `needs-you` lên issue (gộp nhãn cũ `human-gated` vào đó), rồi giữ MỘT
comment, tìm bằng marker ẩn:

    <!-- super-board:needs-you -->
    🙋 Cần bạn: <action> · xong thì <next>

Chạy lại với cùng nội dung: không ghi gì. Việc khác: sửa đúng comment đó. `unmark` gỡ
nhãn, đổi comment (và dòng 🙋 trong mục `## Cần người` của body, nếu có) thành ghi chú ✅.

Vì sao nhãn thôi chưa đủ: ngày 19/10 không view board nào hiện nhãn, nên `board` thêm
trường Labels vào từng view rồi đọc lại view để xác nhận.

Comment không bao giờ mang dòng máy đọc. super-board-approval.py coi comment mới nhất có
`Reason tag: …🙋` hoặc `approval-request:` là yêu cầu duyệt merge, super-board-deps.sh đọc
dòng `blocked-by:` cuối cùng: một trong hai trong comment này sẽ đẩy yêu cầu thật ra hoặc
đổi blocker của thẻ. Text như thế bị từ chối (64).

Gọi `gh` trần có timeout, không dùng file halt của board: người, lane và createTask gọi
helper này, đánh dấu lỗi thì chỉ lệnh đó lỗi, không dừng cả board (super-board-github-read.py).
Exit: 0 xong · 1 một lệnh gh lỗi · 2 sai cú pháp (argparse) · 64 text --action/--next/--repo sai.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

LABEL = "needs-you"
LEGACY_LABEL = "human-gated"
COLOR = "D93F0B"
DESCRIPTION = "🙋 Cần người thực hiện bước chỉ con người được làm"
MARKER = "<!-- super-board:needs-you -->"
DONE_MARKER = "<!-- super-board:needs-you:done -->"
DEFAULT_NEXT = "gỡ nhãn needs-you rồi kéo thẻ về Ready"
MACHINE_LINE = re.compile(r"reason tag:|blocked-by:|approval-request:|<!--", re.I)
# Rào chắn tự chủ: từ chối đánh dấu needs-you cho các việc agent tự làm được (test PR trên máy/máy ảo,
# chạy lại gate/chờ tải CPU, dọn worktree, tách thẻ <400 dòng, tự duyệt ma trận test, tự chốt UI/kỹ thuật).
AGENT_DOABLE_RULES = (
    (
        re.compile(
            r"thử\s+pr\s+#\d+|chạy\s+lại\s+gate|gate\s+--full|cổng\s+perf|chờ\s+load|dừng\s+gradle|"
            r"kiểm\s+không\s+hồi\s+quy|chạy\s+d2\b|bật\s+lại\s+máy\s+ảo|máy\s+ảo\s+phoneconnect|"
            r"roborazzi\s+baseline\s+record|run\s+workflow\s+trên\s+main|\bchmod\b|"
            # 24/10 #319: một suite quá giờ là test treo/tải máy cần điều tra, không phải quyết định của người. Chỉ khi câu
            # nói về gate/suite (REG-, suite, gate): "nâng timeout Lambda trên AWS" vẫn là việc của người.
            r"(?=[^\n]*\b(?:nâng|tăng|nới|đặt|raise[sd]?|bump(?:ed)?|increas(?:e|ed|ing)|extend(?:ed)?|set)\b)"
            r"(?=[^\n]*(?:timeout|giới\s+hạn|thời\s+gian|\blimit\b))(?=[^\n]*(?:\bREG-[A-Z]|\bgate\b|post-fix-gate|test\s+suite))|"
            r"(?=[^\n]*\b(?:chấp\s+nhận|accept)\b)(?=[^\n]*\btimeout\b)(?=[^\n]*\bREG-[A-Z])|"
            r"thay\s+(?:cho\s+)?(?:exit\s*0\s+của\s+gate|gate\s+exit)|instead\s+of\s+a\s+gate\s+exit",
            re.I,
        ),
        "test/verify PR trên máy hoặc máy ảo, chạy gate/perf hoặc workflow CI là việc của agent (Builder/QA/Reviewer)",
    ),
    (
        re.compile(r"gỡ\s+(?:hoặc\s+giữ\s+)?worktree|\.claude/worktrees/|worktree\s+(?:discard|remove)", re.I),
        "dọn dẹp worktree là việc của agent (chép agent-memory nếu có, hoàn tác file runtime DevKit rồi chạy worktree remove)",
    ),
    (
        re.compile(
            r"/to-tickets|tách\s+thẻ|tách\s+phần\s+giao\s+diện|thu\s+body\s+#?\d+|"
            r"(?:dưới|<\s*)400\s+dòng|tách\s+#\d+\s+thành",
            re.I,
        ),
        "tách thẻ lớn (<400 dòng) hoặc thu gọn phạm vi lát cắt là việc agent phải tự thực hiện",
    ),
    (
        re.compile(
            r"approve\s+matrix\s+fix|ma\s+trận\s+hồi\s+quy|chốt\s+phạm\s+vi\s+ac|chốt\s+vị\s+trí\s+nút|"
            r"chốt\s+ưu\s+tiên\s+máy\s+tính\s+bảng|quyết\s+định\s+cách\s+ghi\s+0x|duyệt\s+hướng\s+sửa|"
            r"chốt\s+bủm\s+là\s+loài|chốt\s+bộ\s+mới\s+thay|duyệt\s+hoặc\s+chỉnh\s+thiết\s+kế|"
            r"chọn\s+phạm\s+vi\s+chống\s+cộng\s+trùng|chọn\s+a\s+cho\s+pr\s+#\d+|gen_voice_packs\.py",
            re.I,
        ),
        "quyết định kỹ thuật/UI/phạm vi AC hoặc duyệt ma trận test thuộc thẩm quyền tự chủ của agent (Decide, don't ask / AUTO-APPROVE)",
    ),
)
GENUINE_HUMAN_RE = re.compile(
    r"api[ _-]?key|supabase\s+(?:login|secrets)|play\s+console|apple\s+(?:developer|team\s+id)|"
    r"nđ\s*147|botfather|keystore|admob|firebase|\b[3-9]\s+người\s+chơi\s+thật|"
    r"iarc|pháp\s+nhân|elm327|trên\s+xe\s+thật|ngồi\s+xe|lái\s+một\s+buổi|bật\s+xe|"
    r"cho\s+xe\s+online|đăng\s+nhập\s+vietmap|spending\s+limit|giới\s+hạn\s+chi\s+tiêu|\b(?:postgres|database|db)\s+production\b|\bproduction\s+(?:db|database)\b",
    re.I,
)
TIMEOUT = 60


# #516: bộ đọc [decision] dùng chung; tên file có gạch ngang nên nạp bằng importlib.
_spec = importlib.util.spec_from_file_location("sb_decision", Path(__file__).with_name("super-board-decision.py"))
_DEC = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_DEC)

PROJECT_QUERY = """query($owner:String!,$number:Int!){
  repositoryOwner(login:$owner){
    ... on User { projectV2(number:$number){ ...p } }
    ... on Organization { projectV2(number:$number){ ...p } }
  }
}
fragment p on ProjectV2 {
  id
  fields(first:50){ pageInfo{ hasNextPage } nodes{ ... on ProjectV2FieldCommon { id name dataType } } }
  views(first:20){ pageInfo{ hasNextPage } nodes{ id name layout
    fields(first:50){ pageInfo{ hasNextPage } nodes{ ... on ProjectV2FieldCommon { id name } } } } }
}"""
VIEW_MUTATION = """mutation($view:ID!,$ids:[ID!]!){
  updateProjectV2View(input:{viewId:$view, configuration:{visibleFieldIds:$ids}}){ projectV2View{ id } }
}"""


class GhError(RuntimeError):
    pass


class NotFound(GhError):
    pass


def gh(*args, stdin=None):
    try:
        r = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as e:
        raise GhError(f"gh {' '.join(args[:3])} timed out after {TIMEOUT}s") from e
    if r.returncode != 0:
        err = (r.stderr or r.stdout).strip()
        if "HTTP 404" in err:
            raise NotFound(err)
        raise GhError(f"gh {' '.join(args[:3])} failed: {err}")
    if not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError as e:
        raise GhError(f"gh {' '.join(args[:3])} returned non-JSON output") from e


def one_line(text, what):
    text = " ".join((text or "").split())
    if not text:
        raise ValueError(f"{what} is empty")
    if MACHINE_LINE.search(text):
        raise ValueError(f"{what} must not contain `Reason tag:`, `blocked-by:`, `approval-request:` or `<!--`")
    if len(text) > 500:
        raise ValueError(f"{what} is longer than 500 characters")
    # #529: the denylist screens --action and --next. A genuine human keyword excuses only its own clause: split on
    # `;` `·` `,` `.` and the words "và"/"rồi"/"and"/"then", so "đăng nhập firebase và chạy lại gate" still trips on the gate clause.
    # Split only when a human keyword is present (else the whole text is one clause: the rules' lookaheads and the
    # `.claude/worktrees/` / `x.py` patterns need it intact). A `.` separates only before a space or the end.
    clauses = re.split(r"[;·,]|\.(?=\s|$)|\b(?:và|rồi|and|then)\b", text, flags=re.I) if GENUINE_HUMAN_RE.search(text) else [text]
    for clause in clauses:
        if GENUINE_HUMAN_RE.search(clause):
            continue
        for pat, why in AGENT_DOABLE_RULES:
            if pat.search(clause):
                raise ValueError(
                    f"{what} mô tả việc agent phải tự xử lý ({why}); "
                    "hãy tự thực thi, tự chốt (Decide, don't ask / AUTO-APPROVE) hoặc trả thẻ về Ready/QA thay vì gắn needs-you"
                )
    return text


def comment_body(action, nxt):
    return f"{MARKER}\n🙋 Cần bạn: {action} · xong thì {nxt}"


def ensure_label(repo, dry):
    try:
        cur = gh("api", f"repos/{repo}/labels/{LABEL}")
    except NotFound:
        cur = None
    if cur is None:
        if not dry:
            gh("api", f"repos/{repo}/labels", "-f", f"name={LABEL}", "-f", f"color={COLOR}", "-f", f"description={DESCRIPTION}")
        return "created"
    if (cur.get("color") or "").upper() == COLOR and (cur.get("description") or "") == DESCRIPTION:
        return "kept"
    if not dry:
        gh("api", "-X", "PATCH", f"repos/{repo}/labels/{LABEL}", "-f", f"color={COLOR}", "-f", f"description={DESCRIPTION}")
    return "recoloured"


def remove_label(repo, issue, name):
    try:
        gh("api", "-X", "DELETE", f"repos/{repo}/issues/{issue}/labels/{name}")
        return True
    except NotFound:
        return False  # nhãn đã không còn (người hoặc lần chạy khác đã gỡ): đúng trạng thái mong muốn


def read_issue(repo, issue):
    data = gh("api", f"repos/{repo}/issues/{issue}") or {}
    labels = [l["name"] for l in data.get("labels", [])]
    pages = gh("api", f"repos/{repo}/issues/{issue}/comments", "--paginate", "--slurp") or []
    comments = [c for page in pages for c in (page if isinstance(page, list) else [page])]
    return labels, comments, data.get("body") or ""


# Dòng 🙋 đầu tiên trong mục `## Cần người` của body (createTask viết mục này), trước heading `## ` kế tiếp.
# `[^\r\n]*` chứ không `.*`: `.` nuốt cả `\r`, nên với body CRLF (GitHub web lưu thế) mỗi dòng có hai cách khớp
# và regex backtrack theo hàm mũ khi mục không có dòng 🙋 (24 dòng mất 28 s, đo 19/10).
SECTION_LINE = re.compile(r"(^##[ \t]+Cần người[ \t]*\r?\n(?:(?!##[ \t])[^\r\n]*\r?\n)*?)🙋 Cần bạn:", re.M)


def mark(repo, issue, action, nxt, dry, config=None):
    done = [f"label {ensure_label(repo, dry)}"]
    labels, comments, _ = read_issue(repo, issue)
    # #516: một [decision] hợp lệ mới hơn comment needs-you gần nhất đã xử lý blocker này, trừ DANH SÁCH DỪNG của chủ.
    policy = _DEC.load_policy(config or os.environ.get("SB_CONFIG"))
    at = _DEC.newest_valid_index(comments, policy)
    # Mốc = blocker mới nhất: comment needs-you, hoặc Block 🙋 / dòng `blocked-by:` mà lane vừa đăng trước khi gọi mark.
    last_mark = max((i for i, c in enumerate(comments)
                     if not _DEC.is_valid(c, policy) and ((c.get("body") or "").startswith(MARKER)
                     or re.search(r"Reason tag:[^\n]*🙋|(^|\n)[ \t]*blocked-by:", c.get("body") or "", re.I))), default=-1)
    if at > last_mark and not _DEC.is_stop(action):
        return done + ["skipped: [decision] hợp lệ mới hơn đã xử lý blocker, không gắn needs-you"]
    if LABEL not in labels:
        if not dry:
            gh("api", f"repos/{repo}/issues/{issue}/labels", "-f", f"labels[]={LABEL}")
        done.append("needs-you added")
    if LEGACY_LABEL in labels:
        if not dry:
            remove_label(repo, issue, LEGACY_LABEL)
        done.append("human-gated removed")
    body = comment_body(action, nxt)
    # ponytail: hai lệnh mark cùng lúc trên một thẻ có thể cùng đăng comment; lane đánh dấu từng thẻ một,
    # thêm khoá (hoặc đọc lại sau khi đăng và xoá bản thừa) nếu thấy comment trùng.
    mine = [c for c in comments if (c.get("body") or "").startswith(MARKER)]
    if not mine:
        if not dry:
            gh("api", f"repos/{repo}/issues/{issue}/comments", "-f", f"body={body}")
        done.append("comment created")
    elif mine[-1].get("body") != body:
        if not dry:
            gh("api", "-X", "PATCH", f"repos/{repo}/issues/comments/{mine[-1]['id']}", "-f", f"body={body}")
        done.append("comment updated")
    else:
        done.append("comment kept")
    return done


def unmark(repo, issue, dry):
    labels, comments, body = read_issue(repo, issue)
    done = []
    # ponytail: đọc body rồi PATCH cả body, một sửa tay chen giữa hai bước bị ghi đè; đọc lại ngay trước PATCH
    # nếu thấy mất sửa đổi. mark sau unmark không đặt lại body (body giữ ✅ như lịch sử).
    resolved = SECTION_LINE.sub(r"\1✅ Đã xong phần cần người:", body, count=1)
    if resolved != body:
        if not dry:
            gh("api", "-X", "PATCH", f"repos/{repo}/issues/{issue}", "-f", f"body={resolved}")
        done.append("body section resolved")
    if LABEL in labels:
        if not dry:
            remove_label(repo, issue, LABEL)
        done.append("needs-you removed")
    for c in comments:
        text = c.get("body") or ""
        if text.startswith(MARKER):
            note = text[len(MARKER):].strip().replace("🙋 Cần bạn:", "✅ Đã xong phần cần người:", 1)
            if not dry:
                gh("api", "-X", "PATCH", f"repos/{repo}/issues/comments/{c['id']}", "-f", f"body={DONE_MARKER}\n{note}")
            done.append("comment resolved")
    # Xoá sổ early-deaths cục bộ của thẻ khi gỡ needs-you để thẻ không bị cầu chì SB_EARLY_MAX_TOTAL giữ kẹt.
    ed_file = os.path.join(".claude", "super-board", "inflight", "early-deaths", str(issue))
    if os.path.isfile(ed_file):
        if not dry:
            try:
                os.remove(ed_file)
            except OSError as e:
                print(f"needs-you: warning: could not remove {ed_file}: {e}", file=sys.stderr)
        done.append("early-deaths reset")
    return done or ["nothing to unmark"]


def board(owner, number, dry):
    def views():
        data = gh("api", "graphql", "-f", f"query={PROJECT_QUERY}", "-f", f"owner={owner}", "-F", f"number={number}")
        proj = ((data or {}).get("data") or {}).get("repositoryOwner") or {}
        proj = proj.get("projectV2")
        if not proj:
            raise GhError(f"project {owner}#{number} not found")
        return proj
    proj = views()
    # Một trang là đủ cho board hiện có (2 view, ~13 trường); nhiều hơn thì dừng: gửi visibleFieldIds thiếu sẽ ẩn
    # trường của view đó, còn bỏ qua view sau trang đầu thì báo xong sai.
    pages = [proj["fields"], proj["views"]] + [v["fields"] for v in proj["views"]["nodes"]]
    if any((c.get("pageInfo") or {}).get("hasNextPage") for c in pages):
        raise GhError(f"project {owner}#{number} has more than 20 views or 50 fields: not handled, nothing changed")
    labels_id = next((f["id"] for f in proj["fields"]["nodes"] if f.get("dataType") == "LABELS"), None)
    if not labels_id:
        raise GhError(f"project {owner}#{number} has no Labels field")
    done, changed = [], []
    for v in proj["views"]["nodes"]:
        ids = [f["id"] for f in v["fields"]["nodes"] if f.get("id")]
        if labels_id in ids:
            done.append(f"{v['name']}: kept")
            continue
        changed.append(v["id"])
        if not dry:
            # Biến kiểu danh sách phải nằm trong body JSON: `-f ids=[…]` sẽ gửi một chuỗi.
            gh("api", "graphql", "--input", "-",
               stdin=json.dumps({"query": VIEW_MUTATION, "variables": {"view": v["id"], "ids": ids + [labels_id]}}))
        done.append(f"{v['name']}: Labels shown")
    if changed and not dry:
        after = {v["id"]: [f["id"] for f in v["fields"]["nodes"] if f.get("id")] for v in views()["views"]["nodes"]}
        missing = [vid for vid in changed if labels_id not in after.get(vid, [])]
        if missing:
            raise GhError(f"GitHub kept Labels hidden on view(s) {', '.join(missing)} after the update")
    return done


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("mark", "unmark", "label"):
        p = sub.add_parser(name)
        p.add_argument("--repo", required=True)
        if name != "label":
            p.add_argument("--issue", required=True, type=int)
        if name == "mark":
            p.add_argument("--action", required=True, help="exactly what the person must do")
            p.add_argument("--next", default=DEFAULT_NEXT, help="what to do once it is done")
            p.add_argument("--config", help="super-board config (decision_policy)")
        p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("board")
    p.add_argument("--owner", required=True)
    p.add_argument("--project", required=True, type=int)
    p.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    try:
        if args.cmd == "mark":
            action, nxt = one_line(args.action, "--action"), one_line(args.next, "--next")
    except ValueError as e:
        print(f"needs-you: {e}", file=sys.stderr)
        return 64
    if getattr(args, "repo", None) and not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        print("needs-you: --repo must be owner/name", file=sys.stderr)
        return 64
    try:
        if args.cmd == "mark":
            done, where = mark(args.repo, args.issue, action, nxt, args.dry_run, args.config), f"{args.repo}#{args.issue}"
        elif args.cmd == "unmark":
            done, where = unmark(args.repo, args.issue, args.dry_run), f"{args.repo}#{args.issue}"
        elif args.cmd == "label":
            done, where = [f"label {ensure_label(args.repo, args.dry_run)}"], args.repo
        else:
            done, where = board(args.owner, args.project, args.dry_run), f"board {args.owner}#{args.project}"
    except GhError as e:
        print(f"needs-you: {e}", file=sys.stderr)
        return 1
    print(f"needs-you {'[dry-run] ' if args.dry_run else ''}{where}: {' · '.join(done)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
