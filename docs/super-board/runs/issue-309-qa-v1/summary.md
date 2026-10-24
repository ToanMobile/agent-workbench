# QA #309 v1 — merge-tree không để lại .merge_file_*

- AC1 RED (worktree.py của origin/main): `test_worktree_merge_tree_no_leak.sh` exit 1, "killed merge-tree left 3 .merge_file_* file(s)".
- AC1 GREEN (nhánh PR, e27c955d): cùng test exit 0, 6/6 ✔.
- AC2: driver chạy kịp → `_adds_nothing_to_main` vẫn True (✔ cả hai phía RED/GREEN).
- AC3: rule REG-DK-MERGE-TREE-NOLEAK-01 nằm CUỐI ma trận; `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` exit 0, 68/68.
- Cú pháp: bash -n (merge-gate, proof_gate), py_compile worktree.py đều OK.
- AC4: chỉ kiểm được sau merge (một ngày board chạy) — chưa kiểm.
