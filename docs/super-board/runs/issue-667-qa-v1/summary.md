# QA #667 · PR #1194 · head 09f1a37563

- Oracle `tests/gates/test_gate_trace_select.sh`: PASS 6/6 (QA tự chạy, exit 0)
- Hồi quy `tests/gates/test_gate_shadow_map.sh`: PASS 5/5 (QA tự chạy, exit 0)
- AC1 (≥5 lượt shadow, 0 FAIL bị bỏ sót): đạt theo số đo trong quyết định chủ repo 15/11 (63 lượt, shadow_miss=[]); QA không tự đo lại runs.jsonl
- AC2 (trung vị impacted giảm): CHƯA đo được; cờ DEVKIT_TRACE_MAP_SELECT mặc định tắt, cần số đo thật sau merge (luật 20)
- Review diff: suite matrix_added/stale_rerun/keyed_full không bị bỏ; lỗi dựng map giữ cách chọn cũ; suite FAIL vẫn chạy (ca 4)
- pr-security-review: 0 findings (chỉ đọc biến môi trường, không có input không tin cậy)
