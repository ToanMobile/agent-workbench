# QA v2 #1120 (PR #1168) @ 773e4310

Lý do chạy lại: PR bị preflight ac-check trả về; builder chỉ thêm khối `sb:ac` vào PR body, không đổi mã.

- `bash tests/super-board/test_worker_limit_payment_402.sh`: exit 0 (402 balance exhausted: account chết bị ghi paused)
- `bash tests/super-board/test_account_failover.sh`: exit 0 (8a/8b/8c xanh)
- Merge origin/main: đã mới nhất.
- AC1, AC2: đạt. Không có AC giao diện, không có ảnh.
