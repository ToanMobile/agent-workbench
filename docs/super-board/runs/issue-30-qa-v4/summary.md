# QA v4 — issue #30 (rebuild-3, head c327aae3)

Lệnh: `bash universal-agent-devkit/tests/verification/test_governance_cleanup_fold_intent.sh` → exit 0, 11/11.

Đột biến R6/R7 (khôi phục bằng bản sao, cây sạch sau đó):
- `is_state` luôn False → đỏ 2 ca (age pass xoá `approved_x.json`; mất `worktree_merge_gate.state`, `proof_gate.state`, `.testsourceset_attempts_s1`).
- marker pass thêm `*.state` → đỏ 1 ca (mất `idle_worktree_merge_gate.state`, `idle_proof_gate.state`).
- Khôi phục → xanh 11/11.

AC1: bản sao thư mục audit-gate thật (`cp -Rp`, mtime giữ nguyên) 14056 KB → 3436 KB (du) sau
`devkit_clean --days=7 --apply --keep-state` (1230 mục); chạy lần 2: 0 mục, không đổi.
R6: `foreign_repo_gate.state`, `proof_gate.state`, `worktree_merge_gate.state`, `*.json` (3) còn nguyên.
Mọi tên file thật trong audit-gate khớp một mẫu marker, một mẫu state, hoặc là log/lock/thư mục.
AC2: fold chạy lặp, sửa nguồn, xoá dòng → không phình AGENTS.md. AC3: tên intent đúng.

Chưa chạy `--apply` trên thư mục audit-gate thật (chỉ bản sao).
