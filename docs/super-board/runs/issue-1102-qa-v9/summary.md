# QA #1102 v9 (PR #1173, head e9dc1ab, đã merge origin/main)
- 9 test đích (for_loop_1102, runner_agy_cwd_1102, lane_worktree_kit, qa_detached_worktree, 5 test session_lock cũ): rc 0 cả 9.
- 8 ca vượt tự viết thêm (redirect thứ hai, >>, tee, sau done, sed -i, cp, nền &): đều exit 2; mẫu QA thật /tmp/q-$t.log exit 0.
- Gate: xem comment [qa] [report].
