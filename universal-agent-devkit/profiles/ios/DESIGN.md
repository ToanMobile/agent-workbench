# DESIGN.md — Universal Design System & UI/UX Guidelines for AI Agents

> **Chỉ thị Bắt buộc cho AI Agent:**
> Trước khi sinh hoặc sửa đổi bất kỳ mã nguồn giao diện (UI) nào (SwiftUI, UIKit), AI Agent BẮT BUỘC phải đọc và áp dụng chính xác các Design Tokens và quy chuẩn trong tệp này. Tuyệt đối không hardcode mã màu lạ hoặc khoảng cách tùy tiện.

---

## 1. Hệ Thống Màu Sắc Ngữ Nghĩa (Semantic Color Tokens)

| Token Tên | Light Mode HEX | Dark Mode HEX | Mục đích sử dụng |
|---|---|---|---|
| `color-primary` | `#0D6EFD` | `#3B82F6` | Màu thương hiệu chính, nút CTA, thanh tiêu đề |
| `color-on-primary` | `#FFFFFF` | `#FFFFFF` | Chữ/icon nằm trên nền màu primary |
| `color-surface` | `#FFFFFF` | `#121212` | Nền thẻ (Card), Modal, Sheet, thanh điều hướng (NavigationBar) |
| `color-background` | `#F8F9FA` | `#0A0A0A` | Nền toàn bộ màn hình (background của màn hình) |
| `color-text-primary` | `#1F2937` | `#F3F4F6` | Chữ tiêu đề, nội dung đọc chính (High contrast) |
| `color-text-secondary`| `#6B7280` | `#9CA3AF` | Chữ phụ, mô tả ngắn, timestamp, label phụ |
| `color-border` | `#E5E7EB` | `#27272A` | Đường kẻ phân cách, viền input, divider |
| `color-success` | `#10B981` | `#34D399` | Trạng thái hoàn tất, badge PASS, tiền vào |
| `color-warning` | `#F59E0B` | `#FBBF24` | Trạng thái cảnh báo, pending, chờ duyệt |
| `color-error` | `#EF4444` | `#F87171` | Báo lỗi, nút hủy nghiêm trọng, thất bại |

---

## 2. Thang Đo Typography & Phân Cấp Chữ

Dùng text style hệ thống (SF Pro, co giãn theo Dynamic Type); cỡ mặc định ở mức Large (nguồn: Apple HIG, Typography). Khoảng cách theo bội số của 4 pt (§3).

| Cấp bậc (Level) | Text style | Cỡ mặc định | Weight | Sử dụng cho |
|---|---|---|---|---|
| `Display / Hero` | `.largeTitle` | 34 pt | Regular (hoặc Bold khi cần nhấn) | Tiêu đề màn cấp cao (Large Title), số dư lớn, banner chào |
| `Headline` | `.title` / `.title2` / `.title3` | 28 / 22 / 20 pt | Regular | Tiêu đề màn hình, tên mục lớn |
| `Title` | `.headline` | 17 pt | Semibold | Tiêu đề card, nhóm chức năng, tiêu đề hàng |
| `Body Large` | `.body` | 17 pt | Regular | Nội dung văn bản chính, giá trị input |
| `Body Small` | `.callout` / `.subheadline` / `.footnote` | 16 / 15 / 13 pt | Regular | Ghi chú, mô tả phụ, điều khoản, timestamp |
| `Caption / Label` | `.caption` / `.caption2` | 12 / 11 pt (11 pt là sàn) | Regular / Medium | Badge trạng thái, nhãn nhỏ |

---

## 3. Khoảng Cách (Spacing Grid & Layout)

Tuân thủ hệ số bội của $4\text{pt}$:
- `space-xs`: $4\text{pt}$ — Khoảng cách icon và chữ nhỏ.
- `space-sm`: $8\text{pt}$ — Khoảng cách giữa các chip, tag nội bộ.
- `space-md`: $16\text{pt}$ — Padding tiêu chuẩn của màn hình, lề trong của Card.
- `space-lg`: $24\text{pt}$ — Khoảng cách giữa các khối nội dung lớn.
- `space-xl`: $32\text{pt}$ — Lề trên màn hình, phân tách các section độc lập.

---

## 4. Rào Chắn Khả Năng Tiếp Cận & Tương Tác (Accessibility & a11y)

