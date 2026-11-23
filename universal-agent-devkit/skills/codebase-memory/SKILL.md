---
name: codebase-memory
description: Dùng khi tìm symbol, đọc outline/implementation, trace call flow, blast radius, dead code, Cypher query, kiểm tra coverage hoặc tối ưu chỉ mục đồ thị codebase-memory-mcp.
---

# Codebase Memory & Graph Navigation (SSOT)

Dùng đồ thị AST (`codebase-memory-mcp`) thay cho brute-force grep để giữ context gọn (~500 tokens thay vì ~80K tokens). Tự động fallback sang Read/Grep khi thiếu node, coverage `partial`/`skipped`, hoặc index cũ.

## 1. Protocol Tiết Kiệm Context (Minimal Evidence)

1. **Xác nhận dự án & độ mới:** Gọi `list_projects` hoặc `index_status(project="...")` đầu phiên (hoặc sau `/compact`). Nếu `indexed_at` quá cũ hay `doc_links.status == "error"`, chạy `index_repository` ở checkout chính.
2. **Định vị gọn bằng `format="tree"`:** Dùng `format="tree"` (mặc định, nhẹ token hơn `json`) + `limit` nhỏ:
   - `search_graph(name_pattern="...")` để tìm tên hàm/class/route chính xác.
   - `get_file_outline(file_path="...")` để xem khung symbol của file lớn trước khi đọc code.
3. **Truy vết Blast Radius:** `trace_path(function_name="...", direction="inbound|outbound|both", risk_labels=true)` (luôn dùng tên chính xác lấy từ `search_graph`).
4. **Đọc đúng lát cắt:** `get_code_snippet(qualified_name="...")` thay vì đọc cả file >500 dòng.
5. **Kiểm tra độ phủ trước khi kết luận:** Gọi `check_index_coverage` với các đường dẫn bằng chứng; nếu báo `partial`/`skipped`/`stale`, đọc/grep đúng đoạn bỏ sót trước khi kết luận.

> Không áp trần cứng số tool call — dừng ở chuỗi nhỏ nhất nhưng đủ chứng minh kết luận.

## 2. Mức Bằng Chứng (Evidence Tiers)

- **Scout (Tier 1):** Tra nhanh dương tính; gắn nhãn tạm, không kết luận phủ định/đầy đủ.
- **Verify (Tier 2 — mặc định):** Truy vấn đúng hướng call, trích snippet thật, kiểm tra `check_index_coverage` và phân trang (`has_more`/`offset`).
- **Auditor (Tier 3):** Kiểm đầy đủ 2 chiều call, phân trang trọn bộ, đối chiếu `compare_graphs` hoặc `detect_changes` và nêu rõ mọi giới hạn coverage.

## 3. Ma Trận Chọn Nhanh & 17 MCP Tools

| Nhu cầu | Tool MCP |
|---|---|
| Tìm hàm / class / route | `search_graph(name_pattern="...", format="tree")` |
| Xem khung symbol của file lớn | `get_file_outline(file_path="...")` |
| Ai gọi X / X gọi gì / cả 2 chiều | `trace_path(direction="inbound\|outbound\|both")` |
| Đọc đúng body hàm/class | `get_code_snippet(qualified_name="...")` |
| Kiểm tra vùng bị parse thiếu | `check_index_coverage` |
| So sánh đồ thị / phân tích git diff | `compare_graphs`, `detect_changes()` |
| Tìm code rác (Dead code) | `search_graph(max_degree=0, exclude_entry_points=true)` + verify bằng Grep |
| Quan hệ phức tạp (HTTP/async/handler) | `query_graph` (Cypher, giới hạn 200 dòng) |
| Bức tranh kiến trúc / ADR | `get_architecture`, `manage_adr` |
| Tìm chuỗi văn bản / config / fallback | `search_code` hoặc `Grep`/`Read` trực tiếp |

**Đủ 17 tools:** `index_repository`, `index_status`, `list_projects`, `delete_project`, `search_graph`, `search_code`, `trace_path`, `get_code_snippet`, `get_file_outline`, `get_graph_schema`, `compare_graphs`, `get_architecture`, `check_index_coverage`, `detect_changes`, `query_graph`, `manage_adr`, `ingest_traces`.

## 4. Vệ Sinh Chỉ Mục (`.cbmignore` & Chống Phình Graph)

- **Tạo `.cbmignore` ở gốc repo** (cú pháp `.gitignore`) để chặn dữ liệu không phải mã nguồn làm phình DB:
  - Luôn loại: `.agents/`, `reports/`, log lớn, fixture JSON/WAV telemetry hàng chục nghìn file, `**/androidTest/assets/**`, plugin bên thứ ba (`Assets/Plugins/<vendor>/`, `Library/`, `Temp/`).
  - **Không bao giờ chặn mã lõi first-party** (vd: `libs/` chứa module nội bộ như `pdf-viewer`, `office-reader`).
- **Không bật `auto_index=true`** trên máy chạy nhiều worktree tạm (`aaf` / `super-board`) để tránh sinh DB mồ côi; định kỳ xoá DB worktree/repo đã xoá bằng `delete_project`.
- **Không bật `hook-augment` trên `Read`/`Grep`** nếu đã tắt có chủ đích (tốn ~200 ms–1,3 s mỗi lần gọi và bơm thêm context thừa).

## 5. Rào Chắn & Gotchas

1. **Không bịa đặt:** Không bịa qualified name, số dòng, fan-in hay metric đồ thị.
2. **Source code thắng graph:** Graph và source mâu thuẫn → đọc file thật, ghi nhận graph stale và fallback.
3. **Thư viện ngoài:** Xác thực hành vi bằng Context7 hoặc test thật.
4. **Gotchas:** `search_graph(relationship="HTTP_CALLS")` lọc theo bậc (dùng `query_graph` để thấy cạnh thật); `query_graph` giới hạn 200 dòng; mặc định phân trang 10 mục/trang (`has_more` + `offset`).
