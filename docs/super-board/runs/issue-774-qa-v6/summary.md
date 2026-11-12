# QA #774 v6 — head a96f5155 (origin/main đã là tổ tiên, merge: Already up to date)

Rebuild 3 sửa R4: hooks.json phát lệnh guard hai đường, khoá trùng settings.json.

- test_parity_check.sh: exit 0 (PASS). Ca mới "init trên repo có lệnh guard hai đường: đúng 1 hook guard"; thiếu file vẫn fail closed exit 2 (CLAUDE_PROJECT_DIR cũng trỏ vào thư mục không có).
- test_guard_protected_push.sh: exit 0.
- test_repo_consistency.sh: exit 0, 28 passed, 0 failed.
- test_adb_shim.sh: exit 0.
- AC1–AC4 giữ nguyên như v5; AC4: REG-DK-INIT-PARITY-SYNC-01 chạy test_parity_check.sh.
- Không có AC giao diện. Ảnh: không cần — diff là script, hook, test.
- Log thô ngoài nhánh: /tmp/qa-agent-workbench-774-*.log
