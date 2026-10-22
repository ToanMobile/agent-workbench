# QA #227 vòng 2 · PR #239

- Lệnh: `bash tests/super-board/test_runner_review_approved_head.sh` → exit 0, "all passed" (13/13)
- Hồi quy liên quan: test preflight của runner (#253) vẫn ALL PASS sau khi gộp
- Đột biến: bỏ so sánh `approved = head` → test đỏ; khôi phục → xanh
- Xung đột với origin/main (`super-board-run.sh`: `review_approved_head` vs `preflight_gate`, hai hàm độc lập) → giữ cả hai
