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
        "backlog_option_id": "a537f4c7",
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
    }
}

DEFAULT_REPO = "ToanMobile/agent-workbench"

def run_cmd(cmd, check=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"Command failed ({' '.join(cmd)}):\n{r.stderr.strip()}")
    return r

def detect_repo():
    try:
        r = run_cmd(["git", "remote", "get-url", "origin"], check=False)
        if r.returncode == 0:
            url = r.stdout.strip()
            m = re.search(r"github\.com[:/]([^/]+/[^/.]+)(?:\.git)?$", url)
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

def create_and_push(title, body, labels=None, repo=None, dry_run=False):
    repo = repo or detect_repo()
    labels = labels or []
    
    cfg = resolve_project_config(repo)
    project_number = cfg["number"]
    project_name = cfg["name"]
    project_id = cfg.get("project_id", "")
    status_field_id = cfg.get("status_field_id", "")
    backlog_option_id = cfg.get("backlog_option_id", "")
    project_url = f"https://github.com/users/{PROJECT_OWNER}/projects/{project_number}/views/2"

    # Auto label detection
    lower_title = title.lower()
    if not labels:
        if "[bug]" in lower_title or "lỗi" in lower_title or "fix" in lower_title or "crash" in lower_title:
            labels.append("bug")
        elif "[qa]" in lower_title:
            labels.append("qa")
        else:
            labels.append("feature")

    print(f"\n🚀 {'[DRY-RUN] ' if dry_run else ''}Chuẩn bị tạo Task:")
    print(f"   📌 Tiêu đề : {title}")
    print(f"   🏷️  Labels  : {', '.join(labels)}")
    print(f"   📦 Repo    : {repo}")
    print(f"   📋 Board   : #{project_number} {project_name} ➔ Cột Backlog ({project_url})")

    if dry_run:
        print("\n--- BODY PREVIEW ---")
        print(body)
        print("--------------------")
        return {"url": "https://github.com/.../dry-run", "item_id": "dry-run"}

    # 1. Tạo issue qua gh CLI
    cmd_issue = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    for lbl in labels:
        cmd_issue.extend(["--label", lbl])
    
    print("   ⏳ Đang tạo GitHub Issue...")
    res_issue = run_cmd(cmd_issue)
    issue_url = res_issue.stdout.strip()
    print(f"   ✅ Đã tạo Issue: {issue_url}")

    # 2. Thêm vào Project tương ứng
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
    if item_id:
        print("   ⏳ Đang gán trạng thái 'Backlog'...")
        cmd_edit = [
            "gh", "project", "item-edit",
            "--id", item_id,
            "--project-id", project_id,
            "--field-id", status_field_id,
            "--single-select-option-id", backlog_option_id
        ]
        run_cmd(cmd_edit, check=False)
        print(f"   🎉 THÀNH CÔNG! Task đã nằm trên Backlog Board: {project_url}")

    return {"url": issue_url, "item_id": item_id, "project_url": project_url}

def main():
    parser = argparse.ArgumentParser(description="Tạo Task chuẩn Super-Board và đẩy lên Backlog GitHub Project Board")
    parser.add_argument("summary", nargs="?", help="Mô tả tóm tắt hoặc tiêu đề task")
    parser.add_argument("--repo", help="Chỉ định repo cụ thể (mặc định tự phát hiện theo git origin)")
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
    args = parser.parse_args()

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

    create_and_push(title, body, labels=args.labels, repo=args.repo, dry_run=args.dry_run)

if __name__ == "__main__":
    main()
