# QA #1311 v7 — PR #1312 head 9864f580

- Head đã chứa `origin/main` (merge: Already up to date).
- Target tests: `test_github_read_rate_limit_backoff.sh` rc=0 (R8a/R8b runner thật: sống, không halt), `test_rate_limit_69_train_queue_1311.sh` rc=0 (exit 68, không halt).
- Điểm review trước đã xử lý: `issue_is_open` giữ exit 68 (không ép 79); `super-board-approval.py:393` bắt `RateLimited`; regex chỉ khớp stderr/errors.
- Cổng `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass` (exit 0).
- Ảnh: không cần, chỉ đổi script và test, không có UI.
