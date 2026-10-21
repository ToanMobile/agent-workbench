# QA issue #17 v3 — session_lock macOS pid (chạy lại sau khi board dừng)

- Lệnh: `bash universal-agent-devkit/tests/context_memory/test_session_lock_pid_start.sh` → exit 0, 4/4 PASS
- Hồi quy: 9 suite `test_session_lock*.sh` còn lại → exit 0 cả 9
- Thật trên Darwin: pid_start của chính tiến trình → `is_pid_alive` True; pid_start sai → False; lock cũ không có pid_start → True (tương thích ngược)
- Chi phí `ps`: ~3.4 ms/lần (chấp nhận được)
- AC1 PASS (holder_pid/ps fallback), AC2 PASS (PID cấp lại không khóa nhầm)
- Không có UI nên không có ảnh.
