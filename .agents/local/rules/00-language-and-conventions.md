# Quy Chuẩn Ngôn Ngữ & Báo Cáo Nghiệm Thu (Vietnamese Repository Policy)

## 1. Ngôn Ngữ Mã Nguồn & Comment (Code Comments)
- **Comment mã nguồn**: 100% comment trong code (giải thích logic, thuật toán, ghi chú kỹ thuật, lưu ý kiến trúc) viết bằng **Tiếng Việt**.
- **Mã định danh (Code Identifiers)**: Tên hàm, tên biến, tên class, struct, file path, và command luôn giữ nguyên **Tiếng Anh**.

## 2. Báo Cáo Tiến Độ & Nghiệm Thu (Reports & Handovers)
- **Báo cáo nghiệm thu 4 mục**: Bắt buộc viết bằng **Tiếng Việt**:
  1. Đã fix gì (What Was Fixed): Tên lỗi, nguyên nhân gốc, cơ chế lỗi, bằng chứng đối lập (RED ➔ GREEN).
  2. Đã chặn đứng bug cũ nào (Zero Reopened Bugs): Rào chắn bất biến lịch sử và test hồi quy đạt PASS.
  3. Nguy cơ bug mới nào đã triệt tiêu (Zero Collateral Damage): Rà soát inbound callers, module liên đới.
  4. Trạng thái an toàn mã nguồn: Quét secret (SẠCH), 0 placeholder, OCR tĩnh (0 leak).
- **Trạng thái mở đầu**: Sử dụng `XONG` / `CHƯA XONG` / `CHỜ DUYỆT`.

## 3. Git Commit & Pull Request
- **Commit message**: Tiêu đề và nội dung commit viết bằng **Tiếng Việt**, sử dụng tiền tố conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `perf:`.
- **Pull Request / Issue Comment**: Tiêu đề và mô tả PR, ghi chú review viết bằng **Tiếng Việt**.
