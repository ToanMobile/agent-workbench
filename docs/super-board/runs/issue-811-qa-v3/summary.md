# QA #811 v3 (PR #1086, head 58041af9)
- Lệnh: WORKTREE_AUTO_MERGE=0 bash tests/gates/<test>.sh (không dùng env -u).
- RED: test_suite_env_auto_merge.sh với post-fix-gate.py + clean_git_env.sh của origin/main -> exit 1, 2 ca đỏ (suite_env giữ biến; clean_git_env giữ WORKTREE_AUTO_MERGE=0).
- GREEN: cùng test trên head PR -> exit 0.
- AC2: test_worktree_merge_gate + 6 test _board_kept/_conflict_advice/_owner/_subagent_live/_trunk/_vanished -> 8/8 exit 0.
- AC3: diff chỉ thêm unset + bỏ biến khỏi suite_env; assertion trunk/owner không đổi.
- Bảo mật: chỉ đổi env test/suite, không secret, không đường vào ngoài.
- Gate scoped: xem comment [qa] [report].
