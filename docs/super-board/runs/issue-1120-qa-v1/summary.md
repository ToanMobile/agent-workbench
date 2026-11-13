# QA #1120 v1
- RED trên base (origin/main runner): test_worker_limit_payment_402.sh exit 1 ("402 balance exhausted not recorded")
- GREEN trên PR: test_worker_limit_payment_402.sh exit 0; test_account_failover.sh exit 0 (8a/8b/8c không hồi quy)
- Gate: post-fix-gate --run-tests --scoped --brief --json qua super-board-qa-exit2.sh = pass
- Merge origin/main: Already up to date
