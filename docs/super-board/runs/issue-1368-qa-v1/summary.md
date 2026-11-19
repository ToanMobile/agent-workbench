# QA #1368 (PR #1369) v1
- Lệnh: bash tests/super-board/test_review_blocked_by_dash_bounce_1350.sh, exit 0, 15 ✔ 0 ✖
- RED trên runner của origin/main: 5 ✖; GREEN trên head PR
- AC3: test_review_bounce_ready_1316, stall_blocked_1221, stall_head_reset_1226, runner_noop_worker đều exit 0
- Gate: post-fix-gate --run-tests --scoped, super-board-qa-exit2.sh in `pass`
