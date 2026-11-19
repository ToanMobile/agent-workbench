# QA v2 — #1318 / PR #1340 @ 10b74573 (rebuild 1)
Lệnh: `bash tests/super-board/<file>.sh` từng file, base origin/main đã mới nhất (merge: Already up to date).
Kết quả (exit 0, tự chạy): test_runner_clean_exit_progress_1318, test_skill_rules_stuck_cards_1318,
test_merge_queue_rebase_not_capped_1319, test_dependency_unblock_v1, test_runner_read_halt_recover_1322,
test_runner_noop_worker, test_merge_queue, test_runner_watchdog, test_merge_queue_root_cause_cap,
test_merge_queue_gate_exit_14.
Đã đối chiếu blocker v1: merge-queue.sh:312 chỉ miễn cap với `rebase-pure`; run.sh qa_apply_report bỏ báo cáo @ sha khác head PR.
Gate `post-fix-gate --run-tests --scoped --brief --json` qua qa-exit2.sh: `review` (test cũ bị sửa: tests/super-board/test_dependency_unblock_v1.sh), không đỏ.
Chưa kiểm: AC lượt thật sau merge/sync (#1319, #1320, #1322).
