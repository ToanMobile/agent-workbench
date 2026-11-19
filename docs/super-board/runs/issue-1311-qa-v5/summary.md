# QA #1311 v5 — PR #1312 head f0400848

- Head đã chứa origin/main 260508d8 (`git merge --no-edit origin/main`: Already up to date).
- `test_github_read_rate_limit_backoff.sh` rc=0; `test_rate_limit_69_train_queue_1311.sh` rc=0 (xanh, tự chạy).
- RED: đặt 8 file `.claude/bin` của origin/main: backoff rc=1 (`limit x3 then ok: rc=79 halt=yes`, `issue_is_open rc=79 (want 69)`, `approval_check rc=2 (want 69)`), train/queue rc=1 FAIL (4); khôi phục về head, cây sạch (tự chạy).
- Cổng scoped `post-fix-gate.py --run-tests --scoped --brief --json` qua qa-exit2: `pass`, exit 0 (tự chạy).
- Ảnh: không cần, không có UI.
