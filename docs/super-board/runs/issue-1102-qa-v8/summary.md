# QA v8 · #1102 · PR #1173 @ 562b383 (rebuild-6, R9)
- Test thẻ: test_session_lock_trunk_for_loop_1102.sh, test_runner_agy_cwd_1102.sh, test_lane_worktree_kit.sh, test_qa_detached_worktree.sh: rc 0.
- 14 test session_lock cũ (universal-agent-devkit/tests/context_memory): rc 0.
- Probe 24 payload bằng hook thật (=ls, `|`, `&>`, `2>`, tee, dd of=, sed -i, cd/subshell, git checkout, vòng thứ hai, `$t` sau done, `${t}`): đúng rc, ca đối chứng rc 0.
- Lỗ hổng cũ còn lại (ngoài AC): lệnh `link` (hardlink) thiếu trong `_MAKES_PATH`.
- Gate scoped: xem comment [qa] [report].
