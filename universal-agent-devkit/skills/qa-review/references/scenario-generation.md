# Sinh ma trận test scenario

Load file này ở bước 4 của `qa-review`. Đầu ra là **kịch bản để người kiểm**, không phải code test (R1 không sinh code test).

## Bốn trục

| Trục | Hỏi gì | Bỏ qua khi |
|---|---|---|
| **Happy path** | Luồng đúng, dữ liệu hợp lệ, quyền đủ, gameplay mượt | không bao giờ bỏ |
| **Biên** | rỗng/một/nhiều; 0, âm, max; chuỗi dài; màn 360dp/foldable/tablet/xoay ngang; font scale 150-200% | thay đổi không nhận input / không đổi bố cục |
| **Lỗi & ngoại lệ** | mạng đứt, timeout, bấm spam double-tap, app bị minimize/kill, cuộc gọi đến đè game loop | thay đổi thuần tĩnh, không I/O, không vòng đời |
| **Quyền hạn** | từng vai trò (user/admin/guest); quyền runtime thiết bị (camera, location, notification) | không có khái niệm vai trò hoặc permission trong luồng |

**Chỉ dùng trục áp dụng được.** Đổi màu nút không cần trục quyền hạn — thêm vào chỉ làm loãng.

## Format

| # | Trục | Tiền đề | Thao tác | Kết quả mong đợi | Ưu tiên |
|---|---|---|---|---|---|
| 1 | Happy | Đơn 500.000₫, mã `SALE10` còn hạn | Nhập mã, bấm Áp dụng | Tổng 450.000₫, hiện "Đã giảm 50.000₫" | P0 |
| 2 | Biên | Điện thoại xoay ngang (Landscape), màn 360dp | Mở form nhập liệu | Bàn phím ảo không che mất nút Submit; cuộn mượt | P1 |
| 3 | Lỗi | Mạng chập chờn khi đang ký/thanh toán | Bấm nút Ký 2 lần liên tiếp | Nút lập tức disable, chỉ 1 request gửi đi, không tạo duplicate | P0 |
| 4 | Lỗi | Đang chơi/thao tác thì có cuộc gọi đến | App xuống background rồi mở lại | State không bị reset, game loop tự pause | P1 |
| 5 | Quyền | User từ chối quyền Camera | Bấm quét mã QR | Hiện Dialog giải thích thân thiện + nút mở Cài đặt, không crash | P1 |

**Kết quả mong đợi phải quan sát được** — mã lỗi, con số, chữ hiện trên màn, nút disabled. "Xử lý đúng" không phải kết quả.

## Ưu tiên

| Mức | Nghĩa |
|---|---|
| **P0** | Hỏng là mất tiền / lộ dữ liệu / crash app / chặn luồng chính. Phải kiểm trước khi merge. |
| **P1** | Hỏng gây khó chịu rõ rệt nhưng có đường vòng (lệch nhẹ layout, xoay màn hơi giật). |
| **P2** | Hoàn thiện thẩm mỹ. Kiểm khi có thời gian. |

## Số lượng

Đủ để phủ **mọi nhánh rẽ nhìn thấy trong diff**, không hơn. Liệt kê tổ hợp cho đủ số lượng là cách chắc chắn để không ai chạy bảng này.

Dấu hiệu ma trận sai:
- Hai dòng khác nhau mỗi chỗ đặt tên biến → gộp.
- Một dòng không truy được về dòng nào trong diff → xoá, hoặc chuyển thành câu hỏi.
- Không dòng nào là P0 mà thay đổi chạm `schema`/`auth` → đọc lại diff, chắc chắn đã sót.

## Nối sang bước tiếp theo

- **Nếu có thay đổi Web UI:** Chỉ đích danh route cần chạy `qa-visual` để đối chiếu layout thật, đừng đoán từ diff.
- **Nếu có thay đổi Mobile / Game:**
  1. Chạy Paired Test (RED $\to$ GREEN) trên emulator/device thật.
  2. Chụp ảnh nghiệm thu trạng thái thành công (`proof-capture.py` hoặc runner).
  3. Upload ảnh nghiệm thu lên CDN/R2 bằng `node .agents/skills/qa-review/scripts/upload-proof-r2.mjs <ảnh>` để lấy link nhúng vào PR comment / báo cáo nghiệm thu mà không làm nặng Git repo.

