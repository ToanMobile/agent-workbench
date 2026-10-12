# Kiến trúc Backend — Sairyss/domain-driven-hexagon (chỉ cho profile `backend`)

Phạm vi: chỉ đọc khi profile đang hoạt động là `backend`. Profile game, automotive, android, web, ios không dùng file này.
Nguồn đã đọc 2026-10-12: README đầy đủ. Nguồn tự nhận là khuyến nghị, không phải luật, và "không hợp với CRUD đơn giản": không dựng tầng cho CRUD nhỏ (core §4). Rule ngắn: `profiles/backend/rules/backend-rules.md` §8.

- Bốn tầng: domain (entity, aggregate, value object, domain service, domain event), application (service = use case, command, query, port), infrastructure (repository, ORM model, adapter), interface (controller, DTO). Phụ thuộc hướng vào trong; lõi không dùng framework hay tài nguyên ngoài.
- Port là interface theo nhu cầu domain; adapter triển khai và được nối bằng DI. Lạm dụng port là trừu tượng thừa.
- Module = bounded context theo lát cắt dọc (`commands, queries, domain, database, dtos`); không import chéo module, dùng facade/mediator/message.
- CQS: command đổi state và chỉ trả metadata; tránh command gọi command (dùng command → event → command); query chỉ đọc và có thể đọc DB trực tiếp.
- Entity: bình đẳng theo identity, tự bảo vệ bất biến, fail fast, không public setter. Aggregate: một cửa vào, tham chiếu bằng ID, giữ nhỏ, transaction theo aggregate. Value object bất biến, so sánh theo giá trị, không đặt trong DTO/event/model DB.
- Event: domain event chạy trong tiến trình; integration event ra ngoài sau khi lưu (Outbox/Saga/CDC được nhắc tới).
- Guard (ném, trong domain) khác validate (lọc input ngoài, trả lỗi): validate DTO ở biên (class-validator), không ném HTTP exception trong domain.
- Lỗi nghiệp vụ phục hồi được trả kiểu Result/ADT; lỗi kỹ thuật ném; controller ánh xạ sang HTTP, không biết → 500. Response DTO whitelist field; thay đổi phá vỡ dùng version path (`v2/users`).
- Ép kiến trúc bằng công cụ: dependency-cruiser rule `no-domain-deps` (domain/entity/aggregate/value-object không import api/controller/dtos/database/repository), ArchUnit cho Java.
- Cấu trúc mã: nhóm theo hành vi, hậu tố theo vai trò, kế thừa tối đa 1–2 cấp, ưu tiên composition.
- CHƯA XÁC MINH: mục testing riêng (nguồn trỏ sang tài liệu khác), logging/observability và security không có mục riêng trong README.
- Node.js production và OTel: `backend-rules.md` §9–10; `skills/observability-instrumentation/references/otel-signals.md`.
