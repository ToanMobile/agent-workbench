# QA #109 v2 (rebuild vòng 1) — preflight: tiêu đề AC có hậu tố và "máy thật" phủ định

Head kiểm: cc8bfcdf. Lệnh: `bash tests/super-board/test_preflight_too_big.sh` → exit 0, `PASS: preflight too-big`.

Đột biến (preflight sửa, fixture giữ nguyên):
- origin/main: ĐỎ `✖ Synthetic #908: muốn proceed/clean, được hold/too-big`
- phủ định rộng (bỏ giới hạn ≤2 từ): ĐỎ `✖ Synthetic #911: muốn hold/too-big, được proceed/clean`
- lọc phủ định cả mục AC: ĐỎ `✖ Synthetic #909: muốn hold/too-big, được proceed/clean`
- khôi phục bản đúng: xanh.

Gate: `post-fix-gate.py --run-tests --full --brief --diff <merge-base> --auto-approve-tests` → exit 0 (hồi quy 41/41). Nhánh sau origin/main 2 commit nên dùng merge-base; chỉ test_preflight_too_big.sh bị sửa (thêm ca).

| AC | Kết quả |
|---|---|
| Tiêu đề `(draft)` bị giữ như chuẩn | ✅ #906 hold/too-big |
| "không cần máy thật" không bị giữ | ✅ #908 proceed/clean |
| test xanh | ✅ exit 0 |
| R1 AC "Không OOM trên máy thật" vẫn giữ | ✅ #909 (đỏ khi lọc AC) |
| R2 phủ định chỉ sát cụm | ✅ #911/#912 (đỏ khi mở rộng) |
| R3 fixture hướng ngược | ✅ #909–#912 |

Khoảng trống (Low, không viết): phủ định bắc cầu qua >2 từ ("không bắt buộc phải có máy thật") vẫn tính là tín hiệu → thiên về hold.
