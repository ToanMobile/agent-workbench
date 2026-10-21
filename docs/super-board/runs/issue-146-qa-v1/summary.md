# QA #146 v1 — FAIL (1 lỗ hổng High)

Lệnh: `bash tests/super-board/test_merge_gate_heartbeat.sh` (Builder, 5 ca) → exit 0, 5/5 xanh.
Hồi quy: gate gốc origin/main → ca 1 đỏ (gate B reap khoá). Đột biến bỏ kiểm tra pid → ca 3 đỏ. Cả hai đúng như Builder báo.

## Test-gap (High)
AC2 "heartbeat dừng, không mồ côi" chỉ được test ở đường thoát bình thường. Gate bị SIGKILL (trap EXIT không chạy)
để lại heartbeat sống: nó chỉ so pid trong khoá với pid gate (vẫn khớp), nên tiếp tục ghi `at` mãi.
Reap chỉ xét tuổi `at` (merge-gate.sh:200), nên khoá của gate đã chết không bao giờ bị reap → mọi gate sau kẹt tới --lock-timeout.
Witness: ca 4 mới (đỏ): `at 1792592104 -> 1792592108` sau khi gate bị kill -9.
Sửa gợi ý (1 dòng, đã thử: ca 4 xanh, 6/6): trong vòng lặp heartbeat thêm `kill -0 "$owner" 2>/dev/null &&` trước kiểm tra pid.
