# QA #574 v1 — merge-gate giữ log verify đầy đủ

- Test: `bash tests/super-board/test_merge_gate_verify_log_outside.sh`
  - Gate của origin/main: exit 1 (FAIL 2) — RED
  - Gate của nhánh: exit 0 (PASS) — GREEN
- AC1 (.full.log giữ đủ Traceback nhiều dòng sau khi scratch bị xoá): PASS
- AC2 (verify xanh không để .full.log, xoá cả bản cũ): PASS
- Gate impacted `post-fix-gate.py --run-tests --brief`: 28/29, lớp tĩnh đạt.
  - Suite đỏ: REG-SB-MERGE-TRAIN-01 (`tests/super-board/test_merge_train.sh`), `✖ F4 no worker flag: exit 13`
  - Chạy lại với gate của origin/main: cùng đỏ `F4 no worker flag` — đỏ trên base, không do PR này.
