# Web Application Engineering Rules (Frontend / Full-Stack JS)

## 1. Solo-Dev & Git Security (BẮT BUỘC)
- Việc xong (gate `--full` exit 0, ảnh khi cần, báo cáo nghiệm thu) thì TỰ commit đúng các file của mình và push nhánh hiện tại, không hỏi (quy trình pull/test lại/push: `rules/essentials.md` mục Git). Chỉ hỏi người dùng trước: force-push/viết lại lịch sử, xoá nhánh/tag, phát hành cho người dùng thật (store, deploy production).
- Không commit `.env*` (trừ `.env.example` chỉ chứa placeholder), token, cookie, service account.
- Biến môi trường lộ ra trình duyệt (`NEXT_PUBLIC_*`, `VITE_*`) là **công khai** — tuyệt đối không đặt secret vào đó.

## 2. Paired Executable Oracle & TDD
1. **RED:** viết test tái hiện lỗi (Vitest/Jest/Playwright), chạy và xác nhận FAIL.
2. **GREEN:** sửa tối giản cho test PASS; không xoá/nới assertion, không `.skip`/`.only` còn sót.
- Lệnh test lấy từ `package.json` (`npm test` / `pnpm test` / `yarn test`) — không tự bịa script.

## 3. TypeScript & Hợp đồng dữ liệu
- `strict: true`; cấm `any` mới và `@ts-ignore` không kèm lý do.
- Dữ liệu từ network/URL/localStorage là **không tin cậy**: validate bằng schema (zod/valibot/io-ts) tại biên.

## 4. Bảo mật trình duyệt
- Không `dangerouslySetInnerHTML` / `v-html` / `innerHTML` với dữ liệu người dùng khi chưa sanitize.
- Mutation phải có bảo vệ CSRF (SameSite cookie + token) và kiểm tra quyền ở server, không chỉ ẩn nút ở UI.
- Token phiên để trong cookie `HttpOnly; Secure`, không để trong `localStorage`.

## 5. Hiệu năng & Core Web Vitals
- Ngân sách: LCP ≤ 2.5s, INP ≤ 200ms, CLS ≤ 0.1 trên máy tầm trung.
- Ảnh có kích thước cố định + lazy-load; code-split theo route; không import cả thư viện cho một hàm.
- Tránh re-render thừa: memo hoá có đo đạc, key ổn định cho list.

## 6. Chống Spam & Bất đồng bộ
- Nút gọi API phải disable + hiển thị loading ngay khi bấm; submit form idempotent.
- Huỷ request cũ khi input đổi (AbortController) để tránh race hiển thị dữ liệu cũ.

## 7. Accessibility (WCAG 2.2 AA)
- Vùng bấm ≥ 44×44px, tương phản ≥ 4.5:1, focus ring nhìn thấy, điều hướng bàn phím đầy đủ.
- Dùng phần tử HTML ngữ nghĩa trước ARIA; mọi ảnh có `alt`, mọi input có `<label>`.

## 8. Kiến trúc feature-based & Chất lượng mã (nguồn: alan2207/bulletproof-react · ryanmcdermott/clean-code-javascript · goldbergyoni/javascript-testing-best-practices)
- Cấu trúc `src/features/<tên>/{api,components,hooks,stores,types,utils}`; feature KHÔNG import feature khác, luồng một chiều shared → features → app. Ép bằng ESLint `import/no-restricted-paths` (severity error) và đặt tên file/thư mục kebab-case (`check-file`); vi phạm làm CI đỏ.
- Một API client duy nhất; mỗi endpoint gồm type/schema + fetcher + query hook đặt cùng chỗ. Interceptor xử lý chung (thông báo, 401 → refresh/đăng xuất).
- Tách loại state: component, application, server cache (React Query/SWR), form, URL. Dữ liệu server không nhét vào global store; state đặt gần chỗ dùng; Context chỉ cho dữ liệu đổi chậm.
- Nhiều error boundary theo vùng (không một boundary bọc cả app); production báo lỗi lên tracker kèm source map, không kèm PII (core §11).
- Quy ước review: hàm ≤ 2 tham số (nhiều hơn → options object), một việc, không cờ boolean, không mutate tham số, không code chết/comment-out, magic number → hằng số, `===`, `async/await`, không để promise nổi (`no-floating-promises`).
- Test: phần lớn là integration (Testing Library + MSW chặn HTTP, không mock `fetch`), unit cho logic dùng chung, E2E Playwright ít và chạy headless trong CI. Tên test 3 phần (đơn vị, kịch bản, kết quả), AAA, một khái niệm/test; mỗi test tự tạo dữ liệu, không seed toàn cục; truy vấn UI theo label/test-id (hoặc role khi dùng Testing Library); không `sleep` cố định. Coverage: nguồn nói ~80% là đủ, coi là sàn là quy ước DevKit và chỉ áp khi dự án chưa có ngưỡng (theo `tdd-workflow`); mutation testing cho module quan trọng; linter test cấm test không assert. Chi tiết: `skills/deep-module-design/references/architecture-web.md` và `skills/tdd-workflow/references/testing-practices.md`.