1. **Kích thước Vùng Chạm Tối thiểu (Touch Target Size):**
   - Mọi nút bấm, icon button, switch, checkbox bắt buộc phải có kích thước vùng bấm tối thiểu:
     $$\text{Touch Target} \ge 44\times 44\text{pt} \quad (\text{Apple HIG})$$
   - Tuyệt đối không đặt các nút bấm quá sát nhau gây bấm nhầm trên màn hình cảm ứng.
2. **Độ tương phản màu (Contrast Ratio):**
   - Đảm bảo tỷ lệ tương phản chữ/nền tối thiểu $4.5:1$ cho văn bản thường và $3:1$ cho văn bản lớn (chuẩn WCAG AA).
3. **Trạng thái Tương tác Rõ ràng (Interaction States):**
   - Mỗi component tương tác bắt buộc phải hỗ trợ đủ 4 trạng thái: `Default`, `Pressed/Hover`, `Focused`, và `Disabled`.
   - Khi ở trạng thái `Disabled`, độ mờ (opacity) chuẩn là $0.38$, không nhận bất kỳ sự kiện click nào.

---

## 5. Quy Chuẩn Đồ Họa & Iconography

- Định dạng icon chuẩn: SF Symbols (`Image(systemName:)`, tự co theo Dynamic Type); icon riêng dùng asset vector (PDF/SVG) trong Asset Catalog, không dùng bộ icon web.
- Độ dày nét icon tự vẽ (Stroke): đều đặn $1.5\text{pt}$ hoặc $2.0\text{pt}$ trong toàn bộ ứng dụng (mặc định đề xuất của dự án, cần đo trên máy thật); SF Symbols chọn weight khớp chữ bên cạnh.
- Bán kính bo góc (Corner Radius), kiểu liên tục (`style: .continuous`); các giá trị dưới đây là mặc định đề xuất của dự án, cần đo trên máy thật:
  - Nút bấm nhỏ / Chip: $8\text{pt}$.
  - Thẻ (Card) / Sheet: $16\text{pt}$.
  - Modal / Dialog: $20\text{pt}$.
  - Pill button / Avatar: `Capsule()` (full rounded).

---

# Đặc tả iOS (SwiftUI / UIKit) — mở rộng §1–§5

> Từ mục 6 trở xuống là đặc tả bổ sung cho iOS (SwiftUI/UIKit); §1–§5 ở trên đã viết theo pt và text style iOS. Nhãn số liệu: mỗi con số có **nguồn** hoặc nhãn **"mặc định đề xuất của dự án, cần đo trên máy thật"**.

## 6. Token màu iOS (Color tokens, Dark Mode)

1. Ưu tiên màu ngữ nghĩa hệ thống, tự thích ứng Dark Mode và Increased Contrast: nền `systemBackground`, `secondarySystemBackground`, `systemGroupedBackground`; chữ `label`, `secondaryLabel`, `tertiaryLabel`; viền `separator`, `opaqueSeparator`; màu nhấn `tint` (`Color.accentColor`).
2. Màu thương hiệu và màu trạng thái ở §1 (`color-primary`, `color-success`, `color-warning`, `color-error`...) khai trong Asset Catalog dưới dạng Color Set có biến thể Any/Dark (và High Contrast nếu cần), gọi bằng tên (`Color("BrandPrimary")`) hoặc `ShapeStyle` do dự án định nghĩa; cấm hex rải rác trong View.
3. Một màu `tint` duy nhất cho phần tử tương tác; không dùng màu nhấn để trang trí. Vật liệu mờ (blur) dùng vật liệu hệ thống của SwiftUI (regular, thin, thick, ultraThin...) cho thanh và sheet, không tự dựng kính mờ.
4. Cặp chữ/nền đạt tương phản chữ thường ≥ 4,5:1, chữ lớn ≥ 3:1, icon/viền input ≥ 3:1 (WCAG 2.x AA, tiêu chí 1.4.3 và 1.4.11), kiểm ở cả sáng và tối; trạng thái không chỉ truyền bằng màu mà kèm icon hoặc chữ.
5. Neutral pha 3–5% tông chủ đạo, không `Color.gray`/`#808080` trần, không gradient tím–xanh mặc định (nguồn: DevKit essentials, Zero-Slop).

## 7. Typography & Dynamic Type

