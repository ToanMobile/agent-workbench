# QA #1003 v2 — head fe477f54 (đã chứa main b34b3f14)
- `bash tests/super-board/test_runner_lane_workers.sh` ⇒ exit 0, "all passed".
- Đột biến: đổi dòng khoá common dir của merge gate thành `then :` ⇒ test in "✖ merge gate lost its common-dir merge.lock"; đã khôi phục, tree sạch.
- Gate scoped (`post-fix-gate --scoped` qua super-board-qa-exit2.sh) ⇒ `review` (sửa một test có sẵn, chờ audit chéo).
- Không có ảnh: thay đổi chỉ là test shell, không hiện trên màn hình.
