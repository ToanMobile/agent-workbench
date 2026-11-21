# Backend Service Engineering Rules (API / Workers)

## 1. Solo-Dev & Git Security (BẮT BUỘC)
- Tự commit/push khi xong và danh sách việc phải hỏi người dùng trước: DevKit essentials trong `AGENTS.md`, mục Git và Working style.
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
- Server fetch URL do người dùng đưa (chống SSRF): phân giải host một lần, từ chối địa chỉ private / loopback / link-local / metadata (`169.254.169.254`), kết nối đúng IP đã kiểm (không phân giải DNS lần hai) và kiểm lại từng redirect.
- Không monkeypatch `socket.getaddrinfo` toàn tiến trình để chặn SSRF (không an toàn đa luồng); ghim IP ở kết nối của chính request.

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


## 11. Hiệu năng và SLO (nguồn: Google SRE book, tài liệu k6/Gatling/PostgreSQL; số khác mang nhãn riêng)
- SLO trước khi phát hành: mỗi endpoint và job nền có mục tiêu độ trễ p50/p95/p99 và SLI lỗi = tỉ lệ 5xx, kể cả 503 do quá tải (4xx do client, kể cả 429, không tính; khớp §10). Số lấy từ SLO của dịch vụ hoặc chủ repo; chưa có thì dùng bảng đề xuất giữ nhãn "mặc định đề xuất của dự án, cần đo thật" tới khi có số đo; không bịa ngưỡng ngoài nhãn đó (skill `observability-instrumentation`). Bảng đề xuất, 0,1%/99,9%, error budget, `statement_timeout`/`lock_timeout`, retry budget, load test, profiling nằm ở khối "§11 Bảng SLO đề xuất…" trong `profile-reference.md`.
- Truy vấn mới hoặc đổi: chạy EXPLAIN trên dữ liệu cỡ production, không full scan bảng lớn khi thiếu lý do ghi rõ; `EXPLAIN ANALYZE` thực thi câu lệnh thật nên với INSERT/UPDATE/DELETE dùng transaction rollback hoặc bản sao; đếm số query mỗi request trong test để bắt N+1 (§5).
- Pool kết nối (DB, HTTP client) có kích thước giới hạn tường minh, timeout chờ lấy kết nối và metric bão hòa; kích thước chốt bằng đo.
- Backpressure: hàng đợi, bộ đệm, số worker đều có giới hạn; quá tải thì từ chối sớm bằng 429 (client vượt hạn mức) hoặc 503 kèm `Retry-After` (RFC 9110 / RFC 6585); 503 tính vào SLI lỗi, cộng cảnh báo bão hòa riêng (độ sâu hàng đợi, thời gian chờ pool).
- Mọi claim "nhanh hơn" phải có số đo trên môi trường giống production, đo xen kẽ theo skill `verification-before-completion`; số đo trên máy dev chỉ so sánh tương đối.
- Không chặn event loop hay luồng xử lý yêu cầu bằng I/O đồng bộ hoặc CPU nặng (áp dụng theo tương tự lens chặn luồng chính của council `07-performance-anr`, vốn viết cho Android; Node: §9).
<!-- on-demand: §11 Bảng SLO đề xuất, error budget, pool, timeout, retry, cache, load test k6/Gatling, profiling -->
- Bảng SLO đề xuất cho endpoint chưa có SLO (nhãn ở cuối mỗi dòng; thay bằng số đo thật khi có):

| Loại yêu cầu | p50 | p95 | p99 | Nhãn |
|---|---|---|---|---|
| GET một tài nguyên theo id | 50 ms | 200 ms | 500 ms | mặc định đề xuất của dự án, cần đo thật |
| List / tìm kiếm có phân trang | 150 ms | 500 ms | 1 s | mặc định đề xuất của dự án, cần đo thật |
| Ghi đồng bộ (POST/PUT/PATCH) | 150 ms | 500 ms | 1 s | mặc định đề xuất của dự án, cần đo thật |

