# DESIGN.md — Mobile Design System & UI/UX Guidelines for AI Agents (Android + iOS)

> **Chỉ thị Bắt buộc cho AI Agent:**
> Trước khi sinh hoặc sửa đổi bất kỳ mã nguồn giao diện (UI) nào (Jetpack Compose, SwiftUI, Flutter, React/Tailwind, Unity UI, v.v.), AI Agent BẮT BUỘC phải đọc và áp dụng chính xác các Design Tokens và quy chuẩn trong tệp này. Tuyệt đối không hardcode mã màu lạ hoặc khoảng cách tùy tiện.

---

## 1. Hệ Thống Màu Sắc Ngữ Nghĩa (Semantic Color Tokens)

| Token Tên | Light Mode HEX | Dark Mode HEX | Mục đích sử dụng |
|---|---|---|---|
| `color-primary` | `#0D6EFD` | `#3B82F6` | Màu thương hiệu chính, nút CTA, thanh tiêu đề |
| `color-on-primary` | `#FFFFFF` | `#FFFFFF` | Chữ/icon nằm trên nền màu primary |
| `color-surface` | `#FFFFFF` | `#121212` | Nền thẻ (Card), Modal, Sheet, AppBar |
| `color-background` | `#F8F9FA` | `#0A0A0A` | Nền toàn bộ màn hình (Scaffold background) |
| `color-text-primary` | `#1F2937` | `#F3F4F6` | Chữ tiêu đề, nội dung đọc chính (High contrast) |
| `color-text-secondary`| `#6B7280` | `#9CA3AF` | Chữ phụ, mô tả ngắn, timestamp, label phụ |
| `color-border` | `#E5E7EB` | `#27272A` | Đường kẻ phân cách, viền input, divider |
| `color-success` | `#10B981` | `#34D399` | Trạng thái hoàn tất, badge PASS, tiền vào |
| `color-warning` | `#F59E0B` | `#FBBF24` | Trạng thái cảnh báo, pending, chờ duyệt |
| `color-error` | `#EF4444` | `#F87171` | Báo lỗi, nút hủy nghiêm trọng, thất bại |

---

## 2. Thang Đo Typography & Phân Cấp Chữ

Sử dụng thang đo tiêu chuẩn $8\text{pt} / 4\text{px}$ Grid:

| Cấp bậc (Level) | Cỡ chữ (Size) | Line Height | Weight | Sử dụng cho |
|---|---|---|---|---|
| `Display / Hero` | $28\text{sp} / 32\text{px}$ | $36\text{px}$ | Bold (700) | Màn hình chính, số dư lớn, banner chào |
| `Headline` | $20\text{sp} / 24\text{px}$ | $28\text{px}$ | SemiBold (600) | Tiêu đề màn hình, tên mục lớn |
| `Title` | $16\text{sp} / 18\text{px}$ | $24\text{px}$ | Medium (500) | Tiêu đề card, nhóm chức năng |
| `Body Large` | $14\text{sp} / 16\text{px}$ | $22\text{px}$ | Regular (400) | Nội dung văn bản chính, input value |
| `Body Small` | $12\text{sp} / 14\text{px}$ | $18\text{px}$ | Regular (400) | Ghi chú, tooltip, điều khoản |
| `Caption / Label` | $10\text{sp} / 12\text{px}$ | $16\text{px}$ | Medium (500) | Badge trạng thái, nhãn dưới tab bar |

---

## 3. Khoảng Cách (Spacing Grid & Layout)

Tuân thủ hệ số bội của $4\text{px} / 4\text{dp}$:
- `space-xs`: $4\text{dp}$ — Khoảng cách icon và chữ nhỏ.
- `space-sm`: $8\text{dp}$ — Khoảng cách giữa các chip, tag nội bộ.
- `space-md`: $16\text{dp}$ — Padding tiêu chuẩn của màn hình, lề trong của Card.
- `space-lg`: $24\text{dp}$ — Khoảng cách giữa các khối nội dung lớn.
- `space-xl`: $32\text{dp}$ — Lề trên màn hình, phân tách các section độc lập.

---

## 4. Rào Chắn Khả Năng Tiếp Cận & Tương Tác (Accessibility & a11y)

1. **Kích thước Vùng Chạm Tối thiểu (Touch Target Size):**
   - Icon nhìn thấy có thể 24–32dp. Hit area (vùng cảm ứng) bắt buộc ≥ 48×48dp. Hai vùng tương tác cách nhau ≥ 8dp.
   - Web: ≥ 44×44px.
   - Primary CTA (Ký, Xác nhận, Tiếp tục) đặt trong 40% nửa dưới màn hình (thumb zone).
