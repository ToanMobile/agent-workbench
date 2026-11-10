# QA #811 v1 (PR #1086, head 86430139)
- RED: test_suite_env_auto_merge.sh trên code cũ (origin/main) -> exit 1, 2 failed (suite_env giữ biến, clean_git_env giữ WORKTREE_AUTO_MERGE=0).
- GREEN: cùng test trên code PR -> PASS.
- AC1/AC2: với WORKTREE_AUTO_MERGE=0 export sẵn, 6 test worktree_merge_gate_{board_kept,conflict_advice,owner,subagent_live,trunk,vanished}.sh + test_worktree_merge_gate.sh đều PASS, không cần env -u.
- AC3: diff không đụng assertion của trunk/owner (chỉ thêm unset + drop env).
- Security pass: diff chỉ đổi env test/suite, không có đường vào từ ngoài, không secret.
