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
   - Mọi nút bấm, icon button, switch, checkbox bắt buộc phải có kích thước vùng bấm tối thiểu:
     $$\text{Touch Target} \ge 48\times 48\text{dp} \quad (\text{Web: } \ge 44\times 44\text{px})$$
   - Tuyệt đối không đặt các nút bấm quá sát nhau gây bấm nhầm trên màn hình cảm ứng.
2. **Độ tương phản màu (Contrast Ratio):**
   - Đảm bảo tỷ lệ tương phản chữ/nền tối thiểu $4.5:1$ cho văn bản thường và $3:1$ cho văn bản lớn (chuẩn WCAG AA).
3. **Trạng thái Tương tác Rõ ràng (Interaction States):**
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

# Đặc tả iOS (SwiftUI / UIKit) — mở rộng §1–§5

> Từ mục 6 trở xuống là đặc tả riêng cho iOS. §1–§5 ở trên là bảng chung của kit (đơn vị dp/sp của bảng chung đọc là pt); khi hai bên khác nhau thì phần iOS dưới đây thắng, riêng vùng chạm 48 pt ở §4 vẫn đạt chuẩn vì lớn hơn mức tối thiểu 44 pt của HIG. Nhãn số liệu: mỗi con số có **nguồn** hoặc nhãn **"mặc định đề xuất của dự án, cần đo trên máy thật"**.

## 6. Token màu iOS (Color tokens, Dark Mode)

1. Ưu tiên màu ngữ nghĩa hệ thống, tự thích ứng Dark Mode và Increased Contrast: nền `systemBackground`, `secondarySystemBackground`, `systemGroupedBackground`; chữ `label`, `secondaryLabel`, `tertiaryLabel`; viền `separator`, `opaqueSeparator`; màu nhấn `tint` (`Color.accentColor`).
2. Màu thương hiệu và màu trạng thái ở §1 (`color-primary`, `color-success`, `color-warning`, `color-error`...) khai trong Asset Catalog dưới dạng Color Set có biến thể Any/Dark (và High Contrast nếu cần), gọi bằng tên (`Color("BrandPrimary")`) hoặc `ShapeStyle` do dự án định nghĩa; cấm hex rải rác trong View.
3. Một màu `tint` duy nhất cho phần tử tương tác; không dùng màu nhấn để trang trí. Vật liệu mờ (blur) dùng vật liệu hệ thống của SwiftUI (regular, thin, thick, ultraThin...) cho thanh và sheet, không tự dựng kính mờ.
4. Cặp chữ/nền đạt tương phản chữ thường ≥ 4,5:1, chữ lớn ≥ 3:1, icon/viền input ≥ 3:1 (WCAG 2.x AA, tiêu chí 1.4.3 và 1.4.11), kiểm ở cả sáng và tối; trạng thái không chỉ truyền bằng màu mà kèm icon hoặc chữ.
5. Neutral pha 3–5% tông chủ đạo, không `Color.gray`/`#808080` trần, không gradient tím–xanh mặc định (nguồn: DevKit essentials, Zero-Slop).

## 7. Typography & Dynamic Type

Dùng text style hệ thống (SF Pro); cỡ mặc định ở mức Large (nguồn: Apple HIG, Typography):

| Text style | Cỡ mặc định | Dùng cho |
|---|---|---|
| `.largeTitle` | 34 pt | Tiêu đề màn cấp cao (Large Title, thu gọn khi cuộn) |
| `.title` / `.title2` / `.title3` | 28 / 22 / 20 pt | Tiêu đề section, card, nhóm |
| `.headline` | 17 pt, semibold | Tiêu đề hàng, nhấn mạnh |
| `.body` | 17 pt | Nội dung chính, giá trị input |
| `.callout` / `.subheadline` | 16 / 15 pt | Nội dung phụ, mô tả |
| `.footnote` | 13 pt | Ghi chú, timestamp |
| `.caption` / `.caption2` | 12 / 11 pt | Nhãn nhỏ, badge; 11 pt là sàn |

- Mọi chữ co giãn theo Dynamic Type tới các cỡ accessibility (`accessibility1`...`accessibility5`); font tuỳ chỉnh dùng `Font.custom(_:size:relativeTo:)`; kích thước số liệu đi kèm chữ dùng `@ScaledMetric`.
- Không cố định chiều cao khung chữ; cho phép xuống dòng và chuyển bố cục ngang sang dọc khi cỡ chữ lớn (`ViewThatFits`). Không cố định point cho chữ, chỉ cố định cho icon trang trí.
- SF Symbols cho icon: cùng weight/scale với chữ bên cạnh, `Image(systemName:)` tự co theo Dynamic Type; không trộn bộ icon web.

## 8. Spacing, bố cục và vùng chạm

