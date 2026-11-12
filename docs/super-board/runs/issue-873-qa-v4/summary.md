# QA #873 v4 — head 24582ab1 (PR #1095)
- `bash universal-agent-devkit/tests/gates/test_guard_secrets_residual.sh` → exit 0, all checks passed (gồm ca trần brace R4/R5).
- `bash universal-agent-devkit/tests/gates/test_guard_secrets.sh` → exit 0, không bị sửa.
- ĐỎ→XANH R4/R5: cùng test chạy với hook của 970fa594 (`GUARD=...`) → exit 1, "1 FAILED"; trên head → exit 0.
- Thăm dò: lệnh curl -d JSON 6000 ký tự trong nháy vẫn allow (head, 970fa594, main giống nhau): trần 4096 không chặn nhầm.
- origin/main đã nằm trong head (merge-base --is-ancestor đúng), không cần merge thêm.
- Không sửa mã sản xuất ở vòng QA này. Ảnh: không cần, hook backend.
