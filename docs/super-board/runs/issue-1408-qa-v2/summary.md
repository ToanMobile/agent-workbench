# Tóm tắt QA — Issue #1408 (PR #1409) v2 (sau rebase)

- Lệnh kiểm thử mục tiêu: `bash tests/super-board/test_merge_queue_e2e.sh`
- Kết quả trên nhánh PR đã gộp `origin/main` (`1c256ac2` → `3fdd244f`): thoát `0` (`42 ✔`, `0 ✖`, `✅ test_merge_queue_e2e: all passed`)
- Đối chứng RED trước sửa trên `origin/main` (`0a644f4e`): thoát `79` (`[github-read] HALT`, `issue_last_comment` gọi `issues/N/comments?per_page=1&page=K` chưa có nhánh trong `gh` giả)
- Kiểm tra AC2 (`git diff origin/main...3fdd244f`): chỉ thêm 5 dòng `tests/super-board/test_merge_queue_e2e.sh:189-193`, `0` assertion bị xoá hay nới; audit Antigravity trên head mới sẽ do lane Review thực hiện
- Kiểm tra AC3: đã ghi rõ trong PR — `scoped_gate.cap_selection` (`universal-agent-devkit/bin/scoped_gate.py:982-1047`) đẩy `REG-SB-MERGE-QUEUE-E2E-01` vào `deferred_to_heavy`, còn `[merge-train]` / `[merge-gate #1393]` chạy `--scoped` dùng lại biên nhận cũ và chỉ ép 24 suite `[merge-guard]` (`.agents/gate-core.txt:186-215`)
- Bảo mật: `pr-security-review: skipped (no code in diff)` (chỉ có file test và tài liệu QA)
- Ảnh nghiệm thu: không áp dụng (thay đổi thuần script test CLI)
