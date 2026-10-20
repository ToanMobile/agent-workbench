# Backend Service Engineering Rules (API / Workers)

## 1. Solo-Dev & Git Security (BẮT BUỘC)
- Việc xong (gate `--full` exit 0, ảnh khi cần, báo cáo nghiệm thu) thì TỰ commit đúng các file của mình và push nhánh hiện tại, không hỏi (quy trình pull/test lại/push: `rules/essentials.md` mục Git). Chỉ hỏi người dùng trước: force-push hoặc viết lại lịch sử đã chia sẻ, xoá file hoặc dữ liệu cực kỳ quan trọng không khôi phục được từ origin (dữ liệu người dùng thật, migration phá LIVE, nhánh/tag còn commit chưa có trên remote), và việc cực kỳ nguy hiểm (phát hành store / deploy production, đổi hoặc in secret đang dùng, thao tác billing, cấp quyền camera/location/danh bạ/PII, phá API công khai đã phát hành, làm yếu gate bảo mật khi lượt này chưa được yêu cầu). Commit, push fast-forward kể cả main, PR thường, sửa test và sửa code: tự làm, không hỏi.
- Secret chỉ nạp qua biến môi trường / secret manager; không commit `.env`, key, dump database.
- Không đưa dữ liệu production thật vào test fixture.

## 2. Paired Executable Oracle & TDD
1. **RED:** test tái hiện lỗi ở tầng thấp nhất có thể (unit → integration), xác nhận FAIL.
2. **GREEN:** sửa tối giản cho PASS; không xoá/nới assertion.
- Runner đúng theo dự án: `go test ./...`, `cargo test`, `python3 -m pytest`, `npm test`.

## 3. Hợp đồng API
- Không đổi/xoá field hay đổi kiểu trong API công khai mà không version hoá (`/v2`, field mới + deprecate).
- Lỗi trả về có cấu trúc (mã lỗi ổn định + message), không lộ stack trace ra client.
- Validate input tại biên (schema), từ chối sớm với 4xx rõ ràng.

## 4. Dữ liệu & Migration
- Migration chỉ tiến, có thể chạy lại an toàn; tách "thêm cột" và "xoá cột" thành 2 lần deploy.
- Mọi truy vấn dùng tham số hoá — cấm nối chuỗi SQL.
- Thao tác ghi quan trọng có transaction và idempotency key (retry không tạo bản ghi trùng).

## 5. Độ bền & Hiệu năng
- Mọi lời gọi mạng có timeout; retry có giới hạn + backoff + jitter; không retry thao tác không idempotent.
- Tránh N+1 query; thêm index khi thêm điều kiện lọc mới; phân trang mọi endpoint trả danh sách.
- Không nuốt lỗi (`except: pass`, `catch {}`) — log kèm ngữ cảnh rồi xử lý hoặc ném lại.

## 6. Quan sát & Log
- Log có cấu trúc (JSON) với request/trace id; mask PII, token, mật khẩu.
- Endpoint health/readiness riêng; metric cho latency, error rate, queue depth.

## 7. Bảo mật
- AuthN ở middleware, AuthZ kiểm tra theo **từng tài nguyên** (chống IDOR).
- Rate limit cho endpoint đăng nhập/gửi mã; không trả khác biệt thông báo giữa "sai user" và "sai mật khẩu".

## 8. Kiến trúc Hexagonal / DDD (nguồn: Sairyss/domain-driven-hexagon)
- Phụ thuộc chỉ hướng vào trong: domain (entity, aggregate, value object, domain service/event) không import controller/DTO/ORM/framework. CI bắt bằng dependency-cruiser (`no-domain-deps`, severity error) hoặc ArchUnit (Java).
- Port = interface ở tầng application/domain, adapter ở infrastructure, nối bằng DI. Chỉ tạo port ở ranh giới thật (DB, HTTP, queue); port cho mọi thứ là over-abstraction (core §4).
- Một use case = một application service/handler; controller không chứa nghiệp vụ. Command đổi state và chỉ trả metadata (ID); query chỉ đọc.
- Module là lát cắt dọc; không import trực tiếp giữa module, đi qua facade/mediator/message. Aggregate tham chiếu aggregate khác bằng ID, một transaction một aggregate, value object không ra DTO/event/DB model.
- Domain không ném HTTP exception: lỗi nghiệp vụ phục hồi được trả kiểu `Result`, lỗi kỹ thuật ném; controller ánh xạ sang HTTP status (không biết → 500). Response DTO whitelist field, không lộ model persistence.
- Không áp full DDD cho CRUD đơn giản (chính nguồn cũng nói vậy). Chi tiết: `skills/deep-module-design/references/architecture-backend.md`.

## 9. Node.js production (nguồn: goldbergyoni/nodebestpractices — chỉ áp dụng khi dự án là Node)
- Mọi lỗi kế thừa một `AppError extends Error` (`code` ổn định, `isOperational`); một error handler trung tâm; cấm `throw "chuỗi"`. Lỗi không-operational: log đủ ngữ cảnh, drain, thoát khác 0 để supervisor khởi động lại.
- `unhandledRejection` và `uncaughtException` đăng ký ở entrypoint; `return await` trong `try/catch` để giữ stack; mọi emitter/stream có handler `'error'`.
- Config validate bằng schema lúc boot và thoát nếu sai; body/query/param validate bằng schema (Zod/Joi/ajv) → 4xx mã ổn định. API public có giới hạn kích thước payload (413), rate limit (429), header bảo mật (helmet) — mỗi cái có test.
- CPU nặng không chạy trên event loop (worker/process riêng). Regex từ input người dùng phải qua kiểm tra ReDoS; cấm `eval`.
- Docker/CI: `USER` không phải root, base image ghim tag/digest (không `latest`), `CMD ["node", …]` (không `npm start`) và xử lý SIGTERM để drain, `.dockerignore` loại `.env`/`.npmrc`, `npm ci` + audit phụ thuộc trong CI.

## 10. Observability theo OpenTelemetry (nguồn: open-telemetry/opentelemetry-specification)
- Tên span và `http.route` là template ít biến thể (`GET /users/{id}`); id, email, URL thô vào attribute chứ không vào tên span/label metric.
- Span status: server giữ Unset với 4xx, đặt Error với 5xx/lỗi mạng (kèm `error.type`); `Ok` chỉ do code ứng dụng đặt, thư viện không đặt.
- Log có `trace_id` + `span_id` khi đang trong span; severity map theo dải OTel (ERROR ≥ 17). Xoá credential/chữ ký trong URL attribute.
- Telemetry không bao giờ ném lỗi vào luồng nghiệp vụ: bọc exporter/callback; test với exporter hỏng, kết quả request phải không đổi.
- Thư viện chỉ phụ thuộc OTel API; SDK/exporter cấu hình ở entrypoint ứng dụng. Sampling mặc định `ParentBased(AlwaysOn)`; chốt tỉ lệ trước production và không rẽ logic nghiệp vụ theo cờ sampled. Chi tiết: `skills/observability-instrumentation/references/otel-signals.md`.
