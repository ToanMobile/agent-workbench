# QA #147 vòng 2 (rebuild-1, R2: AC1)
Lệnh: `bash tests/gates/test_guard_shell_norm_monotonic.sh` x10 (bản thật, không wrapper), 56 vòng lặp CPU làm tải.
Kết quả: 10/10 exit 0. Load 1 phút lúc từng lần: 42, 94, 113, 100, 228, 185, 193, 191, 202, 197 (đều > 40).
Đo bằng `sysctl vm.loadavg`; tiến trình tải đã dừng sau khi chạy xong.
Head PR: 4b7c51b6. Vòng 1: oracle mô phỏng + gate `--full` exit 0 (xem v1).
