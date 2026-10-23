# QA #228 v1 (PR #295)
- Gate: `post-fix-gate.py --run-tests --full --force-full --diff origin/main` → PASS, 64/64 test hồi quy (trên nhánh đã merge origin/main).
- `tests/super-board/test_runner_review_merge_train.sh`: exit 0 (xanh).
- `tests/super-board/test_merge_train.sh`: exit 0 (xanh).
- Mutant: đảo công tắc `SB_REVIEW_TRAIN` (super-board-run.sh:933) → test đỏ, 10 lỗi; khôi phục → xanh.
- AC1 xanh, rule cuối ma trận · AC2 3 thẻ → `--prs 70,71,72`, 1 lần verify · AC3 PR đỏ tách ra (`test_merge_train.sh`) · AC4 gate exit 0, diff +214/−6.
