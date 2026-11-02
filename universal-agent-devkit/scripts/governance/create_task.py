#!/usr/bin/env python3
"""
create_task.py — Tự động tạo issue và đẩy lên cột Backlog của GitHub Project Board
Hỗ trợ cả 5 repositories:
  1. ToanMobile/agent-workbench             ➔ Project #1: Agent Workbench
  2. ToanMobile/OfficeReader                ➔ Project #2: OfficeReader
  3. ToanMobile/Goods-Triple-Shelf-Match-3D ➔ Project #3: Goods Triple Shelf Match 3D
  4. ToanMobile/GeelyEx2                    ➔ Project #4: GeelyEx2
  5. ToanMobile/Idle-Plaza-3D               ➔ Project #5: Idle Plaza 3D

Sử dụng:
  1. Tạo nhanh từ câu tóm tắt (auto-format):
     python3 create_task.py "fix lỗi review_gate tự xả 43 lần"
  2. Tạo chi tiết chuẩn Super-Board:
     python3 create_task.py --title "🐛 [bug] hooks: sửa lỗi X" --problem "..." --fix "..."
  3. Đẩy từ file mẫu (như docs/super-board/backlog-tickets.md):
     python3 create_task.py --from-file docs/super-board/backlog-tickets.md --ticket 1
  4. Cả file là body (không --ticket; file phải có `## Problem`, title lấy từ --title):
     python3 create_task.py --from-file card.md --title "🐛 [fix] scope: what"

Mã thoát:
  0   đã tạo (hoặc --dry-run / gom vào thẻ chưa chạy)
  2   --from-file không kèm --ticket mà file thiếu `## Problem` hoặc không đọc được: không tạo thẻ
  3   thẻ đã tạo nhưng chưa đánh dấu "cần người" hoặc chưa gán cột Backlog
  64  đối số sai: --new-card thiếu lý do, --needs-you rỗng, --ticket nhỏ hơn 1, --from-file không kèm --ticket
      mà thiếu --title (hoặc --title toàn khoảng trắng), hoặc thẻ nhắc tên repo khác mà chưa có --repo / --here
"""

import os
import sys
import re
import json
import argparse
import subprocess
from pathlib import Path

PROJECT_OWNER = "ToanMobile"

# Cấu hình 5 repositories tương ứng 5 Project Boards trên ToanMobile
PROJECT_REGISTRY = {
    "ToanMobile/agent-workbench": {
        "number": 1,
        "name": "Agent Workbench",
        "project_id": "PVT_kwHOAGnqzM4BnS4g",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnS4gzhl4Kok",
        "backlog_option_id": "81f934af",
        # #724: đợt (nhiều thẻ, một nhánh/PR/gate) cần merge gate hiểu marker sb:batch-of; repo khác bật khi port ac-check.
        "batch": True,
    },
    "ToanMobile/OfficeReader": {
        "number": 2,
        "name": "OfficeReader",
        "project_id": "PVT_kwHOAGnqzM4BnS_9",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnS_9zhl4RiM",
        "backlog_option_id": "118f3719",
    },
    "ToanMobile/Goods-Triple-Shelf-Match-3D": {
        "number": 3,
        "name": "Goods Triple Shelf Match 3D",
        "project_id": "PVT_kwHOAGnqzM4BnTAC",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnTACzhl4Rm8",
        "backlog_option_id": "0e6f84ef",
    },
    "ToanMobile/GeelyEx2": {
        "number": 4,
        "name": "GeelyEx2",
        "project_id": "PVT_kwHOAGnqzM4BnTAH",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnTAHzhl4Rrk",
        "backlog_option_id": "cbc05bf8",
    },
    "ToanMobile/Idle-Plaza-3D": {
        "number": 5,
        "name": "Idle Plaza 3D",
        "project_id": "PVT_kwHOAGnqzM4BnTFL",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnTFLzhl4WVM",
        "backlog_option_id": "5eaaa6e6",
    },
    "ToanMobile/Humans-vs.-UFOs": {
        "number": 6,
        "name": "Humans vs. UFOs",
        "project_id": "PVT_kwHOAGnqzM4Bnjmj",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnjmjzhmHqYI",
        "backlog_option_id": "9466928a",
    },
}

DEFAULT_REPO = "ToanMobile/agent-workbench"

# Tên một repo app trong chữ của thẻ (tiêu đề, body). Thẻ nêu tên repo app mà chạy từ checkout khác thì phải đi
# với --repo, nếu không nó nằm trên board của checkout (22/10: 8 thẻ Goods/NFH/GeelyEx2/OfficeReader ở Project #1).
# agent-workbench không có mặt ở đây: thẻ app nhắc kit là chuyện thường, và sự cố 22/10 chỉ đi chiều kit sang app.
# ponytail: heuristic theo tên, tên viết thường hoặc cách khác (officereader, Office Reader) lọt; nâng cấp khi có thẻ nhầm lọt.
REPO_NAME_PATTERNS = {
    "ToanMobile/OfficeReader": r"OfficeReader",
    "ToanMobile/Goods-Triple-Shelf-Match-3D": r"Goods(?:-Triple-Shelf-Match-3D)?",
    "ToanMobile/GeelyEx2": r"GeelyEx2",
    "ToanMobile/Idle-Plaza-3D": r"Idle(?:-| )Plaza(?:-| )3D",
    "ToanMobile/Humans-vs.-UFOs": r"Humans-vs\.-UFOs",
}

# Thẻ chỉ người làm được (máy thật, playtest, store, secret, quyết định): nhãn + comment do
# .claude/bin/super-board-needs-you.py ở thư mục gốc của checkout đang đứng gắn (nó nhận --repo); nhãn, màu và
# mô tả dưới đây chỉ dùng khi chưa có helper đó.
NEEDS_YOU_HELPER = Path(".claude/bin/super-board-needs-you.py")
NEEDS_YOU_LABEL = "needs-you"
NEEDS_YOU_COLOR = "D93F0B"
NEEDS_YOU_DESC = "🙋 Cần người thực hiện bước chỉ con người được làm"
# Bước sau mặc định: --needs-you (có thể còn phần của lane) về Ready; thẻ tự đánh dấu vì MỌI dòng AC là việc
# của người thì xong là hết việc, kéo về Ready chỉ khiến lane build một thẻ không có gì để build.
NEEDS_YOU_NEXT = "gỡ nhãn needs-you rồi kéo thẻ về Ready"
NEEDS_YOU_DONE_NEXT = "dán bằng chứng vào issue rồi đóng issue"
# ponytail: danh sách cụm từ chỉ là đường dự phòng khi không truyền --needs-you; trần = các cụm dưới đây,
# thêm cụm (hoặc bỏ cụm) khi thấy thẻ bị đánh dấu sai/thiếu.
HUMAN_ONLY = re.compile("|".join([
    r"thiết bị thật", r"máy thật", r"điện thoại thật", r"\breal device", r"\bphysical device",
    r"xe thật", r"head ?unit thật", r"\bin[- ]car\b",
    r"playtest", r"người chơi thật", r"\breal players?\b",
    r"play console", r"app store connect", r"testflight", r"apple team id", r"\biarc\b",
    r"(đặt|thêm|nhập|tạo|cấp|set|add|provide) (secret|api key|khoá api|khóa api)",
    r"chốt (thiết kế|phương án|vị trí|scope)", r"(design|product|scope) decision",
    r"cần người (quyết|duyệt|chọn|làm|thử)", r"chủ (repo|sản phẩm|dự án) (quyết|chọn|duyệt|đặt)",
]), re.I)

