# QA #327 v1 (PR #350)

Lệnh: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` (sau khi merge origin/main)
Kết quả: exit 0, 82/82 suite PASS, lớp tĩnh đạt.

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 gc liệt kê thư mục mồ côi | ✅ | đã ở main (2b5de6cc); `test_worktree_gc.sh` PASS |
| AC2 file duy nhất thì giữ + nêu lý do | ✅ | `gc: giữ .../leftover-unique: notes.md` |
| AC3 khoá pid chết báo/mở, pid sống không đụng | ✅ | 3 ca mới (#327 b) PASS |
| AC4 `test_worktree_remove_kit_links.sh` + test gc cũ | ✅ | cả hai exit 0 |
| AC5 gate `--full` exit 0 | ✅ | 82/82 |

Mutant: đổi `if k and not k[2]:` thành `if False and ...` → `test_worktree_gc.sh` exit 1, 2 ca đỏ; khôi phục → exit 0.
Chưa làm (ngoài phạm vi PR, ghi trong PR): báo khoá/thư mục mồ côi ở list/heal/SessionStart, và (c) tìm đường gỡ đăng ký để lại thư mục. Issue giữ mở.
