# QA v4 — #1121 (PR #1169, head 9e3551c5, origin/main đã merge, up to date)
- `bash tests/super-board/test_account_failover.sh` → exit 0, ca 8d PASS (log 402 nguyên văn của #838).
- `bash tests/super-board/test_runner_claim_loop.sh` → exit 0, ca 4e PASS (402 → account tạm dừng, không ghi `early end`; cờ không rò sang lock kế).
- ĐỎ: với `super-board-run.sh` của origin/main, test_runner_claim_loop exit 1: `✖ 402 death still logged as early end or account not paused (#1121)`.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `review` (exit 2): test có sẵn bị sửa (chỉ thêm ca 8d, 4e), chờ Antigravity cross-review.
- Không UI, không ảnh.
