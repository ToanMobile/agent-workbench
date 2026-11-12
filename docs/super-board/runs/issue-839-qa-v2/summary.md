# QA v2 — #839 / PR #1093

Cây: head PR f9031b1b + merge origin/main 3a995cb7 (worktree QA tách rời).

| Lệnh | Exit | Kết quả |
|---|---|---|
| test_gate_since_trunk_merge.sh | 0 | 31 ca xanh, gồm ca 13 (foxtrot + gộp T + trả M0 ⇒ exit 1) và ca 1, 2, 11 (exit 0) |
| test_gate_since_new_test.sh | 0 | xanh |
| test_gate_since_test_edit.sh | 0 | xanh |
| RED: post-fix-gate.py của origin/main + cùng test | 1 | 7 dòng đỏ; đã khôi phục bản PR |
| post-fix-gate.py --run-tests --scoped --brief --json | qa-exit2 = pass | biên nhận scoped + task |

AC1 (ca 13 ĐỎ trên main, XANH sau): đạt. AC2 (ca 1, 2, 11 sau clone vẫn exit 0): đạt.
Log thô giữ ở /tmp/qa-agent-workbench-839-*.log, không commit.
