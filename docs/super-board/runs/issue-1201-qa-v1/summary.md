# QA #1201 / PR #1208 @ 994dafd8
- test_worktree_gc_squash_pr.sh: exit 0, 8/8 ca xanh (ca 1-5, 7-9); FAILS=0
- RED: worktree.py của origin/main + cùng test: FAILS=4 (rc 1)
- Test cũ xanh: gc, gc_merged, gc_stale_remote_ref, remove, remove_reflog_squash, discard, prune_ancestor_of_merged
- AC5 (chạy thật không dry-run) chưa chạy: xoá worktree/branch thật, cần chủ repo
