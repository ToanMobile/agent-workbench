#!/usr/bin/env python3
"""
push-to-github-board.py
Tự động đọc `docs/super-board/backlog-tickets.md`, trích xuất các Ticket
và đẩy lên GitHub Issues của `ToanMobile/agent-workbench` đồng thời thêm vào Project #1 (Backlog).

Sử dụng:
    python3 docs/super-board/push-to-github-board.py --dry-run      # Xem trước danh sách sẽ tạo
    python3 docs/super-board/push-to-github-board.py --apply        # Tạo thật trên GitHub Board
    python3 docs/super-board/push-to-github-board.py --ticket 1..5  # Chỉ đẩy 5 ticket đầu
"""

import sys
import re
import json
import subprocess
import argparse
from pathlib import Path

PROJECT_NUMBER = 1
PROJECT_OWNER = "ToanMobile"
REPO = "ToanMobile/agent-workbench"
TICKETS_FILE = Path(__file__).resolve().parent / "backlog-tickets.md"

def parse_tickets(md_path: Path):
    content = md_path.read_text(encoding="utf-8")
    # Split by ### TICKET-
    parts = re.split(r"(?=###\s+TICKET-\d+:)", content)
    tickets = []
    for part in parts:
        part = part.strip()
        if not part.startswith("### TICKET-"):
            continue
        header_line = part.split("\n", 1)[0]
        # header format: ### TICKET-01: 🐛 [bug] hooks: sửa quy chụp nhầm quyền tác giả...
        m = re.match(r"###\s+TICKET-(\d+):\s*(.*)", header_line)
        if not m:
            continue
        num = int(m.group(1))
        title = m.group(2).strip()
        body = part[len(header_line):].strip()
        
        # Determine labels
        labels = []
        if "[bug]" in title:
            labels.append("bug")
        elif "[feature]" in title:
            labels.append("feature")
        elif "[docs]" in title or "[chore]" in title:
            labels.append("feature")
        
        tickets.append({
            "num": num,
            "title": title,
            "body": body,
            "labels": labels
        })
    return tickets

def create_issue_and_add_to_board(ticket, dry_run=True):
    print(f"[{'DRY-RUN' if dry_run else 'APPLY'}] #{ticket['num']:02d}: {ticket['title']}")
    if dry_run:
        return None
    
    # 1. gh issue create
    cmd = [
        "gh", "issue", "create",
        "--repo", REPO,
        "--title", ticket["title"],
        "--body", ticket["body"],
    ]
    for lbl in ticket["labels"]:
        cmd.extend(["--label", lbl])
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  ❌ Lỗi tạo issue: {res.stderr.strip()}", file=sys.stderr)
        return None
    
    issue_url = res.stdout.strip()
    print(f"  ✅ Đã tạo issue: {issue_url}")
    
    # 2. Add to project
    cmd_proj = [
        "gh", "project", "item-add", str(PROJECT_NUMBER),
        "--owner", PROJECT_OWNER,
        "--url", issue_url,
        "--format", "json"
    ]
    res_proj = subprocess.run(cmd_proj, capture_output=True, text=True)
    if res_proj.returncode == 0:
        print(f"  📌 Đã thêm vào Project #{PROJECT_NUMBER} (Agent Workbench)")
        try:
            item_data = json.loads(res_proj.stdout)
            item_id = item_data.get("id")
            if item_id:
                # 3. Gán cột Backlog
                cmd_edit = [
                    "gh", "project", "item-edit",
                    "--id", item_id,
                    "--project-id", "PVT_kwHOAGnqzM4BnS4g",
                    "--field-id", "PVTSSF_lAHOAGnqzM4BnS4gzhl4Kok",
                    "--single-select-option-id", "a537f4c7"
                ]
                subprocess.run(cmd_edit, capture_output=True, text=True)
                print(f"  🎯 Đã chuyển vào cột: Backlog")
        except Exception as e:
            print(f"  ⚠️ Lỗi gán Status Backlog: {e}", file=sys.stderr)
    else:
        print(f"  ⚠️ Lỗi thêm vào project: {res_proj.stderr.strip()}", file=sys.stderr)
    
    return issue_url

def main():
    parser = argparse.ArgumentParser(description="Push backlog tickets to GitHub Project Board")
    parser.add_argument("--apply", action="store_true", help="Thực hiện tạo thật (không chạy dry-run)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Chạy thử không tạo issue")
    parser.add_argument("--ticket", type=str, help="Chỉ định ticket (ví dụ: 1 hoặc 1..5)")
    args = parser.parse_args()
    
    dry_run = not args.apply
    
    tickets = parse_tickets(TICKETS_FILE)
    print(f"Tìm thấy {len(tickets)} tickets trong {TICKETS_FILE.name}")
    
    selected_indices = None
    if args.ticket:
        if ".." in args.ticket:
            start, end = map(int, args.ticket.split(".."))
            selected_indices = set(range(start, end + 1))
        else:
            selected_indices = {int(args.ticket)}
    
    for t in tickets:
        if selected_indices and t["num"] not in selected_indices:
            continue
        create_issue_and_add_to_board(t, dry_run=dry_run)
    
    if dry_run:
        print("\n💡 Chạy với `--apply` để chính thức tạo các issue này lên GitHub Project Board!")

if __name__ == "__main__":
    main()
