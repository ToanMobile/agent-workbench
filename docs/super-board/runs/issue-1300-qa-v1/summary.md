# QA #1300 (PR #1307) v1: PASS

Đầu PR d1355bb1; main đã được gộp (Already up to date).

| Lệnh | Kết quả |
|---|---|
| bash tests/super-board/test_qa_report_redos_timeout.sh | ALL PASS (32000 x `a.` 0 s, vẫn exit 1 khi nêu AC, gate checker treo exit 7 sau 3 s, quét names_ac 1 s) |
| bash tests/super-board/test_qa_report_cross_repo_ac.sh | PASS |
| bash tests/super-board/test_merge_gate_qa_report.sh | ALL PASS |
| bash tests/super-board/test_merge_gate_qa_report_issue_decision.sh | ALL PASS |
| post-fix-gate.py --run-tests --scoped --brief --json | exit 0, 3/3 hồi quy, core-touched, không sửa test cũ |

RED độc lập: regex cũ trên `a.` x 32000 mất 5,96 s, regex mới 0,02 s (tự đo, python3 -I).
Không có UI: không cần ảnh.