# Gom việc (23/10, 29/10): mỗi thẻ một PR + một merge-gate + một lần gate --full, nên nhiều thẻ nhỏ làm gate chạy đè nhau
# (load 112 trên 12 lõi). Thẻ mới cùng loại mặc định NHẬP vào thẻ Backlog hoặc Ready chưa chạy; mở thẻ riêng phải có --new-card.
# Trần số dòng PR không còn: board không tách việc vì diff dài. Trần mục AC (max_card_ac) vẫn giữ (#369).
AC_ITEM_RE = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]+\S")
GENERIC_SCOPES = {"", "task", "misc", "general", "chore"}   # create_task "<tóm tắt>" sinh "[bug] task: …" cho mọi việc
KINDS = {"bug", "feature", "qa"}   # "cùng loại" = cùng một trong ba nhãn này; nhãn khác (priority:high…) không tính
# Thẻ runner không build (nhãn) hoặc chưa build được (Blocked by không phải đúng "- None.") không nhận thêm việc: việc
# mới vào đó nằm im. Cùng định nghĩa với FOR_A_PERSON_JQ và wave-plan (fail-safe) của super-board.
NOT_BUILDABLE = {NEEDS_YOU_LABEL, "human-gated", "wontfix", "loop:halted"}
BATCH_HEADING = "## Gộp thêm: "
# Đợt (#724): thẻ mới không gom được (khác chủ đề, thẻ đủ trần AC) vào ĐỢT của một thẻ chưa chạy cùng loại — thẻ vẫn riêng (AC riêng,
# đóng riêng), nhưng builder thẻ trưởng build cả đợt trên MỘT nhánh, một PR, một gate. Chỉ ghi trên chính thẻ mới: Blocked by thẻ
# trưởng (board không build nó riêng) + marker dưới đây (merge gate cho PR của thẻ trưởng Closes nó). Cùng regex với
# .claude/bin/super-board-ac-check.py BATCH_OF.
BATCH_OF_RE = re.compile(r"<!--\s*sb:batch-of\s+#(\d+)\s*-->")
# Marker trong code fence/span chỉ là ví dụ (thẻ bàn về cơ chế): không tính — cùng luật prose() của ac-check (INSTINCT-015).
FENCE_BLOCK = re.compile(r"^[ \t]*```.*?^[ \t]*```[^\n]*$", re.S | re.M)
CODE_SPAN = re.compile(r"`[^`\n]*`")
# Runner (super-board-run.sh top_card_in_column) giao thẻ Ready không đọc `## Blocked by`, chỉ giữ thẻ mang nhãn
# `waiting-on:#N` (#601); super-board-waiting-on.py sweep gỡ nhãn khi #N đóng. Thẻ thành viên mang nhãn này ngay lúc tạo.
WAITING_ON_COLOR = "FBCA04"   # cùng LABEL_COLOR của .claude/bin/super-board-waiting-on.py
# Đường dẫn file có "/" (tên trơn như server.py quá chung để coi là trùng).
PATH_RE = re.compile(r"[\w.\-]+(?:/[\w.\-]+)+\.\w{1,5}")
# PR mở nhắc thẻ (#735): từ khoá đóng của GitHub hoặc Refs trước `#N` / `owner/repo#N`. Số trùng của repo khác chỉ làm bỏ thêm
# một thẻ khỏi việc gom (thẻ riêng — hướng an toàn).
PR_MENTION_RE = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?):?\s+(?:[\w.-]+/[\w.-]+)?#(\d+)\b", re.I)

# Mỗi lệnh gh có hạn (#305): mạng treo không được làm createTask treo theo. Quá hạn = lỗi exit 124 (như lệnh thất bại).
def gh_timeout_s():
    """Đọc lúc gọi, không lúc import (#330): rỗng/rác/≤ 0 → 60 kèm cảnh báo, không traceback trước argparse."""
    raw = os.environ.get("CREATE_TASK_GH_TIMEOUT_S", "60")
    try:
        v = float(raw)
        if v > 0 and v == v:
            return v
    except ValueError:
        pass
    print(f"   ⚠️  CREATE_TASK_GH_TIMEOUT_S={raw!r} không hợp lệ: dùng 60s.", file=sys.stderr)
    return 60.0

def env_cap(name, default):
    """Trần số nguyên dương từ env `name`; rác/≤ 0 → `default` kèm cảnh báo (không traceback trước argparse)."""
    raw = os.environ.get(name, str(default))
    try:
        v = int(raw)
        if v > 0:
            return v
    except ValueError:
        pass
    print(f"   ⚠️  {name}={raw!r} không hợp lệ: dùng {default}.", file=sys.stderr)
    return default

def max_card_ac():
    """Trần dòng AC mỗi thẻ gom (#369; thẻ #323/#330 phình tới build 7873 s). SB_MAX_CARD_AC ghi đè; rác/≤ 0 → 12 kèm cảnh báo."""
    return env_cap("SB_MAX_CARD_AC", 12)

# Trần đợt (#724, bài học #369): số thẻ kể cả thẻ trưởng, và tổng mục AC cấp 1 của mọi thẻ (thước đo thời gian build).
# ponytail: AC thay cho thời gian build ước; đổi sang giây build đo được mỗi AC khi runs.jsonl có đủ số liệu.
def max_batch_cards():
    return env_cap("SB_MAX_BATCH_CARDS", 5)

def max_batch_ac():
    return env_cap("SB_MAX_BATCH_AC", 16)

def run_cmd(cmd, check=True):
    limit = gh_timeout_s()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=limit)
    except subprocess.TimeoutExpired:
        r = subprocess.CompletedProcess(cmd, 124, "", f"quá {limit:g}s không phản hồi")
    if check and r.returncode != 0:
        raise RuntimeError(f"Command failed ({' '.join(cmd)}):\n{r.stderr.strip()}")
    return r

def detect_repo():
    try:
        r = run_cmd(["git", "remote", "get-url", "origin"], check=False)
        if r.returncode == 0:
            url = r.stdout.strip()
            m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url)
            if m:
                repo_slug = m.group(1)
                # Chuẩn hóa tên slug
                for known_repo in PROJECT_REGISTRY:
                    if repo_slug.lower() == known_repo.lower():
                        return known_repo
                return repo_slug
    except Exception:
        pass
    return DEFAULT_REPO

def other_repos_named(text, repo):
    """Repo đã đăng ký, khác `repo`, mà `text` nhắc tên (đúng hoa thường, không dính chữ cái hay số)."""
    return [r for r, pat in REPO_NAME_PATTERNS.items()
            if r.lower() != repo.lower() and re.search(rf"(?<![A-Za-z0-9_])(?:{pat})(?![A-Za-z0-9_])", text)]

