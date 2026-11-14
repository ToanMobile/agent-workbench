# QA v3 #1102 (rebuild-2) — head fbf97080
- Lệnh: bash từng test; log ở /tmp/qa-agent-workbench-1102-*.log (ngoài nhánh). Merge origin/main: Already up to date.
- rc 0: test_session_lock_trunk_for_loop_1102 (cả R5), test_runner_agy_cwd_1102, test_lane_worktree_kit, test_qa_detached_worktree.
- rc 0: 5 test session_lock cũ (target_repo, issue427, round3_427, backlog427, resolve) + file_writes, grok_shell, trunk, trunk_generated_restore, trunk_reads, trunk_wrappers.
- RED: test mới chạy với session_lock.py của 923fe359 -> rc 1, 7 ca R5 đỏ (rc 0, muốn 2); hook mới rc 0.
- Probe tay 10 payload (read, t+=, IFS read -r, eval, declare, { read }, export, (( )), gán bằng $(..)) rc 2; đối chứng rc 0.
