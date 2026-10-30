# QA #473 v1 — head 35111455
Lệnh (trong universal-agent-devkit/), exit code:
- bash tests/verification/test_run_impacted.sh → 0 (có dòng progress start/done + oracle SIGPIPE)
- bash tests/verification/test_agent_kit_test_order.sh → 0 (A9b ✔)
- bash tests/gates/test_gate_robustness.sh → 0 (A18, A19 ✔)
Mutant: đảo thứ tự `record` và printf `· done` trong run_one → test_run_impacted ĐỎ
  "✖ run_one: no per-test cache record after SIGPIPE"; khôi phục → XANH.
Gate: post-fix-gate --run-tests --scoped --brief → exit 1, chỉ 2 suite đỏ:
  REG-SB-SETUP-BIN-01 (thiếu super-board-merge-cards.py), REG-SB-MERGE-TRAIN-01 (✖ F4 no worker flag: exit 13).
  Chạy lại trên bản export sạch origin/main: cả hai ĐỎ y hệt → đỏ trên base, không do PR này.
