# QA #1311 v4 — PR #1312 head 30bb39f4

- Head đã chứa origin/main c8427d5b (merge-base --is-ancestor rc=0).
- `test_github_read_rate_limit_backoff.sh` rc=0 (xanh); `test_rate_limit_69_train_queue_1311.sh` rc=0, 5/5 xanh (tự chạy).
- RED: đặt 8 file `.claude/bin` của origin/main, chạy `test_rate_limit_69_train_queue_1311.sh` → rc=1, FAIL (4); khôi phục về head, cây sạch (tự chạy).
- Cổng scoped `post-fix-gate.py --run-tests --scoped --brief` exit 0, 12/12 (tự chạy).
- Ảnh: không cần, không có UI.
