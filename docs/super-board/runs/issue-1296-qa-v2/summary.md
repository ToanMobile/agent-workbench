# QA #1296 v2 @ ac7b546 (sau rebuild)
- test_learn_worktree_root.sh: exit 0, 11 ca xanh (gồm 6 ca mới: project=worktree/cwd=main, record_lesson, repo khác, ngoài git)
- Mutant (bỏ worktree_root ở project_dir + record_lesson): 4 ✖ -> test bắt được
- test_learn.sh hồi quy: exit 0
- Gate: post-fix-gate --run-tests --scoped sau merge origin/main: pass (qa-exit2)
