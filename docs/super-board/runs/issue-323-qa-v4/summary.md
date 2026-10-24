# QA v4 · PR #349 · head ee4cf59e + gộp origin/main
Lệnh: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 90/90.
R1 (#262 biên nhận head): `test_merge_gate_approved_head_second_run.sh` XANH; mutant tắt dòng ghi biên nhận (merge-gate.sh:477) → ĐỎ (rc=1), đã khôi phục.
R2: test biên shell ở trên + `test_approval_auto_merge_head.py` 5/5 XANH.
R3: `test_merge_gate_scratch_agents_clean.sh` XANH, đã nằm trong ma trận (regression_matrix.active.json:1340).
Không có AC đỏ. #301 đã tách sang #356.
