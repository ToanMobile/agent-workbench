# QA #1003 v1
- Lệnh: `bash tests/super-board/test_runner_lane_workers.sh` — exit 0, "all passed".
- Đột biến: đổi `then LOCK_DIR="$LOCK_GD/super-board/merge.lock"` thành `then :` trong merge gate — exit 1, "✖ merge gate lost its common-dir merge.lock". Đã khôi phục gate (git status sạch).
- Đã merge origin/main: Already up to date.
