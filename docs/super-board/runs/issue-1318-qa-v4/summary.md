# QA v4 — issue #1318, PR #1340 @ b9527197 (đã merge origin/main 1f7b15e2)

Lệnh: `bash tests/super-board/test_<file>.sh` (mỗi file một lần). Kết quả: cả 12 file in PASS / all passed.

- runner_clean_exit_progress_1318 (AC1, AC2, thẻ qa Ready→QA): PASS
- runner_handed_to_qa_pushed_1318 (#1295 kiểm push): PASS
- runner_qa_apply_rollback_1318: PASS
- skill_rules_stuck_cards_1318 (AC4, AC5 ghim câu skill/run.md): PASS
- merge_queue_rebase_not_capped_1319, merge_queue_rebase_pure_cap_1318 (AC rebase vs cap): PASS
- dependency_unblock_v1 (AC #1320): PASS
- runner_read_halt_recover_1322 (AC 504 ×3): PASS
- runner_noop_worker (AC3, thoát không comment vẫn Blocked ❓): PASS
- runner_watchdog, github_read_auto_reconcile, merge_queue: PASS

Không phải test cũ bị sửa trong lượt này. AC cần lượt board thật sau merge (#1319, #1320) chưa kiểm được ở QA.
