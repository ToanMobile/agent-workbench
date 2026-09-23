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

## 6. HMI Đầu Xe (IVI) — Ưu Tiên An Toàn Khi Lái

> Mục này **ghi đè** các mục trên khi màn hình chạy trên đầu xe. Nếu dự án đã có theme riêng (Compose `MaterialTheme`, token trong module UI dùng chung), token của dự án thắng bảng màu mẫu ở §1 — ghi đường dẫn file theme thật vào `DESIGN.md` của dự án.

1. **Màn hình & mật độ:** Đầu xe IVI phổ biến là $1920\times 1080$ landscape, density 160 (mdpi ⇒ $1\text{dp} = 1\text{px}$). Không hardcode chiều cao màn hình: thanh điều khiển/dock của OEM và nav bar chiếm chỗ — dùng layout co giãn (`BoxWithConstraints`, `WindowInsets`). Kiểm cả chế độ chia đôi / cửa sổ nổi (bề rộng có thể chỉ còn ~1/2–1/3).
2. **Nhìn lướt (Glanceability):** Mỗi thao tác khi đang lái phải xong trong các lần liếc ngắn (hướng dẫn NHTSA: mỗi lần liếc ≤ 2 s, tổng ≤ 12 s). Tối đa **1 chạm, không quá 2 bước** cho chức năng dùng khi lái; không cuộn danh sách dài, không nhập bàn phím khi xe chạy.
3. **Vùng chạm:** Sàn cứng $\ge 48\times 48\text{dp}$ (core rules); điều khiển dùng khi đang lái nên $\ge 76\times 76\text{dp}$ (khuyến nghị Android for Cars), khoảng cách giữa hai vùng chạm $\ge 16\text{dp}$ để không bấm nhầm khi xe rung.
4. **Chữ:** Thân chữ đọc khi lái $\ge 24\text{sp}$ (không dùng thang 12–14sp của mobile cho nội dung chính); tối đa ~2 dòng mỗi thông báo; con số trạng thái (tốc độ, nhiệt độ, % pin) là phần tử lớn nhất trên thẻ.
5. **Ngày / Đêm:** Hỗ trợ cả hai theme và **tự chuyển theo xe** (UI mode night của hệ thống / đèn pha), không chỉ theo giờ. Ban đêm tránh nền trắng lớn gây chói; ban ngày đảm bảo tương phản dưới nắng (chữ chính ≥ 7:1 — WCAG AAA). Lớp overlay tự vẽ (widget nổi, số trên thanh OEM) cũng phải đổi màu theo theme.
6. **Phản hồi & xao nhãng:** Phản hồi tức thì (≤ 100 ms thị giác) và bằng **giọng nói** cho lệnh thoại; không animation trang trí/nhấp nháy khi xe chạy; trạng thái lỗi ghi rõ việc tài xế cần làm, không mã lỗi kỹ thuật.
7. **Trạng thái thật, không trạng thái giả:** Chỉ hiện "thành công" sau khi ECU/VHAL xác nhận giá trị mới; đang chờ thì hiện trạng thái chờ. Không có nút/cờ giả lập dữ liệu xe trên UI khách; nút kỹ thuật/dev ẩn hoàn toàn với người dùng thường.
8. **Hộp thoại xác nhận:** Chỉ cho thao tác có rủi ro khi xe chạy; đặt trên cùng (không chìm dưới thẻ), nút "Huỷ" và "Đồng ý" tách xa nhau, có hành vi an toàn khi hết giờ chờ.
