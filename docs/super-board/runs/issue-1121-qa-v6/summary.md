# QA v6 — #1121 (PR #1169) @ 63d587e

- `bash tests/super-board/test_account_failover.sh`: exit 0, ca 8d PASS.
- `bash tests/super-board/test_runner_claim_loop.sh`: exit 0, ca 4e PASS.
- Với `super-board-run.sh` của origin/main: 8d ĐỎ (`resets_at=''`), 4e ĐỎ (`402 death still logged as early end or account not paused`).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` exit 0, `super-board-qa-exit2.sh` in `pass`.
- Log thô: /tmp/qa-agent-workbench-1121-*.log (không commit).
