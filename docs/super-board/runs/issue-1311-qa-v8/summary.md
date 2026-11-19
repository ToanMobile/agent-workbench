# QA v8 · issue #1311 · PR #1312 · head a35a094d
- test_github_read_rate_limit_backoff.sh: rc=0 (R8a, R8b, R9 start-up, R10 đều xanh)
- test_rate_limit_69_train_queue_1311.sh: rc=0
- test_merge_queue_route_rows.sh: rc=0
- post-fix-gate --run-tests --scoped (qua super-board-qa-exit2.sh): `pass`, exit 0 (head a35a094d, đã chứa origin/main)
- Security pass: không có phát hiện (không eval/curl/secret mới trong diff mã)
- Ảnh: không cần, không có UI
