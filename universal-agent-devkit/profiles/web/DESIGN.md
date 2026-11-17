# DESIGN.md — Web Design System & UI Guidelines for AI Agents

> **Chỉ thị cho AI Agent:** trước khi sinh/sửa UI (React/Vue/Svelte/HTML/CSS/Tailwind), đọc và dùng đúng token trong tệp này. Không hardcode mã màu, cỡ chữ hay khoảng cách lạ — dùng CSS custom properties hoặc theme của dự án.

## 1. Color Tokens (CSS custom properties)

| Token | Light | Dark | Dùng cho |
|---|---|---|---|
| `--color-primary` | `#2563EB` | `#60A5FA` | CTA, link, trạng thái active |
| `--color-on-primary` | `#FFFFFF` | `#0B1220` | Chữ/icon trên nền primary |
| `--color-bg` | `#FFFFFF` | `#0B0F17` | Nền trang |
| `--color-surface` | `#F8FAFC` | `#111827` | Card, popover, modal |
| `--color-text` | `#0F172A` | `#E5E7EB` | Nội dung chính |
| `--color-text-muted` | `#475569` | `#9CA3AF` | Chữ phụ (vẫn ≥ 4.5:1 trên nền) |
| `--color-border` | `#E2E8F0` | `#1F2937` | Viền input, divider |
| `--color-success` / `--color-warning` / `--color-danger` | `#059669` / `#B45309` / `#DC2626` | `#34D399` / `#FBBF24` / `#F87171` | Trạng thái |

- Hỗ trợ `prefers-color-scheme` và `prefers-reduced-motion`.

## 2. Typography (rem, base 16px)

| Level | Size | Line height | Weight |
|---|---|---|---|
| Display | 2rem | 1.25 | 700 |
| H1 / H2 / H3 | 1.5 / 1.25 / 1.125rem | 1.3 | 600 |
| Body | 1rem | 1.5 | 400 |
| Small / Caption | 0.875 / 0.75rem | 1.4 | 400–500 |

- Chữ body không nhỏ hơn 16px trên mobile (tránh iOS zoom khi focus input).

## 3. Spacing & Layout
- Thang 4px: 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64.
- Breakpoints: `sm 640`, `md 768`, `lg 1024`, `xl 1280`; thiết kế mobile-first.
- Nội dung đọc dài: tối đa ~70 ký tự mỗi dòng.

## 4. Accessibility (WCAG 2.2 AA)
- Vùng bấm ≥ 44×44px, khoảng cách giữa 2 target ≥ 8px.
- Tương phản chữ ≥ 4.5:1 (chữ lớn ≥ 3:1); focus ring rõ (`:focus-visible`, 2px, tương phản ≥ 3:1).
- Mỗi component tương tác có đủ trạng thái: default, hover, active, focus-visible, disabled (`aria-disabled` + không nhận click).
- Form: `<label>` gắn với input, thông báo lỗi liên kết bằng `aria-describedby`, không chỉ dùng màu để báo lỗi.

## 5. Motion & Media
- Transition 150–250ms, ease-out; tắt animation không cần thiết khi `prefers-reduced-motion: reduce`.
- Ảnh có `width`/`height` (chống CLS), định dạng AVIF/WebP, `loading="lazy"` dưới fold.
- Icon SVG inline hoặc sprite, `aria-hidden="true"` nếu chỉ trang trí.

---
Các mục 6–12 bổ sung cho mục 1–5, không thay. Mọi số mục 6–10 là mặc định đề xuất của dự án, cần đo thật (chỉnh theo thương hiệu rồi kiểm lại bằng công cụ), trừ số ghi rõ tiêu chí WCAG; các mục 6–10 nhắc lại nhãn này ở đầu mục.

## 6. Token bổ sung (cùng quy tắc: không hardcode trong component)
Nhãn số: mặc định đề xuất của dự án, cần đo thật; tỷ lệ tương phản là số tính theo công thức WCAG.
Tỷ lệ tương phản bên dưới do agent tự tính bằng công thức WCAG 2.x trên bảng mục 1.

