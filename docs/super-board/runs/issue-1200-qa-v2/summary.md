# QA #1200 v2 — head 23425bc6 (đã gộp origin/main 438971a6)
- test_edited_approval_survives_base_move.sh: exit 0 (H1–H5 ALL OK)
- test_merge_gate_pm_edited_base_moved.sh: exit 0 (ALL OK)
- ĐỎ trước: bản origin/main của gate cho H1, H2 đỏ (QA v1, cùng logic, không đổi code từ đó)
- gate scoped qua super-board-qa-exit2.sh: `review` (test cũ bị sửa: tests/super-board/test_merge_gate_pm_edited_base_moved.sh)
- Không có ảnh: AC không liên quan UI
