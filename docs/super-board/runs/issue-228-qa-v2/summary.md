# QA #228 v2 (PR #295, head e0c54c2c + merge origin/main)
- Gate: `post-fix-gate.py --run-tests --full --force-full --diff origin/main` → PASS, 68/68 test hồi quy (cây đã merge origin/main).
- `tests/super-board/test_runner_review_merge_train.sh`: exit 0 (xanh).
- `tests/super-board/test_merge_train.sh`: exit 0 (xanh).
- Mutant: `super-board-run.sh:960` đổi `!= "0"` → `== "0"` → test đỏ (exit 1, 13 dòng lỗi); khôi phục → xanh, cây sạch.
- AC1 xanh, rule nối cuối ma trận · AC2 3 thẻ → 1 lần verify, 3 PR merge · AC3 PR đỏ tách ra, PR còn lại merge · AC4 gate exit 0, diff +306/−15 (<400 dòng).
- Ảnh: không cần — backend, không lên màn hình.
