# QA #618 v2 — shell_norm: NUL trong từ ANSI-C (rebuild-2, thêm \c@)

Head kiểm: 217d658c (origin/main 46ccb4a6 đã nằm trong nhánh, "Already up to date").

| Lệnh | Kết quả |
|---|---|
| test_guard_shell_norm_nul.sh (code mới) | exit 0, ALL PASS (8 ca ép đẩy rc 2, đối chứng status rc 0) |
| Cùng test, shell_norm.py bản origin/main (qua GG_HOOK) | ĐỎ: FAILS=8, cả 8 lệnh ép đẩy rc 0 (lọt guard) |
| test_guard_shell_norm.sh, _load_retry.sh, _monotonic.sh | cả 3 ALL PASS (monotonic: 3133 lệnh, 0 failed) |

Đối chiếu bash thật: ab\c@cd, ab\c cd, ab\c + backtick + cd trong $'…' đều in `ab` (NUL cắt từ).
ansi_c_to_single cho git + $'\c@foo' ra "git''" (phần sau NUL bị bỏ).

Ghi chú nhỏ: shell_norm.py có `code =int(` thiếu dấu cách (thẩm mỹ, không ảnh hưởng).
Hậu tố sau dấu nháy đóng: có từ trước PR, tách ticket riêng theo reviewer.
