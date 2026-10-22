# QA v4 · PR #182 · head d2551546 + merge main (51fcb706)

Lệnh: `bash tests/super-board/test_merge_train.sh` → exit 0, 27 kiểm tra ✔ (ca 7 R11 preflight, ca 8 R8 deferred, ca 9 R9 exit 6).
Lệnh: `bash tests/super-board/test_merge_gate_dead_holder.sh` → exit 0 (sau merge main).
Main đã dời (#219) và xung đột ma trận lần 3: giữ cả hai rule, rule merge-train ở CUỐI, 48 id không trùng.
Lệnh: `post-fix-gate.py --run-tests --full --diff origin/main --brief` → exit 0, 47/47.

AC1 3 PR một lần --full: đạt (ca 3 PR)
AC2 một PR đỏ → chia đôi: đạt (culprit #5; ca gate chặn giữa đợt: main không nhận cây chưa verify)
AC3 một PR như hiện tại: đạt
AC4 gh giả ĐỎ→XANH: đạt (builder ca 7-9 ĐỎ→XANH; đột biến R1 ở v2)

Test gaps (không chặn, Medium): R7 chưa có test riêng cho gate exit 9/11 sau preflight · R5 over-engineering.
Ảnh: không cần, script backend.
