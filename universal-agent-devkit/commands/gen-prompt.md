---
name: gen-prompt
description: Tự động chuyển đổi ý tưởng hoặc yêu cầu ngắn thành Prompt kỹ thuật chuẩn XML của Anthropic (<role>, <system_context>, <task>, <mandatory_oracle>, <injected_constraints>, <historical_traps>, <instructions>) để copy sử dụng ngay cho Claude, ChatGPT, Grok hoặc đồng nghiệp.
---

# Generate Anthropic Standard Prompt (`/gen-prompt`)

Lệnh này nhận vào câu yêu cầu ngắn gọn của người dùng và xuất ra ngay **Prompt kỹ thuật hoàn chỉnh 10/10 theo chuẩn Anthropic XML** có đầy đủ:
- **`<role>`**: Xác định vai trò Senior tương ứng với `active-profile` (Game, Android, iOS, Backend...).
- **`<system_context>`**: Định vị Profile, Intent, và các truy vấn AST Codebase Graph (`search_graph`, `trace_path`).
- **`<task>`**: Nhiệm vụ cụ thể từ prompt người dùng.
- **`<mandatory_oracle>`**: Ép buộc cặp test kiểm chứng đối lập RED ➔ GREEN (với task sửa bug).
- **`<injected_constraints>`**: Tự nạp các yêu cầu phi chức năng (Debounce $\ge 1000\text{ms}$, Touch target $\ge 48\text{dp}$, Non-blocking main thread, Zero placeholders, Mask PII).
- **`<historical_traps>`**: Nạp chính xác mã bẫy lỗi lịch sử (`instincts`) kèm câu lệnh `sed` để trích xuất.
- **`<instructions>`**: Hướng dẫn tư duy từng bước qua `<thinking>` và giữ nguyên lý Zero Blast Radius.

---

## Cách sử dụng

### 1. Trong Claude Code / Antigravity:
```bash
/gen-prompt "<câu yêu cầu của bạn>"
```

### 2. Từ dòng lệnh Terminal (CLI):
```bash
python3 universal-agent-devkit/scripts/enrich_context.py "<câu yêu cầu của bạn>" --prompt
```

Ví dụ:
```bash
python3 universal-agent-devkit/scripts/enrich_context.py "tối ưu giảm GC allocation trong Unity" --prompt
```
Output in ra khối thẻ XML để bạn copy-paste sử dụng trực tiếp ở bất kỳ nền tảng nào.
