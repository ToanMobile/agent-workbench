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

## 6. Game Mobile Casual (Unity uGUI / UI Toolkit, màn hình dọc)

> Áp dụng cho HUD, modal, bản đồ màn và mọi màn hình trong game. Token màu/typography ở trên là mặc định cho menu/cài đặt; bảng màu thế giới game do art bible của dự án quyết định — nhưng các ràng buộc dưới đây luôn giữ.

1. **Bố cục dọc theo dải (tham chiếu 1080×1920):**
   - HUD 1 hàng ở đỉnh, *bên trong* safe area (tránh notch / Dynamic Island / status bar).
   - Vùng chơi chính ở giữa-dưới; nút thao tác thường xuyên (booster, hoàn tác, gợi ý) trong **vùng ngón cái** — khoảng 40 % dưới màn hình, cách mép dưới ≥ home indicator.
   - Nút hiếm/nguy hiểm (thoát, mua, reset) ở xa vùng ngón cái và có xác nhận.
2. **Safe area & tỉ lệ:** mọi phần tử tương tác nằm trong container áp `Screen.safeArea`; nền/ảnh trang trí được phép tràn full màn hình. Kiểm tối thiểu 16:9, 19.5:9, 20:9 (+ 4:3 nếu chạy iPad), mỗi trạng thái UI chính.
3. **Vùng chạm & khoảng cách:** ≥ 44 pt / 48 dp (≈ 132 px ở 1080 px chiều ngang tham chiếu); giữa 2 nút ≥ 8 dp; icon trong vùng chơi phân biệt được ở kích thước nhỏ nhất xuất hiện (thử ở 60 px và bản đen trắng).
4. **Đọc được khi nhìn lướt:** chữ ≥ 12 pt thực tế trên máy; tương phản chữ ≥ 4.5:1 (< 18 pt), ≥ 3:1 (≥ 18 pt); không truyền thông tin chỉ bằng màu (thêm hình dạng/biểu tượng cho người mù màu); ưu tiên icon + số thay cho câu chữ (bớt khối lượng bản địa hóa, người chơi nhỏ tuổi đọc được).
5. **Phản hồi ("juice") có ngân sách:**
   - Mỗi chạm có phản hồi trong ≤ 100 ms (scale/âm thanh/rung nhẹ); kết quả thao tác (ghép, thắng) ≤ 0,5 s rồi mới tới hiệu ứng dài.
   - Hiệu ứng thưởng lớn không bị quảng cáo/modal đè; modal xuất hiện sau khi hiệu ứng xong và nút Next/Retry chỉ bật khi animation kết thúc.
   - Tween UI chạy theo unscaled time khi game pause/hit-stop; mọi hiệu ứng có thể tắt (rung, nhấp nháy mạnh).
6. **Hiệu năng UI:** 60 fps (16,7 ms/frame) là mục tiêu, 30 fps là sàn máy yếu; tách Canvas động/tĩnh, `raycastTarget` tắt cho phần trang trí, sprite UI trong atlas, không đổi layout mỗi frame.
7. **Trạng thái tương tác:** nút có Default / Pressed / Disabled rõ ràng (Disabled mờ + không nhận chạm); nút tốn tài nguyên (xu, quảng cáo, IAP) khóa ngay lần chạm đầu cho tới khi có kết quả; nút Back (Android)/ESC đóng modal trên cùng.
