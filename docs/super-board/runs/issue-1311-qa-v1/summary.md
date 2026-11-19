# QA #1311 (PR #1312) v1

- Head QA: base origin/main đã merge (Already up to date), cổng chạy trên cây này.
- Test mới `tests/super-board/test_github_read_rate_limit_backoff.sh`: exit 0, 3/3 ✔ (tự chạy).
- RED trên bản cũ (`GHR_READ` = github-read của origin/main): exit 1, 2 ✖ (rc=79, có github-halt.json); case lỗi vĩnh viễn vẫn ✔.
- Cổng `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass`, exit 0.
- Chưa kiểm: runner/watchdog chưa có đường xử lý riêng exit 69 (card.sh items đọc lại 1 lần với 69, vô hại).