| Token | Light | Dark | Ghi chú |
|---|---|---|---|
| `--color-border-strong` | `#64748B` (4.76:1 trên nền `#FFFFFF`, 4.55:1 trên surface `#F8FAFC`) | `#6B7280` (3.97:1 trên nền `#0B0F17`, 3.67:1 trên surface `#111827`) | Biên input, checkbox, nút outline: cần ≥ 3:1 (WCAG SC 1.4.11). `--color-border` mục 1 chỉ dành cho divider trang trí (khoảng 1.2–1.3:1) |
| `--color-success-text` | `#047857` (5.48:1 trên nền `#FFFFFF`) | dùng `--color-success` | `--color-success` light (3.77:1 trên nền `#FFFFFF`) chỉ đủ cho icon, viền, chữ lớn; chữ thường báo thành công dùng token này |
| `--focus-ring` | 2px `--color-primary`, offset 2px | như light | Mục 4 đã quy định độ dày và tương phản |
| `--radius-sm` / `--radius-md` / `--radius-lg` | 4 / 8 / 12px | như light | đề xuất; một họ bo góc cho cả app |
| `--shadow-sm` / `--shadow-md` | bóng xám pha tông chủ đạo, mờ | không dùng bóng để tạo độ cao | Cấm glow tím-xanh (xem `rules/web-rules.md` §9); dark mode tạo độ cao bằng `--color-surface` sáng hơn một bậc |
| `--z-sticky` / `--z-overlay` / `--z-modal` / `--z-toast` | 10 / 100 / 200 / 300 | như light | đề xuất; không viết `z-index` số thô trong component |

- Chữ `danger` đạt 4.83:1 trên nền `#FFFFFF` và 4.62:1 trên surface `#F8FAFC`; `warning` đạt 5.02:1 trên nền và 4.8:1 trên surface (theme sáng); ở theme tối `danger` và `warning` đều ≥ 4.5:1 trên nền `#0B0F17` và surface `#111827` theo bảng tính; chữ `success` ở theme sáng phải dùng `--color-success-text`.
- Màu không phải kênh duy nhất báo trạng thái: kèm icon hoặc nhãn.

## 7. Typography fluid
Nhãn số: mặc định đề xuất của dự án, cần đo thật.
- Chỉ Display và H1 co giãn theo viewport: `clamp(2rem, 1.5rem + 2vw, 3rem)` (Display) và `clamp(1.5rem, 1.25rem + 1vw, 2rem)` (H1); đề xuất. Cận dưới bằng đúng cỡ ở mục 2 nên màn hẹp không đổi.
- Luôn có thành phần `rem` trong `clamp` (không chỉ `vw`) để người dùng phóng chữ 200% vẫn thấy chữ lớn lên (WCAG SC 1.4.4). Không dùng `vw` thuần cho chữ.
- Body, Small, Caption cố định theo mục 2 (không fluid). Không đặt `user-scalable=no` hay `maximum-scale` trong viewport meta.
- Đơn vị `rem` cho cỡ chữ và khoảng cách; `px` chỉ cho viền 1px và vùng chạm tối thiểu. Font hệ thống hoặc font tự host (WOFF2, subset); `font-display` chọn có chủ đích (xem `rules/web-rules.md` §10).

## 8. Layout & khoảng cách thích ứng
Nhãn số: mặc định đề xuất của dự án, cần đo thật (trừ 320 CSS px của WCAG SC 1.4.10).
- Kiểm 4 mốc: 360 (điện thoại nhỏ), 768, 1024, 1440 CSS px (đề xuất); không cuộn ngang ở 320 CSS px (WCAG SC 1.4.10).
- Lề ngang trang: 16px ở < 640, 24px từ `sm`, 32px từ `lg` (đề xuất); khoảng cách dùng thang mục 3 theo nhịp: 4–8 trong một nhóm, 12–16 trong một khối, 24–32 giữa các section.
- Khung nội dung `max-width` theo `rem` (đề xuất 72rem) và căn giữa; bảng dữ liệu cuộn ngang trong khung riêng, không làm cả trang cuộn ngang.
- Vùng an toàn thiết bị có tai thỏ: cộng `env(safe-area-inset-*)` cho thanh dính trên/dưới.
- Ưu tiên `gap`, `grid`, `flex-wrap` hơn chiều rộng cố định; ảnh/video `max-width: 100%` kèm `aspect-ratio`.