- Ngân sách theo endpoint: ghi p95 mục tiêu cạnh route; trường hợp xấu nhất (kể cả retry) của các lời gọi con cộng thời gian xử lý vẫn nằm trong timeout gateway (DESIGN §5).
- Tỉ lệ lỗi 5xx tối đa 0,1% yêu cầu và khả dụng 99,9% trong cửa sổ 30 ngày: mặc định đề xuất của dự án, cần đo thật. Error budget = 1 − mục tiêu SLO (SRE book); với 99,9%/30 ngày là 43,2 phút (tính: 0,1% × 43 200 phút). Cảnh báo theo tốc độ đốt error budget, không theo từng lỗi lẻ (DESIGN §6); ngưỡng cửa sổ chốt theo SLO của dịch vụ. 429 theo dõi riêng, không vào SLI lỗi.
- Đo percentile bằng histogram; không lấy trung bình của các p99 và không báo SLO bằng trung bình độ trễ. Bốn tín hiệu vàng (độ trễ, lưu lượng, lỗi, bão hòa — SRE book); RED cho endpoint (DESIGN §6); USE (Utilization, Saturation, Errors — Brendan Gregg) cho CPU, bộ nhớ, pool, đĩa.
- Pool DB: điểm xuất phát để đo là connections = ((số core vật lý của máy chủ DB, không tính hyperthread) × 2) + số ổ đĩa hiệu dụng (HikariCP wiki "About Pool Sizing", dẫn từ PostgreSQL). Kết quả là TỔNG kết nối hoạt động trên mọi instance app: chia cho số replica để ra pool mỗi instance. Pool quá lớn làm DB chậm vì tranh chấp. Định luật Little: số yêu cầu đồng thời ≈ thông lượng × độ trễ trung bình, dùng để ước lượng trần trước khi đo.
- Timeout và retry: trần connect 10 s và read 15 s theo essentials; mặc định 2–5 s và tối đa 3 lần retry xem DESIGN §5. Giới hạn cộng dồn: số lần thử × timeout mỗi lần phải nhỏ hơn timeout gateway; 3 × 5 s = 15 s đã vượt xa ngân sách p99 0,5–1 s của bảng trên (số học), nên đặt timeout mỗi lần theo phần ngân sách còn lại. Thêm hạn mức retry tổng (retry budget, SRE book) để retry không khuếch đại quá tải; DB có `statement_timeout` và `lock_timeout` (PostgreSQL) hoặc tương đương.
- Cache có TTL, cách vô hiệu hoá, key gồm tenant/quyền (không rò dữ liệu giữa người dùng, §7), chống stampede, đo hit ratio; không cache phản hồi 5xx.
- Phân trang bằng cursor/keyset thay offset trên bảng lớn (offset phải quét và bỏ qua N dòng); đếm tổng (COUNT) đắt nên chỉ trả khi client cần; trả đúng field cần (whitelist §8), nén phản hồi lớn, giới hạn kích thước payload (§9).
- Load test chạy trên staging với dữ liệu giả (§1), mô hình mở (tốc độ đến cố định) để không che độ trễ khi hệ thống chậm (coordinated omission). Loại theo tài liệu k6: smoke, load, stress, soak, spike. k6 với `thresholds` cú pháp `http_req_duration: ['p(95)<B']`, `http_req_failed: ['rate<E']` (B, E lấy từ SLO) và executor `constant-arrival-rate`; Gatling dùng injection mở như `constantUsersPerSec`. Kit không ship hai công cụ này, dự án tự thêm vào CI hoặc staging. Lưu kết quả: RPS, p50/p95/p99, tỉ lệ lỗi, CPU, bộ nhớ, bão hòa pool, commit.
- Soak đủ dài để lộ rò rỉ (RSS, kết nối, file descriptor); thời lượng chốt theo chu kỳ cache TTL, GC và job của dịch vụ.
- Vượt budget p99 hoặc bộ nhớ tăng đều thì profile trước khi sửa, đính flame graph hoặc số đo vào PR; profile dưới tải giống thật, so trước/sau bằng cùng kịch bản: Go `pprof` và `go test -bench -benchmem`; Python `py-spy` hoặc `cProfile`; Rust `cargo flamegraph` hoặc `perf`; Node `node --cpu-prof` và heap snapshot.
- Môi trường đo giống production: cỡ dữ liệu, số replica, cấu hình DB, độ trễ mạng; ghi khác biệt. Kết quả đo ở nơi khác ghi nhãn "CHƯA ĐO TRÊN MÔI TRƯỜNG GIỐNG PRODUCTION".
<!-- /on-demand -->