def ac_list(ac):
    """--ac (một chuỗi hoặc danh sách, mỗi phần có thể nhiều dòng) → các dòng của mục AC. Dòng chưa có dấu danh sách
    thành `- [ ] …` (26/10: #419, #421 tạo bằng một câu thường, pre-flight không đếm được AC và giữ thẻ ở Blocked);
    dòng đã là mục theo đúng AC_ITEM_RE mà pre-flight đếm, dòng thụt lề (phần tiếp của mục trên), dòng trong code fence
    và dòng comment HTML giữ nguyên."""
    out = []
    for part in ([ac] if isinstance(ac, str) else ac or []):
        fenced = commented = False   # mỗi --ac một khối riêng: fence/comment chưa đóng không lan sang --ac sau
        for line in part.strip().splitlines():
            if not line.strip():
                continue
            fence = not commented and line.lstrip().startswith("```")   # khối này nằm trong khối kia là chữ thường
            opens = not commented and not fenced and line.lstrip().startswith("<!--")
            keep = fenced or fence or commented or opens or line[0].isspace() or AC_ITEM_RE.match(line)
            out.append(line if keep else f"- [ ] {line.strip()}")
            fenced ^= fence
            if opens or commented:
                commented = "-->" not in line
    return out


def build_body(problem, context=None, fix=None, ac=None, risk=None, blocked_by=None):
    lines = []
    lines.append("## Problem")
    lines.append(problem.strip() if problem else "Chưa có mô tả chi tiết.")
    lines.append("")
    lines.append("## Context")
    if context:
        lines.append(context.strip())
    else:
        lines.append("- **Where:** Toàn bộ repository")
        lines.append("  - a. Phát hiện qua quá trình vận hành/kiểm toán")
        lines.append("- **Who:** Lập trình viên / Agent")
    lines.append("")
    lines.append("## Fix")
    lines.append(fix.strip() if fix else "Thực hiện sửa lỗi và bổ sung kiểm thử hồi quy.")
    lines.append("")
    lines.append("## Acceptance Criteria")
    ac = ac_list(ac)
    if ac:
        lines.extend(ac)
    else:
        lines.append("- [ ] Đã sửa đúng nguyên nhân gốc rễ và pass paired oracle RED→GREEN.")
        lines.append("- [ ] post-fix-gate --run-tests --full --brief đạt exit 0.")
    lines.append("")
    lines.append("## Risk")
    lines.append(risk.strip() if risk else "🟢 **Low** · Thay đổi cục bộ có test bảo vệ.")
    lines.append("")
    lines.append("## Blocked by")
    lines.append(blocked_by.strip() if blocked_by else "- None.")
    lines.append("")
    return "\n".join(lines)

def section(body, name):
    """Các dòng sau heading `## <name>` cuối cùng, tới heading `## ` kế tiếp."""
    lines = (body or "").splitlines()
    heads = [i for i, line in enumerate(lines) if re.match(rf"^##\s+{name}\s*$", line, re.I)]
    if not heads:
        return []
    tail = lines[heads[-1] + 1:]
    end = next((i for i, line in enumerate(tail) if line.startswith("## ")), len(tail))
    return tail[:end]

def ac_lines(body):
    return section(body, "Acceptance Criteria")

def auto_labels(title, labels=None):
    if labels:
        return list(labels)
    lower_title = title.lower()
    if "[bug]" in lower_title or "lỗi" in lower_title or "fix" in lower_title or "crash" in lower_title:
        return ["bug"]
    return ["qa"] if "[qa]" in lower_title else ["feature"]

def ready_started(repo):
    """Số issue có PR mở: head `issue-<n>-`, hoặc PR nhắc thẻ dù nhánh tên tuỳ ý (#735: body Closes/Fixes/Resolves/Refs #n,
    closingIssuesReferences — PR #730 chạy #721 #722 #723 trên nhánh fix-stop-hold-fixture-now). Lỗi đọc, JSON hỏng, hoặc đủ 100
    PR (danh sách có thể bị cắt) → RuntimeError.

    ponytail: trần 100 PR mở của `gh pr list --limit 100`; khi một repo có nhiều hơn, bỏ mọi thẻ Ready thay vì gom nhầm
    vào thẻ đã chạy. Nâng khi một board thật vượt 100 PR mở."""
    res = run_cmd(["gh", "pr", "list", "--repo", repo, "--state", "open",
                   "--json", "headRefName,body,closingIssuesReferences", "--limit", "100"], check=False)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip()[:200] or f"gh pr list thoát {res.returncode}")
    try:
        prs = json.loads(res.stdout or "[]")
    except ValueError as e:
        raise RuntimeError(f"gh pr list không phải JSON: {e}") from e
    if not isinstance(prs, list):
        raise RuntimeError("gh pr list không trả một mảng")
    if len(prs) >= 100:
        raise RuntimeError("đủ 100 PR mở: không biết thẻ Ready nào đã có PR")
    started = set()
    for p in prs:
        p = p or {}
        m = re.match(r"issue-(\d+)-", str(p.get("headRefName") or ""))
        if m:
            started.add(int(m.group(1)))
        started.update(int(n) for n in PR_MENTION_RE.findall(str(p.get("body") or "")))
        started.update(int(i["number"]) for i in p.get("closingIssuesReferences") or []
                       if isinstance(i, dict) and str(i.get("number")).isdigit())
    return started

def board_items(cfg):
    """Mọi item của board (gh project item-list). Lỗi đọc → RuntimeError; danh sách bị cắt → cảnh báo."""
    res = run_cmd(["gh", "project", "item-list", str(cfg["number"]), "--owner", PROJECT_OWNER,
                   "--format", "json", "--limit", "500"], check=False)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip()[:200] or f"gh project item-list thoát {res.returncode}")
    data = json.loads(res.stdout)
    if data.get("totalCount", 0) > len(data.get("items", [])):
        print(f"   ⚠️  Board có {data['totalCount']} item, chỉ đọc được {len(data['items'])}: danh sách thẻ chưa chạy bị cắt, "
              "thẻ mới nhất có thể bị bỏ sót.", file=sys.stderr)
    return data.get("items", [])

def item_repo(content):
    return str(content.get("repository") or "").rstrip("/").split("github.com/")[-1].lower()

def backlog_cards(cfg, repo, items=None):
    """Thẻ Issue của `repo` chưa chạy: Backlog, và Ready chưa có PR mở (ready_started). [{number, title, body, labels}].
    Thẻ Backlog có PR mở bị loại ở lần đọc lại thẻ đích (fresh_body), không ở đây.

    Lỗi đọc board → RuntimeError. Không đọc được PR mở → bỏ mọi thẻ Ready, vẫn trả Backlog.
    Board có thể chứa issue của repo khác (repo chưa đăng ký dùng Project #1): `gh issue edit N --repo <repo>` lên số
    issue của repo khác sẽ ghi đè nhầm issue cùng số, nên thẻ không khớp repository (hoặc thiếu) bị bỏ.
    `items`: kết quả board_items đã đọc (không đọc lại board)."""
    cards = []
    for it in board_items(cfg) if items is None else items:
        c = it.get("content") or {}
        card_repo = item_repo(c)
        status = it.get("status")
        if (status in ("Backlog", "Ready") and c.get("type") == "Issue" and c.get("number")
                and card_repo == repo.lower()):
            cards.append({"number": c["number"], "title": c.get("title", ""), "body": c.get("body") or "",
                          "labels": it.get("labels") or [], "status": status})
    if any(c["status"] == "Ready" for c in cards):
        try:
            started = ready_started(repo)
        except (RuntimeError, ValueError, OSError) as e:
            print(f"   ⚠️  Không đọc được PR mở ({e}): không gom vào thẻ Ready, chỉ gom vào Backlog.", file=sys.stderr)
            cards = [c for c in cards if c["status"] != "Ready"]
        else:
            cards = [c for c in cards if not (c["status"] == "Ready" and int(c["number"]) in started)]
    return cards

