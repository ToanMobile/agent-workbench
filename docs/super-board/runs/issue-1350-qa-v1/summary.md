# QA #1350 v1 — PR #1360 head 43135b5b

- Lệnh: `bash tests/super-board/test_runner_read_recover_sites_1350.sh` (sau khi merge origin/main: Already up to date)
- Kết quả trên PR: exit 0, 9 ca PASS (A, B, C, D, E, F1, F2, F3, G)
- Kết quả trên base (origin/main + cùng test): exit 1, 4 ca FAIL (A, E, F1, G) → RED đúng
- Duyệt call site: mọi `issue_is_open` (dòng 933, 1636, 2005, 3092, 3511, 3843) và `backlog_issue_body` đi qua `rate_limit_skip`, nay gọi `recover_read_halt` khi mã 79; `mq_collect_rc` 79 cũng vậy, 9 vẫn halt
- Lỗi đọc dai dẳng vẫn exit 79 (ca B, F2); halt do ghi chưa rõ không được nhả (ca C)
- Watchdog: chạm trần restart → `hold_and_notify gave-up` (ca G)
- Chưa kiểm: AC4 (chạy thật sau merge + sync kit trên 5 repo app) — chỉ làm được sau merge
