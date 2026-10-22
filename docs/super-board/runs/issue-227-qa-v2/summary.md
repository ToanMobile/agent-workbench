# QA #227 vòng 2 · PR #239

- Lệnh: `bash tests/super-board/test_runner_review_approved_head.sh` → exit 0, "all passed"
- Hồi quy gần: test preflight của runner (#253) vẫn ALL PASS sau khi gộp
- Đột biến: bỏ so sánh `approved = head` → 2 ca đỏ (duyệt cũ, duyệt cũ hơn); khôi phục → xanh
- Xung đột với origin/main trong `super-board-run.sh` (`review_approved_head` và `preflight_gate`, hai hàm độc lập) → giữ cả hai