def fresh_body(repo, n):
    """Body hiện tại của issue #n nếu còn mở và chưa có PR nào sắp đóng nó, ngược lại None (không đọc được, đã đóng, đang chạy).

    #731: backlog_cards chỉ đọc PR mở khi có thẻ Ready, nên thẻ Backlog có PR mở `Closes #n` nhánh tên tuỳ ý (31/10: #723 ở
    PR #730) chỉ lộ ra ở đây — closedByPullRequestsReferences trong cùng lời gọi, không thêm lệnh mạng."""
    res = run_cmd(["gh", "issue", "view", str(n), "--repo", repo, "--json", "body,state,closedByPullRequestsReferences"],
                  check=False)
    try:
        d = json.loads(res.stdout) if res.returncode == 0 else {}
    except ValueError:
        d = {}
    return d.get("body") if d.get("state") == "OPEN" and not d.get("closedByPullRequestsReferences") else None

def scope_of(title):
    """Phần giữa `]` và `:` của tiêu đề (`🐛 [fix] gate: …` → "gate"); scope chung chung (task, misc…) như không có."""
    m = re.search(r"\]\s*([^:\]]+):", title or "")
    s = m.group(1).strip().lower() if m else ""
    return "" if s in GENERIC_SCOPES else s

def ac_count(body):
    """Số mục AC cấp 1 (cùng dạng super-board-ac-check.py / preflight: -, *, 1., 1)) — dòng trống, ↳ không tính."""
    return sum(1 for l in ac_lines(body) if AC_ITEM_RE.match(l))

def pick_card(cards, labels, text, title="", new_ac=0):
    """Thẻ chưa chạy nhận thêm việc: cùng loại (bug/feature/qa), runner build được, tổng mục AC sau gom không vượt
    max_card_ac(), VÀ cùng chủ đề — cùng scope cụ thể trong tiêu đề hoặc trùng ≥1 đường dẫn file (T0054: #344 cache gate
    từng bị gom vào #319 khác chủ đề rồi kẹt). Trùng đường dẫn nhiều nhất, hòa thì thẻ mới nhất. None khi không có thẻ hợp."""
    paths = set(PATH_RE.findall(text))
    scope, cap = scope_of(title), max_card_ac()
    fits = [c for c in cards
            if set(labels) & set(c["labels"]) and not NOT_BUILDABLE & set(c["labels"])
            and [l.strip() for l in section(c["body"], "Blocked by") if l.strip()] in ([], ["- None."])
            and ac_count(c["body"]) + new_ac <= cap
            and ((scope and scope_of(c.get("title", "")) == scope) or paths & set(PATH_RE.findall(c["body"])))]
    return max(fits, key=lambda c: (len(paths & set(PATH_RE.findall(c["body"]))), c["number"]), default=None)

def is_high(risk):
    """Rủi ro 🔴 High theo NHÃN, không theo chữ mô tả: emoji thắng; không emoji thì chữ đầu (High / Cao)."""
    risk = risk or ""
    return bool("🔴" in risk or ("🟡" not in risk and "🟢" not in risk and re.match(r"\W*(?:high|cao)\b", risk, re.I)))

def batch_of(body):
    """Số thẻ trưởng của đợt mà body thẻ mang marker, hoặc None."""
    m = BATCH_OF_RE.search(CODE_SPAN.sub("", FENCE_BLOCK.sub("", body or "")))
    return int(m.group(1)) if m else None

def batch_index(items, repo):
    """{thẻ trưởng: [content thành viên]} — item chưa Done của `repo` mang marker đợt (thẻ đã đóng mà chưa sang Done vẫn tính:
    trần bảo thủ). Dựng một lần cho cả lượt."""
    out = {}
    for it in items or []:
        c = it.get("content") or {}
        if it.get("status") != "Done" and c.get("type") == "Issue" and item_repo(c) == repo.lower() and c.get("number"):
            lead = batch_of(c.get("body"))
            if lead is not None:
                out.setdefault(lead, []).append(c)
    return out

def batch_members(items, lead, repo):
    return batch_index(items, repo).get(int(lead), [])

def batch_ac(card, index):
    """(số thành viên, tổng mục AC của thẻ + mọi thành viên đợt của nó); `index` = batch_index()."""
    members = index.get(int(card["number"]), [])
    return len(members), ac_count(card["body"]) + sum(ac_count(m.get("body")) for m in members)

def pick_batch_lead(cards, items, labels, repo, new_ac=0):
    """Thẻ trưởng của đợt nhận thẻ mới (#724), hoặc None. Ứng viên = thẻ chưa chạy (`cards` của backlog_cards) cùng loại,
    build được (Blocked by `- None.`, không nhãn NOT_BUILDABLE — thành viên đợt khác vì thế cũng bị loại), không mang marker,
    rủi ro không 🔴 High, đọc lại còn mở và chưa có PR; đợt còn chỗ: 1 + thành viên + 1 ≤ max_batch_cards() và tổng mục AC (trưởng
    + thành viên + mới) ≤ max_batch_ac(); Risk và AC của thẻ trưởng kiểm lại trên body đọc lại (#731). Thẻ số lớn nhất (đợt mới
    nhất) trước. Trả (thẻ trưởng với body đọc lại, thứ tự thẻ mới trong đợt, trần thẻ, tổng AC, trần AC)."""
    if not PROJECT_REGISTRY.get(repo, {}).get("batch"):
        return None
    cap_cards, cap_ac = max_batch_cards(), max_batch_ac()
    index = batch_index(items, repo)
    fits = [c for c in cards
            if set(labels) & set(c["labels"]) and not (NOT_BUILDABLE | {"ac-open"}) & set(c["labels"])
            and [l.strip() for l in section(c["body"], "Blocked by") if l.strip()] in ([], ["- None."])
            and batch_of(c["body"]) is None and not is_high("\n".join(section(c["body"], "Risk")).strip())]
    for c in sorted(fits, key=lambda c: c["number"], reverse=True):
        members, total = batch_ac(c, index)
        total += new_ac
        if 1 + members + 1 > cap_cards or total > cap_ac:
            continue
        current = fresh_body(repo, c["number"])   # board có thể trễ: thẻ trưởng đã đóng thì đợt của nó không nhận thêm
        if (current is None or batch_of(current) is not None
                or [l.strip() for l in section(current, "Blocked by") if l.strip()] not in ([], ["- None."])):
            continue
        # #731: phiên song song vừa gom vào thẻ trưởng (merge_body nâng Risk, thêm AC) mà board còn body cũ: Risk và AC theo body tươi.
        total += ac_count(current) - ac_count(c["body"])
        if is_high("\n".join(section(current, "Risk")).strip()) or total > cap_ac:
            continue
        return dict(c, body=current), members + 2, cap_cards, total, cap_ac
    return None

