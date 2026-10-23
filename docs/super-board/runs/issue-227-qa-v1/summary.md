# QA #227 v1 — thẻ Review đã duyệt head X chỉ chạy lại merge gate

Lệnh: `bash tests/super-board/test_runner_review_approved_head.sh` → exit 0, 13/13 ✔
RED: runner của origin/main → exit 1, 6 ca ✖ (không có merge-only).
Đột biến 1 (bỏ so sánh sha approved = head): 2 ca đỏ (duyệt cũ, duyệt mới hơn).
Đột biến 2 (bỏ lọc authorAssociation): 2 ca đỏ (NONE, CONTRIBUTOR).
Khôi phục: test xanh lại.
Gate: `post-fix-gate.py --run-tests --full --diff origin/main --brief` → exit 0, hồi quy 52/52 (sau khi merge origin/main vào nhánh).
Ảnh: không cần — đổi runner shell/docs, không có màn hình.
