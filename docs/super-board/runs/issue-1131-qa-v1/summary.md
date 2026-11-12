# QA #1131 v1 — PASS
- Nhánh: issue-1131-edited-tests-line (PR #1133), đã merge origin/main trước khi chạy.
- RED: test_queue_approval_no_edited_tests_line.sh trên origin/main: D1, D2 FAIL (rc=1).
- GREEN: cùng test trên PR: D1-D3 ok (rc=0).
- Hồi quy: test_qa_exit2_edited_test, test_has_edited_tests_pm_record, test_merge_gate_pm_edited_base_moved: PASS (rc=0).
- Gate: post-fix-gate.py --run-tests --scoped --brief --json -> super-board-qa-exit2.sh in `pass`.
- Security pass: diff chỉ gồm prompt/tài liệu và 1 test shell, không có bề mặt khai thác.
- Ảnh: không cần (không đổi giao diện).