## 9. Vùng chạm & con trỏ
Nhãn số: 44px là lựa chọn của dự án (mặc định đề xuất của dự án, cần đo thật); 24×24 là số của WCAG SC 2.5.8.
- Mục tiêu bấm ≥ 44×44px (mục 4); vùng bấm được phép lớn hơn phần vẽ (padding hoặc pseudo-element), icon 24px vẫn có vùng bấm 44px.
- WCAG 2.2 SC 2.5.8 (AA) là sàn 24×24 CSS px (có ngoại lệ về khoảng cách): 44px là lựa chọn chặt hơn của dự án, không hạ xuống 24px.
- Hover chỉ là phụ: mọi chức năng đạt được không cần hover (`@media (hover: hover)` cho hiệu ứng thêm). Màn cảm ứng không phụ thuộc chuột phải, rê chuột hay kéo thả không có phương án bấm (SC 2.5.7).
- Bề mặt kéo (slider, danh sách sắp xếp) khai `touch-action` phù hợp và xử lý huỷ cử chỉ.

## 10. Chuyển động
Nhãn số: mặc định đề xuất của dự án, cần đo thật.
- Token thời lượng (đề xuất): `--duration-fast` 150ms, `--duration-base` 200ms, `--duration-slow` 250ms (nằm trong dải 150–250ms mục 5); easing `ease-out` khi vào, thoát nhanh hơn vào.
- Chỉ animate `transform` và `opacity`; không animate `width`/`height`/`top`/`left`, không `will-change` rải khắp nơi.
- `prefers-reduced-motion: reduce`: thay dịch chuyển/phóng to bằng đổi màu hoặc mờ dần giữ nguyên phản hồi trạng thái; không tắt toàn bộ transition bằng `0.01ms` đại trà.
- Chuyển động phải truyền đạt thay đổi trạng thái hoặc quan hệ không gian; không lặp vô hạn quá 5 giây nếu không dừng được (SC 2.2.2); không nhấp nháy quá 3 lần/giây (SC 2.3.1).

## 11. Trạng thái màn hình & component
| Trạng thái | Mô tả | Yêu cầu |
|---|---|---|
| Đang tải | Skeleton đúng kích thước nội dung thật, hoặc spinner trong nút | Không dịch chuyển bố cục khi nội dung về (CLS); `aria-busy` hoặc vùng `role="status"` |
| Rỗng | Một câu giải thích + một hành động chính | Không để khoảng trắng trơn; không minh hoạ rập khuôn |
| Lỗi | Nói rõ lỗi gì và cách thử lại; giữ dữ liệu người dùng đã nhập | `role="alert"` (hoặc `aria-live`), không lộ stack/mã nội bộ, có nút thử lại |
| Thành công | Phản hồi tức thì tại chỗ vừa thao tác | Toast không là nơi duy nhất: trạng thái cũng hiện trong giao diện |
| Ngoại tuyến / chậm | Báo rõ khi mất mạng hoặc quá thời gian | Giữ nội dung đã có, cho thử lại |
| Vô hiệu | `aria-disabled` + không nhận click (mục 4) | Chữ vô hiệu vẫn đọc được; không dùng độ mờ làm cách duy nhất |
- Mỗi màn dữ liệu liệt kê đủ trạng thái trên trước khi coi là xong; nút bất đồng bộ theo `rules/web-rules.md` §6.

## 12. Dark mode
- Hai bộ giá trị cho cùng một tên token (mục 1); chuyển bằng `prefers-color-scheme` và `color-scheme: light dark` ở `:root`. Nếu có nút đổi theme thì ghi lựa chọn của người dùng và áp trước khi vẽ để không nháy sai theme.
- Không đảo màu bằng `filter: invert`; không thêm màu nền ngoài token (đen thuần `#000000` làm nền lớn trong theme tối bị cấm); giảm độ sáng ảnh quá chói khi cần.
- Độ cao lớp thể hiện bằng surface sáng dần, không bằng bóng đổ (mục 6).
- Kiểm tương phản (≥ 4.5:1 chữ, ≥ 3:1 thành phần UI) và ảnh chụp riêng cho theme tối; mọi ảnh chụp nghiệm thu nêu rõ theme.
