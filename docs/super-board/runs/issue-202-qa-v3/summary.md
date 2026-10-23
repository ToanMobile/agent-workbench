# QA v3 · #202 · PR #205 @ 0849ba58

- `bash tests/super-board/test_runner_ready_order.sh` → exit 0, 17/17 ca ALL PASS
- 9 test runner lân cận: 8 exit 0; `test_runner_lane_workers.sh` exit 2 khi tải máy 117, chạy riêng lại exit 0 (flaky do tải, có sẵn trên main)
- 5 thread review (R1-R5) đều resolved
- `post-fix-gate.py --run-tests --full --no-cache --diff origin/main` → exit 0 (12/12). Hai lần chạy có cache ra exit 4 (PASS dùng lại bị vô hiệu giữa chừng, không có test đỏ), nên chạy lại với --no-cache
- Thay đổi từ v2: chỉ gộp main (#147), không đụng runner
