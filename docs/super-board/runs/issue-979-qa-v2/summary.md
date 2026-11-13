# QA #979 vòng 2 @ ec39e485 (đã chứa origin/main fd609c37)
- test_qa_stale_routes_to_qa.sh: rc=0 (A, B, B2 xanh)
- Test liên quan rc=0: test_merge_gate_qa_report, test_qa_report_stale_pin, test_merge_queue, test_merge_queue_route_rows, test_merge_queue_gate_exit_14, test_merge_gate_stale_message
- post-fix-gate --run-tests --scoped: `pass` (exit 0)
- AC2 đạt: QA cũ → Review → QA, không loop:rebuild-N; lẫn ac-check vẫn về Build
- AC1 chưa đo được: cần 10 thẻ sau merge
