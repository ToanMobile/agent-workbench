# QA #1008 v6 — PR #1238 @ bcf70d3

- Lệnh: bash universal-agent-devkit/tests/gates/test_gate_scoped_same_tree_reuse.sh → exit 0 (XANH; ca g, h đều ✔)
- Oracle: đặt post-fix-gate.py của origin/main vào → exit 1, ca g ĐỎ (A=0, mong A=1); đã khôi phục file
- origin/main đã là tổ tiên của head (merge: Already up to date)
- Cổng scoped: post-fix-gate.py --run-tests --scoped --brief --json → exit 2; super-board-qa-exit2.sh in `review`
  (lý do duy nhất: test có sẵn bị sửa, chờ duyệt chéo)
- AC1 ✅ (lượt Stop sc=None void PASS cũ) · AC2 ✅ (HEAD/base/lệnh/merge-check khác ⇒ chạy lại)