## 12. Chất lượng (nguồn: skills `tdd-workflow`, `qc`; số khác mang nhãn riêng)
- Mỗi migration đi cùng migration test: nâng từ schema cũ lên mới không mất dữ liệu và chạy lại an toàn (§4; agent `database-reliability-auditor`). Truy vấn và migration được chứng minh bằng DB thật, không mock.
- Test xác định: không sleep cố định, không đồng hồ/mạng thật, không dữ liệu chung; đúng khi đảo thứ tự và chạy song song.
- Test mới xanh ngay lần chạy đầu phải thử phá dòng được bảo vệ một lần để thấy RED (skill `tdd-workflow`).
- Cổng CI chạy đúng runner theo skill `qc` §0; PASS cần số test > 0 và 0 fail, `UP-TO-DATE` hay không có test không phải PASS.
- Ngưỡng coverage của repo hoặc chủ repo thắng; chưa có thì sàn 80%: mặc định đề xuất của dự án, cần đo thật (skill `qc` §7: nguồn goldbergyoni/javascript-testing-best-practices chỉ nói khoảng 80% là đủ).
<!-- on-demand: §12 Kim tự tháp test backend, test DB thật, mutation, flaky, cổng CI, canary -->
- Tầng test theo ROI backend (`skills/tdd-workflow/references/testing-practices.md`): unit (domain thuần, nhanh) → component/API (module thật, stub dịch vụ ngoài; ROI tốt nhất cho backend, không bó vào kim tự tháp unit) → integration (DB, queue, cache thật) → contract (Pact kiểu consumer-driven, hoặc kiểm phản hồi với schema OpenAPI khi client và server khác repo) → E2E rất ít. Mỗi flow kiểm đủ 5 kết quả khi liên quan: phản hồi, trạng thái đã lưu, lời gọi ra ngoài, thông điệp queue, tín hiệu quan sát.
- DB thật: Testcontainers (Java, Go, Node, Python, Rust, .NET) hoặc DB tạm của CI, dữ liệu do từng test tự tạo, dọn sau cả bộ; test truy vấn đủ ba ca: rỗng, một dòng, nhiều trang. Migration test chạy cả hướng nâng từ bản cũ trên dữ liệu mẫu và lần chạy lại lần hai.
- Mutation: module quan trọng chạy thêm mutation testing: Stryker (JS/TS), mutmut (Python), cargo-mutants (Rust), PIT (Java) hoặc làm tay một đột biến theo skill `tdd-workflow`; đột biến còn sống nghĩa là test chưa bắt được lỗi. Test chỉ assert trên giá trị của chính mock hoặc lặp công thức của hàm đang test là tautology, bị loại.
- Flaky: sửa hoặc loại có lý do ghi rõ, không retry mù; chẩn đoán theo agent `test-architect-seti` (scheduler, đồng hồ, trạng thái chung, thứ tự, cache); số lần lặp để xác nhận và tỉ lệ flaky chấp nhận được lấy từ kế hoạch đo của repo, không tự đặt. Go thêm `go test -race`; pytest `--durations` để thấy test chậm.
- Cổng CI: lint/static của runner đó, CI và máy local chạy cùng lệnh. Go `go vet ./...`; Python `ruff check .` khi có cấu hình; Rust `cargo clippy -- -D warnings`; Node `npm run lint` khi script tồn tại; kiểm không còn `.only`/`.skip`/`xit`/`fit` và không có test thiếu assertion (skill `qc` §7).
- Canary hoặc feature flag cho thay đổi chạm đường nóng, migration, auth: tăng dần phần lưu lượng, so các chỉ số RED với bản đang chạy cùng cửa sổ thời gian, dừng và rollback khi vượt SLO; tỉ lệ lưu lượng và thời gian quan sát chốt theo dịch vụ, không có số mặc định. Migration expand → migrate → contract (DESIGN §4) để bản cũ và mới chạy song song trong lúc canary.
<!-- /on-demand -->

