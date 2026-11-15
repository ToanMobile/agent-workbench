# QA v5 · #1199 · head 3e806d4 (merge origin/main: no-op)
- `test_qa_report_cross_repo_ac.sh`: base exit 1 (3 ca ĐỎ), head exit 0, XANH 10/10 (thêm ca xem / phẩy / ngoặc).
- `test_qa_report_stale_pin.sh`: ALL OK · `test_merge_gate_qa_report.sh`: ALL PASS · `test_merge_gate_qa_report_issue_decision.sh`: ALL PASS.
- gate scoped (`post-fix-gate.py --run-tests --scoped --brief --json` | qa-exit2): `pass`.
- Security pass: chỉ regex/parse chuỗi comment, không I/O mới, không finding.
- Test-gap: không còn High; finding audit T0519 (dấu phẩy/ngoặc) đã đóng.
