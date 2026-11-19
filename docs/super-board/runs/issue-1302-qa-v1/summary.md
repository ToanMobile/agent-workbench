# QA #1302 v1 (PR #1304 @ 01f9c1af)
- Lệnh: bash tests/super-board/test_qa_head_settle_1302.sh → exit 0, 5/5 PASS.
- Mutation: đổi nhánh `attempt >= max_tries` thành `if false` → case 4 ĐỎ (rc=10 thay vì 11); đã khôi phục.
- AC1 (head đổi → rerun, không Blocked): case 2, 3 PASS.
- AC2 (quá N lần / không đứng yên → Blocked kèm lý do + số lần): case 4, 5 PASS.
- Không có UI: không cần ảnh.