## 13. UI/UX cho backend: API và DX (quy ước chi tiết ở `DESIGN.md` §7–8 của profile)
<!-- on-demand: §13 UI/UX cho backend: lỗi, phân trang, OpenAPI, CLI, giao diện quản trị -->
- Người dùng backend là lập trình viên client và người vận hành: thiết kế API, lỗi, tài liệu và công cụ dòng lệnh như một sản phẩm; mã lỗi ổn định, phân trang/lọc/sắp xếp một quy ước, OpenAPI có ví dụ thành công và lỗi, `Retry-After` và 202 cho việc dài, CLI có `--dry-run` cho thao tác phá huỷ: xem `DESIGN.md` §7–8.
- Giao diện web quản trị (nếu có) theo Zero-Slop của essentials; profile backend không cài skill UI (`ui-ux-pro-max`, `taste-mobile-app`), giao diện đáng kể thì dùng profile web.
<!-- /on-demand -->

## 14. Bộ công cụ và cách nghiệm thu
<!-- on-demand: §14 Bộ công cụ sẵn có trong kit và giới hạn áp dụng cho backend -->
- Công cụ sẵn có (tên thật; chỉ dùng phần áp dụng cho backend, phần Android/game/UI thuần bỏ qua):
- Hiệu năng: skill `observability-instrumentation` (câu hỏi chẩn đoán, p95/p99, correlation), skill `verification-before-completion` (đo xen kẽ, claim cần bằng chứng), agent `database-reliability-auditor` (N+1, index, khoá bảng, phân trang, migration), council `07-performance-anr` (chỉ agent 7.1 áp dụng, theo tương tự cho event loop; 7.2–7.5 là Android).
- Chất lượng: skill `tdd-workflow` (RED→GREEN, mutation guard), skill `qc` (phát hiện runner, bằng chứng PASS), agent `test-architect-seti` (thiết kế test, flake, orchestration CI; bỏ phần Android), agent `principal-code-reviewer` (diff nhiều file, auth, concurrency, security; bỏ lens Android và state matrix).
- API/DX và bảo mật: skill `deep-module-design` (seam, contract nhỏ, adapter thật và test), skill `security-checklist` (dùng mục tương đương web/backend: secret, CORS, telemetry; mục Android bỏ), agent `security-penetration-auditor` (secret, PII, injection, validate biên; mục exported component và WebView bỏ).
- Ngoài kit, dự án tự cài: k6 hoặc Gatling, profiler, Pact, công cụ mutation.
- `database-reliability-auditor` còn kiểm cột `mode` DEMO/LIVE: chỉ áp khi dự án có hai chế độ đó, nếu không ghi N/A.
<!-- /on-demand -->
Cách nghiệm thu (trước khi báo xong, mỗi dòng một bằng chứng chạy thật):
1. Mọi task: RED→GREEN cùng oracle (§2), runner theo `qc` exit 0 với số test > 0, gate của skill `verification-before-completion`.
2. Hiệu năng (query, đường nóng, pool, cache, worker): SLO của endpoint, EXPLAIN trước/sau, số đo trước/sau; `database-reliability-auditor` trên diff có query hoặc migration.
3. Chất lượng: test tầng thấp nhất tái hiện lỗi, DB thật, mutation guard; `test-architect-seti` khi đổi CI hoặc có flake; `principal-code-reviewer` cho diff nhiều file, auth, security.
4. API/UX (endpoint, lỗi, phân trang, CLI): diff OpenAPI không phá tương thích (§3), danh sách mã lỗi, contract test; `security-penetration-auditor` khi chạm input ngoài, secret, PII.
5. Thiếu môi trường giống production hoặc công cụ đo: ghi "CHƯA ĐO" kèm thứ đã chạy thay, không claim hiệu năng.
