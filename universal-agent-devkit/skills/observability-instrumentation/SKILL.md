---
name: observability-instrumentation
description: Dùng khi thêm hoặc audit log, metric, trace, Crashlytics/Firebase Performance, hay khi production bug thiếu dữ liệu chẩn đoán. Bỏ qua UI thuần không có failure mode và code chỉ chạy trong test/script.
---

# Observability & Instrumentation

## Nguyên Tắc Đặt Signal Giám Sát

Viết câu hỏi chẩn đoán/on-call cụ thể. Mỗi signal phải trả lời một câu hỏi; không map được thì không emit. Dùng signal nhỏ nhất.

Trước khi thêm bất kỳ log, metric hay trace nào, hãy xác định câu hỏi chẩn đoán cụ thể:
- **Metric:** Đo lường tỷ lệ lỗi (error rate), throughput, latency phân vị P95/P99.
- **Trace:** Xác định chính xác latency nằm ở giai đoạn nào trong luồng xử lý phân tán.
- **Log / Breadcrumb:** Ghi lại ngữ cảnh tại sao một instance/transaction cụ thể thất bại.

Không bịa threshold, percentile hoặc alert budget. Dùng gate/measurement/owner requirement thật.

## Tiêu Chuẩn Dữ Liệu (Telemetry Contract)

1. **Machine-Readable & Low Cardinality:** Event key ổn định, nhóm theo enum hoặc format hữu hạn; không dùng User ID hay nội dung tự do làm label metric. Không dùng user id, full path, URI, free-form error text hoặc document content làm metric label.
2. **Che giấu PII Tối thượng:** Tuyệt đối không log thông tin nhạy cảm, mật khẩu, access token, số thẻ, số định danh CCCD. Không log PII, secret, token, credential, file content hay path lộ danh tính.
3. **Correlation ID / Trace ID:** Gắn mã định danh ngẫu nhiên xuyên suốt các tầng xử lý để kết nối luồng mà không chứa dữ liệu nhạy cảm. Correlation ID chỉ khi cần nối flow; phải ngẫu nhiên/opaque và không chứa PII.
4. **Cấp độ Severity:**
   - `ERROR`: Chỉ cho các lỗi cần can thiệp xử lý ngay (actionable).
   - `WARN`: Cho các rủi ro đã lường trước hoặc trạng thái suy giảm hiệu năng (degraded).
   - `INFO`: Ghi nhận các mốc chuyển trạng thái nghiệp vụ lớn.
   - `DEBUG`: Chỉ phục vụ môi trường phát triển cục bộ.

## Crashlytics

Classify trước `recordException`. Network/offline, permission denial, user error hoặc platform noise đã được codebase phân loại thì dùng pattern hiện có và giữ breadcrumb phù hợp; không tạo classifier mới khi đã có. Chỉ report exception bất ngờ/actionable. Không swallow lỗi chỉ để dashboard sạch.

Với auth/cloud/file/permission path, review Security/Privacy và mọi entry point. Firebase/SDK behavior phải verify bằng official docs hoặc Context7.

## Verification

Trong debug/staging phù hợp, gây một success/failure có kiểm soát và xác nhận signal xuất hiện, field đã redact, correlation nối đúng và duplicate/noise không tăng. Nếu thiếu device/dashboard/access, báo residual; compile hoặc unit test mock không chứng minh telemetry production hoạt động.
