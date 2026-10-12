# Kiến trúc Web — alan2207/bulletproof-react (chỉ cho profile `web`)

Phạm vi: chỉ đọc khi profile đang hoạt động là `web`. Profile game, automotive, android, backend, ios không dùng file này.
Nguồn đã đọc 2026-10-12: README và `docs/` (project-structure, project-standards, state-management, api-layer, error-handling, security, performance, testing). Nguồn tự nhận là khuyến nghị có chủ kiến; không nêu ngưỡng số. Rule ngắn: `profiles/web/rules/web-rules.md` §8.

- `src/{app,assets,components,config,features,hooks,lib,stores,testing,types,utils}`; phần lớn mã nằm trong `features/`; mỗi feature chứa `api, assets, components, hooks, stores, types, utils` chỉ khi cần.
- Feature không import feature khác (ghép ở tầng app); luồng shared → features → app. Ép bằng ESLint `import/no-restricted-paths` với `zones` cho từng feature (`target`, `from`, `except`), severity error.
- Chuẩn: ESLint + Prettier + TypeScript, Husky pre-commit (lint, format, typecheck), import tuyệt đối `@/*`, tên file/thư mục kebab-case (`check-file`).
- State chia 5 loại: component, application, server cache, form, URL; bắt đầu cục bộ, chỉ nâng lên khi cần.
- API: một client cấu hình sẵn; mỗi request khai riêng cùng chỗ (type + schema, fetcher, query hook). Interceptor (ở tài liệu error-handling) xử lý thông báo chung, đăng xuất khi unauthorized, refresh token.
- Lỗi: nhiều error boundary theo vùng; production dùng tracker kiểu Sentry và upload source map.
- Bảo mật: JWT trong bộ nhớ an toàn hơn nhưng mất khi refresh; `localStorage` bị XSS đọc được; ưu tiên cookie `HttpOnly`; sanitize HTML người dùng; phân quyền RBAC/PBAC ở UI chỉ là tiện ích, API vẫn phải ép.
- Hiệu năng: tách code theo route (đừng chia quá nhỏ), đặt state gần nơi dùng, Context chỉ cho dữ liệu đổi chậm, ảnh lazy, theo dõi Web Vitals.
- Test: dồn công sức vào integration (Testing Library, MSW, Vitest), unit cho logic dùng chung/phức tạp, Playwright E2E headless trong CI.
- Thực hành kiểm thử và mã sạch JS/TS: `skills/tdd-workflow/references/testing-practices.md`.
