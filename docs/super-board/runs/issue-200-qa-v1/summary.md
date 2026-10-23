# QA #200 v1 — worktree.py discard chuỗi đã squash

Head: f33cb978 (đã merge origin/main trước khi chạy).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash universal-agent-devkit/tests/worktree_git/test_worktree_discard_squash.sh` | 0 | s1–s11 PASS, ALL PASS |
| Cùng test trên `worktree.py` của origin/main (RED độc lập) | 1 | 3 FAILED (s1, s4 và ca dựa vào chuỗi squash) |
| `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | 0 | hồi quy 67/67, lớp tĩnh đạt |

Log gate đầy đủ giữ ngoài nhánh (không commit).
Ghi chú: ảnh không cần — thay đổi backend/kit, không lên màn hình.
