# QA issue #17 v1 — session_lock macOS pid

- Lệnh: `bash universal-agent-devkit/tests/context_memory/test_session_lock_pid_start.sh` → exit 0, 4/4 PASS
- Hồi quy: 9 suite `test_session_lock*.sh` còn lại → exit 0 cả 9
- Mutant 1 (bỏ so sánh pid_start): test ĐỎ (2 ca fail), đã khôi phục
- Mutant 2 (holder_pid không bỏ qua sh cha): test ĐỎ (2 ca fail), đã khôi phục
- AC1 (xác định PID phiên trên macOS qua ps): ca 4 PASS
- AC2 (PID bị cấp lại không khóa nhầm): ca 2 + 3 PASS
- Không có UI nên không có ảnh.
