---
name: createTask
description: "Tự động tạo task chuẩn Super-Board và đẩy lên cột Backlog của GitHub Project #1 (https://github.com/users/ToanMobile/projects/1/views/2)"
---

# /createTask

Đọc skill `create-task` tại `.agents/skills/create-task/SKILL.md` (hoặc `universal-agent-devkit/skills/create-task/SKILL.md`) và thực hiện tạo task chuẩn Super-Board cho: $ARGUMENTS

### Quy trình thực hiện:
1. Nếu `$ARGUMENTS` chứa `--from-file` hoặc `--ticket <N>`, gọi script:
   `python3 .agents/devkit/scripts/governance/create_task.py $ARGUMENTS`
2. Nếu `$ARGUMENTS` là mô tả ngắn hoặc yêu cầu mới:
   - Làm giàu ngữ cảnh thành 6 phần: `## Problem`, `## Context`, `## Fix`, `## Acceptance Criteria`, `## Risk`, `## Blocked by`.
   - Gọi `python3 .agents/devkit/scripts/governance/create_task.py --title "..." --problem "..." --fix "..." --ac "..."` để tạo issue và thêm vào cột Backlog của Project #1.
   - Gom, đừng tách (skill `create-task`, mục "Gom Việc"): script tự nhập việc cùng loại vào thẻ Backlog đang có; nhiều việc trong một lượt thì gọi MỘT lần với nhiều dòng AC. Thẻ riêng chỉ với `--new-card "<lý do>"`.
   - Khác chủ đề thì script tự đưa thẻ mới vào đợt của một thẻ chưa chạy (mục "🚃 Đợt" của skill): thẻ riêng, nhưng cả đợt build trên một nhánh, một PR, một lần gate.
3. `$ARGUMENTS` là câu hỏi hoặc xác nhận (không có việc cần làm): trả lời trực tiếp, không tạo thẻ.
4. Báo cáo lại cho người dùng: link Issue vừa tạo, hoặc `#N` của thẻ đã gom (script in `🧺 Đã gom … vào thẻ Backlog #N`), hoặc thẻ mới kèm đợt (`🚃 Vào đợt #N`), kèm link Board [https://github.com/users/ToanMobile/projects/1/views/2](https://github.com/users/ToanMobile/projects/1/views/2).
