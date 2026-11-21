# QA Summary — Issue #1408 (PR #1409) v1

- Lệnh kiểm thử chính: `bash tests/super-board/test_merge_queue_e2e.sh`
- Đối chứng RED trên `origin/main` (`0a644f4e`): thoát `79` (`[github-read] HALT`, `issue_last_comment` gọi `issues/7/comments?per_page=1&page=1` rơi vào `unexpected` của `gh` giả)
- Kết quả GREEN trên PR #1409 (`b0389639`): thoát `0` (`42 ✔`, `0 ✖`, `✅ test_merge_queue_e2e: all passed`)
- Kiểm tra diff (AC2): `git diff origin/main...b0389639` chỉ thêm 5 dòng (`tests/super-board/test_merge_queue_e2e.sh:189-193`), 0 assertion bị xoá hay nới; audit Antigravity `T0001-audit-pr-1409` pass trên `b0389639`
- Giải trình AC3 (vì sao merge gate #1393 để lọt suite đỏ):
  - `scoped_gate.cap_selection` (`scoped_gate.py:982-1047`) chỉ giữ 1 test nhanh nhất/file đổi, đẩy `tests/super-board/test_merge_queue_e2e.sh` (`REG-SB-MERGE-QUEUE-E2E-01`) vào `deferred_to_heavy` (`.git/postfix-gate/scoped_receipts/5515fcd972db3d74344db89d.json`).
  - `[merge-train]` (`12:55:55`) và `[merge-gate #1393]` (`13:00:03`) đều chạy `post-fix-gate.py --scoped` (`merge_point=True`), dùng lại biên nhận `5515fcd972db3d74344db89d` và chỉ ép chạy 24 suite `[merge-guard]` trong `.agents/gate-core.txt` (`REG-SB-MERGE-QUEUE-E2E-01` không nằm trong `[merge-guard]`), nên suite không chạy trước khi merge (`cfd9197f`).
- Bảo mật: `pr-security-review: skipped (no code in diff)` (chỉ sửa file test).
- Giao diện / ảnh: không áp dụng (thay đổi thuần script test CLI).
