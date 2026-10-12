# OpenTelemetry — quy ước tín hiệu (tham chiếu nạp khi cần)

Phạm vi: dịch vụ backend và web đã dùng (hoặc quyết định dùng) OpenTelemetry. Không áp dụng cho game Unity, ứng dụng Android/iOS dùng Crashlytics/Firebase hay phần mềm đầu xe, trừ khi dự án đó tự chọn OTel.

Nguồn: `open-telemetry/opentelemetry-specification` (README mỏng, chi tiết ở https://opentelemetry.io/docs/specs/otel/, các file `specification/`) và `goldbergyoni/nodebestpractices` (mục Going to Production). Đã đọc 2026-10-12 qua WebFetch. Rule ngắn: `profiles/backend/rules/backend-rules.md` §10; skill này giữ nguyên nguyên tắc "mỗi signal trả lời một câu hỏi chẩn đoán". Spec không nêu ngưỡng cardinality bằng số: không bịa ngưỡng.

## API và SDK
- Mỗi tín hiệu có API, SDK, semantic conventions và contrib. Thư viện/instrumentation chỉ tham chiếu API; ứng dụng chọn SDK và exporter (overview.md).
- Phần triển khai KHÔNG được ném exception chưa bắt lúc chạy: mất telemetry chấp nhận được, làm gián đoạn ứng dụng thì không (error-handling.md). Fail fast chỉ lúc khởi tạo; dùng sai thì trả giá trị an toàn/no-op; callback nền phải được bao bọc.
- Propagator mặc định kết hợp W3C TraceContext và Baggage; `extract` không được ném khi gặp header hỏng.

## Trace
- SpanKind: SERVER, CLIENT, PRODUCER, CONSUMER, INTERNAL (mặc định). TraceId 16 byte, SpanId 8 byte, đều khác 0; SpanContext bất biến.
- Status: Unset (mặc định) < Error < Ok; mô tả chỉ có với Error; `Ok` dành cho code ứng dụng; thư viện để Unset trừ khi có lỗi. `RecordException` là một event.
- Tên span ít biến thể: `get_account` đúng, `get_account/42` sai (id vào attribute). Kiểm `IsRecording` trước khi tính attribute đắt; code ứng dụng không đọc cờ sampled để rẽ logic.
- Sampling mặc định `ParentBased(root=AlwaysOn)`; quyết định DROP / RECORD_ONLY / RECORD_AND_SAMPLE; tỉ lệ chỉ áp ở root. Cần chốt tỉ lệ có chủ đích trước production.
- Mặc định SDK đáng biết: giới hạn 128 event/link/attribute; batch processor queue 2048, delay 5000 ms, batch 512, export timeout 30000 ms (đo lại theo phiên bản SDK đang dùng).

## HTTP semantic conventions (ổn định)
- Tên span `{method} {http.route}`, không dùng path thô. Server span giữ 4xx là Unset; client span đặt Error với 4xx; cả hai Error với 5xx hoặc lỗi mạng kèm `error.type`.
- Thuộc tính: `http.request.method`, `http.response.status_code`, `url.path`, `url.scheme`, `server.address`, `error.type`. Che giá trị query nhạy cảm (`sig`, `X-Amz-Signature`); bắt header là opt-in.

## Metric
- Loại: Counter (đơn điệu tăng), UpDownCounter (cộng được, lên xuống), Histogram (phân phối, dùng cho thời lượng), Gauge (không cộng). Biến thể async dùng callback không phát trùng tập attribute.
- Tên instrument bắt đầu bằng chữ ASCII, ≤ 255 ký tự; unit ≤ 63 ký tự. Attribute phải bị chặn giá trị (cấm id, email, URL thô).

## Log
- Trường: Timestamp, ObservedTimestamp, TraceId, SpanId, TraceFlags, SeverityText, SeverityNumber, Body, Resource, Attributes. Dải severity: TRACE 1–4, DEBUG 5–8, INFO 9–12, WARN 13–16, ERROR 17–20, FATAL 21–24; có SpanId thì nên có TraceId.

## Thực hành vận hành (nodebestpractices)
- Log có cấu trúc, ghi ra stdout, mỗi dòng có transaction id (5.2, 5.14, 5.18); health/maintenance endpoint có xác thực (5.7); xử lý SIGTERM để drain (8.6).

## Kiểm chứng (bổ sung cho mục Verification của skill)
- Exporter hỏng/đầy: kết quả request không đổi, không ném.
- Seed secret vào request: log, span attribute và URL không chứa secret.
- Gọi hai route cùng mẫu với id khác nhau: một tên span, một giá trị `http.route`.
- Request 404 ở server: span Unset; request 500: span Error có `error.type`.
- Dòng log trong span có `trace_id`/`span_id` khớp span đó.
