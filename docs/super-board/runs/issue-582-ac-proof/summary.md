# Bằng chứng AC #582 (PR chứng minh sau #593)

Mã đã merge ở PR #593 (02b763a4). PR này chỉ ghi bằng chứng để gỡ nhãn `ac-open`.

- AC 1 (ĐỎ trước khi sửa): QA v1 (`docs/super-board/runs/issue-582-qa-v1/summary.md`) chạy
  `bash universal-agent-devkit/tests/gates/test_gate_worktree_main_transcript.sh` trên gate gốc:
  exit 1, `✖ main_transcript_approves: muốn True, được False`.
- AC 2 (XANH sau khi sửa): chạy lại trên origin/main 274130ef: exit 0, `PASS`,
  `✔ main_transcript_approves: muốn True, được True`.
- AC 3 (vẫn chặn): cùng lần chạy, 5 ca âm đều `✔` (muốn False, được False):
  `edit_after_answer`, `not_an_approve_label`, `other_session_in_main_folder`,
  `subdir_of_parent_repo`, `other_project_transcript`.
- Ảnh: không cần (gate backend).
