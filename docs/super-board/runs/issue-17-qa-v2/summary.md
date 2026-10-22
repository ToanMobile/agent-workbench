# QA issue #17 v2 — session_lock macOS pid

- Lệnh: `bash universal-agent-devkit/tests/context_memory/test_session_lock_pid_start.sh` → exit 0, 4/4 PASS
- Hồi quy: 9 suite `test_session_lock*.sh` còn lại → exit 0 cả 9
- Thật trên Darwin: PID root (PermissionError) + pid_start sai → is_pid_alive=False; đúng pid_start → True
- Thật trên Darwin: `_parent_and_comm` đọc được ppid/comm qua `ps` (không có /proc)
- AC1 PASS (holder_pid/ps fallback), AC2 PASS (PID cấp lại không khóa nhầm)
- Không có UI nên không có ảnh.
