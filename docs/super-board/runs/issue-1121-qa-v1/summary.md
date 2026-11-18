# QA #1121 (PR #1169) v1

- Lệnh: `bash tests/super-board/test_account_failover.sh`
- Trên đầu PR: exit 0, ca 8d PASS (account tạm dừng ~1 giờ khi log có 402 Payment Required).
- Trên run.sh của origin/main: exit 1, `8d: 402 balance exhausted not recognised (resets_at='')` (RED).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass`.
- Test hiện có chỉ được thêm ca 8d, không nới assertion cũ.
