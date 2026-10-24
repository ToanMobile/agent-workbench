# QA #240 v10 (head sau merge origin/main)
- Test: `bash universal-agent-devkit/tests/gates/test_multi_session_gate_session_env.sh` → exit 0 (3 ✔: multi_session_gate, reuse_race, registry không nhận `leaked-*`).
- Đột biến: gỡ `unset` ở CẢ HAI suite → ĐỎ exit 1 (multi_session_gate "own session counted as other"; reuse_race thấy leaked-a/b/c); khôi phục → xanh.
- AC2: chỉ kiểm `leaked-*` không vào registry thật, không so mtime dùng chung.
- Gate: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 83/83 (tải máy ~100, chạy lần đầu sau khôi phục).
- Ảnh: không cần — chỉ sửa test.
- Chưa kiểm: AC3 (merge gate #78/PR #170, PR còn OPEN, phụ thuộc PR khác). Phần gộp #347 (guard-secrets) chưa làm: file bị gitignore, nới chốt bảo mật cần người quyết.
