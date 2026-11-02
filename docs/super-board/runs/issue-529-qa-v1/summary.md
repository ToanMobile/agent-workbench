# QA #529 v1 — PASS (không có UI, không ảnh)

Head đã merge origin/main (ab9d89fc) trước khi test.

- `bash tests/super-board/test_issue529_sweep_needs_you.sh` → exit 0, PASS 11/11 ca (1, 1b, 2, 3/4, 5a, 5b, 6, 6b, 6c, 7, 7b)
- Test cũ bị sửa, chạy lại exit 0: test_runner_noop_worker, test_runner_preflight_swept, test_runner_reclaim_dead_build
- Đột biến AC1 (deps.sh: bullet lại bắt buộc) → ca 1 ĐỎ ("bare numbers unreadable"), khôi phục → XANH
- `post-fix-gate.py --run-tests --brief --auto-approve-tests` → exit 0, 34/34
- AC8: diff không chứa bộ đọc decision (#516)

Test cũ sửa, agent tự duyệt: test_runner_noop_worker.sh (chỉ comment), test_runner_reclaim_dead_build.sh
(assert F đổi sang `! blocked-by:  -`, đúng AC5).

Test gaps (không viết): ca 6 chỉ chạy lane build; lane qa dùng chung nhánh code nhưng chưa có ca riêng.
