# QA v2 · #1303 / PR #1306 (head 0cb9bce1, đã up to date với origin/main 79cc2a5a)
- Lệnh: `bash tests/super-board/test_lane_worktree_kit.sh` → exit 0, mục 5 và 6 xanh (tự chạy).
- ĐỎ trên nền: cùng test với `super-board-run.sh` + `super-board-wave.js` của origin/main → exit 1, 2 mục fail (tự chạy).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` → `pass`, exit 0.
- Chưa kiểm: lane thật gặp worktree bị giữ (test kiểm brief + hook thật, không chạy lane).
- Không có ảnh: AC không phải UI.