2. **Frame budget 16.6ms:** danh sách động dùng `LazyColumn`/`LazyRow` với stable key, không `Column` + `verticalScroll`. Tính toán nặng trong Composable bọc `remember` hoặc `derivedStateOf`.
3. **Độ tương phản màu (Contrast Ratio):**
   - Đảm bảo tỷ lệ tương phản chữ/nền tối thiểu $4.5:1$ cho văn bản thường và $3:1$ cho văn bản lớn (chuẩn WCAG AA).
4. **Trạng thái Tương tác Rõ ràng (Interaction States):**
   - Mỗi component tương tác bắt buộc phải hỗ trợ đủ 4 trạng thái: `Default`, `Pressed/Hover`, `Focused`, và `Disabled`.
   - Khi ở trạng thái `Disabled`, độ mờ (opacity) chuẩn là $0.38$, không nhận bất kỳ sự kiện click nào.

---

## 5. Quy Chuẩn Đồ Họa & Iconography

- Định dạng icon chuẩn: Vector SVG (Web) hoặc Vector Drawable (Android XML / Compose Icons).
- Độ dày viền icon (Stroke): Đều đặn $1.5\text{dp}$ hoặc $2.0\text{dp}$ trong toàn bộ ứng dụng.
- Bán kính bo góc (Corner Radius):
  - Nút bấm nhỏ / Chip: $8\text{dp}$.
  - Thẻ (Card) / Sheet: $16\text{dp}$.
  - Modal / Dialog: $20\text{dp}$.
  - Pill button / Avatar: $999\text{dp}$ (Full rounded).

---

## 6. Vùng Chạm & Khoảng Cách — Quy Tắc Chung Hai Nền Tảng (từ iOS/universal)

1. **Kích thước Vùng Chạm Tối thiểu (Touch Target Size) — Android 48 dp, iOS 44 pt, Web 44 px:**
   - Mọi nút bấm, icon button, switch, checkbox bắt buộc phải có kích thước vùng bấm tối thiểu:
     $$\text{Touch Target} \ge 48\times 48\text{dp} \quad (\text{Web: } \ge 44\times 44\text{px})$$
   - iOS: $\ge 44\times 44\text{pt}$ (Apple Human Interface Guidelines), dùng `.frame(minWidth: 44, minHeight: 44)` hoặc `.contentShape(Rectangle())` để mở rộng vùng chạm mà không phóng to icon.
   - Tuyệt đối không đặt các nút bấm quá sát nhau gây bấm nhầm trên màn hình cảm ứng.
2. Android: mở rộng hit area bằng `Modifier.minimumInteractiveComponentSize()`; Android và iOS đều giữ khoảng cách giữa hai vùng chạm ≥ $8\text{dp}$ / $8\text{pt}$ (mặc định đề xuất của dự án, cần đo trên máy thật).
3. **Safe area / insets:** Android `enableEdgeToEdge()` + `WindowInsets`; iOS `.safeAreaInset(edge: .bottom)`; nội dung không lẹm vào tai thỏ, Dynamic Island, thanh điều hướng cử chỉ.

---

## 7. Typography Co Giãn (Android `sp` / iOS Dynamic Type)

- Android: cỡ chữ luôn `sp`, chịu được font scale $200\%$ (Android accessibility docs); iOS: dùng text style hệ thống (`Font.TextStyle`: `.body`, `.headline`, …) hoặc font tuỳ chỉnh co giãn theo Dynamic Type, hỗ trợ cả các cỡ accessibility; không ép chiều cao cố định cho khung chữ.
- Bảng ở mục 2 là thang mặc định của dự án cho cả hai nền tảng (Android đọc là `sp`, iOS đọc là `pt` gắn text style gần nhất); dự án có thể chuyển sang type scale của Material 3 (Android) và text style của Apple HIG (iOS) miễn là dùng một thang nhất quán.
- Tối đa 2 họ chữ; độ dài dòng đọc thoải mái; không viết hoa toàn bộ cho đoạn dài; kiểm tra bố cục ở font scale lớn nhất (không cắt chữ, không chồng lấp, nút không vỡ).
- Chuỗi hiển thị qua tài nguyên (`stringResource` / `String(localized:)`), chừa chỗ cho chuỗi dài (tiếng Đức, tiếng Việt) và RTL.

