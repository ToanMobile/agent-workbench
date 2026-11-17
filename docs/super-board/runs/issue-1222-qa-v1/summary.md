# QA #1222 v1 (PR #1223, head b1b63c00)
- Lệnh: bash tests/super-board/<test>.sh (5 file), trên head đã merge origin/main (Already up to date)
- test_card_done_closed_ac_open (A,B), test_runner_closed_card_acopen (C,D), test_card_done_ac_open, test_runner_reconcile_ac_open, test_route_pr_issue_ac: rc=0 cả 5
- ĐỎ trên script của origin/main: ca A, C, D ĐỎ (rc=1); ca B (thẻ MỞ vẫn bị từ chối) xanh cả hai bên
- post-fix-gate --run-tests --scoped --brief --json qua super-board-qa-exit2.sh: pass
- AC1 = ca A, AC2 = ca B, AC3 = ca D (dispatch_lane bỏ qua issue CLOSED)
