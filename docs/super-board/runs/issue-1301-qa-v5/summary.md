# QA #1301 v5 — head 732e40a1 (đã chứa origin/main)
- test_review_gate_round_cap.sh: exit 0, C1–C8 xanh (đủ ca C8.1–C8.5).
- RED: cùng test trên hook của origin/main: exit 1, 6 ca đỏ (C1, C6 x3, C8.3, C8.4).
- 13 test test_review_gate*.sh: đều exit 0.
- post-fix-gate --run-tests --scoped --brief --json qua super-board-qa-exit2.sh: pass (exit 0).
- Log thô: /tmp/qa-agent-workbench-1301-*.log (ngoài nhánh).