Bảng text style và cỡ mặc định (nguồn: Apple HIG, Typography) nằm ở §2; không dùng cỡ chữ cố định ngoài bảng đó.

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
- Nhóm nội dung liên quan bằng `accessibilityElement(children: .combine)`; ẩn trang trí bằng `accessibilityHidden(true)`; thứ tự đọc theo logic, không theo toạ độ ngẫu nhiên; thay đổi động báo bằng `AccessibilityNotification` (iOS 17+, kiểm lại tài liệu hiện hành; bản cũ `UIAccessibility.post`).
- Hành động thay thế cho cử chỉ (vuốt, kéo) qua `accessibilityAction`; không có thao tác chỉ làm được bằng cử chỉ phức tạp.
- Tôn trọng: Dynamic Type, Bold Text, Increased Contrast, Reduce Transparency, Reduce Motion, Differentiate Without Color, Smart Invert, Voice Control (nhãn hiển thị khớp nhãn đọc).
- Kiểm bằng `app.performAccessibilityAudit()` trong XCUITest và một lượt VoiceOver thủ công trên máy thật cho màn hình mới.

## 10. Chuyển động (Motion) và Reduce Motion

- Dùng chuyển cảnh và animation mặc định của hệ thống (push, sheet, spring của SwiftUI) trước khi tự vẽ; chuyển động phải truyền ý nghĩa (nguồn gốc, phân cấp), không trang trí thuần.
- Thời lượng animation tuỳ chỉnh: micro-interaction 150–250 ms, chuyển cảnh lớn 300–400 ms (mặc định đề xuất của dự án, cần đo trên máy thật); animate `opacity`/`offset`/`scale`, không animate thứ gây layout lại cả cây.
- Khi `accessibilityReduceMotion` bật: thay parallax, zoom, trượt lớn bằng crossfade hoặc tắt hẳn; animation không chứa thông tin duy nhất; không có chuyển động tự lặp vô hạn nếu không cần.
- Nút tương tác có hiệu ứng nhấn tức thì (trong khung hình đầu tiên sau chạm); phản hồi bằng haptic xem mục 11.

## 11. Trạng thái giao diện và Haptic

- Mỗi màn hình đủ 4 trạng thái: Loading (skeleton/`redacted(reason: .placeholder)` bám layout, không spinner trơ), Empty (giải thích + CTA, `ContentUnavailableView`, iOS 17+, kiểm lại tài liệu hiện hành; iOS 16 dùng View tự dựng), Error (thông điệp + Thử lại), Populated.
- Mỗi component tương tác có đủ Default, Pressed, Focused (bàn phím rời/Full Keyboard Access), Disabled (dùng `.disabled(_:)` của hệ thống cho control chuẩn; phần tự vẽ theo §4); nút kích hoạt thao tác tốn kém disable ngay lần chạm đầu và debounce ≥ 1000 ms (nguồn: DevKit essentials).
- Haptic chỉ để xác nhận hành động hoặc báo lỗi: `UISelectionFeedbackGenerator` (chọn), `UIImpactFeedbackGenerator` (va chạm/nhấn), `UINotificationFeedbackGenerator` (thành công/cảnh báo/lỗi) hoặc `.sensoryFeedback` (iOS 17+, kiểm lại tài liệu hiện hành); không rung liên tục, không rung cho thao tác thường.
- Lỗi form hiện cạnh trường lỗi, nhãn luôn hiện (không chỉ placeholder), bàn phím đúng loại (`keyboardType`, `textContentType`) và không che input.

## 12. Apple HIG và Zero-Slop

- HIG trước, tự vẽ sau: tab bar cho 2–5 khu vực, navigation stack cho phân cấp, sheet cho tác vụ khép kín, alert/confirmation dialog/context menu/swipe actions; không tắt cử chỉ vuốt cạnh trái để quay lại; Large Title cho màn cấp cao.
- Dấu hiệu "bê từ web sang" là lỗi thiết kế: thanh điều hướng tự chế, nút hover, back tự chế, switch/picker vẽ lại.
- Zero-Slop: không `Card` lồng `Card`, không ô icon đặt trên tiêu đề, không `Color.gray` trần, không gradient tím–xanh mặc định, không câu chào sáo rỗng "Welcome back", mỗi màn hình một điểm neo thị giác. Quy trình: skill `taste-mobile-app` (khoá `MOBILE-DESIGN.md` lấy token từ tệp này) và `impeccable` (`skills/impeccable/reference/ios.md`); kiểm bằng `agent:real-device-ui-auditor` và ảnh máy thật sáng/tối, cỡ chữ lớn.
