# QA #1234 v1 — PASS
- test_worktree_remove_save_reflog.sh (A1,A2,B,C,D + ca E mới): rc=0
- test_sweep_closed_save_reflog_1234.sh (E,F1,F2): rc=0
- Test sẵn có (sweep_1232, discard_squash, sandbox, post_merge_clean, dropped_cards): rc=0
- Đột biến (waive = True vô điều kiện): ca E ĐỎ (rc=0, gỡ mất commit thật) → ca E phân biệt được; B, C vẫn bị chặn bởi blocker khác
- post-fix-gate --run-tests --scoped: pass (exit 0)
