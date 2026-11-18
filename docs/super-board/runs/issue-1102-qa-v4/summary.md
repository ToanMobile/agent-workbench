# QA v4 #1102 — PR #1173 @ af4ad725 (rebuild-3, R6a–e)
- test_session_lock_trunk_for_loop_1102.sh rc 0; test_runner_agy_cwd_1102.sh rc 0; test_lane_worktree_kit.sh rc 0; test_qa_detached_worktree.sh rc 0
- 13 test session_lock cũ (target_repo, issue427, round3_427, backlog427, resolve, trunk, grok_shell, file_writes, session_lock, trunk_wrappers, trunk_reads, trunk_generated_restore, shell_writes_fd_427) rc 0
- RED: test mới + hook cũ (eb74c267) rc 1, 4 ca đỏ (R6a `{ . file; }`, R6c `_`, `PWD`, `REPLY`); hook mới rc 0
- Probe tay 13 payload (gán lại t, ${t:-b}, ${t=b}, cd, eval, for t;, ln, dùng t sau done, $(ls), glob, subshell, read, tee) rc 2; đối chứng rc 0
- Chưa làm: SessionStart một dòng (tuỳ chọn)
