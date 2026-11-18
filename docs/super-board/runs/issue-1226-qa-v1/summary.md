# QA #1226 (PR #1227) v1
- Test mới `test_review_stall_head_reset_1226.sh`: exit 0 (A–C2 xanh). Trên base (script cũ): exit 1, A đỏ → ĐỎ→XANH.
- Test cũ `test_review_stall_blocked_1221.sh` (không sửa): exit 0 (A–E xanh).
- Gate `post-fix-gate.py --run-tests --scoped`: qa-exit2 = pass.
- Base origin/main đã merge: Already up to date.
