# QA #830 v5 (rebuild vòng 4)

Head mã: `c29e6cbee2a978b68913f6b6b3b4334c1d604f60` (PR #1076).
Ảnh: không cần — hook dòng lệnh, không có UI.

Lệnh: `bash universal-agent-devkit/tests/gates/test_hardware_issue830.sh`
- Head: exit 0, 86 ✔, 0 ✖.
- Hook `origin/main`: exit 1, 42 ✖ (AC gốc còn lọt).
- Hook `9f693ea2` (trước sửa R16–R19): exit 1, đúng 7 ✖ vòng 4. Sau sửa cả 7 ✔.

`test_guard_shell_norm.sh` exit 0. `test_guard_shell_norm_monotonic.sh` exit 0.
12 test `test_hardware_*.sh` còn lại exit 0.

R16–R18 trên hook head: 4 ca chặn (rc 2), 3 ca không chặn nhầm (rc 0).
pr-security-review: diff không thêm eval, exec, subprocess hay IO mới.

Residual (không phải AC, main cũng vậy hoặc reviewer chưa chốt):
`$X -rf build ~`, `${X:+rm} -rf ~`, `/bin/$X -rf ~` vẫn rc 0 như main.
`(export ANDROID_SERIAL=emulator-5554); adb shell ls` khi get-serialno lỗi và có allowlist: main rc 0, head rc 2 (serial dính `)`).
`adb -s emulator-5554 wait-for-device && adb -e shell ls` khi get-serialno lỗi: main rc 0, head rc 2 (seen_wait, cùng hành vi từ trước vòng 4).
