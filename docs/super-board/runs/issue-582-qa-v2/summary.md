# QA v2 #582 (PR #596, PR chứng minh AC)

- Nền: origin/main 274130ef (đã có mã sửa của #593), merge vào nhánh: "Already up to date".
- Lệnh: `bash universal-agent-devkit/tests/gates/test_gate_worktree_main_transcript.sh` → exit 0, PASS 6/6.
  - `main_transcript_approves`: muốn True, được True (AC 2).
  - 5 ca âm đều chặn: `edit_after_answer`, `not_an_approve_label`, `other_session_in_main_folder`, `subdir_of_parent_repo`, `other_project_transcript` (AC 3).
- AC 1 (ĐỎ trước khi sửa): dẫn `docs/super-board/runs/issue-582-qa-v1/summary.md` dòng 4: gate gốc exit 1, `muốn True, được False`.
- Gate: `post-fix-gate.py --run-tests --brief` exit 0 (biên nhận task đã ghi).
- Ảnh: không cần (gate backend).
