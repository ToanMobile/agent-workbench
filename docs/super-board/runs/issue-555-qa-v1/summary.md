# QA #555 v1
Lệnh: `bash universal-agent-devkit/tests/verification/test_instincts_file_context.sh` → exit 0 (PASS, gồm ca mới: crash thật được ghi .err, exit 0)
Lệnh: `bash universal-agent-devkit/hooks/tests/hook_contract_test.sh` (mục instincts_file_context.sh) → 2 ok
AC1 khớp glob → inject đúng mục: PASS. AC2 lần 2 cùng phiên im lặng: PASS. AC3 không khớp/không glob im lặng exit 0: PASS. AC4 lỗi không chặn Read, có log: PASS (ca mới chứng minh).
Khoảng trống Medium chưa viết: không có test e2e đăng ký hook thật qua settings.json của repo.