- Thang spacing theo bội của 4 pt: 4, 8, 12, 16, 24, 32 pt; nhịp 4–8 / 12–16 / 24–32, không dùng 16 cho mọi thứ (nguồn: DevKit essentials). Lề ngang màn hình 16 pt, khoảng cách giữa khối lớn 24–32 pt: mặc định đề xuất của dự án, cần đo trên máy thật.
- Tôn trọng safe area và layout margins; CTA dính đáy dùng `.safeAreaInset(edge: .bottom)`; không điều khiển dưới Dynamic Island hay home indicator.
- Vùng chạm tối thiểu 44×44 pt (Apple HIG); hai vùng chạm cạnh nhau cách ≥ 8 pt (nguồn: skill `ui-ux-pro-max`); mở rộng hit area bằng `.contentShape(Rectangle())` + `.frame(minWidth: 44, minHeight: 44)` khi icon nhỏ hơn.
- Bo góc dùng kiểu liên tục (`RoundedRectangle(cornerRadius:style: .continuous)`); bán kính theo §5 là mặc định đề xuất của dự án, cần đo trên máy thật. Không `Card` lồng `Card`, không panel trong panel.
- Danh sách dạng cài đặt dùng `List`/`Form` grouped hoặc inset của hệ thống, không dựng chồng card tự chế.

## 9. Accessibility — VoiceOver và các thiết lập hệ thống

- Mỗi phần tử tương tác có `accessibilityLabel` (ngắn, danh từ/động từ rõ), `accessibilityValue` cho giá trị động, `accessibilityHint` chỉ khi hệ quả không hiển nhiên; trait đúng vai trò (`.isButton`, `.isHeader`, `.isSelected`).
- Nhóm nội dung liên quan bằng `accessibilityElement(children: .combine)`; ẩn trang trí bằng `accessibilityHidden(true)`; thứ tự đọc theo logic, không theo toạ độ ngẫu nhiên; thay đổi động báo bằng `AccessibilityNotification`.
- Hành động thay thế cho cử chỉ (vuốt, kéo) qua `accessibilityAction`; không có thao tác chỉ làm được bằng cử chỉ phức tạp.
- Tôn trọng: Dynamic Type, Bold Text, Increased Contrast, Reduce Transparency, Reduce Motion, Differentiate Without Color, Smart Invert, Voice Control (nhãn hiển thị khớp nhãn đọc).
- Kiểm bằng `app.performAccessibilityAudit()` trong XCUITest và một lượt VoiceOver thủ công trên máy thật cho màn hình mới.

## 10. Chuyển động (Motion) và Reduce Motion

- Dùng chuyển cảnh và animation mặc định của hệ thống (push, sheet, spring của SwiftUI) trước khi tự vẽ; chuyển động phải truyền ý nghĩa (nguồn gốc, phân cấp), không trang trí thuần.
- Thời lượng animation tuỳ chỉnh: micro-interaction 150–250 ms, chuyển cảnh lớn 300–400 ms (mặc định đề xuất của dự án, cần đo trên máy thật); animate `opacity`/`offset`/`scale`, không animate thứ gây layout lại cả cây.
- Khi `accessibilityReduceMotion` bật: thay parallax, zoom, trượt lớn bằng crossfade hoặc tắt hẳn; animation không chứa thông tin duy nhất; không có chuyển động tự lặp vô hạn nếu không cần.
- Nút tương tác có hiệu ứng nhấn tức thì (trong khung hình đầu tiên sau chạm); phản hồi bằng haptic xem mục 11.

## 11. Trạng thái giao diện và Haptic

- Mỗi màn hình đủ 4 trạng thái: Loading (skeleton/`redacted(reason: .placeholder)` bám layout, không spinner trơ), Empty (giải thích + CTA, `ContentUnavailableView`), Error (thông điệp + Thử lại), Populated.
- Mỗi component tương tác có đủ Default, Pressed, Focused (bàn phím rời/Full Keyboard Access), Disabled (dùng `.disabled(_:)` của hệ thống cho control chuẩn; phần tự vẽ theo §4); nút kích hoạt thao tác tốn kém disable ngay lần chạm đầu và debounce ≥ 1000 ms (nguồn: DevKit essentials).
- Haptic chỉ để xác nhận hành động hoặc báo lỗi: `UISelectionFeedbackGenerator` (chọn), `UIImpactFeedbackGenerator` (va chạm/nhấn), `UINotificationFeedbackGenerator` (thành công/cảnh báo/lỗi) hoặc `.sensoryFeedback` (iOS 17+); không rung liên tục, không rung cho thao tác thường.
- Lỗi form hiện cạnh trường lỗi, nhãn luôn hiện (không chỉ placeholder), bàn phím đúng loại (`keyboardType`, `textContentType`) và không che input.

## 12. Apple HIG và Zero-Slop

- HIG trước, tự vẽ sau: tab bar cho 2–5 khu vực, navigation stack cho phân cấp, sheet cho tác vụ khép kín, alert/confirmation dialog/context menu/swipe actions; không tắt cử chỉ vuốt cạnh trái để quay lại; Large Title cho màn cấp cao.
- Dấu hiệu "bê từ web sang" là lỗi thiết kế: thanh điều hướng tự chế, nút hover, back tự chế, switch/picker vẽ lại.
- Zero-Slop: không `Card` lồng `Card`, không ô icon đặt trên tiêu đề, không `Color.gray` trần, không gradient tím–xanh mặc định, không câu chào sáo rỗng "Welcome back", mỗi màn hình một điểm neo thị giác. Quy trình: skill `taste-mobile-app` (khoá `MOBILE-DESIGN.md` lấy token từ tệp này) và `impeccable` (`skills/impeccable/reference/ios.md`); kiểm bằng `agent:real-device-ui-auditor` và ảnh máy thật sáng/tối, cỡ chữ lớn.
