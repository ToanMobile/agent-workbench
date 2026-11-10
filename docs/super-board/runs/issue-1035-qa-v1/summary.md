# QA #1035 v1 — PASS

- Nền: origin/main đã gộp (Already up to date), head PR 1c160b41.
- `bash tests/super-board/test_runner_file_wait.sh` → exit 0, AC1-AC5 XANH.
- ĐỎ trên code nền (super-board-run.sh của origin/main): exit 1, `4 FAILED`.
- `test_runner_total_cap`, `test_runner_merge_queue`, `test_runner_lanes` → exit 0.
- `post-fix-gate.py --run-tests --scoped --brief --json` qua super-board-qa-exit2.sh → `pass` (exit 0).
- Không sửa test cũ (chỉ thêm 52 dòng vào test_runner_file_wait.sh).
