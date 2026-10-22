# QA #155 — v1 (PASS)

Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_worktree_merge_scratch_slot.sh`

| Bước | Kết quả | Exit |
|---|---|---|
| Bản sửa nguyên trạng | 2/2 ✔ (3 scratch mồ côi không chặn add; worktree thật thứ 4 vẫn exit 4) | 0 |
| Hoàn tác bản sửa (mutation: bỏ `.merge-scratch-` khỏi `startswith`) | ✖ `add refused next to merge scratches (rc 4)`; ✔ trần vẫn giữ | 1 |
| Khôi phục bản sửa | 2/2 ✔, `git status` sạch | 0 |
| `test_worktree_limits.sh` (hồi quy) | PASS | 0 |

AC: ĐỎ trước sửa / XANH sau sửa — đạt. Scratch của merge gate đang chạy: diff không thêm thao tác gỡ nào
(chỉ đổi bộ lọc đếm slot trong `_live_worktrees`), nên không thể bị gỡ.

Chưa bao phủ: scratch mồ côi vẫn nằm trên đĩa (PR đã nêu); build output trong scratch chưa xử lý (phương án 3 của issue).
