# Quy Chuẩn Ngôn Ngữ & Báo Cáo Nghiệm Thu (Vietnamese Repository Policy)

## 1. Ngôn Ngữ Mã Nguồn & Comment (Code Comments)
- **Comment mã nguồn**: 100% comment trong code (giải thích logic, thuật toán, ghi chú kỹ thuật, lưu ý kiến trúc) viết bằng **Tiếng Việt**.
- **Mã định danh (Code Identifiers)**: Tên hàm, tên biến, tên class, struct, file path, và command luôn giữ nguyên **Tiếng Anh**.

## 2. Báo Cáo Tiến Độ & Nghiệm Thu (Reports & Handovers)
- **Báo cáo nghiệm thu 5 mục** (chi tiết: `rules/core-rules.md` §2.3): Bắt buộc viết bằng **Tiếng Việt**, mỗi con số ghi nguồn `tự chạy` hoặc `agent báo`:
  1. Đã làm gì / Đã fix gì: Lỗi hoặc thay đổi, nguyên nhân gốc, bằng chứng đối lập (RED ➔ GREEN).
  2. Chặn bug cũ: Test hồi quy và rào chắn bất biến lịch sử đã chạy lại, kèm kết quả.
  3. Nguy cơ bug mới: Phép so cũ–mới đã chạy (lệnh, số đầu vào, số ca đổi kết quả) hoặc `chưa so — <lý do>`.
  4. An toàn mã nguồn: Quét secret, placeholder; OCR chỉ ghi khi đã chạy, không thì `OCR: không chạy — <lý do>`.
  5. Còn hở / chưa kiểm: Liệt kê, hoặc `không có`.
- **Văn phong (mọi text DevKit tạo ra: báo cáo, comment, PR, ticket)**: ngắn gọn, đơn giản, tự nhiên như người nói với đồng đội; câu ngắn, từ thông dụng, một ý một dòng, kết quả trước lý do sau, ai đọc cũng hiểu. Ngắn nhưng phải rõ nghĩa: cắt chữ thừa, không cắt ý; người đọc không có ngữ cảnh vẫn biết đã xảy ra gì, vì sao và ai làm gì tiếp (không viết cụt kiểu "xong, đạt"). Không dán log (trích tối đa 3 dòng), không dòng nghi thức rỗng. Báo cáo 5 mục vẫn đủ 5 mục (hook đọc) nhưng mỗi mục một câu.
- **Bằng chứng trước/sau trong báo cáo** (chọn đúng một trường hợp, gửi bằng chứng thật của lượt này, không dùng lại cái cũ):
  - Bug có giao diện: gửi ảnh cũ đang lỗi (`reports/before-*.png`) và ảnh mới vừa fix xong (`reports/proof-*.png`).
  - Task mới có giao diện: gửi ảnh nghiệm thu mới.
  - Task không có ảnh (backend, tooling, docs): viết hai câu, cũ bị gì và mới đã sửa gì, kèm một kết quả chạy thật (vd test ĐỎ rồi XANH).
- **Ảnh hiện thẳng, không bắt bấm link**: trong Claude Code, mở file PNG bằng công cụ Read để ảnh hiện ngay trong khung chat, rồi nhúng `![mô tả](đường dẫn)` ở báo cáo; không chỉ dán đường dẫn hay link. Cả ảnh cũ lỗi và ảnh mới đều hiện như vậy.
- **Comment trên task theo đúng mẫu báo cáo này**: dòng đầu là kết quả, rồi bằng chứng trước/sau theo 3 trường hợp ở trên, rồi các mục còn hở. Ảnh nhúng thẳng vào comment (URL raw ghim theo sha), không để link. Giữ nguyên dòng tiêu đề `[role] [label]` và các dòng máy đọc (`blocked-by:`, `Local tests:`).
- **Trạng thái mở đầu**: Sử dụng `XONG` / `CHƯA XONG` / `CHỜ DUYỆT`.

## 3. Git Commit & Pull Request
- **Commit message**: Tiêu đề và nội dung commit viết bằng **Tiếng Việt**, sử dụng tiền tố conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `perf:`.
- **Pull Request / Issue Comment**: Tiêu đề và mô tả PR, ghi chú review viết bằng **Tiếng Việt**.
