# QA #836 v3 — PR #1089

Head QA: gộp origin/main vào a63cce6f. Backend gate, không có ảnh.

- test_gate_since_renamed_weakened.sh: exit 0 (3/3)
- test_gate_renamed_test_edit.sh: exit 0
- test_gate_since_test_edit.sh: exit 0
- test_gate_since_new_test.sh: exit 0
- test_gate_since_trunk_merge.sh: exit 0
- test_gate_since_landed_base.sh: exit 0
- RED: cùng test với post-fix-gate.py của origin/main: exit 1
  (`flagged=no want yes, exit 0 want 2`)
