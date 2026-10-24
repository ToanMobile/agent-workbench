# QA #240 v1
- Test mới `test_multi_session_gate_session_env.sh`: exit 0 (xanh); đột biến gỡ `unset` trong test_multi_session_gate.sh → ĐỎ ("own session counted as other"), khôi phục → xanh.
- AC1: đăng ký 3 phiên giả (F1-F3) vào registry của worktree + id phiên máy thật rò vào → test_multi_session_gate.sh xanh.
- AC2: snapshot trước/sau (khoá/phiên trong git-dir, /tmp/claude-uid, heavy-slots) giống hệt.
- Gate: `post-fix-gate.py --run-tests --full --diff origin/main` exit 0, 59/59.
- QA sửa thêm: merge origin/main (conflict test_durations) + 1 dòng thời lượng test_tree_fp_super_board_runs (REG-DK-ALL-01 đỏ sẵn trên main).
- Chưa kiểm: chạy lại merge gate của #78 (PR #170); reuse_race chỉ kiểm dòng `unset`, không chạy thật.
