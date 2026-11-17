# DESIGN.md — Universal Design System & UI/UX Guidelines for AI Agents

> **Chỉ thị Bắt buộc cho AI Agent:**
> Trước khi sinh hoặc sửa đổi bất kỳ mã nguồn giao diện (UI) nào (Jetpack Compose, Flutter, React/Tailwind, Unity UI, v.v.), AI Agent BẮT BUỘC phải đọc và áp dụng chính xác các Design Tokens và quy chuẩn trong tệp này. Tuyệt đối không hardcode mã màu lạ hoặc khoảng cách tùy tiện.

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

## 6. Vùng Chạm & Khoảng Cách — Android

1. Mọi nút bấm, icon button, switch, checkbox có vùng chạm tối thiểu $48\times 48\text{dp}$ (Android accessibility docs); hai vùng chạm cách nhau ≥ $8\text{dp}$ (mặc định đề xuất của dự án, cần đo trên máy thật). Icon nhìn thấy 24–32dp: mở hit area bằng `Modifier.minimumInteractiveComponentSize()` hoặc `Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)`, không phóng to icon.
2. Tuyệt đối không đặt các nút bấm sát nhau gây bấm nhầm; hai vùng chạm chồng nhau phải được kiểm bằng bounds thật (`compose-overlap-invariants`, `dump-view-hierarchy.sh`; rules §15).
3. **Safe area / insets:** `enableEdgeToEdge()` + `WindowInsets` (status bar, navigation bar, cutout, IME); nội dung không lẹm vào tai thỏ, camera khoét lỗ, thanh điều hướng cử chỉ; danh sách cuộn có content padding để không bị bottom bar che.
4. Chiều rộng nội dung có chủ đích theo lớp màn hình (compact/medium/expanded); đoạn văn dài không kéo kín cạnh trên tablet; gutter ngang tăng ở màn rộng và khi xoay ngang.

---

## 7. Typography Co Giãn (`sp`)

- Cỡ chữ luôn `sp`, chịu được font scale $200\%$ (Android accessibility docs); không ép chiều cao cố định cho khung chữ; kiểm tra bố cục ở font scale lớn nhất (không cắt chữ, không chồng lấp, nút không vỡ).
- Bảng ở mục 2 là thang mặc định của dự án; dự án có thể chuyển sang type scale Material 3 (Display/Headline/Title/Body/Label, mỗi vai trò large/medium/small) miễn là dùng một thang nhất quán và map chữ vào vai trò, không chọn cỡ tay theo từng màn hình.
- Chữ đọc dùng line-height ≥ $1.5$ cỡ chữ (nguồn kit: `skill:ui-ux-pro-max`, bước `/typeset`); tối đa 2 họ chữ; không viết hoa toàn bộ cho đoạn dài.
- Font hệ thống là Roboto; tiêu đề quan trọng không để Roboto trần mà không chủ đích: nạp font thương hiệu qua `Typography` của theme, giữ body, label và control dễ đọc và nhất quán.
- Chuỗi hiển thị qua `stringResource`, chừa chỗ cho chuỗi dài (tiếng Đức, tiếng Việt) và RTL (`start`/`end`, `Icons.AutoMirrored.*`).

---

## 8. Chuyển Động (Motion) & Giảm Chuyển Động

- Chuyển động phục vụ ý nghĩa (phản hồi chạm, chuyển ngữ cảnh), không trang trí. Phản hồi nhấn (ripple/opacity/elevation) xuất hiện trong khoảng $80$–$150\text{ms}$ và không dịch bounds làm giật layout (nguồn kit: `skill:ui-ux-pro-max`, `references/pro-rules.md`). Thời lượng chuyển cảnh thông thường $150$–$300\text{ms}$: mặc định đề xuất của dự án, cần đo trên máy thật (đối chiếu duration/easing token của Material motion).
- Dùng mẫu Material motion cho điều hướng (container transform, shared axis, fade through) với easing chuẩn; một thời lượng cho mọi chuyển cảnh là lỗi.
- Tôn trọng "Remove animations": đọc thang thời lượng animation (`ANIMATOR_DURATION_SCALE` trong `Settings.Global`); khi tắt thì thay chuyển động lớn (parallax, zoom, trượt xa) bằng mờ dần hoặc đổi tức thì. Animation không chứa thông tin duy nhất.
- Animation chỉ chạy thuộc tính rẻ (`graphicsLayer`: translation, scale, alpha); đọc state animation ở layout/draw phase, không animate layout nặng trong danh sách. Phải qua cổng khung hình (mục 15).

