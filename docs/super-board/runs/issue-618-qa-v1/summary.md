# QA #618 v1 — shell_norm: NUL trong từ ANSI-C

Head kiểm: 126f9a7a (đã merge origin/main, "Already up to date").

| Lệnh | Kết quả |
|---|---|
| test_guard_shell_norm_nul.sh (code mới) | exit 0, ALL PASS (5 ép đẩy rc 2, đối chứng status rc 0) |
| Cùng test, shell_norm.py bản origin/main (qua GG_HOOK) | ĐỎ: FAILS=5, cả 5 lệnh ép đẩy rc 0 (lọt guard) |
| test_guard_shell_norm.sh, _load_retry.sh, _monotonic.sh | cả 3 ALL PASS (monotonic: 3133 lệnh nguy hiểm, 0 failed) |
| post-fix-gate.py --run-tests --brief | exit 0, hồi quy 5/5 |

Đối chiếu bash thật: git$'\x00foo' chạy `git`; $'a\x00b'cd thành `acd`.
ansi_c_to_single cho các ca đó ra kết quả khớp (NUL cắt thân, phần sau dấu nháy đóng giữ nguyên).

Ghi chú nhỏ: thân PR liệt kê biến thể `\^@`; test thực tế dùng `\u0000`. Không ảnh hưởng AC.