---

## 8. Chuyển Động (Motion) & Giảm Chuyển Động (Reduced Motion)

- Chuyển động phục vụ ý nghĩa (phản hồi chạm, chuyển ngữ cảnh), không trang trí. Phản hồi chạm tức thì (không chờ animation); thời lượng thông thường 150–300 ms: mặc định đề xuất của dự án, cần đo trên máy thật (đối chiếu duration token của Material 3 và hướng dẫn Motion của Apple HIG).
- Tôn trọng cài đặt hệ thống giảm chuyển động: Android đọc thang thời lượng animation (`ANIMATOR_DURATION_SCALE`), iOS `accessibilityReduceMotion` (SwiftUI `@Environment(\.accessibilityReduceMotion)`); khi bật thì thay chuyển động lớn (parallax, zoom, trượt xa) bằng mờ dần hoặc đổi tức thì.
- Animation chỉ chạy thuộc tính rẻ (transform, alpha); không animate layout nặng trong danh sách. Phải qua cổng khung hình ở mục 15.

---

## 9. Trạng Thái Màn Hình (Loading / Empty / Error / Populated)

- Mọi màn hình/luồng có đủ 4 trạng thái: **Loading** (skeleton bám layout / `redacted(reason: .placeholder)`, không spinner toàn màn), **Empty** (một câu giải thích + CTA), **Error** (nêu nguyên nhân người dùng hiểu được + nút Thử lại, không lộ stack trace), **Populated**.
- Trạng thái tương tác của component: Default, Pressed, Focused, Disabled (opacity $0.38$); thêm trạng thái Loading cho nút tốn kém (disable ngay lần chạm đầu, debounce ≥ $1000\text{ms}$ — mục 16).
- Offline/mạng chập chờn là trạng thái thường gặp: giữ dữ liệu cũ (nguồn sự thật cục bộ) và báo rõ, không xoá trắng.
- Cấm câu chào sáo rỗng ("Welcome back 👋"), cấm màn hình rỗng không có hành động tiếp theo.

---

## 10. Dark Mode

- Mọi màn hình có chế độ tối từ **token ngữ nghĩa** (mục 1), không đảo màu thủ công, không hardcode `Color(0x…)` / `#hex` trong component.
- Android: `MaterialTheme.colorScheme` + `isSystemInDarkTheme()`; iOS: asset colour có biến thể Light/Dark hoặc `Color` ngữ nghĩa của hệ thống.
- Kiểm tra tương phản (mục 11) và ảnh/icon ở cả hai chế độ; bề mặt tối dùng các mức độ nổi (elevation/tonal), không dựa vào bóng đổ.
- Chụp ảnh minh chứng cả chế độ sáng và tối cho màn hình mới.

---

## 11. Accessibility (TalkBack / VoiceOver / Contrast / Dynamic Type)

1. **Tương phản:** chữ thường ≥ $4.5:1$, chữ lớn ≥ $3:1$ (WCAG 2.x AA); thành phần không phải chữ (icon, viền input, trạng thái focus) ≥ $3:1$ (WCAG 2.x, tiêu chí 1.4.11). Màu không phải kênh duy nhất truyền thông tin (thêm icon/chữ).
2. **TalkBack (Android):** `contentDescription` bằng chuỗi resource cho icon có nghĩa, `null` cho icon trang trí; `Modifier.semantics { role = …; stateDescription = … }`; nhóm phần tử liên quan (`mergeDescendants`); thứ tự đọc theo thứ tự logic.
3. **VoiceOver (iOS):** `accessibilityLabel`, `accessibilityHint` chỉ khi cần, trait đúng (`.isButton`, `.isHeader`), nhóm bằng `accessibilityElement(children: .combine)`; thứ tự đọc logic.
4. **Dynamic Type / font scale:** mục 7; kiểm tra ở cỡ lớn nhất.
5. **Điều khiển thay thế:** thao tác chính không chỉ có cử chỉ phức tạp; có tương đương cho bàn phím/Switch Access/Voice Control; focus nhìn thấy được.
6. Duyệt thủ công bằng TalkBack/VoiceOver trên máy thật cho luồng chính của mỗi màn hình mới; trình quét tự động (Accessibility Scanner, Accessibility Inspector) chỉ bổ sung, không thay thế.

---

## 12. Haptic (Phản Hồi Xúc Giác)

