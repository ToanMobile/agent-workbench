# DevKit Git, Hooks & Worktree Engine

Nhóm công cụ quản trị Git an toàn, githooks và parallel sandbox:

- `backup_conflict.sh`: Bảo vệ file cấu hình và tài nguyên cục bộ khi cập nhật DevKit (cơ chế `*_old`).
- `git-commit-msg.sh`: Kiểm tra định dạng commit message và bắt buộc ghi nhận Bug ID / No-Guard.
- `git-pre-commit.sh`: Chạy kiểm tra tĩnh post-fix gate trước khi commit.
- `githooks.sh`: Quản lý cài đặt / gỡ bỏ các git hooks chuẩn của DevKit.
- `worktree.py`: Quản trị worktree độc lập cho các phiên agent song song.
- `worktree_sandbox.py`: Quản trị APFS Copy-on-Write sandbox siêu tốc (<100ms, 0-byte đĩa ban đầu).
