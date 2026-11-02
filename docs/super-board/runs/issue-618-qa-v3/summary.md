# QA #618 v3 — shell_norm: NUL trong từ ANSI-C (rebuild-3, \c UTF-8, \C- zsh, cách đọc không cắt NUL)

Head kiểm: 6433f186 (nhánh issue-618-shell-norm-nul).

| Lệnh | Kết quả |
|---|---|
| test_guard_shell_norm_nul.sh (code mới) | exit 0, ALL PASS (13 ca ép đẩy rc 2, gồm \cक, \C-@, \C-space, \C-backtick, bash -c / eval; đối chứng rc 0) |
| Cùng test, shell_norm.py của 52cfd6bd (head trước) | ĐỎ: 7 ca lọt |
| test_guard_shell_norm.sh, _monotonic.sh, _load_retry.sh | cả 3 ALL PASS (monotonic: 3133 lệnh, 0 failed) |
| post-fix-gate --run-tests --scoped --brief | 149/150; suite đỏ duy nhất test_runner_self_reload.sh (exit 1 lúc tải máy ~80), chạy lại riêng: all passed. Không thuộc diff PR |