- Dùng để xác nhận hành động quan trọng (gửi, ký, xoá) hoặc báo lỗi; không rung cho mọi lần chạm, không rung liên tục.
- Android: `HapticFeedbackConstants`/`LocalHapticFeedback`; iOS: `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` hoặc `.sensoryFeedback` (SwiftUI, iOS 17+).
- Tôn trọng cài đặt hệ thống (người dùng tắt rung thì không ép); haptic không phải kênh duy nhất báo kết quả (kèm thị giác/chữ).

---

## 13. Nguyên Tắc UI/UX: Material 3 (Android) & Apple HIG (iOS)

> Khi nào gọi skill/agent UI/UX, hiệu năng, chất lượng: xem `rules/mobile-rules.md` mục "22. Bộ công cụ theo tình huống".

- Android theo Material 3: `MaterialTheme` (colorScheme, typography, shapes), thành phần M3 chuẩn trước khi tự vẽ; điều hướng dưới cho 3–5 đích chính, back theo hệ thống (predictive back).
- iOS theo Apple Human Interface Guidelines: `NavigationStack`/`TabView`, sheet với `.presentationDetents`, nút/chữ hệ thống; vuốt back mép trái không bị cản.
- Hai nền tảng dùng **chung token ngữ nghĩa** (mục 1) và nhịp spacing (mục 3), nhưng giữ hành vi điều hướng/sheet/menu đúng thói quen từng nền tảng; không dựng lại thành phần hệ thống bằng tay trừ khi có lý do ghi trong PR.

---

## 14. Zero-Slop (Chống Giao Diện Phèn)

- Cấm card lồng card (`Card { Card { … } }`, panel trong panel): dùng khoảng trắng và divider mảnh.
- Cấm icon tile (ô vuông bo góc nhạt chứa icon) đặt phía trên heading.
- Cấm `Color.Gray` / `Color.gray` / `#808080` trần: neutral pha $3$–$5\%$ tông chủ đạo (ví dụ `MaterialTheme.colorScheme.onSurfaceVariant`).
- Cấm gradient tím–xanh mặc định; mỗi màn hình một điểm nhấn chính.
- Nhịp spacing có chủ đích: $4$–$8\text{dp}$ trong nhóm, $12$–$16\text{dp}$ nội dung, $24$–$32\text{dp}$ giữa section; không $16\text{dp}$ cho mọi thứ.
- Quy trình: skill `taste-mobile-app` + `impeccable` + `ui-ux-pro-max` (nhóm `VisualSlop`).

---

## 15. Hiệu Năng Giao Diện (Frame Budget)

> Ngân sách đầy đủ và cách đo: `rules/mobile-rules.md` §19. Dưới đây là phần giao diện.

- Khung hình $16.6\text{ms}$ ở $60\text{Hz}$ và $8.3\text{ms}$ ở $120\text{Hz}$ (1000 ms chia tần số quét); Android coi khung vượt $16\text{ms}$ là slow frame, vượt $700\text{ms}$ là frozen frame (Android vitals). Đo trên máy thật bằng Macrobenchmark `FrameTimingMetric`/Perfetto (Android) và Instruments "Animation Hitches" (iOS).
- Danh sách động: `LazyColumn`/`LazyRow` với stable `key` + `contentType`, không `Column` + `verticalScroll`; iOS `LazyVStack`/`List` với `id` ổn định.
- Android Compose: tính nặng bọc `remember`/`derivedStateOf`, đọc state ở owner hẹp nhất. iOS SwiftUI: `var body` thuần túy, `@Observable`, cache `DateFormatter`/`NumberFormatter` (rules §17.3).
- Ảnh giải mã theo kích thước hiển thị; không decode ảnh gốc lớn trên main thread.
- Khung hình đo vượt ngân sách thì sửa trước khi thêm hiệu ứng.

---

## 16. Chống Spam Thao Tác & Phản Hồi Tức Thì

- Thao tác tốn kém (gọi API, giao dịch, ký, gửi): disable ngay lần chạm đầu, hiển thị Loading, debounce tối thiểu $1000\text{ms}$ (Android `isLoading`/`enabled`, iOS `.disabled(isLoading)`).
- Phản hồi thị giác cho mọi lần chạm trong khung hình kế tiếp (ripple/pressed state, scale xuống khi nhấn); không để người dùng chạm mà không thấy gì.
- Primary CTA (Ký, Xác nhận, Tiếp tục) nằm trong $40\%$ nửa dưới màn hình (thumb zone).
