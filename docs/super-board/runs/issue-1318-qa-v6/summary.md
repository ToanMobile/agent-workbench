# QA v6 · #1318 · PR #1358 @ bb2b0a72
- Merge origin/main: Already up to date.
- RED: test_dependency_unblock_v1.sh bản main (không có stub worker_session_args) → exit 1 (FAIL).
- GREEN: bản PR → exit 0 (PASS, T1..T11).
- 8 file test đích của #1318/#1319/#1322 (clean_exit_progress, skill_rules_stuck_cards, merge_queue_rebase_not_capped, merge_queue_rebase_pure_cap, runner_read_halt_recover, runner_noop_worker, handed_to_qa_pushed, qa_apply_rollback) → mỗi file exit 0.
- Chưa kiểm: AC lượt board thật sau sync kit (#1320) và #1302 rebase (#1319).
