# QA #1296 (PR #1324) v1
- test_learn_worktree_root.sh: exit 0, 5 ✔ (learn + record_lesson ghi vào worktree, main không đổi, main checkout vẫn ghi main)
- test_learn.sh (hồi quy): exit 0, all checks passed
- Mutant (bỏ worktree_root trong project_dir): exit 1, 3 ✖ → test bắt được lỗi
- post-fix-gate --run-tests --scoped (sau merge origin/main): pass (exit 0)
