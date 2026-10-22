# QA #146 v2 — PASS

Lệnh: `bash tests/super-board/test_merge_gate_heartbeat.sh` → exit 0, 6/6 xanh (đã gồm ca 4 SIGKILL).
Đột biến: bỏ dòng `kill -0 "$owner"` trong heartbeat → ca 4 ĐỎ (`at 1792600025 -> 1792600030`); khôi phục → 6/6 xanh.
Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` → exit 0, PASS 40/40.
AC1 ca 1 (verify > --stale-after giữ khoá) · AC2 ca 3 + ca 4 (không mồ côi, kể cả SIGKILL) · AC3 ca 5 (khoá bị chiếm không bị ghi) · AC4 đỏ→xanh có đủ.
Còn lại (Low, không chặn): cửa sổ mili giây giữa đọc pid và mv, đã ghi `ponytail:` trong code; own_lock_or_stop trước merge bắt được.
Ảnh: không cần — thay đổi script backend/test, không lên màn hình.
