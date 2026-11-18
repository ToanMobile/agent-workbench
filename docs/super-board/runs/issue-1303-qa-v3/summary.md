# QA v3 · #1303 / PR #1306 (head 65665ce1, đã up to date với origin/main 79cc2a5a)
- Lệnh: `bash tests/super-board/test_lane_worktree_kit.sh` → exit 0, mục 5, 6, 7 xanh (tự chạy).
- ĐỎ trên nền: cùng test với brief của origin/main → exit 1, cả 3 mục 5/6/7 fail (tự chạy).
- Gate: `post-fix-gate.py --run-tests --scoped --brief` → exit 0, 5/5 hồi quy (tự chạy).
- Chưa kiểm: lane thật gặp worktree bị giữ (test kiểm brief + hook + worktree.py thật, không chạy lane).
- Không có ảnh: AC không phải UI.
