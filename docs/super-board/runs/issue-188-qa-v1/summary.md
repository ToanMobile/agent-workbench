# QA #188 v1 (PR #212)

- Lệnh: `bash tests/super-board/test_runner_gate_red_requeue.sh` → exit 0, 10 ✔ (A, B, C1, C2, C3, D, E, F, G, H), 0 ✖.
- Đột biến 1: bỏ so sánh ngày main → ca H ĐỎ (bắt được).
- Đột biến 2: bỏ dedupe theo SHA → test cũ vẫn XANH (cooldown che). Thêm ca C3 (cooldown 0, cùng SHA) → XANH trên mã PR, ĐỎ dưới đột biến.
- Gate: `post-fix-gate.py --run-tests --full --diff origin/main` → exit 0, 47/47 test hồi quy (sau khi merge origin/main, giữ cả hai khối ma trận).
- Chưa kiểm: AC4 (#147, #78 rời Blocked) chỉ kiểm được sau khi triển khai.
- Ảnh: không cần, không có giao diện.
