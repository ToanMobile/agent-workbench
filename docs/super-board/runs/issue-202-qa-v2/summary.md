# QA v2 · #202 · PR #205 · vòng rebuild (builder 2a56538a)

Lệnh: `bash tests/super-board/test_runner_ready_order.sh` → exit 0, ALL PASS (17 ca, gồm R1–R4 của review vòng 1)
Đột biến (mỗi lần 1 dòng, rồi khôi phục): bỏ `-lt` (R3) → ĐỎ · bỏ `-e $REPO_ROOT/$owner` (R1) → ĐỎ · mở rộng mục Fix|Context sang Problem (R2) → ĐỎ
Test runner lân cận sau khi gộp main: lane_workers, lanes, build_workers, backlog_pull, claim_loop, disk_gc, reclaim_dead_build → exit 0
Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` → exit 0, hồi quy 49/49 (head 83ea2387)
Lượt gate trước đỏ vì: nhánh tụt sau main (2 suite lane), mục ma trận không ở cuối (exit 2), REG-DK-SESSION-01 chập chờn khi tải ~60 (chạy riêng pass)
Test gaps (not written): Medium — test_runner_build_workers.sh mất thư mục tạm khi chạy song song dưới tải cao (flaky có sẵn trên main, ngoài PR này)
Ảnh: không cần — đổi script runner, không có UI
