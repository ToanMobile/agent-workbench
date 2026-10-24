# QA #240 v9 (nhánh đã merge origin/main 35a86448)
- Test: `bash universal-agent-devkit/tests/gates/test_multi_session_gate_session_env.sh` → exit 0 (chạy thật cả 2 suite với id phiên rò vào, không còn grep dòng `unset`).
- Đột biến: gỡ dòng `unset` trong test_gate_stop_reuse_race.sh → ĐỎ (exit 1, shim thấy `DEVKIT_SESSION_ID=leaked-a ...`); khôi phục → xanh (exit 0).
- AC2: registry phiên thật chụp trước/sau trong test → không đổi.
- Gate: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 67/67 (sau merge main).
- Lần gate đầu sau merge đỏ 2 suite dưới tải ~80 (REG-DK-SESSION-01 "impacted verdict missing", REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01); REG-DK-SESSION-01 chạy riêng xanh, gate chạy lại xanh toàn bộ.
- Diff so với origin/main: chỉ thêm dòng, 0 xoá.
- Ảnh: không cần — chỉ sửa test, không lên màn hình.
- Chưa kiểm: AC3 (merge gate của #78/PR #170; PR #170 còn OPEN); đột biến chưa chạy cho `unset` của test_multi_session_gate.sh.
