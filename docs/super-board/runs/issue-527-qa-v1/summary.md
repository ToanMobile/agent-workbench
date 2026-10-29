# QA #527 v1 — worktree finish không bỏ gate khi mất ma trận

Base: origin/main đã merge vào nhánh (head PR 0f100fce).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash universal-agent-devkit/tests/worktree_git/test_worktree_trunk_merge.sh` (code PR) | 0 | PASS, gồm ca 17, 18 |
| cùng test, `worktree.py` của origin/main | 1 | FAIL (2): ca 17 "deleted matrix file skipped the gate (rc 0)", ca 18 "DevKit repo without a matrix merged ungated (rc 0)" |
| `bash universal-agent-devkit/tests/worktree_git/test_worktree_automerge.sh` | 0 | all checks passed |
| `post-fix-gate.py --run-tests --brief` (impacted) | 0 | PASS, hồi quy 13/13 |

AC1 (blocked khi HEAD không có ma trận): ca 18. AC2 (xoá file ở working tree vẫn gate): ca 17. AC3 (đỏ trước, xanh sau): bảng trên.
