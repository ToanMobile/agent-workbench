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
- **Trạng thái mở đầu**: Sử dụng `XONG` / `CHƯA XONG` / `CHỜ DUYỆT`.

## 3. Git Commit & Pull Request
- **Commit message**: Tiêu đề và nội dung commit viết bằng **Tiếng Việt**, sử dụng tiền tố conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `perf:`.
- **Pull Request / Issue Comment**: Tiêu đề và mô tả PR, ghi chú review viết bằng **Tiếng Việt**.
