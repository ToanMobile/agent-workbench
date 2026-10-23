#!/usr/bin/env python3
"""
create_task.py — Tự động tạo issue và đẩy lên cột Backlog của GitHub Project Board
Hỗ trợ cả 5 repositories:
  1. ToanMobile/agent-workbench             ➔ Project #1: Agent Workbench
  2. ToanMobile/OfficeReader                ➔ Project #2: OfficeReader
  3. ToanMobile/Goods-Triple-Shelf-Match-3D ➔ Project #3: Goods Triple Shelf Match 3D
  4. ToanMobile/GeelyEx2                    ➔ Project #4: GeelyEx2
  5. ToanMobile/Neighbours-From-Hell        ➔ Project #5: Neighbours From Hell

Sử dụng:
  1. Tạo nhanh từ câu tóm tắt (auto-format):
     python3 create_task.py "fix lỗi review_gate tự xả 43 lần"
  2. Tạo chi tiết chuẩn Super-Board:
     python3 create_task.py --title "🐛 [bug] hooks: sửa lỗi X" --problem "..." --fix "..."
  3. Đẩy từ file mẫu (như docs/super-board/backlog-tickets.md):
     python3 create_task.py --from-file docs/super-board/backlog-tickets.md --ticket 1
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
    "ToanMobile/Neighbours-From-Hell": {
        "number": 5,
        "name": "Neighbours From Hell",
        "project_id": "PVT_kwHOAGnqzM4BnTFL",
        "status_field_id": "PVTSSF_lAHOAGnqzM4BnTFLzhl4WVM",
        "backlog_option_id": "8b4a5523",
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
    "ToanMobile/Neighbours-From-Hell": r"Neighbours(?:-| )From(?:-| )Hell|NFH",
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

# Gom việc (23/10): mỗi thẻ một PR + một merge-gate + một lần gate --full, nên nhiều thẻ nhỏ làm gate chạy đè nhau
# (load 112 trên 12 lõi). Thẻ mới cùng loại mặc định NHẬP vào thẻ Backlog đang có; mở thẻ riêng phải có --new-card.
# ponytail: trần 6 việc/thẻ vì PR > 400 dòng đổi phải người duyệt (merge gate); nâng khi đo thấy PR gộp vẫn nhỏ.
MAX_BATCH = 6
KINDS = {"bug", "feature", "qa"}   # "cùng loại" = cùng một trong ba nhãn này; nhãn khác (priority:high…) không tính
# Thẻ runner không build (nhãn) hoặc chưa build được (Blocked by không phải đúng "- None.") không nhận thêm việc: việc
# mới vào đó nằm im. Cùng định nghĩa với FOR_A_PERSON_JQ và wave-plan (fail-safe) của super-board.
NOT_BUILDABLE = {NEEDS_YOU_LABEL, "human-gated", "wontfix", "loop:halted"}
BATCH_HEADING = "## Gộp thêm: "
# Đường dẫn file có "/" (tên trơn như server.py quá chung để coi là trùng).
PATH_RE = re.compile(r"[\w.\-]+(?:/[\w.\-]+)+\.\w{1,5}")

# Mỗi lệnh gh có hạn (#305): mạng treo không được làm createTask treo theo. Quá hạn = lỗi exit 124 (như lệnh thất bại).
GH_TIMEOUT_S = float(os.environ.get("CREATE_TASK_GH_TIMEOUT_S", "60"))

def run_cmd(cmd, check=True):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        r = subprocess.CompletedProcess(cmd, 124, "", f"quá {GH_TIMEOUT_S:g}s không phản hồi")
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
    if ac:
        lines.append(ac.strip())
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

def backlog_cards(cfg, repo):
    """Thẻ Issue của `repo` đang ở cột Backlog của board: [{number, title, body, labels}]. Lỗi đọc board → RuntimeError.

    Board có thể chứa issue của repo khác (repo chưa đăng ký dùng Project #1): `gh issue edit N --repo <repo>` lên số
    issue của repo khác sẽ ghi đè nhầm issue cùng số, nên thẻ không khớp repository (hoặc thiếu) bị bỏ."""
    res = run_cmd(["gh", "project", "item-list", str(cfg["number"]), "--owner", PROJECT_OWNER,
                   "--format", "json", "--limit", "500"], check=False)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip()[:200] or f"gh project item-list thoát {res.returncode}")
    data = json.loads(res.stdout)
    if data.get("totalCount", 0) > len(data.get("items", [])):
        print(f"   ⚠️  Board có {data['totalCount']} item, chỉ đọc được {len(data['items'])}: danh sách thẻ Backlog bị cắt, "
              "thẻ mới nhất có thể bị bỏ sót.", file=sys.stderr)
    cards = []
    for it in data.get("items", []):
        c = it.get("content") or {}
        card_repo = str(c.get("repository") or "").rstrip("/").split("github.com/")[-1].lower()
        if (it.get("status") == "Backlog" and c.get("type") == "Issue" and c.get("number")
                and card_repo == repo.lower()):
            cards.append({"number": c["number"], "title": c.get("title", ""), "body": c.get("body") or "",
                          "labels": it.get("labels") or []})
    return cards

def fresh_body(repo, n):
    """Body hiện tại của issue #n nếu còn mở, ngược lại None (không đọc được, đã đóng)."""
    res = run_cmd(["gh", "issue", "view", str(n), "--repo", repo, "--json", "body,state"], check=False)
    try:
        d = json.loads(res.stdout) if res.returncode == 0 else {}
    except ValueError:
        d = {}
    return d.get("body") if d.get("state") == "OPEN" else None

def pick_card(cards, labels, text):
    """Thẻ Backlog nhận thêm việc: cùng loại (bug/feature/qa), runner build được, chưa đủ MAX_BATCH; trùng đường dẫn
    file nhiều nhất, hòa thì thẻ mới nhất. None khi không có thẻ nào hợp."""
    paths = set(PATH_RE.findall(text))
    fits = [c for c in cards
            if set(labels) & set(c["labels"]) and not NOT_BUILDABLE & set(c["labels"])
            and [l.strip() for l in section(c["body"], "Blocked by") if l.strip()] in ([], ["- None."])
            and c["body"].count(BATCH_HEADING) + 1 < MAX_BATCH]   # +1: việc gốc của thẻ cũng tính
    return max(fits, key=lambda c: (len(paths & set(PATH_RE.findall(c["body"]))), c["number"]), default=None)

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
    detail = [f"{BATCH_HEADING}{title}"]
    for name in ("Problem", "Fix"):
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

def create_and_push(title, body, labels=None, repo=None, dry_run=False, needs_you=None, needs_you_next=NEEDS_YOU_NEXT):
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
    print(f"   🏷️  Labels  : {', '.join(labels)}")
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
    create_labels = list(labels)
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
    parser.add_argument("--ac", help="Nội dung ## Acceptance Criteria")
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

    if args.from_file and args.ticket:
        title, body = parse_ticket_from_file(args.from_file, args.ticket)
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
    if not args.repo and not args.here and not (args.from_file and args.ticket):
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

    # Gom: thẻ thường (không cần người, không từ file có chủ đích, không --new-card) nhập vào thẻ Backlog hợp nhất.
    # Không gom việc có --blocked-by hoặc rủi ro khác 🟢: blocker và mức rủi ro của một việc không tách được khỏi thẻ chứa nó.
    low_risk = not args.risk or "🟢" in args.risk
    # Nhãn ngoài bug/feature/qa (needs-device…) có tác dụng với runner; đường gom không áp nhãn lên thẻ cũ → thẻ riêng.
    plain_labels = set(auto_labels(title, args.labels)) <= KINDS
    if (needs_you is None and args.new_card is None and not (args.from_file and args.ticket)
            and not args.blocked_by and low_risk and plain_labels):
        repo = args.repo or detect_repo()
        try:
            card = pick_card(backlog_cards(resolve_project_config(repo), repo), auto_labels(title, args.labels),
                             f"{title}\n{body}")
        except (RuntimeError, ValueError, OSError) as e:
            card = None
            print(f"   ⚠️  Không gom được vào thẻ Backlog (không đọc được board: {e}): tạo thẻ mới.", file=sys.stderr)
        if card:
            n = card["number"]
            if args.dry_run:
                print(f"\n🧺 [DRY-RUN] Sẽ gom \"{title}\" vào thẻ Backlog #{n} ({card['title']}).")
                sys.exit(0)
            # ponytail: GitHub không có ghi-có-điều-kiện; đọc lại ngay trước khi ghi thu hẹp khoảng hở còn một lời gọi,
            # và đọc lại sau khi ghi bắt lần ghi của mình bị phiên khác đè (việc không mất: tạo thẻ mới). Nâng cấp khi
            # va chạm xảy ra thật (khoá file theo số thẻ).
            current = fresh_body(repo, n)
            if current is None:
                print(f"   ⚠️  Không gom được vào #{n} (đã đóng hoặc không đọc lại được): tạo thẻ mới.", file=sys.stderr)
            else:
                res = run_cmd(["gh", "issue", "edit", str(n), "--repo", repo, "--body", merge_body(current, title, body)],
                              check=False)
                if f"{BATCH_HEADING}{title}" in (fresh_body(repo, n) or ""):
                    print(f"\n🧺 Đã gom \"{title}\" vào thẻ Backlog #{n} ({card['title']}): một PR, một gate. "
                          "Việc độc lập cần PR riêng thì thêm --new-card \"<lý do>\".")
                    sys.exit(0)
                print(f"   ⚠️  Không gom được vào #{n} (gh issue edit thoát {res.returncode}: {res.stderr.strip()[:200]}, "
                      "hoặc lần ghi bị phiên khác đè): tạo thẻ mới.", file=sys.stderr)

    result = create_and_push(title, body, labels=args.labels, repo=args.repo, dry_run=args.dry_run,
                             needs_you=needs_you, needs_you_next=needs_you_next)
    if not result.get("needs_you_marked", True) or not result.get("column_ok", True):
        sys.exit(3)

if __name__ == "__main__":
    main()