---

## 9. Trạng Thái Màn Hình (Loading / Empty / Error / Populated)

- Mọi màn hình/luồng có đủ 4 trạng thái: **Loading** (skeleton bám layout, không spinner toàn màn), **Empty** (một câu giải thích + CTA), **Error** (nêu nguyên nhân người dùng hiểu được + nút Thử lại, không lộ stack trace), **Populated**.
- Trạng thái tương tác của component: Default, Pressed, Focused, Disabled (opacity $0.38$); thêm trạng thái Loading cho nút tốn kém (disable ngay lần chạm đầu, debounce ≥ $1000\text{ms}$, mục 16). Trạng thái pressed/focused/disabled phải phân biệt được ở cả sáng và tối.
- Offline/mạng chập chờn là trạng thái thường gặp: giữ dữ liệu cũ (nguồn sự thật cục bộ) và báo rõ, không xoá trắng.
- Cấm câu chào sáo rỗng ("Welcome back 👋"), cấm màn hình rỗng không có hành động tiếp theo. Phản hồi thoáng qua dùng snackbar (kèm hành động khi cần), dialog chỉ cho quyết định bắt buộc ngắt luồng.

---

## 10. Dark Mode

- Mọi màn hình có chế độ tối từ **token ngữ nghĩa** (mục 1), không đảo màu thủ công, không hardcode `Color(0x…)` / `#hex` trong component.
- `MaterialTheme.colorScheme` + `isSystemInDarkTheme()`; bề mặt tối dùng các mức độ nổi tonal (surface tonal elevation), không dựa vào bóng đổ. Dynamic Color (Android 12+) tuỳ chỗ, luôn có scheme tĩnh dự phòng từ token mục 1.
- Kiểm tra tương phản (mục 11), viền/divider, trạng thái tương tác, scrim và ảnh/icon ở cả hai chế độ; không suy bản tối từ bản sáng.
- Chụp ảnh minh chứng cả chế độ sáng và tối cho màn hình mới.

---

## 11. Accessibility (TalkBack / Contrast / Font Scale)

1. **Tương phản:** chữ thường ≥ $4.5:1$, chữ lớn ≥ $3:1$ (WCAG 2.x AA); thành phần không phải chữ (icon có nghĩa, viền input, trạng thái focus) ≥ $3:1$ (WCAG 2.x, tiêu chí 1.4.11). Màu không phải kênh duy nhất truyền thông tin (thêm icon/chữ).
2. **TalkBack:** `contentDescription` bằng chuỗi resource cho icon có nghĩa, `null` cho icon trang trí; `Modifier.semantics { role = …; stateDescription = … }`; nhóm phần tử liên quan (`mergeDescendants`); thứ tự đọc theo thứ tự logic khớp thứ tự nhìn; control icon có tên và báo trạng thái chọn/bật/mở.
3. **Font scale:** mục 7; kiểm tra ở cỡ lớn nhất.
4. **Điều khiển thay thế:** thao tác chính không chỉ có cử chỉ phức tạp; kéo/vuốt có nút tương đương; focus nhìn thấy được và không bị bottom bar/overlay che; hỗ trợ Switch Access/Voice Access.
5. Duyệt thủ công bằng TalkBack trên máy thật cho luồng chính của mỗi màn hình mới; Accessibility Scanner chỉ bổ sung, không thay thế.

---

## 12. Haptic (Phản Hồi Xúc Giác)

- Dùng để xác nhận hành động quan trọng (gửi, ký, xoá) hoặc báo lỗi; không rung cho mọi lần chạm, không rung liên tục.
- `HapticFeedbackConstants` / `LocalHapticFeedback`; tôn trọng cài đặt hệ thống (người dùng tắt rung thì không ép); haptic không phải kênh duy nhất báo kết quả (kèm thị giác/chữ).

