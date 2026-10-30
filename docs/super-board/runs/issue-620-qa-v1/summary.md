# QA v1 — #620 (PR #636)

- RED trên mã gốc (origin/main): `test_merge_train_single_test_retry.sh` đỏ 2 ca dedupe; `test_instincts_archive.sh` đỏ "stale pre-edit text".
- GREEN trên nhánh: cả hai xanh (exit 0).
- `test_merge_train.sh`: exit 0 khi bỏ SB_BOARD_WORKER (F4 đỏ oan nếu biến này rò vào, #528).
- Gate `post-fix-gate.py --run-tests --brief`: exit 0, 10/10.
