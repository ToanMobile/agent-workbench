# QA #125 v1 — watchdog safe_path giữ nguyên văn

Head: d3fafc4c · không có UI, không cần ảnh.

| Lệnh | Exit | Kết quả |
|---|---|---|
| bash tests/super-board/test_watchdog_path_sanitize.sh | 0 | PASS (có 2 ca mới) |
| bash tests/super-board/test_runner_watchdog.sh | 0 | all passed |
| bash tests/super-board/test_watchdog_lock_mtime.sh | 0 | PASS |

ĐỎ→XANH: test mới chạy với watchdog của 5ebdd952~1 (bản cũ) thì exit 1:
`✖ outside symlink entry pinned: PATH='…/outside' (want '…/jlink')`.
Trên nhánh: exit 0.

Ca `..` và ca symlink trong repo trỏ ra ngoài đã có sẵn và vẫn XANH.
