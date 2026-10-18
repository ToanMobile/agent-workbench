# QA v2 — issue #12 (PR #87, head d00a619)
Chạy trong worktree sạch của nhánh; base = origin/main cb04be4 với CÙNG 3 file test.
| Suite | Base (ĐỎ) | Head (XANH) |
|---|---|---|
| tests/worktree_git/test_worktree_gc.sh | exit 1, 12 failed | exit 0, 57 ✔ |
| tests/worktree_git/test_worktree_sandbox.sh | exit 1, 33 errors | exit 0, 64 ✔ |
| tests/verification/test_red_proof.sh | exit 1, 1 failed | exit 0, 73 ✔ |
Không có ảnh: script CLI, không có giao diện.
