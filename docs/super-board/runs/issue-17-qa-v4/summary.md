# QA issue #17 v4 — FAIL: pid_start phụ thuộc múi giờ (TZ)

- Hồi quy: 10 suite `test_session_lock*.sh` (gồm pid_start 4/4) → exit 0 sau khi merge origin/main
- AC1 PASS (holder_pid dùng ps khi không có /proc)
- AC2 FAIL một phần: `ps -o lstart=` in giờ địa phương theo `TZ`. Cùng một tiến trình: `TZ=UTC` → `07:35:57`, mặc định → `14:35:57`.
- Repro: ghi `pid_start` dưới `TZ=UTC`, đọc dưới TZ mặc định:
  `is_pid_alive(os.getpid(), "Wed Oct 21 07:35:57 2026")` → False dù PID đang sống
- Hậu quả: hook chạy với TZ khác lệnh `status`/phiên khác → lock phiên SỐNG bị coi là trống, hai phiên sửa cùng checkout
- Sửa gợi ý: chạy `ps` với `TZ=UTC LC_ALL=C` trong `_ps` (hoặc dùng epoch); thêm test RED: ghi dưới TZ=UTC, đọc dưới TZ khác phải True
- Không có UI nên không có ảnh.
