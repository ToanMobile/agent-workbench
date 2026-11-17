# Web Application Engineering Rules (Frontend / Full-Stack JS)

## 1. Solo-Dev & Git Security (BẮT BUỘC)
- Tự commit/push khi xong và danh sách việc phải hỏi người dùng trước: DevKit essentials trong `AGENTS.md`, mục Git và Working style.
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

## 9. Chuẩn Thiết Kế Giao Diện & Chống AI Slop (Impeccable Craft Floor)
- Khi dựng mới, làm lại hoặc audit giao diện Web (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`, `.html`, `.css`), kích hoạt skill `impeccable` (`/impeccable` với các verb `shape`, `critique`, `audit`, `polish`, `distill`, `typeset`, `colorize`, `layout`) để khoá ngữ cảnh thiết kế (`DESIGN.md` / `PRODUCT.md`) và quét lỗi thẩm mỹ bằng `.agents/skills/impeccable/scripts/impeccable detect <path>`.
- **Zero-Slop bắt buộc:** cấm kicker/eyebrow chữ in hoa nhỏ đặt phía trên heading; cấm viền nhấn cạnh thẻ dày > 1px (`border-left: 3px/4px` kiểu side-tab); cấm chữ gradient (`background-clip: text`), glow shadow tím-xanh, card lồng trong card và lưới 3 cột icon-trên-heading rập khuôn; cấm lạm dụng `Inter`/`Roboto` làm display font mặc định khi chưa có chủ đích thiết kế.
- **Typography & Bố cục số liệu:** độ rộng dòng văn bản đọc (measure) giữ ở mức `65–75ch`; cột số liệu, giá tiền, bộ đếm thời gian và bảng dữ liệu bắt buộc bật `font-variant-numeric: tabular-nums`; ưu tiên không gian trắng, đường kẻ mảnh 1px và phân cấp kích thước chữ rõ ràng thay vì bọc mọi khối vào card.
- **Vệ sinh thư mục runtime `.impeccable/`:** trạng thái phiên thiết kế cục bộ (`.impeccable/live/`, `.impeccable/runs/`, `.impeccable/config.local.json`) không được commit lên git (CLI tự ghi vào `.git/info/exclude`; nếu tạo tay thì thêm vào `.gitignore`), chỉ commit `.impeccable/config.json` khi team thống nhất chia sẻ cấu hình rule.

## 10. Hiệu năng chi tiết (mở rộng §5, không thay thế)
Mỗi con số mang nhãn nguồn. Nhãn "mặc định đề xuất của dự án, cần đo thật" nghĩa là chưa có nguồn chuẩn: đo trên chính app rồi chỉnh, không coi là chuẩn ngành.

| Chỉ số / ngân sách | Ngưỡng | Nguồn |
|---|---|---|
| LCP | tốt ≤ 2.5s, kém > 4s | web.dev/vitals (đánh giá ở phân vị 75 của lượt tải thật, tách mobile và desktop) |
| INP | tốt ≤ 200ms, kém > 500ms | web.dev/vitals (cùng cách đánh giá) |
| CLS | tốt ≤ 0.1, kém > 0.25 | web.dev/vitals (cùng cách đánh giá) |
| Tác vụ dài (long task) trên luồng chính | > 50ms | web.dev (Long Tasks API) |
| Điểm Lighthouse Performance dùng làm cổng CI | ≥ 90 (mobile, route chính) | dải 90–100 là mức "tốt" theo Lighthouse scoring (web.dev); dùng làm cổng là mặc định đề xuất của dự án, cần đo thật |
| JS nạp cho route đầu (sau nén) | ≤ 200 KB | mặc định đề xuất của dự án, cần đo thật |
| Ảnh LCP | ≤ 200 KB | mặc định đề xuất của dự án, cần đo thật |
| Font ở lần tải đầu | ≤ 2 họ, ≤ 4 tệp WOFF2 | mặc định đề xuất của dự án, cần đo thật |

- **Lab và field là hai việc khác nhau.** Lab (Lighthouse, Lighthouse CI, Playwright) lặp lại được, dùng bắt hồi quy trước khi merge; field (RUM, thư viện `web-vitals`: `onLCP`/`onINP`/`onCLS`) mới quyết định "tốt" theo phân vị 75. Lighthouse không đo INP: chỉ có TBT làm chỉ báo thay trong lab (web.dev), nên INP phải lấy từ RUM hoặc kịch bản tương tác thật. RUM theo `observability-instrumentation`: không PII, nhãn URL là template thấp biến thể, không bịa ngưỡng cảnh báo.
- **Cổng ngân sách:** ngân sách số nằm trong cấu hình CI của dự án (Lighthouse CI `assert` hoặc budget của bundler), không chỉ trong tài liệu. DevKit không ship cấu hình này; thiếu thì ghi rõ "chưa có cổng đo", không báo PASS.
- **Mạng chậm, máy yếu:** đo bằng profile mobile của Lighthouse (giả lập mạng chậm + giảm tốc CPU) hoặc DevTools throttling; không kết luận từ máy dev nhanh trên mạng văn phòng. Kiểm thêm trạng thái offline/timeout hiển thị đúng (`DESIGN.md` mục 11).
- **Chặn render:** CSS tới hạn nhỏ; `<script>` ở `<head>` phải `defer`/`type="module"`/`async`; script bên thứ ba cần lý do, nạp muộn, không nằm trên đường tới LCP.
- **LCP:** phần tử LCP (thường ảnh hero) không `loading="lazy"`; dùng `fetchpriority="high"` hoặc `preload` khi đo thấy cần; ảnh responsive (`srcset`/`sizes`) kèm `width`/`height`.
- **Font:** WOFF2, subset theo ngôn ngữ dùng, `font-display` chọn có chủ đích (`swap` hoặc `optional`), preload font chính; fallback có metric gần font thật để giảm CLS.
- **Caching:** tệp build có hash trong tên đặt `Cache-Control` dài kèm `immutable`; HTML không cache lâu (revalidate); nén brotli/gzip; không đưa dữ liệu theo người dùng vào cache chung/CDN.
- **Chia mã và bundle:** chia theo route (§5), `import()` cho widget nặng dưới màn đầu; xem báo cáo bundle (analyzer của bundler) khi thêm dependency và ghi chênh lệch KB; không import cả thư viện cho một hàm.
- **Luồng chính:** không tính toán đồng bộ nặng trong event handler; tách việc dài (chia nhỏ, `requestIdleCallback`/worker). Council `07-performance-anr.md` viết cho Android (ANR, Binder): trên web chỉ lấy ý chống chiếm luồng chính, bỏ phần Android. Animation chỉ `transform`/`opacity`, không đọc-ghi layout xen kẽ trong vòng lặp (kiểm bằng `impeccable` `audit`/`optimize`).
- **Bằng chứng cải thiện:** tuyên bố "nhanh hơn" cần đo xen kẽ AB,BA ≥ 5 cặp sau warmup; `range > 20% median` hoặc hai dải chồng lấp thì báo `inconclusive` (`verification-before-completion`).

## 11. Chất lượng & Kiểm thử (mở rộng §2 và §8)
- **Kim tự tháp:** unit (Vitest/Jest) cho logic dùng chung; integration (Testing Library + MSW) chiếm phần lớn; E2E Playwright ít, đi qua hành trình quan trọng, headless trong CI (khớp §8, không đặt tỷ lệ số vì các nguồn không nêu).
- **Playwright:** chọn phần tử bằng `getByRole`/`getByLabel`/`getByTestId`, assert dạng web-first (`await expect(locator)...`, tự chờ), cấm `waitForTimeout`; CI bật `forbidOnly`; `trace: 'on-first-retry'` để có dấu vết khi flaky. Thử viewport mobile và desktop (`devices`), cả theme sáng và tối cho màn có giao diện riêng.
- **Chống flaky:** retry chỉ để thu trace, test chỉ xanh nhờ retry vẫn là test lỗi phải sửa; cô lập dữ liệu mỗi test, không phụ thuộc thứ tự (§8), chặn mạng/đồng hồ thật. Nghi flaky thì chạy lặp (`--repeat-each`) trước và sau sửa; số lần lặp là mặc định đề xuất của dự án, cần đo thật. Không `.skip` âm thầm: test bị bỏ qua phải có lý do được chủ repo chấp nhận (`qc` mục 3); rà flake và cấu trúc test với agent `test-architect-seti`.
- **Visual regression:** ảnh chuẩn (`toHaveScreenshot`) sinh và so trong cùng môi trường CI (cùng OS/trình duyệt/font), che vùng động (ngày giờ, quảng cáo), tắt animation; thay ảnh chuẩn phải được người xem diff, không cập nhật hàng loạt cho xanh. Kiểm bố cục đo trên DOM (tràn khung, lệch, chồng lấp, chạm cạnh) bằng `qa-visual` khi dự án có `qa.config.json`.
- **A11y tự động:** chạy axe (`@axe-core/playwright`) trên mỗi route chính, với thẻ WCAG A/AA, ở viewport hẹp và rộng, theme sáng và tối; fail khi có vi phạm mức serious/critical. Axe chỉ bắt một phần lỗi: vẫn phải duyệt bàn phím và đọc cây accessibility (§12); `qa-visual --a11y` thêm kiểm tương phản chữ và vùng chạm ≥ 44×44.
- **Cổng CI theo thứ tự rẻ trước đắt:** lint, `tsc --noEmit` (REG-WEB-02), unit/integration (REG-WEB-01), build, E2E + axe, Lighthouse CI, visual regression. Ma trận hồi quy của kit chỉ chạy hai mục REG-WEB; phần còn lại là CI của dự án, thiếu thì ghi residual.
- **Test UI/route chỉ tính đạt khi** render dữ liệu hoặc trạng thái rỗng thật (không chỉ shell/spinner), 0 `console.error`/`pageerror`, 0 request nền 5xx/401/403 (`verification-before-completion`).
- Coverage, mutation testing, linter test: theo §8; không tự đặt ngưỡng khi dự án đã có.

## 12. UI/UX & Accessibility chi tiết (mở rộng §7, §9 và `DESIGN.md`)
- **Responsive:** mobile-first; kiểm ở 360, 768, 1024 và 1440 CSS px (mặc định đề xuất của dự án, cần đo thật). Không cuộn ngang ở 320 CSS px (WCAG 2.2 SC 1.4.10 Reflow); chữ phóng 200% không mất nội dung (SC 1.4.4); dùng đơn vị tương đối, không chiều rộng cố định. Ảnh, bảng, code block tự co hoặc cuộn trong khung riêng.
- **Token, không hardcode:** màu, cỡ chữ, khoảng cách, bo góc, bóng, z-index lấy từ `DESIGN.md`; không mã hex thô trong component. Typography fluid và quy tắc dark mode, chuyển động, trạng thái nằm trong `DESIGN.md`.
- **Vùng chạm:** giữ ≥ 44×44px (§7); WCAG 2.2 AA (SC 2.5.8) chỉ đòi tối thiểu 24×24 CSS px, còn 44×44 là mức SC 2.5.5 (AAA): 44 là lựa chọn chặt hơn của dự án. Kiểm bằng `qa-visual --a11y` hoặc `impeccable` `audit`.
- **Tương phản:** chữ thường ≥ 4.5:1, chữ lớn (≥ 18pt hoặc ≥ 14pt đậm) ≥ 3:1 (SC 1.4.3); thành phần UI, biên input và focus ring ≥ 3:1 so với nền kề (SC 1.4.11). Đo bằng công cụ trên cả theme sáng và tối, không đoán bằng mắt.
- **Focus & bàn phím:** `:focus-visible` rõ (SC 2.4.7); phần tử đang focus không bị header/banner dính che hoàn toàn (SC 2.4.11, mới ở WCAG 2.2); không bẫy bàn phím; modal giữ focus bên trong và trả focus về nút mở; thứ tự Tab theo thứ tự đọc; có skip link ở trang nhiều điều hướng. Mọi thao tác kéo-thả phải có cách thay thế bằng bấm (SC 2.5.7); xác thực không bắt người dùng nhớ/chép mã (SC 3.3.8, cho phép dán mật khẩu và trình quản lý mật khẩu).
- **Dark mode:** theo `prefers-color-scheme` + `color-scheme`, chuyển chỉ bằng đổi giá trị token (không đảo màu bằng filter); không nháy sai theme khi tải; kiểm tương phản và ảnh chụp ở cả hai theme.
- **Giảm chuyển động:** `prefers-reduced-motion: reduce` thay chuyển động bằng phản hồi tĩnh (đổi màu/mờ dần) chứ không xoá phản hồi trạng thái; không nhấp nháy quá 3 lần/giây (SC 2.3.1); nội dung tự chạy > 5 giây phải dừng/ẩn được (SC 2.2.2).
- **Bốn trạng thái mọi màn dữ liệu:** rỗng (giải thích + hành động tiếp theo), đang tải (skeleton giữ đúng kích thước để không gây CLS, kèm trạng thái cho trình đọc màn hình), lỗi (nói rõ chuyện gì, cho thử lại, `role="alert"` hoặc vùng `aria-live`, không lộ stack), thành công. Nút gọi API theo §6. Dựng và rà bằng `impeccable` `onboard` (rỗng/lần đầu) và `harden` (lỗi, i18n, biên).
- **Zero-Slop:** theo §9 và `DESIGN.md`; chạy `impeccable detect <path>` trước khi báo xong. Màu xám trung tính pha 3–5% tông chủ đạo, nhịp khoảng cách 4–8 / 12–16 / 24–32 (không 16 khắp nơi); không card lồng card, không ô icon trên heading.

## 13. Bộ công cụ & Cách nghiệm thu
Chỉ dùng thứ có trong kit. Skill/agent viết cho Android hoặc Mobile thì chỉ lấy phần chung, ghi rõ phần bỏ.

| Tình huống | Chạy | Dùng để |
|---|---|---|
| Hiệu năng (thêm dependency, ảnh, font, route, script ngoài; sửa bị chậm) | `impeccable` `audit`/`optimize`; `verification-before-completion`; `observability-instrumentation`; council `07-performance-anr.md` | kiểm mã tĩnh (layout thrash, animation đắt, ảnh chưa tối ưu); chuẩn bằng chứng cải thiện; RUM không PII; ý chống chiếm luồng chính (bỏ phần Android) |
| Chất lượng (logic mới, bug, test) | `tdd-workflow` (+ `references/testing-practices.md`); `qc`; agent `test-architect-seti`; agent `principal-code-reviewer` | RED→GREEN và test JS/TS; lint + test theo `package.json`; rà test/flake (bỏ phần Android); review diff theo lens correctness, UX/a11y, bảo mật, kiến trúc (bỏ phần Kotlin/Android) |
| Bảo mật bề mặt trình duyệt | `security-checklist` (phương pháp: mỗi finding có đường tấn công tới được và bằng chứng; bản kê Android bỏ qua, dùng §4) | rà XSS/CSRF/secret/CSP |
| UI/UX (màn mới, làm lại, sửa giao diện) | `impeccable` (`shape`, `critique`, `audit`, `adapt`, `polish`, `detect`); `qa-visual`; `ui-ux-pro-max`; agent `real-device-ui-auditor` | thiết kế và rà thẩm mỹ; chụp route × viewport + audit bố cục đo trên DOM + `--a11y`; tra cứu hướng dẫn UX/stack bằng `search.py --domain ux` hoặc `--stack <stack>` với stack là react, nextjs, vue, svelte hoặc html-tailwind (phạm vi gốc là Mobile/Game, bỏ checklist native trong `references/pro-rules.md`; ưu tiên `impeccable` cho web); vùng chạm, tràn khung, ảnh nghiệm thu (agent viết cho Android: chỉ lấy ý ≥ 44px web, tràn khung, bằng chứng thật) |

**Cách nghiệm thu (trước khi báo xong; chỉ nêu bước thật sự áp dụng cho thay đổi):**
1. Mọi thay đổi mã: RED→GREEN theo §2, rồi gate của DevKit (REG-WEB-01 và REG-WEB-02) exit 0.
2. Đổi giao diện: mở màn ở 360 và 1440 CSS px, theme sáng và tối, với dữ liệu thật, rỗng và lỗi; `impeccable detect <path>` sạch; `qa-visual` (cả `--a11y`) khi có `qa.config.json`; axe trong E2E; một lượt duyệt bàn phím thật; ảnh nghiệm thu theo `AGENTS.md`.
3. Đổi có thể ảnh hưởng hiệu năng: so KB bundle/ảnh/font với §10, chạy Lighthouse mobile nhiều lần lấy trung vị, đối chiếu RUM nếu có; tuyên bố cải thiện cần đủ bằng chứng AB,BA của §10.
4. Công cụ hoặc cổng thiếu (không có `qa.config.json`, Lighthouse CI, Playwright...) thì nêu là residual chưa kiểm; không viết PASS thay phần chưa chạy.
