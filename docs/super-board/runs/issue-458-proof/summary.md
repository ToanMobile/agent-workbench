# #458 — bằng chứng AC (PR chứng minh, fix đã vào main ở #493)

Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_worktree_remove_safety.sh`

- Có fix (origin/main 0a535f1f): exit 0, "all checks passed".
  - AC1: `✔ held HEAD + reflog-only commit: still refused for the reflog-only commit` và `✔ held HEAD: the refusal no longer says its commits are on no branch`
  - AC2: `✔ unheld detached commit: still refused with the 'on no branch' sentence`
- Bỏ fix (hoàn nguyên worktree.py của #493): exit 1, "1 FAILED":
  - `✖ held HEAD: false 'on no branch' sentence` (lời từ chối vẫn in "1 commit(s) on no branch")
- Khôi phục fix: XANH lại.
