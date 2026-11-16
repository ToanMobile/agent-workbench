# QA v5 #1102 — PR #1173 @ f0460e1b (rebuild-4, R7 whitelist)
- test_session_lock_trunk_for_loop_1102.sh rc 0; test_runner_agy_cwd_1102.sh rc 0; test_lane_worktree_kit.sh rc 0; test_qa_detached_worktree.sh rc 0
- 16 test session_lock cũ (target_repo, issue427, round3_427, backlog427, resolve, session_lock, trunk, grok_shell, file_writes, trunk_wrappers, trunk_reads, trunk_generated_restore, gitdir_write, robust, readonly, worktree_hint) rc 0
- RED: test mới + hook cũ (af4ad725) rc 1, 7 ca R7 đỏ (for giả trong nháy, printf -v/declare với tên che bằng `$(..)`/nháy/`$'\x74'`); hook mới rc 0
- Probe tay 10 payload (read, printf -v, eval, cd, tee, `$'\x74'`, for giả trong nháy, `${t#a}`, `$(ls)`) rc 2; đối chứng rc 0
- Chưa làm: SessionStart một dòng (tuỳ chọn)
