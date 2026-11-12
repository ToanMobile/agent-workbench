# QA #811 v8 — head 362da3db

Lệnh: `WORKTREE_AUTO_MERGE=0` export sẵn, không dùng `env -u`.

| Kiểm tra | Exit |
|---|---|
| test_suite_env_auto_merge.sh | 0 (2 ca ✔) |
| test_worktree_merge_gate.sh + 6 test `worktree_merge_gate_*` | 0 (7/7) |
| RED: post-fix-gate.py + clean_git_env.sh của origin/main, test mới | suite_env exit 1 (2 ca ✖); conflict_advice exit 1 (4 failed) |
| post-fix-gate.py --run-tests --scoped --brief --json qua super-board-qa-exit2.sh | `pass`, exit 0 |

Diff sản phẩm: 3 dòng (post-fix-gate.py suite_env bỏ biến; clean_git_env.sh thêm unset).
Assertion `_trunk` / `_owner` không đổi. Không UI, không ảnh.
