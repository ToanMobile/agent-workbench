# QA #1008 v1 (PR #1238 @ 50bc73d)
- Lệnh: bash universal-agent-devkit/tests/gates/test_gate_scoped_same_tree_reuse.sh
- Gate post-fix-gate.py của main: exit 1 (ĐỎ, ca g); gate của PR: exit 0 (XANH, ca g + h).
- AC1 (lượt Stop FAIL/chập chờn ⇒ void PASS cũ): ĐẠT. AC2 (HEAD/base/lệnh/merge-check khác ⇒ chạy lại): ĐẠT.
- Cổng scoped: `review` (test có sẵn bị sửa), chờ duyệt chéo Antigravity.
