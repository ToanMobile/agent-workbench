---
name: createTask
description: "Tự động tạo task chuẩn Super-Board và đẩy lên cột Backlog của GitHub Project #1 (https://github.com/users/ToanMobile/projects/1/views/2)"
---

# /createTask

Đọc skill `create-task` tại `.agents/skills/create-task/SKILL.md` (hoặc `universal-agent-devkit/skills/create-task/SKILL.md`) và thực hiện tạo task chuẩn Super-Board cho: $ARGUMENTS

### Quy trình thực hiện:
1. Nếu `$ARGUMENTS` chứa `--from-file` hoặc `--ticket <N>`, gọi script:
   `python3 universal-agent-devkit/scripts/governance/create_task.py $ARGUMENTS`
2. Nếu `$ARGUMENTS` là mô tả ngắn hoặc yêu cầu mới:
   - Làm giàu ngữ cảnh thành 6 phần: `## Problem`, `## Context`, `## Fix`, `## Acceptance Criteria`, `## Risk`, `## Blocked by`.
   - Gọi `python3 universal-agent-devkit/scripts/governance/create_task.py --title "..." --problem "..." --fix "..." --ac "..."` để tạo issue và thêm vào cột Backlog của Project #1.
3. Báo cáo lại cho người dùng kèm link Issue và link Board [https://github.com/users/ToanMobile/projects/1/views/2](https://github.com/users/ToanMobile/projects/1/views/2).
