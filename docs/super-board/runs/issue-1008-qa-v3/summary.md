# QA #1008 v3 · PR #1238 @ 2f786c8d (đã chứa origin/main 484f4d6a)

- Test: bash universal-agent-devkit/tests/gates/test_gate_scoped_same_tree_reuse.sh · exit 0 · ca g, h đều ✔.
- Oracle: đặt post-fix-gate.py của origin/main vào ⇒ exit 1 (ca g ĐỎ); khôi phục bản PR ⇒ cây sạch.
- Gate scoped: post-fix-gate.py --run-tests --scoped --brief --json qua super-board-qa-exit2.sh ⇒ `review` (chỉ vì test có sẵn bị sửa: test_gate_scoped_same_tree_reuse.sh).
- AC1 ✅ lượt Stop sc=None void PASS cũ · AC2 ✅ HEAD/base/lệnh/merge-check khác ⇒ chạy lại.
