# QA #377 · PR #382 · head d6799fd7 (v1)

Merge origin/main vào nhánh: Already up to date.

| Lệnh | Exit | Kết quả |
|---|---|---|
| `super-board-verify-cmd.sh --record` (post-fix-gate --full --force-full --diff origin/main) | 0 | PASS 97/97, biên nhận cây 00101b1f52e6… ghi xong |
| `test_gate_suite_cache_void.sh` | 0 | V1–V5 xanh |
| `test_gate_suite_cache_selection.sh` | 0 | S1–S6 xanh (S1: test chạy 2 → 2) |
| `test_gate_slot_started.sh` | 0 | G1–G3 xanh (nghỉ 0,06 / 0,07 s dưới tải giả 150) |
| `test_gate_slot_classes.sh` | 0 | xanh (test 9 do builder sửa, AUTO-APPROVE ở 37050ec8) |

RED: 3 test mới chạy trên mã origin/main (bản sao scratch, đã xoá) không in "all passed", không xanh.

AC kiểm bằng test: 1, 2, 3, 6, 7, 9 PASS. Gate exit 0 PASS.
AC chưa kiểm được trước merge (cần đo thật): 4 (tải ≥ 60), 5 (một ngày board sau merge), 8 (AB/BA ≥ 5 cặp).
Chưa chạy đột biến lại: tin log đột biến của builder.
