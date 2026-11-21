# QA Evidence · #1397 / PR #1407 (v2)

- **Head kiểm thử:** `58539b3d60af3b779c67bc1bfce9658882696ed2` (đã đối chiếu `origin/main` `0a644f4e`: already up to date)
- **Ảnh chụp màn hình:** bỏ qua có chủ đích (issue backend/runner không có UI)
- **Local tests (10 bộ mục tiêu + liên đới, exit 0):**
  - `bash tests/super-board/test_runner_review_wait_agent_1399.sh`: PASS (13/13)
  - `bash tests/super-board/test_merge_queue_rebuild_total_cap_1400.sh`: PASS (3/3)
  - `bash tests/super-board/test_runner_remove_assignee_no_halt_1397.sh`: PASS (9/9)
  - `bash tests/super-board/test_merge_queue.sh`: PASS
  - `bash tests/super-board/test_merge_queue_root_cause_cap.sh`: PASS
  - `bash tests/super-board/test_merge_queue_rebase_not_capped_1319.sh`: PASS
  - `bash tests/super-board/test_runner_cap_progress_sweep_1342.sh`: PASS
  - `bash tests/super-board/test_runner_review_antigravity_1390.sh`: PASS
  - `bash tests/super-board/test_runner_review_antigravity_1390_qa_gaps.sh`: PASS
  - `bash tests/super-board/test_issue671_review_wait_not_noop.sh`: PASS
- **Security pass (`pr-security-review`):** 0 findings (đã kiểm `eval` + `python3 -I`, `shlex.quote`, làm sạch biến/tham số và ranh giới marker comment)
- **Test-gap check:** 0 High gaps (8/8 AC có thể test trên PR đều đã có oracle chạy xanh; 3 AC hậu sync `ac-open`: AC3, AC8, AC11 giữ chưa tick).
  - Medium gaps (chưa viết, không chặn): `qa_apply_report` đếm/ghi `rebuild-total`, `rebuild_total_drop` khi PR merge, khẳng định `blocked-by:  -` ngay ở lần sweep thứ 3 trong 24h.
