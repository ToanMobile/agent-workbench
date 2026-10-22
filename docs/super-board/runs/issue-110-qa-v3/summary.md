# QA v3 · PR #182 · head b9bb7d86 (sau vòng sửa xung đột ma trận)

Lệnh: `bash tests/super-board/test_merge_train.sh` → exit 0, 20 kiểm tra ✔ (3 PR một lần verify; 1 PR đỏ chia đôi ra #5; 1 PR đi cổng thường; biên nhận sai cây vẫn verify; github-read 79 tới caller; timeout exit 12 không quy đỏ).
Lệnh: `git merge-tree --write-tree origin/main HEAD` → exit 0 (không xung đột; main 11:04).
Lệnh: `post-fix-gate.py --run-tests --full --diff origin/main --brief`
- Lần 1: REJECT 45/46, REG-DK-SESSION-01 đỏ (`--force-full not named`, máy tải ~58). PR không đụng file DevKit đó; `test_multi_session_gate.sh` chạy riêng: xanh.
- Lần 2: exit 0, 46/46.

AC1 3 PR một lần --full: đạt (test_merge_train ca 3 PR)
AC2 một PR đỏ → chia đôi: đạt (ca 1 red PR, culprit #5)
AC3 một PR như hiện tại: đạt (ca 1 PR)
AC4 gh giả ĐỎ→XANH: đạt (bằng chứng v1/v2; đột biến R1 đỏ ở v2)

Test gaps (not written, Medium, không chặn): R7 exit 11 của gate che exit 79/9 · R8 PR chỉ xung đột với PR đứng trước bị báo exit 5 · R9 thiếu `git cat-file -e` cho SHA ghim · R10 thiếu ca gate chặn giữa đợt / base dời / `git clean` ở lần thử lại.
Ảnh: không cần, script backend.
