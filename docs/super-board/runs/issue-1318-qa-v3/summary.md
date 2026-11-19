# QA v3 — PR #1340 @ 3d7405f9 (rebuild 2)

Lệnh: `bash tests/super-board/<file>.sh` từng file, sau `git merge origin/main`.
Kết quả: exit 0 cả 9 file.
- test_runner_clean_exit_progress_1318 (AC 1-3 #1318, gồm R1 thẻ qa Ready→QA, R4 regex Next)
- test_skill_rules_stuck_cards_1318 (AC skill/run.md #1318 #1319)
- test_merge_queue_rebase_not_capped_1319 (AC #1319, gồm R2)
- test_dependency_unblock_v1 (AC #1320; test cũ bị sửa)
- test_runner_read_halt_recover_1322 (AC #1322, gồm R3)
- test_runner_noop_worker, test_runner_watchdog, test_github_read_auto_reconcile, test_merge_queue
Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua qa-exit2 → `review`
(test cũ bị sửa: tests/super-board/test_dependency_unblock_v1.sh, chờ duyệt chéo Antigravity).
