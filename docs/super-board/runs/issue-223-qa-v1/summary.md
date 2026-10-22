# QA #223 v1 — đầu nhánh 5ec28e0a, đã merge origin/main 937a2953
- test_precommit_test_durations.sh → exit 0 (10 kiểm tra), chạy lại độc lập
- test_run_impacted_order.sh → exit 0
- Đột biến (`&& exit 0` → `|| exit 0` ở check-test-durations.sh:30): ĐỎ (exit 1) → khôi phục → XANH
- post-fix-gate --run-tests --full --brief --diff origin/main → exit 0, 49/49 hồi quy, lớp tĩnh đạt
- Lần gate đầu REJECT 48/49 chỉ vì nhánh cũ hơn main (test của #209/#174/#164 hiện như bị xoá); merge main xong thì PASS
- Ảnh: không cần — backend, không có màn hình
