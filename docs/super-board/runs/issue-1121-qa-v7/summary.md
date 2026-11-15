# QA v7 #1121 — head code 63d587ee (origin/main đã nằm trong nhánh)
- `bash tests/super-board/test_account_failover.sh`: exit 0, ca 8d PASS.
- `bash tests/super-board/test_runner_claim_loop.sh`: exit 0, ca 4e PASS.
- Với `super-board-run.sh` của origin/main: cả hai exit 1 (`8d ... resets_at=''`, `402 death still logged as early end`) nên test bắt đúng lỗi 402.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` in `pass` (exit 0).
- Không có ảnh (không phải UI).
