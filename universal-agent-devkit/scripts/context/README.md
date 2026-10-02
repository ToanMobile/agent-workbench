# DevKit Context & Intent Enrichment

Nhóm công cụ phân tích prompt, truy vết bẫy mã nguồn và làm giàu ngữ cảnh 5 chiều:

- `agent_hooks.py`: Cấu hình tích hợp hook gates cho Claude, Codex, Gemini CLI, Cursor.
- `enrich_context.py`: Phân tích ý định prompt, nạp NFRs, tra cứu bẫy lỗi (`instincts`), và gán skill phù hợp.
- `hardware_boundaries.py`: Phát hiện và bảo vệ ranh giới phần cứng / ngoại vi đặc thù.
- `rule_context.py`: Ánh xạ câu prompt tới các phần quy tắc tương ứng trong `.agents/local/rules/`.
- `rules_index.py`: Tạo chỉ mục quy tắc dự án dạng bảng `sed -n` tối ưu nạp vào context.
