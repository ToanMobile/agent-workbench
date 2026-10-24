# QA #323 v2 (PR #349, sau khi #301 tách sang #356)

Lệnh: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` trên cây đã gộp origin/main (8930cfc6) → exit 0, test hồi quy 85/85, lớp tĩnh đạt.

RED→GREEN từng thẻ con: giữ nguyên bằng chứng v1 (docs/super-board/runs/issue-323-qa-v1/summary.md); nhánh không đổi mã nguồn kể từ v1, chỉ gộp main.
- #157 #234 #262 #326: RED trên mã main, GREEN trên nhánh. #302: GREEN 3/3. #327: đã vào main (#350).
- #301: tách sang #356, đã bỏ khỏi AC của #323 → không còn AC chưa đạt.

Test đã có bị sửa (agent tự duyệt): test_worktree_discard_squash.sh (#326, bám đúng thông báo chặn).
Ảnh nghiệm thu: không cần (profile backend, không có màn hình).
Lưu ý cho Reviewer: #262 chạm cổng duyệt của người (merge-gate) → cần Reviewer độc lập.
