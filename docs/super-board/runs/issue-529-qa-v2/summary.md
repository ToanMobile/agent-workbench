# QA v2 #529 (rebuild-1, head 75381a0f + merge origin/main)
- Lệnh: `bash tests/super-board/test_issue529_sweep_needs_you.sh` -> exit 0, PASS (ca 1, 1b, 2, 3/4, 5a, 5b, 6, 6b, 6c, 7, 7b, 8).
- R1 (reviewer bounce): ca 8 đã có; đột biến gỡ dòng `agentParked` ở super-board-wave-plan.sh -> ca 8 ĐỎ (`sweep = [9,10] (want [9])`), khôi phục -> XANH.
- Test cũ bị sửa (khớp AC5, đảo assert có chủ đích): test_runner_noop_worker.sh (chú thích), test_runner_reclaim_dead_build.sh (ca F: không còn `blocked-by:  -`), test_runner_preflight_swept.sh (stub needs-you.py). Tự duyệt.
- Không UI, không ảnh. Gate impacted chạy sau commit này.
