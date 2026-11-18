# QA v5 — #1121 (PR #1169) @ f5bba93

- `bash tests/super-board/test_account_failover.sh`: exit 0, ca 8d PASS.
- `bash tests/super-board/test_runner_claim_loop.sh`: exit 0, ca 4e PASS.
- Với `super-board-run.sh` của origin/main: 4e ĐỎ (`402 death still logged as early end or account not paused`), 8d ĐỎ (`resets_at=''`).
- origin/main đã nằm trong nhánh (Already up to date).
- Log thô: /tmp/qa-agent-workbench-1121-*.log (không commit).
