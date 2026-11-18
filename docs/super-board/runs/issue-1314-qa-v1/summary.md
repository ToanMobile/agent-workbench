# QA #1314 v1 — PR #1315 (head 5de6a008)

- AC1: test_qa_report_ac_many_spaces.sh GREEN trên nhánh PR (8/8). RED trên checker của origin/main (ce14784a): 3 ca đỏ (`AC       4`, `AC          4`, `AC       - 4` thoát 0, cần 1).
- AC2: `AC` + 60000 khoảng trắng + `x` (thân PR và dòng Not done) xong 0 s (< 5 s); thêm `AC`+60000sp+`-`+60000sp+`x`, `AC ` x30000, (`AC`+50sp+`-`)x2000: mỗi ca ≤ 0,003 s.
- AC3: test_qa_report_review_only_ac, test_qa_report_redos_timeout, test_qa_report_cross_repo_ac, test_merge_gate_qa_report đều exit 0.
- Security pass: diff 1 dòng regex, không đụng input ngoài/secret; không có finding.
- Test-gap: không có gap High.
