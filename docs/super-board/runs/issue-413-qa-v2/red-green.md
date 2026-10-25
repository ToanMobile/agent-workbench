# #413 — ĐỎ→XANH do builder tự chạy (26/10, head be330cfc)

Lệnh: `bash universal-agent-devkit/tests/gates/test_session_worktree_enter_lock.sh`

## ĐỎ — mã nền
Bản sao tạm: cây HEAD, riêng `bin/session_lock.py` và `hooks/session_worktree.py` lấy từ `origin/main`.
Exit 1, 5 ca đỏ:
- ✖ N1 (startup, khoá hỏng -> không có NOT LOCKED)
- ✖ N1b (git treo: 5 s, không có cảnh báo)
- ✖ N2 (compact sau startup hỏng -> không khoá lại)
- ✖ N2b (compact khoá lại đúng worktree của phiên)
- ✖ N3d (record không có thời điểm khởi động pid, dòng 3)
`test_session_worktree_enter_lock: 5 FAIL`

## XANH — mã nhánh
- `test_session_worktree_enter_lock.sh`: exit 0, PASS (N1, N1b, N2, N2b, N3d, E9 đều ✔)
- `test_worktree_merge_gate_board_kept.sh`: exit 0, PASS

## AC 5 (lstart qua ngủ)
Chủ thẻ chấp nhận mẫu thay thế (comment orchestrator 25/10 23:32 UTC): pid 1120 khởi động
22/10 21:48:43, `ps -o lstart=` không trôi sau 56 lần ngủ/thức (`pmset -g log`).