def with_batch(body, lead):
    """Body thẻ thành viên: `## Blocked by` thành đúng một blocker là thẻ trưởng (deps.sh/wave-plan không giao thẻ riêng)
    + marker đợt (merge gate nhận Closes của nó trên nhánh issue-<lead>-)."""
    lines = (body or "").rstrip().splitlines()
    heads = [i for i, l in enumerate(lines) if re.match(r"^##\s+Blocked by\s*$", l, re.I)]
    start = heads[-1] if heads else len(lines)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    block = ["## Blocked by",
             f"- #{lead} — đợt: build chung nhánh issue-{lead}-…, một PR, một gate (tách: card_batch.py split)",
             f"<!-- sb:batch-of #{lead} -->"]
    return "\n".join(lines[:start] + block + lines[end:]) + "\n"

def merge_body(old, title, new):
    """Body thẻ cũ + việc mới: dòng AC mới vào mục AC của thẻ (lane chỉ đọc mục đó), Problem/Fix thành mục Gộp thêm."""
    lines = old.rstrip().splitlines()
    # Dòng AC mang tên việc: lane đọc mỗi mục AC của thẻ, và AC mặc định ("đã sửa đúng nguyên nhân gốc") giống nhau ở mọi việc.
    tag = (re.search(r"\]\s*([^:]+):", title) or re.match(r"(.{0,40})", title)).group(1).strip()
    new_ac = [re.sub(r"^(\s*-\s*\[ \]\s*)", lambda m: f"{m.group(1)}[{tag}] ", l) for l in ac_lines(new) if l.strip()]
    heads = [i for i, l in enumerate(lines) if re.match(r"^##\s+Acceptance Criteria\s*$", l, re.I)]
    if heads:
        end = next((i for i in range(heads[-1] + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        while end > heads[-1] + 1 and not lines[end - 1].strip():
            end -= 1
        lines[end:end] = new_ac
    else:
        lines += ["", "## Acceptance Criteria"] + new_ac
    # The card's own `## Risk` is what preflight and readers see: raise it when the merged item is riskier.
    def rank(text):   # emoji first; without one, the first word of the label (High/Cao, Medium/Trung bình, Low/Thấp)
        by_emoji = max((i for i, e in enumerate("🟢🟡🔴") if e in text), default=-1)
        if by_emoji >= 0:
            return by_emoji
        m = re.match(r"\W*(high|cao|medium|trung\s+bình|low|thấp)\b", text, re.I)
        return -1 if not m else 2 if m.group(1).lower() in ("high", "cao") else 0 if m.group(1).lower() in ("low", "thấp") else 1
    new_risk = [l for l in section(new, "Risk") if l.strip()]
    risk_heads = [i for i, l in enumerate(lines) if re.match(r"^##\s+Risk\s*$", l, re.I)]
    if new_risk and risk_heads:
        r0 = risk_heads[0]
        r_end = next((i for i in range(r0 + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        old_rank = rank("\n".join(l for l in lines[r0 + 1:r_end] if l.strip()))
        if old_rank >= 0 and rank("\n".join(new_risk)) > old_rank:   # an unreadable card risk is never overwritten
            old = [l for l in lines[r0 + 1:r_end] if l.strip()]
            lines[r0 + 1:r_end] = new_risk + [f"Trước khi gom: {l.strip()}" for l in old] + [""]   # keep the card's own risk text
    detail = [f"{BATCH_HEADING}{title}"]
    for name in ("Problem", "Fix", "Risk"):   # Risk: a 🟡 item merged into a 🟢 card must not read as low risk
        detail += [f"### {name}"] + [l for l in section(new, name) if l.strip()]
    return "\n".join(lines + [""] + detail) + "\n"


def detect_needs_you(text):
    """(dòng đầu tiên chỉ người làm được, mọi dòng đều chỉ người làm được?) — (None, False) khi không dòng nào khớp.
    AC trộn (lane còn phần code) không được đánh dấu lúc tạo: bước kế tiếp là của lane, không phải của người."""
    lines = [re.sub(r"^\s*[-*]\s*(\[[ xX]\]\s*)?", "", line).strip() for line in (text or "").splitlines()]
    lines = [line for line in lines if line]
    hits = [line for line in lines if HUMAN_ONLY.search(line)]
    return (hits[0] if hits else None), bool(hits) and len(hits) == len(lines)


# Cùng luật với one_line() của super-board-needs-you.py: comment và mục Cần người không mang dòng máy đọc
# (super-board-approval.py, super-board-deps.sh đọc chúng). Kiểm TRƯỚC khi tạo issue để lỗi không để lại issue thừa.
NEEDS_YOU_FORBIDDEN = re.compile(r"reason tag:|blocked-by:|approval-request:|<!--", re.I)


def clean_needs_you(text, what):
    text = " ".join((text or "").split())
    if not text:
        raise ValueError(f"{what} rỗng")
    if NEEDS_YOU_FORBIDDEN.search(text):
        raise ValueError(f"{what} không được chứa `Reason tag:`, `blocked-by:`, `approval-request:` hay `<!--`")
    if len(text) > 500:
        raise ValueError(f"{what} dài quá 500 ký tự")
    return text


def needs_you_line(action, nxt):
    return f"🙋 Cần bạn: {action} · xong thì {nxt}"


def with_needs_you_section(body, action, nxt):
    """Mục `## Cần người` đứng đầu body; body đã có mục đó thì giữ nguyên."""
    if re.search(r"^##\s+Cần người\s*$", body or "", re.M):
        return body
    return f"## Cần người\n{needs_you_line(action, nxt)}\n\n{body}"


def find_needs_you_helper():
    """Helper của repo đang đứng (git root), hoặc None khi repo chưa có super-board-needs-you.py."""
    r = run_cmd(["git", "rev-parse", "--show-toplevel"], check=False)
    root = Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else Path(".")
    helper = root / NEEDS_YOU_HELPER
    return helper if helper.is_file() else None


def parse_ticket_from_file(file_path: Path, ticket_num: int):
    content = file_path.read_text(encoding="utf-8")
    pattern = rf"###\s+TICKET-0*{ticket_num}:\s*([^\n]+)\n(.*?)(?=(?:###\s+TICKET-|\Z))"
    m = re.search(pattern, content, re.DOTALL)
    if not m:
        raise ValueError(f"Không tìm thấy TICKET-{ticket_num} trong {file_path}")
    title = m.group(1).strip()
    body = m.group(2).strip()
    return title, body


def read_body_from_file(file_path: Path):
    """Đọc cả file làm body thẻ (--from-file không kèm --ticket, #695); file phải có mục `## Problem`."""
    content = file_path.read_text(encoding="utf-8").strip()
    if not re.search(r"^##[ \t]+Problem\b", content, re.M):
        raise ValueError(f"{file_path} không có mục `## Problem`: không tạo thẻ.")
    return content


def resolve_project_config(repo: str):
    if repo in PROJECT_REGISTRY:
        return PROJECT_REGISTRY[repo]
    
    # 1. Tìm trong .claude/super-board/configs/
    for p in Path(".").glob(".claude/super-board/configs/*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            p_num = data.get("project", {}).get("number")
            p_title = data.get("project", {}).get("title", repo)
            if p_num:
                # Query dynamic fields
                f_res = run_cmd(["gh", "project", "field-list", str(p_num), "--owner", PROJECT_OWNER, "--format", "json"], check=False)
                if f_res.returncode == 0:
                    f_data = json.loads(f_res.stdout)
                    s_field = next((f for f in f_data.get("fields", []) if f.get("name") == "Status"), None)
                    if s_field:
                        b_opt = next((o for o in s_field.get("options", []) if o.get("name") == "Backlog"), None)
                        return {
                            "number": p_num,
                            "name": p_title,
                            "project_id": "",
                            "status_field_id": s_field.get("id"),
                            "backlog_option_id": b_opt.get("id") if b_opt else "",
                        }
        except Exception:
            pass

    # Fallback mặc định về Agent Workbench (Project #1)
    return PROJECT_REGISTRY[DEFAULT_REPO]

def project_node_id(number):
    """ID node của board, cho repo tìm board qua .claude/super-board/configs (cấu hình đó không ghi ID này)."""
    res = run_cmd(["gh", "project", "view", str(number), "--owner", PROJECT_OWNER, "--format", "json"], check=False)
    try:
        return json.loads(res.stdout)["id"] if res.returncode == 0 else ""
    except (KeyError, ValueError, TypeError):
        return ""

def backlog_target(cfg):
    """(field_id, option_id) của cột Backlog đọc từ board lúc chạy; ID trong registry là phương án dự phòng.

    Cột đổi tên hoặc thêm cột (22/10: thêm Needs You) làm ID cứng trong registry lệch, và gh item-edit với ID lạ
    để lại cột trống mà không báo lỗi."""
    fallback = (cfg.get("status_field_id", ""), cfg.get("backlog_option_id", ""))
    res = run_cmd(["gh", "project", "field-list", str(cfg["number"]), "--owner", PROJECT_OWNER, "--format", "json"], check=False)
    why = f"gh project field-list thoát {res.returncode}"
    if res.returncode == 0:
        try:
            status = next(f for f in json.loads(res.stdout).get("fields", []) if f.get("name") == "Status")
            option = next(o for o in status.get("options", []) if o.get("name") == "Backlog")
            return status["id"], option["id"]
        except (StopIteration, KeyError, ValueError, TypeError, AttributeError):
            why = "board không có trường Status hoặc cột Backlog"
    print(f"   ⚠️  Dùng ID cột Backlog dự phòng trong registry ({why}).", file=sys.stderr)
    return fallback

def create_and_push(title, body, labels=None, repo=None, dry_run=False, needs_you=None, needs_you_next=NEEDS_YOU_NEXT,
                    extra_labels=()):
    repo = repo or detect_repo()
    labels = auto_labels(title, labels)
    if needs_you:
        body = with_needs_you_section(body, needs_you, needs_you_next)

    cfg = resolve_project_config(repo)
    project_number = cfg["number"]
    project_name = cfg["name"]
    project_id = cfg.get("project_id", "")
    project_url = f"https://github.com/users/{PROJECT_OWNER}/projects/{project_number}/views/2"

    print(f"\n🚀 {'[DRY-RUN] ' if dry_run else ''}Chuẩn bị tạo Task:")
    print(f"   📌 Tiêu đề : {title}")
    print(f"   🏷️  Labels  : {', '.join(list(labels) + list(extra_labels))}")
    print(f"   📦 Repo    : {repo}")
    print(f"   📋 Board   : #{project_number} {project_name} ➔ Cột Backlog ({project_url})")
    if needs_you:
        print(f"   🙋 Cần người: {needs_you}")

    if dry_run:
        print("\n--- BODY PREVIEW ---")
        print(body)
        print("--------------------")
        return {"url": "https://github.com/.../dry-run", "item_id": "dry-run"}

    helper = find_needs_you_helper() if needs_you else None
    create_labels = list(labels) + list(extra_labels)
    if needs_you and helper is None:
        # Repo chưa có helper: nhãn phải có trước, `gh issue create --label` với nhãn lạ thì thất bại.
        run_cmd(["gh", "label", "create", NEEDS_YOU_LABEL, "--repo", repo, "--color", NEEDS_YOU_COLOR,
                 "--description", NEEDS_YOU_DESC, "--force"])
        create_labels.append(NEEDS_YOU_LABEL)
        print(f"   ⚠️  Repo chưa có {NEEDS_YOU_HELPER}: chỉ gắn nhãn + mục ## Cần người, chưa có comment 🙋. "
              "Chép helper từ agent-workbench để có comment.")

    # 1. Tạo issue qua gh CLI
    cmd_issue = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    for lbl in create_labels:
        cmd_issue.extend(["--label", lbl])
    
    print("   ⏳ Đang tạo GitHub Issue...")
    res_issue = run_cmd(cmd_issue)
    issue_url = res_issue.stdout.strip()
    print(f"   ✅ Đã tạo Issue: {issue_url}")

    # 2. Thêm vào Project tương ứng
    if not project_id:
        project_id = project_node_id(project_number)
        if not project_id:
            print(f"   ⚠️  Chưa tra được ID node của Project #{project_number}: gán cột sẽ lỗi.", file=sys.stderr)
    print(f"   ⏳ Đang đẩy vào Project #{project_number} ({project_name})...")
    cmd_add = [
        "gh", "project", "item-add", str(project_number),
        "--owner", PROJECT_OWNER,
        "--url", issue_url,
        "--format", "json"
    ]
    res_add = run_cmd(cmd_add)
    item_data = json.loads(res_add.stdout)
    item_id = item_data.get("id")

    # 3. Chuyển sang cột Backlog
    column_ok = bool(item_id)
    if not item_id:
        print("   ❌ Issue đã tạo nhưng gh project item-add không trả id: thẻ chưa có cột.", file=sys.stderr)
    if item_id:
        print("   ⏳ Đang gán trạng thái 'Backlog'...")
        field_id, option_id = backlog_target(cfg)
        cmd_edit = [
            "gh", "project", "item-edit",
            "--id", item_id,
            "--project-id", project_id,
            "--field-id", field_id,
            "--single-select-option-id", option_id
        ]
        res_edit = run_cmd(cmd_edit, check=False)
        if res_edit.returncode == 0:
            print(f"   🎉 THÀNH CÔNG! Task đã nằm trên Backlog Board: {project_url}")
        else:
            column_ok = False
            print(f"   ❌ Issue đã tạo nhưng chưa gán được cột Backlog (exit {res_edit.returncode}): "
                  f"{res_edit.stderr.strip()[:300]}", file=sys.stderr)

    marked = True
    if needs_you and helper is not None:
        # 4. Nhãn needs-you + comment "🙋 Cần bạn" (idempotent) qua helper của repo.
        number = issue_url.rstrip("/").rsplit("/", 1)[-1]
        res_mark = run_cmd(["python3", str(helper), "mark", "--repo", repo, "--issue", number,
                            "--action", needs_you, "--next", needs_you_next], check=False)
        print("   " + (res_mark.stdout.strip() or res_mark.stderr.strip()))
        if res_mark.returncode != 0:
            marked = False
            print(f"   ❌ Chưa đánh dấu được thẻ cần người (exit {res_mark.returncode}): {res_mark.stderr.strip()}",
                  file=sys.stderr)

    return {"url": issue_url, "item_id": item_id, "project_url": project_url, "needs_you_marked": marked,
            "column_ok": column_ok}

def main():
    parser = argparse.ArgumentParser(description="Tạo Task chuẩn Super-Board và đẩy lên Backlog GitHub Project Board")
    parser.add_argument("summary", nargs="?", help="Mô tả tóm tắt hoặc tiêu đề task")
    parser.add_argument("--repo", help="Chỉ định repo cụ thể (mặc định tự phát hiện theo git origin)")
    parser.add_argument("--here", action="store_true",
                        help="Giữ thẻ ở repo đang đứng dù chữ của thẻ nhắc tên repo khác (thẻ về kit, lấy repo khác làm ví dụ)")
    parser.add_argument("--title", help="Tiêu đề chuẩn Super-Board: <emoji> [<kind>] <scope>: <what>")
    parser.add_argument("--problem", help="Nội dung ## Problem")
    parser.add_argument("--fix", help="Nội dung ## Fix")
    parser.add_argument("--ac", action="append",
                        help="Một điều kiện của ## Acceptance Criteria (lặp lại cho nhiều điều kiện; câu thường tự thành `- [ ] …`)")
    parser.add_argument("--risk", help="Nội dung ## Risk (🟢 Low / 🟡 Medium / 🔴 High)")
    parser.add_argument("--blocked-by", help="Nội dung ## Blocked by")
    parser.add_argument("--labels", nargs="*", help="Labels (bug, feature, qa)")
    parser.add_argument("--from-file", type=Path, help="Đọc ticket từ file markdown")
    parser.add_argument("--ticket", type=int, help="Số thứ tự ticket trong file (ví dụ: 1, 2, 3...)")
    parser.add_argument("--dry-run", action="store_true", help="Chạy thử không tạo thật trên GitHub")
    parser.add_argument("--needs-you", help="Thẻ cần người: ĐÚNG việc người phải làm (máy thật, playtest, store, secret, quyết định)")
    parser.add_argument("--needs-you-next", help="Người làm xong thì làm gì tiếp (mặc định: --needs-you thì "
                        f"'{NEEDS_YOU_NEXT}', tự đánh dấu thì '{NEEDS_YOU_DONE_NEXT}')")
    parser.add_argument("--no-needs-you", action="store_true", help="Không tự đánh dấu cần người dù AC khớp cụm từ")
    parser.add_argument("--new-card", metavar="LÝ DO",
                        help="Mở thẻ riêng thay vì nhập vào thẻ Backlog đang có (bắt buộc nêu lý do: việc độc lập, cần PR riêng…)")
    args = parser.parse_args()
    if args.new_card is not None and not args.new_card.strip():
        print("❌ --new-card cần lý do (vì sao việc này không nhập vào thẻ Backlog đang có).", file=sys.stderr)
        sys.exit(64)

    title = None
    body = None

    if args.from_file and args.ticket is not None and args.ticket < 1:
        print("❌ --ticket phải là số từ 1 (TICKET-1, TICKET-2…).", file=sys.stderr)
        sys.exit(64)
    from_ticket = bool(args.from_file) and args.ticket is not None
    if from_ticket:
        title, body = parse_ticket_from_file(args.from_file, args.ticket)
    elif args.from_file:
        if not args.title or not args.title.strip():
            print("❌ --from-file không kèm --ticket cần --title (title của thẻ; cả file là body).", file=sys.stderr)
            sys.exit(64)
        try:
            body = read_body_from_file(args.from_file)
        except (OSError, UnicodeDecodeError, ValueError) as e:
            print(f"❌ --from-file: {e}", file=sys.stderr)
            sys.exit(2)
        title = args.title
        if any([args.problem, args.fix, args.ac, args.risk, args.blocked_by]):
            print("   ⚠️  --from-file đặt cả body: --problem/--fix/--ac/--risk/--blocked-by bị bỏ qua.", file=sys.stderr)
    elif args.title:
        title = args.title
        body = build_body(args.problem, fix=args.fix, ac=args.ac, risk=args.risk, blocked_by=args.blocked_by)
    elif args.summary:
        raw = args.summary.strip()
        if not re.match(r"^[^\w\s].*\[(bug|feature|qa)\]", raw):
            prefix = "🐛 [bug]" if any(w in raw.lower() for w in ["lỗi", "bug", "crash", "fix", "sai"]) else "✨ [feature]"
            title = f"{prefix} task: {raw}"
        else:
            title = raw
        body = build_body(f"Cần thực hiện: {raw}", fix=f"Giải quyết triệt để yêu cầu: {raw}")
    else:
        print("💡 Cách dùng /createTask:")
        print('   1. Tạo nhanh từ câu tóm tắt:')
        print('      python3 create_task.py "fix lỗi review_gate tự xả"')
        print('   2. Tạo chi tiết theo chuẩn Super-Board:')
        print('      python3 create_task.py --title "🐛 [bug] hooks: sửa review_gate" --problem "..." --fix "..."')
        print('   3. Đẩy từ file có sẵn:')
        print('      python3 create_task.py --from-file docs/super-board/backlog-tickets.md --ticket 1')
        sys.exit(0)

    # --from-file: ticket nằm trong backlog của chính checkout này, tên repo khác chỉ là ngữ cảnh đo.
    if not args.repo and not args.here and not from_ticket:
        here = detect_repo()
        others = other_repos_named(f"{title}\n{body}", here)
        if others:
            hint = " hoặc ".join(f"--repo {r}" for r in others)
            print(f"❌ Thẻ nhắc tên repo khác ({', '.join(others)}) mà chưa chỉ repo đích: thẻ sẽ nằm ở board của "
                  f"{here}. Thêm {hint}; thẻ chạm hai repo thì tạo một thẻ mỗi repo. "
                  "Thẻ thật sự về repo này (chỉ lấy repo kia làm ví dụ) thì thêm --here.", file=sys.stderr)
            sys.exit(64)

    # Cờ --needs-you là đường chính (nó nói đúng việc người phải làm); không có cờ thì chỉ tự đánh dấu khi MỌI
    # dòng AC là việc của người; AC trộn và câu tóm tắt khi tạo nhanh chỉ in gợi ý.
    needs_you = None if args.no_needs_you else args.needs_you
    try:
        if needs_you is not None:
            needs_you = clean_needs_you(needs_you, "--needs-you")
        needs_you_next = clean_needs_you(NEEDS_YOU_NEXT if args.needs_you_next is None else args.needs_you_next, "--needs-you-next")
    except ValueError as e:
        print(f"❌ {e}", file=sys.stderr)
        sys.exit(64)
    if needs_you is None and not args.no_needs_you:
        summary_mode = bool(args.summary and not args.title and not args.from_file)
        hit, only_people = detect_needs_you(args.summary if summary_mode else "\n".join(ac_lines(body)))
        if summary_mode:
            only_people = False  # một câu tóm tắt không tách được phần code của lane với bước của người
        if hit and not only_people:
            print(f"   💡 \"{hit}\" cần người sau khi lane làm phần code: không đánh dấu lúc tạo; "
                  "QA/Review đánh dấu (super-board-needs-you.py mark) khi thẻ dừng ở bước đó. "
                  "Cả thẻ là việc của người thì truyền --needs-you \"<việc cụ thể>\".")
        elif hit:
            try:
                needs_you = clean_needs_you(f"Làm bước chỉ người làm được trong AC: {hit[:300]}", "dòng AC")
                if args.needs_you_next is None:
                    needs_you_next = NEEDS_YOU_DONE_NEXT
                print(f"   🔎 AC cần người: \"{hit}\" — truyền --needs-you \"<việc cụ thể>\" để ghi rõ hơn, "
                      "hoặc --no-needs-you nếu lane tự làm được.")
            except ValueError as e:
                print(f"   ⚠️  AC có vẻ cần người nhưng {e}: chưa đánh dấu; truyền --needs-you \"<việc cụ thể>\".")

    # Gom: thẻ thường (không cần người, không từ file có chủ đích, không --new-card) nhập vào thẻ Backlog hoặc Ready chưa chạy.
    # Không gom việc có --blocked-by hoặc rủi ro 🔴: blocker và rủi ro cao của một việc không tách được khỏi thẻ chứa nó.
    # 24/10: trước đây chỉ 🟢 mới gom, mà gần như mọi thẻ ghi 🟡 nên không bao giờ gom (người dùng: "gom … không hoạt động").
    # Only the risk LABEL counts, not the description after it: an emoji wins; without one, the first word (High / Cao).
    low_risk = not is_high(args.risk)
    # Nhãn ngoài bug/feature/qa (needs-device…) có tác dụng với runner; đường gom không áp nhãn lên thẻ cũ → thẻ riêng.
    plain_labels = set(auto_labels(title, args.labels)) <= KINDS
    batch_labels = []
    if (needs_you is None and args.new_card is None and not args.from_file
            and not args.blocked_by and low_risk and plain_labels):
        repo = args.repo or detect_repo()
        items = cards = None
        try:
            cfg = resolve_project_config(repo)
            items = board_items(cfg)
            cards = backlog_cards(cfg, repo, items)
            fold_into = cards
            if PROJECT_REGISTRY.get(repo, {}).get("batch"):
                # Gom vào thẻ trưởng của một đợt cũng làm đợt nặng thêm: không gom khi tổng AC của đợt vượt trần (#724).
                index = batch_index(items, repo)
                cap, sizes = max_batch_ac(), {c["number"]: batch_ac(c, index) for c in cards}
                fold_into = [c for c in cards if sizes[c["number"]][0] == 0 or sizes[c["number"]][1] + ac_count(body) <= cap]
            card = pick_card(fold_into, auto_labels(title, args.labels),
                             f"{title}\n{body}", title=title, new_ac=ac_count(body))
        except (RuntimeError, ValueError, OSError) as e:
            card = None
            print(f"   ⚠️  Không gom được vào thẻ chưa chạy (không đọc được board: {e}): tạo thẻ mới.", file=sys.stderr)
        # Không gom được (khác chủ đề, thẻ đủ trần AC) mà đọc được board: vào đợt của một thẻ chưa chạy (#724). Gom thử mà
        # ghi lỗi thì không vào đợt (thẻ riêng như cũ).
        lead = None
        if card is None and cards is not None:
            try:
                lead = pick_batch_lead(cards, items, auto_labels(title, args.labels), repo, new_ac=ac_count(body))
            except (RuntimeError, ValueError, OSError) as e:
                print(f"   ⚠️  Không xét được đợt ({e}): tạo thẻ riêng.", file=sys.stderr)
        if lead and not args.dry_run:
            wait = f"waiting-on:#{lead[0]['number']}"
            res = run_cmd(["gh", "label", "create", wait, "--repo", repo, "--color", WAITING_ON_COLOR, "--force"], check=False)
            if res.returncode != 0:
                lead = None   # không có nhãn thì runner giao thẻ Ready riêng: thà thẻ riêng còn hơn hai builder một việc
                print(f"   ⚠️  Không tạo được nhãn {wait} ({res.stderr.strip()[:200]}): tạo thẻ riêng, không vào đợt.", file=sys.stderr)
        if lead:
            head, nth, cap_cards, total, cap_ac = lead
            body = with_batch(body, head["number"])
            batch_labels = [f"waiting-on:#{head['number']}"]
            print(f"\n🚃 {'[DRY-RUN] Sẽ vào' if args.dry_run else 'Vào'} đợt #{head['number']} ({head['title']}): thẻ thứ "
                  f"{nth}/{cap_cards}, {total}/{cap_ac} AC. Build chung nhánh issue-{head['number']}-…, "
                  "một PR, một gate (card_batch.py plan). Việc độc lập cần PR riêng thì thêm --new-card \"<lý do>\".")
        if card:
            n = card["number"]
            if args.dry_run:
                print(f"\n🧺 [DRY-RUN] Sẽ gom \"{title}\" vào thẻ chưa chạy #{n} ({card['title']}).")
                sys.exit(0)
            # ponytail: GitHub không có ghi-có-điều-kiện; đọc lại ngay trước khi ghi thu hẹp khoảng hở còn một lời gọi,
            # và đọc lại sau khi ghi bắt lần ghi của mình bị phiên khác đè (việc không mất: tạo thẻ mới). Nâng cấp khi
            # va chạm xảy ra thật (khoá file theo số thẻ).
            current = fresh_body(repo, n)
            if current is None:
                print(f"   ⚠️  Không gom được vào #{n} (đã đóng, có PR mở sắp đóng nó, hoặc không đọc lại được): tạo thẻ mới.",
                      file=sys.stderr)
            else:
                res = run_cmd(["gh", "issue", "edit", str(n), "--repo", repo, "--body", merge_body(current, title, body)],
                              check=False)
                mark = f"{BATCH_HEADING}{title}"
                # Ghi thành công = edit exit 0 VÀ số mục cùng tên tăng (thẻ đã có mục trùng tên thì "có mặt" chưa chứng minh gì, #330).
                if res.returncode == 0 and (fresh_body(repo, n) or "").count(mark) > current.count(mark):
                    print(f"\n🧺 Đã gom \"{title}\" vào thẻ chưa chạy #{n} ({card['title']}): một PR, một gate. "
                          "Việc độc lập cần PR riêng thì thêm --new-card \"<lý do>\".")
                    sys.exit(0)
                print(f"   ⚠️  Không gom được vào #{n} (gh issue edit thoát {res.returncode}: {res.stderr.strip()[:200]}, "
                      "hoặc lần ghi bị phiên khác đè): tạo thẻ mới.", file=sys.stderr)

    result = create_and_push(title, body, labels=args.labels, repo=args.repo, dry_run=args.dry_run,
                             needs_you=needs_you, needs_you_next=needs_you_next, extra_labels=batch_labels)
    if not result.get("needs_you_marked", True) or not result.get("column_ok", True):
        sys.exit(3)

if __name__ == "__main__":
    main()
