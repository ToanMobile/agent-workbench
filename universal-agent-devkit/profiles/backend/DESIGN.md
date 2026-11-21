# DESIGN.md — Backend API & Service Design Conventions for AI Agents

> **Chỉ thị cho AI Agent:** backend không có UI; "design system" ở đây là quy ước API, lỗi, dữ liệu và vận hành. Đọc và tuân thủ trước khi thêm/sửa endpoint, bảng dữ liệu hay job nền.

## 1. API Resource & Naming
- REST: danh từ số nhiều (`/v1/orders/{id}`), `kebab-case` cho path, `camelCase` hoặc `snake_case` cho JSON — **một** kiểu cho toàn dự án.
- Version ở path (`/v1`); thay đổi phá vỡ tương thích → version mới.
- Phân trang bằng cursor (`?cursor=&limit=`, `limit` tối đa 100), trả `nextCursor`.

## 2. Error Envelope

```json
{ "error": { "code": "ORDER_NOT_FOUND", "message": "Order not found", "requestId": "…" } }
```

| Tình huống | HTTP |
|---|---|
| Input sai / thiếu | 400 (kèm danh sách field lỗi) |
| Chưa xác thực / không có quyền | 401 / 403 |
| Không tồn tại (kể cả khi không có quyền xem, để tránh dò ID) | 404 |
| Xung đột phiên bản / trùng idempotency key khác payload | 409 |
| Vượt rate limit | 429 + `Retry-After` |
| Lỗi server | 500 — không lộ stack trace |
| Dịch vụ quá tải / đang bão hòa | 503 + `Retry-After`; là 5xx nên tính vào SLI lỗi của SLO (rules §11) |

## 3. Idempotency & Concurrency
- `POST` tạo tài nguyên/giao dịch nhận header `Idempotency-Key`; lưu kết quả để trả lại khi retry.
- Cập nhật đồng thời dùng optimistic locking (`version`/`ETag` + `If-Match`).

## 4. Data & Migrations
- Thời gian lưu UTC (ISO 8601), tiền tệ lưu số nguyên đơn vị nhỏ nhất + mã tiền tệ.
- Migration: expand → migrate → contract, mỗi bước deploy riêng; không khoá bảng lớn trong giờ cao điểm.

## 5. Timeouts, Retries, Limits
- Timeout mặc định cho outbound call: 2–5s; tổng request budget < timeout của gateway.
- Retry: tối đa 3 lần, exponential backoff + jitter, chỉ cho thao tác idempotent.
- Payload tối đa và rate limit được khai báo rõ theo endpoint.

## 6. Observability
- Log JSON một dòng: `timestamp, level, message, requestId, traceId, userId(hash)`; không log token/mật khẩu/PII thô.
- Metric RED (Rate, Errors, Duration) cho mọi endpoint; alert theo SLO, không theo từng lỗi lẻ.

## 7. API UX và DX (người dùng của backend là lập trình viên client và người vận hành)
- Mã lỗi: `code` UPPER_SNAKE, ổn định, liệt kê trong OpenAPI; không đổi nghĩa, chỉ thêm mới. `message` nói chuyện gì xảy ra và cách sửa, không lộ nội bộ. Lỗi 400 trả thêm `details: [{ "field", "code", "message" }]` (mở rộng danh sách field lỗi ở §2, envelope giữ nguyên).
- Lọc và sắp xếp nhất quán với cursor ở §1: `?status=…`, `?sort=-createdAt`; sắp xếp luôn có khoá phụ (id) để cursor không lặp hay mất dòng; `limit` mặc định khai trong OpenAPI.
- Hiển thị thời gian và trạng thái cho client: `requestId` ở envelope và header phản hồi; `Retry-After` cho 429/503 (RFC 9110 / RFC 6585); việc chạy lâu trả `202 Accepted` kèm URL trạng thái; `Server-Timing` (W3C) chỉ bật ở môi trường tin cậy hoặc nội bộ và chỉ phơi số tổng, không tên truy vấn hay host.
- Tài liệu: OpenAPI 3.x là hợp đồng; mỗi endpoint có ví dụ thành công và từng mã lỗi; CI so spec với triển khai (contract test). Sắp ngừng một endpoint: header `Sunset` (RFC 8594) và ghi vào changelog trước khi gỡ.
- Nhất quán: một kiểu đặt tên field (§1), enum là chuỗi ổn định, `null` và vắng mặt có nghĩa khác nhau và được ghi trong spec, thời gian ISO 8601 UTC (§4).
- CLI và công cụ quản trị: `--help` có ví dụ, `--json` cho máy đọc, dữ liệu ra stdout còn thông báo ra stderr, mã thoát khác 0 khi lỗi, thao tác phá huỷ có `--dry-run` và bước xác nhận, không in secret hay PII thô.
- Giao diện web quản trị (nếu có): profile backend không cài skill UI (`ui-ux-pro-max` ở profile web); tương phản chữ 4.5:1 và vùng chạm tối thiểu 44 px (essentials), phản hồi tức thì, nút thao tác đắt vô hiệu hoá ở lần bấm đầu và debounce ≥ 1000 ms (essentials). Giao diện đáng kể thì cân nhắc thêm profile web.

## 8. Quy ước hiệu năng cho API
- Mỗi route ghi p95 mục tiêu cạnh định nghĩa route (số theo `rules/backend-rules.md` §11, chưa có SLO thì dùng bảng đề xuất kèm nhãn của nó); metric RED gắn nhãn bằng `http.route` dạng template (§6).
- Danh sách luôn phân trang và có `limit` tối đa (§1); trả field cần thiết, nén phản hồi lớn; endpoint đắt (xuất file, báo cáo) chạy bất đồng bộ theo mẫu 202 ở §7.
- Quá tải: 429 (client vượt hạn mức, không tính vào SLI lỗi, theo dõi riêng) hoặc 503 (dịch vụ bão hòa, là 5xx nên tính vào SLI lỗi và có cảnh báo bão hòa riêng), cả hai kèm `Retry-After` (RFC 9110 / RFC 6585), không đứng chờ vô hạn; client retry theo §5.
