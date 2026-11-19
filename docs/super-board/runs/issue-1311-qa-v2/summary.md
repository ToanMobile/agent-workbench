# QA #1311 v2 — head 2b561841

- Test mới `tests/super-board/test_github_read_rate_limit_backoff.sh`: 6/6 xanh, rc=0 (tự chạy).
- RED: với `super-board-run.sh` của origin/main, test đỏ `issue_is_open rc=79 (want 69)`, rc=1 (tự chạy).
- Lỗi 401 (kể cả stdout có chữ "rate limit") vẫn halt ngay; approval.py thoát 69 không traceback.
- Cổng scoped `post-fix-gate.py --run-tests --scoped --brief`: exit 0 (tự chạy).
- Ảnh: không cần, không có UI.
