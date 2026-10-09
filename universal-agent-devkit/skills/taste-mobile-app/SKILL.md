---
name: taste-mobile-app
description: Dùng khi thiết kế hoặc dựng màn hình/luồng mobile mới (Jetpack Compose, SwiftUI, Flutter, React Native) hay làm lại giao diện mobile trông rập khuôn. Bỏ qua khi chỉ sửa logic không đổi UI, game Unity (dùng ui-ux-pro-max) hoặc web.
---

# Taste Mobile App Art Direction (Anti-Slop)

Quy trình 7 pha chống giao diện rập khuôn, lấy cảm hứng từ phương pháp của github.com/orbitextechlab/taste-mobile-app-skill (MIT © Orbitex Lab). Áp dụng cùng luật thiết kế tại rules/essentials.md (Zero-Slop), rules/core-rules.md §6, và tham chiếu dữ liệu màu/font từ skills/ui-ux-pro-max/SKILL.md.

## Pha 1: Brief Gate
Tự suy luận yêu cầu từ repo và brief trước. Chỉ hỏi lại tối đa 3 câu nếu thiếu thông tin, và chỉ hỏi về sản phẩm/nghiệp vụ. Tuyệt đối cấm hỏi về màu sắc, font chữ. Đây KHÔNG phải là cổng duyệt (approval gate), hỏi xong tiếp tục làm.

## Pha 2: Dials & DNA
Xác định 3 thông số dial (thang 1-10) ghi rõ số: Expression, Motion, Density. Rút ra nguyên lý thiết kế DNA từ 2-3 app tham chiếu xuất sắc nhưng không sao chép y nguyên.

## Pha 3: Design Lock
Ghi file `MOBILE-DESIGN.md` ở gốc project (gồm dial, DNA, palette, typography, motion) TRƯỚC dòng code UI đầu tiên. Nếu dự án đã có `DESIGN.md`, bắt buộc LẤY token từ đó (không tự tạo thêm).

## Pha 4: Content Before Components
Tập trung vào tác vụ cốt lõi và điểm neo thị giác (hero) cho mỗi màn hình. Mỗi màn hình chỉ có 1 ý tưởng thị giác chủ đạo. Cấm bọc Card bừa bãi.

## Pha 5: Layout Mechanics
Tuân thủ kỹ thuật layout chuẩn: edge-to-edge (Android 15 / iOS Safe Area), touch target >= 48dp / >= 44pt, CTA chính ở nửa dưới (tầm ngón cái) hoặc dính đáy, bàn phím không che input. Tham khảo profiles/android/rules/android-rules.md và profiles/ios/rules/ios-rules.md.

## Pha 6: Mandatory 4 States
Bắt buộc thiết kế đủ 4 trạng thái:
1. Loading: dùng skeleton/shimmer bám theo đúng form layout, cấm dùng spinner tròn vô nghĩa.
2. Empty: kèm giải thích và CTA.
3. Error: kèm nút Thử lại.
4. Populated: dữ liệu thật.

## Pha 7: QA Pass
Kiểm tra chéo:
- Mechanical: grep tìm `Card {` lồng nhau, `Color.Gray`, `#808080`, gradient tím/indigo, và câu chào sáo rỗng "Welcome back".
- Visual: 10 câu hỏi ngắn tự đánh giá giao diện:
  1. Màn hình có duy nhất 1 điểm neo thị giác (hero) chưa?
  2. Nút CTA chính có nằm trong tầm ngón cái (nửa dưới) không?
  3. Đã có đủ 4 trạng thái thiết kế (Loading, Empty, Error, Populated)?
  4. Độ tương phản chữ đã đạt >= 4.5:1 chưa?
  5. Nhịp điệu khoảng cách (spacing) có tuân thủ 4-8/12-16/24-32 không?
  6. Có tránh được lỗi Card lồng Card bừa bãi không?
  7. Màu và font có lấy từ DESIGN.md hoặc theme hệ thống không?
  8. Giao diện có tràn viền (edge-to-edge/insets) an toàn không?
  9. Bàn phím ảo có làm che khuất input hoặc nút bấm không?
  10. Chữ có đọc được tốt khi bật scale font lên 200% không?
