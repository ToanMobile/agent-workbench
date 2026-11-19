# QA v9 — issue #1311, PR #1312 @ 156b4918 (rebuild-4: R12, R13)
Lệnh (tự chạy, worktree QA đã merge origin/main: Already up to date):
- bash tests/super-board/test_github_read_rate_limit_backoff.sh → rc=0 (29 ✔, gồm R12 chốt không tự gia hạn, R13 mốc start-up)
- bash tests/super-board/test_rate_limit_69_train_queue_1311.sh → rc=0
- bash tests/super-board/test_merge_queue_route_rows.sh → rc=0 (test cũ, không đổi so với main)
AC1 backoff không halt: đạt. AC2 card.sh status không ghi halt: đạt. AC3 lỗi vĩnh viễn (401) vẫn halt lần đầu: đạt.
Ảnh: không cần, không có UI. Log gốc nằm ngoài nhánh (/tmp/qa-agent-workbench-1311-*.log).
