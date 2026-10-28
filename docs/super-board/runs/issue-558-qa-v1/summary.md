# #558 QA v1 — sweep thẻ có issue đã đóng sang Done

Lệnh: `bash tests/super-board/test_sweep_closed_cards.sh`
- Nhánh PR (đã merge origin/main): exit 0, 6/6 ✔
- Runner cũ của origin/main (`SB_RUNNER=<bản main>`): exit 1, 4 ✖ (không có hàm sweep) → ĐỎ trên main, XANH sau sửa.

AC:
1. Blocked + CLOSED completed → Done + comment report: ✔
2. Đóng not_planned: không chuyển cột, chỉ log: ✔
3. Ghi board hỏng: SB_CARD_BLOCKING=1 (không chặn/halt), không comment, rc≠0 → tick sau thử lại: ✔
Phụ: thẻ đã Done không bị đụng; danh sách rỗng không ghi gì; `bash -n` sạch.
Rà thêm: issue_is_open (0=mở, 1=đóng, 79=halt) dùng đúng; nhãn ac-open vẫn mở lại thay vì Done.
