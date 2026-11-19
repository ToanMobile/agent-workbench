# QA #1311 v6 — PR #1312 head 02470b82

- Head `02470b82` đã chứa `origin/main` `55b735ba` (`git merge --no-edit origin/main`: Already up to date).
- Target tests: `test_github_read_rate_limit_backoff.sh` (14/14 rc=0), `test_rate_limit_69_train_queue_1311.sh` (12/12 rc=0), `test_merge_queue_route_rows.sh` (rc=0), `test_queue_ac_autofix_1310.sh` (rc=0).
- RED trên `origin/main` (`55b735ba`): `test_github_read_rate_limit_backoff.sh` rc=1 (11 failed), `test_rate_limit_69_train_queue_1311.sh` rc=1 (11 failed).
- Hồi quy tác động (13/13 hạng mục của gate + bổ sung): `test_github_read.sh` rc=0, `test_runner_watchdog.sh` rc=0, `test_merge_train.sh` rc=0, `test_merge_queue.sh` rc=0, `test_approval_cross_review.py` (37/37 rc=0), `test_card_done_ac_open.sh` + `test_runner_reconcile_ac_open.sh` + `test_preflight_ac_open.sh` rc=0, `agent-office` unittest (222 tests, 1 skipped, rc=0), `cc-switcher-mcp` `npm test` (142/142 rc=0), `run_impacted.sh` rc=0, `test_github_read_reconcile.sh` rc=0, `test_card_items_count_retry.sh` rc=0, `test_merge_queue_e2e.sh` rc=0, `test_runner_board_read_retry.sh` rc=0.
- Security pass (`pr-security-review`): 0 high-confidence findings.
- Cổng `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `review` (exit 2 — test đã có bị sửa: `tests/super-board/test_merge_queue_route_rows.sh`).
- Ảnh: không cần, chỉ đổi script và test, không có UI.
