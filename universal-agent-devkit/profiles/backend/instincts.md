# Instincts & Failure Memory — Backend Profile

> **Quy định cho AI Agent:** đọc lướt các bẫy dưới đây trước khi sửa code backend. Gặp bẫy mới thì thêm một mục theo mẫu ở cuối tệp.

---

### [INSTINCT-BE-01] Retry tạo giao dịch trùng
- **Hiện tượng lỗi:** Client timeout rồi gửi lại, server tạo 2 đơn hàng / trừ tiền 2 lần.
- **Nguyên nhân gốc rễ:** Endpoint tạo tài nguyên không idempotent.
- **Quy tắc bắt buộc:** Nhận `Idempotency-Key`, lưu (key, hash payload, kết quả) trong transaction; trùng key cùng payload → trả kết quả cũ.

---

### [INSTINCT-BE-02] N+1 query sau khi thêm field vào response
- **Hiện tượng lỗi:** Latency tăng tuyến tính theo số bản ghi sau một thay đổi nhỏ ở serializer.
- **Nguyên nhân gốc rễ:** Truy cập quan hệ lazy trong vòng lặp.
- **Quy tắc bắt buộc:** Eager-load / batch (`JOIN`, `IN (...)`, dataloader); test đếm số query cho endpoint danh sách.

---

### [INSTINCT-BE-03] Migration khoá bảng lớn
- **Hiện tượng lỗi:** Deploy treo vài phút, request timeout hàng loạt.
- **Nguyên nhân gốc rễ:** `ALTER TABLE` thêm cột có default / tạo index không `CONCURRENTLY` trên bảng lớn.
- **Quy tắc bắt buộc:** Expand → backfill theo lô → contract; index tạo online; thử migration trên bản sao dữ liệu kích thước thật.

---

### [INSTINCT-BE-04] Lỗi bị nuốt, job "thành công" giả
- **Hiện tượng lỗi:** Worker báo xong nhưng dữ liệu không được ghi; không có log.
- **Nguyên nhân gốc rễ:** `except Exception: pass` / `catch {}` / bỏ qua `err` trong Go.
- **Quy tắc bắt buộc:** Lỗi phải được log kèm ngữ cảnh và trả về/đẩy vào dead-letter; linter bật `errcheck` / rule cấm except trống.

---

### [INSTINCT-BE-05] IDOR — truy cập tài nguyên của người khác bằng cách đổi ID
- **Hiện tượng lỗi:** `GET /v1/invoices/123` trả hoá đơn của user khác.
- **Nguyên nhân gốc rễ:** Chỉ kiểm tra đã đăng nhập, không kiểm tra quyền sở hữu tài nguyên.
- **Quy tắc bắt buộc:** Truy vấn luôn kèm điều kiện chủ sở hữu/tenant; test với 2 user khác nhau phải trả 404.

---

### [INSTINCT-BE-06] Domain Import Framework/ORM — Nghiệp Vụ Dính Chặt Hạ Tầng
- **Hiện tượng lỗi:** Nâng ORM/framework phải sửa cả entity và use case; unit test nghiệp vụ cần DB hoặc HTTP.
- **Nguyên nhân gốc rễ:** Entity/aggregate import decorator ORM, controller, DTO hoặc ném HTTP exception (nguồn: domain-driven-hexagon, dependency rule).
- **Quy tắc bắt buộc:** Domain không import controller/DTO/database/repository; port ở application/domain, adapter ở infrastructure; domain trả `Result`, controller ánh xạ sang HTTP.
- **Kiểm tra tự động:** dependency-cruiser rule `no-domain-deps` (severity error) hoặc ArchUnit chạy trong CI; mutation: thêm một import cấm vào domain phải làm CI đỏ.

---

### [INSTINCT-BE-07] Lỗi Không Bắt Ở Entrypoint Và Lỗi Tuỳ Tiện (Node)
- **Hiện tượng lỗi:** Promise reject rơi im lặng, tiến trình tiếp tục ở trạng thái hỏng; client nhận stack trace hoặc `throw "chuỗi"` không có mã.
- **Nguyên nhân gốc rễ:** Thiếu handler `unhandledRejection`/`uncaughtException`; không có lớp lỗi chung; nhiều nơi tự xử lý lỗi (nguồn: nodebestpractices mục 2).
- **Quy tắc bắt buộc:** Một `AppError` (`code`, `isOperational`), một error handler trung tâm; lỗi không-operational: log, drain, thoát khác 0; response không kèm stack.
- **Kiểm tra tự động:** grep -E "throw +['\"]" trong mã nguồn = 0; test ném `AppError` và lỗi lạ, assert body không chứa stack và exit code của lỗi không-operational.

---

### [INSTINCT-BE-08] Telemetry Làm Hỏng Request, Hoặc Span/Label Nổ Cardinality
- **Hiện tượng lỗi:** Exporter lỗi làm request 500; dashboard chậm hoặc đắt vì mỗi `user_id` thành một chuỗi thời gian; span tên `GET /users/42` không gom được.
- **Nguyên nhân gốc rễ:** Gọi API telemetry không bọc; nhét id/URL thô vào tên span hoặc label metric (spec OTel: tên span ít biến thể; telemetry không được ném).
- **Quy tắc bắt buộc:** Bọc exporter/callback, tên span theo `{method} {http.route}`, id vào attribute chứ không vào label metric, log mang `trace_id`/`span_id`.
- **Kiểm tra tự động:** test exporter hỏng → kết quả request không đổi; gọi hai id khác nhau → một tên span.

---

## Nhật ký bẫy bổ sung

<!--
### [INSTINCT-BE-XX] <Tên bẫy>
- **Ngày phát hiện:** YYYY-MM-DD
- **Hiện tượng lỗi:** …
- **Nguyên nhân:** …
- **Quy tắc phòng ngừa:** …
- **Lệnh kiểm tra:** …
-->
