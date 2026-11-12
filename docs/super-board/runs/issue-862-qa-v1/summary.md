# QA #862 v1 — PR #1128 @ 476268e5

Cách chạy: `bash universal-agent-devkit/tests/<nhóm>/<test>.sh` trên PR; RED = cùng test trên bản sao `origin/main` (code gốc).

| Test | Trên PR | Trên code gốc |
|---|---|---|
| context_memory/test_session_lock_trunk_generated_restore.sh | exit 0 | exit 1 |
| gates/test_gate_full_schedule_weekdays.sh | exit 0 | exit 1 |
| worktree_git/test_mark_stale_ignored_proof.sh | exit 0 | exit 1 |
| worktree_git/test_worktree_automerge_head_moved.sh | exit 0 | exit 1 |
| worktree_git/test_worktree_discard_merged_pr_bookkeeping.sh | exit 0 | exit 1 |
| worktree_git/test_worktree_remove_big_ignored.sh | exit 0 | exit 1 |
| context_memory/test_session_lock_trunk.sh (AC4) | exit 0 | - |
| gates/test_worktree_merge_gate_owner.sh (AC3) | exit 0 (lần 1 lỗi Errno 35: máy hết tiến trình 3865/4000; chạy lại khi tải giảm: PASS) | - |

Security pass: 0 phát hiện đủ chắc chắn (`_trunk_generated_restore` chỉ khôi phục đúng file đã khai báo, từ chối mọi cú pháp shell/option).
