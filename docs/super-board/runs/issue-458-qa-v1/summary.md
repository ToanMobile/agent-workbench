# QA #458 v1
- Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_worktree_remove_safety.sh` (nhánh đã merge origin/main)
- XANH: exit 0, "all checks passed"
- Đột biến (bỏ điều kiện held_only ở worktree.py): exit 1, check mới ĐỎ; đã khôi phục, không commit
- AC1: nhánh khác giữ HEAD + 1 commit chỉ-reflog → lời từ chối nêu reflog, không còn câu "không thuộc nhánh nào" (ĐỎ→XANH)
- AC2: commit không ref nào giữ → vẫn in câu cũ và vẫn chặn (XANH)
