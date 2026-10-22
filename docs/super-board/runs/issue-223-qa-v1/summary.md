# QA #223 v1 — head 5ec28e0a
- test_precommit_test_durations.sh → exit 0 (10 kiểm tra)
- test_run_impacted_order.sh → exit 0
- Mutant (bỏ dòng `[ -z "$missing" ] && exit 0`): ĐỎ 4 ca → khôi phục → XANH
- post-fix-gate --run-tests --full --brief --diff origin/main → exit 0
- Ảnh: không cần — backend, không có màn hình
