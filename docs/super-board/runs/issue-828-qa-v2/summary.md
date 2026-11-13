# QA #828 vòng 2 — head cde48b85

- R1/R3: test mục tiêu xanh ở head (index thiếu, symlink, hook xoá biến thừa kế).
- R2: thêm ca `git commit -- <path>` thật qua hook thật (post-fix-gate thay bằng stub chạy agent-health, bỏ GIT_INDEX_FILE như suite_env).
- Mutation: bỏ dòng `export DEVKIT_PRECOMMIT_INDEX` trong git-pre-commit.sh thì test ĐỎ ("committed kit file was reported (R2)"); khôi phục thì XANH.
- Gate: `post-fix-gate.py --run-tests --scoped --brief` PASS.
- Không phải UI, không có ảnh.
