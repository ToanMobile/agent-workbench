# QA #781 v7 (head 075f0902 + merge origin/main)
- CI macOS run 42851172532 (devkit-tests) trên head 075f0902: success (49 phút, trần 90).
- Test cục bộ trên base đã merge, rc=0: test_pr_review_workflow, test_budgets, test_session_lock_trunk,
  test_prompt_hook_gate_env, test_evidence_log, test_gates_follow_session_worktree.
- post-fix-gate scoped: `review` (exit 2, chỉ vì có test có sẵn bị sửa).
