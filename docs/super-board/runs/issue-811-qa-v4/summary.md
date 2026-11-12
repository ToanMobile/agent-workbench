# QA #811 v4 — PR #1086 head 8098dc77

Chạy độc lập, `WORKTREE_AUTO_MERGE=0` export sẵn, không dùng `env -u`.

- AC1: `test_suite_env_auto_merge.sh` exit 0. RED: bin/post-fix-gate.py + tests/lib/clean_git_env.sh của origin/main thì `test_suite_env_auto_merge` exit 1 ("clean_git_env keeps WORKTREE_AUTO_MERGE=0", 2 ca đỏ) và `test_worktree_merge_gate_conflict_advice` exit 1.
- AC2: `test_worktree_merge_gate.sh` + 6 test `test_worktree_merge_gate_{board_kept,conflict_advice,owner,subagent_live,trunk,vanished}.sh` đều exit 0 (8/8 cùng test_suite_env_auto_merge).
- AC3: diff chỉ thêm `unset` ở clean_git_env.sh (+2), bỏ biến khỏi suite_env ở post-fix-gate.py (3 dòng), thêm test mới; assertion trunk/owner không đổi, vẫn exit 0.
- Gate scoped `post-fix-gate.py --run-tests --scoped --brief`: exit 0, 5/5 test hồi quy, lớp tĩnh đạt.
- Ảnh: không cần, thay đổi chỉ chạm tooling/test.
