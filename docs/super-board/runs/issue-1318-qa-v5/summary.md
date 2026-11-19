# QA v5 — issue #1318, PR #1340 @ ba5dda83 (origin/main đã có sẵn, không cần merge)

Lệnh: `bash tests/super-board/test_<file>.sh` (mỗi file một lần). Kết quả: 12/12 exit 0.

- runner_clean_exit_progress_1318, runner_handed_to_qa_pushed_1318: PASS
- runner_qa_apply_head_unknown_1318 (finding 1 của audit: fail-open): PASS
- runner_qa_apply_rollback_1318, runner_read_halt_recover_1322: PASS
- skill_rules_stuck_cards_1318: PASS
- merge_queue_rebase_not_capped_1319, merge_queue_rebase_pure_cap_1318, merge_queue_rebase_pure_ledger_1318 (finding 2 của audit): PASS
- dependency_unblock_v1, merge_queue, runner_noop_worker: PASS

Cổng: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` in `review` (rc 0).
Lý do: test cũ bị sửa `tests/super-board/test_dependency_unblock_v1.sh` cần Antigravity duyệt chéo.
Chưa kiểm được: AC lượt board thật sau merge + sync kit (#1319, #1320).
