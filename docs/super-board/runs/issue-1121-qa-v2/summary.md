# QA v2 · issue #1121 · PR #1169 @ e25a844

Vòng rebuild 1: code không đổi, chỉ sửa block `sb:ac` của body PR.

- Lệnh: `bash tests/super-board/test_account_failover.sh` · exit 0 · ca 8a-8d PASS (8d: 402 balance exhausted tạm dừng account).
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` in `pass` (exit 0).
- Merge base: `origin/main` đã up to date.
- AC: 2/2 khớp block `sb:ac` của PR; không có ảnh (không phải UI).
