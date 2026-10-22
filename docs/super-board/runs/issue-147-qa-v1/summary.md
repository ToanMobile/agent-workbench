# QA #147 vòng 1
- Lệnh: bash universal-agent-devkit/tests/gates/test_guard_shell_norm_load_retry.sh → exit 0 (3/3 ok)
- test_guard_shell_norm_monotonic.sh (bản đã sửa) → ALL PASS, 3133 dangerous, 0 vacuous, 0 failed
- ĐỎ trước sửa: oracle load_retry chạy với monotonic của origin/main → exit 1, "hw rc 2 (want 0)" + thông điệp watchdog
- Chưa kiểm chứng: AC1 (10/10 ở load > 40); load đo khi QA 19-31
