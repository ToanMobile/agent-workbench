# QA #1302 @ 47281aeb
- `bash tests/super-board/test_qa_head_settle_1302.sh`: exit 0, PASS (tất cả ✔, gồm AC1 rerun khi head đổi và AC2 Blocked sau N lần).
- Đột biến `-ge`→`-gt` ở super-board-qa-head.sh: test exit 1 (ĐỎ), đã khôi phục.
- `post-fix-gate.py --run-tests --scoped --brief --json` qua super-board-qa-exit2.sh: `pass` (exit 0).
- `super-board-qa-head.sh --sha 47281aeb`: exit 0 (current).
