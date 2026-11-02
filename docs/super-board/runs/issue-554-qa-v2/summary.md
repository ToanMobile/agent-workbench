# QA v2 · issue #554 · head a6e25344

- `bash universal-agent-devkit/tests/verification/test_instincts_archive.sh` → exit 0, PASS
- RED trước sửa: cùng test chạy với instincts.py của 2c400784 → exit 1 ("add did not issue INSTINCT-004": cấp lại ID đã archive)
- `test_instincts_add_concurrent.sh`, `test_instincts_generic_promote.sh` → exit 0
- AC3: test enrich_context sau archive PASS (nạp INSTINCT-001, không nạp mục đã archive)
- `post-fix-gate.py --run-tests --brief` → exit 0 (1/1), biên nhận task đã ghi