---

## 13. Nguyên Tắc UI/UX: Material 3

> Khi nào gọi skill/agent UI/UX, hiệu năng, chất lượng: xem `rules/android-rules.md` mục "21. Bộ công cụ theo tình huống".

- Dùng `MaterialTheme` (colorScheme, typography, shapes) và thành phần M3 chuẩn trước khi tự vẽ (button filled/tonal/outlined/text, FAB, chip, switch, snackbar, bottom sheet, dialog); không dựng lại thành phần hệ thống bằng tay trừ khi có lý do ghi trong PR.
- Điều hướng: navigation bar (3–5 đích chính) ở chiều rộng compact; navigation rail hoặc drawer ở chiều rộng expanded, không để bottom bar điện thoại nguyên trên tablet. Back hệ thống và predictive back luôn hoạt động, không chặn cử chỉ.
- Top app bar cho ngữ cảnh màn hình; một FAB cho một hành động chính, không xếp chồng FAB.
- Màu theo vai trò (primary, on-primary, surface, surface-variant, outline, error), không dùng hex rời.

---

## 14. Zero-Slop (Chống Giao Diện Phèn)

- Cấm card lồng card (`Card { Card { … } }`, panel trong panel): dùng khoảng trắng và divider mảnh.
- Cấm icon tile (ô vuông bo góc nhạt chứa icon) đặt phía trên heading.
- Cấm `Color.Gray` / `#808080` trần: neutral pha $3$–$5\%$ tông chủ đạo (ví dụ `MaterialTheme.colorScheme.onSurfaceVariant`).
- Cấm gradient tím–xanh mặc định; mỗi màn hình một điểm nhấn chính; không emoji làm icon cấu trúc; icon cùng một họ, cùng độ dày nét (mục 5).
- Nhịp spacing có chủ đích: $4$–$8\text{dp}$ trong nhóm, $12$–$16\text{dp}$ nội dung, $24$–$32\text{dp}$ giữa section; không $16\text{dp}$ cho mọi thứ.
- Quy trình: skill `taste-mobile-app` + `impeccable` + `ui-ux-pro-max` (nhóm `VisualSlop`).

---

## 15. Hiệu Năng Giao Diện (Frame Budget)

> Ngân sách đầy đủ và cách đo: `rules/android-rules.md` mục "18. Hiệu năng". Dưới đây là phần giao diện.

- Khung hình $16.6\text{ms}$ ở $60\text{Hz}$ và $8.3\text{ms}$ ở $120\text{Hz}$ (1000 ms chia tần số quét); Android coi khung vượt $16\text{ms}$ là slow frame, vượt $700\text{ms}$ là frozen frame (Android vitals). Đo trên máy thật bằng Macrobenchmark `FrameTimingMetric`/Perfetto và `adb-fps-measure.sh`; cổng của kit: ≥ 58 FPS (60 Hz) / ≥ 115 FPS (120 Hz) và jank ≤ 5% (`council:07-performance-anr`).
- Danh sách động: `LazyColumn`/`LazyRow` với stable `key` + `contentType`, không `Column` + `verticalScroll`.
- Compose: tính nặng bọc `remember`/`derivedStateOf`, đọc state ở owner hẹp nhất và ở layout/draw phase khi có thể (`skill:compose-recomp-audit`).
- Ảnh giải mã theo kích thước hiển thị; không decode ảnh gốc lớn trên main thread.
- Khung hình đo vượt ngân sách thì sửa trước khi thêm hiệu ứng.

---

## 16. Chống Spam Thao Tác & Phản Hồi Tức Thì

- Thao tác tốn kém (gọi API, giao dịch, ký, gửi): disable ngay lần chạm đầu (`enabled = !isLoading`), hiển thị Loading, debounce tối thiểu $1000\text{ms}$.
- Phản hồi thị giác cho mọi lần chạm trong khung hình kế tiếp (ripple/pressed state); không để người dùng chạm mà không thấy gì.
- Primary CTA (Ký, Xác nhận, Tiếp tục) nằm trong $40\%$ nửa dưới màn hình (thumb zone).
