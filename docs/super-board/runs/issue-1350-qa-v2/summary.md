# QA v2 · #1350 · PR #1360 @ 8e4fe4b6 (lượt rebuild)
- `bash tests/super-board/test_runner_read_recover_sites_1350.sh`: exit 0 (PASS, gồm H1/H2/I1/I2/I3/J mới).
- `bash tests/super-board/test_runner_mq_restart.sh`: exit 0 (all passed, test cũ bị sửa).
- `bash tests/super-board/test_runner_watchdog.sh`: exit 0.
- Đã merge origin/main (Already up to date), rồi `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh`: exit 0, kết quả `review`.
- Lý do `review`: test cũ `tests/super-board/test_runner_mq_restart.sh` bị sửa, cần Antigravity audit chéo.
- AC4 (chạy thật sau merge + sync kit) chưa kiểm được trước merge.
