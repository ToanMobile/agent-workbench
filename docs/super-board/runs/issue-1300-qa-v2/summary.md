# QA #1300 v2 (rebuild-1, đầu PR 61c1f485)

Mã không đổi so với v1; builder chỉ sửa body PR (thêm khối sb:ac). QA chạy lại trên head 61c1f485.

- test_qa_report_redos_timeout.sh: ALL PASS (`a.` x 32000 xong 0 s, vẫn exit 1 khi nêu AC; checker treo thì gate exit 7 + `qa-report: timeout` sau 3 s; names_ac 3000x30000 = 1 s)
- test_qa_report_cross_repo_ac.sh: PASS
- test_merge_gate_qa_report.sh: ALL PASS
- post-fix-gate --run-tests --scoped --brief: exit 0
- Không có UI: không cần ảnh.
