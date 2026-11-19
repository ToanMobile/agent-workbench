# QA #1318 (PR #1340) v1
Head: 83a91c43 (origin/main merged: already up to date)
Test per file (bash tests/super-board/<file>), all exit 0:
- test_runner_clean_exit_progress_1318.sh PASS (A,A2,B,B2,C,C2,C3,D,E,F)
- test_skill_rules_stuck_cards_1318.sh PASS (6)
- test_merge_queue_rebase_not_capped_1319.sh PASS
- test_dependency_unblock_v1.sh PASS
- test_runner_read_halt_recover_1322.sh PASS (A-E)
- test_runner_noop_worker.sh PASS
- test_merge_queue.sh PASS
- test_runner_watchdog.sh PASS (watchdog existing, unchanged)
Gate: post-fix-gate --run-tests --scoped --brief --json | super-board-qa-exit2.sh -> review
Reason: existing tests edited (test_merge_queue.sh, test_dependency_unblock_v1.sh) -> await cross-review.
Not verifiable in QA: the 2 live-run ACs (after merge/sync).
