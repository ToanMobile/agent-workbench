# #662 · QA v1 — gate_full chống trùng thẻ (head b89cb3a)

Kết quả: ĐẠT 4/4 AC. Hai suite đỏ của gate scoped đều đỏ cả trên origin/main, không do PR này.

| AC | Bằng chứng |
|---|---|
| 1. Thẻ mở tay có mã suite trong body ⇒ comment, không tạo thẻ | `bash universal-agent-devkit/tests/gates/test_gate_full_nightly.sh` exit 0, b9 + b9b ✔. Cùng test chạy với gate_full.py của origin/main (bản scratch): b9 ✖, b9b ✖, exit 1 (ĐỎ→XANH) |
| 2. Thẻ CARD_PREFIX cũ vẫn được comment | b8 ✔ trên nhánh PR (không hồi quy) |
| 3. Không có thẻ khớp ⇒ vẫn mở thẻ mới | b2 ✔, b10 ✔ (REG-FAKE-011 dài hơn, không khớp lỏng) |
| 4. test nightly exit 0; gate --scoped | test nightly exit 0. Gate scoped exit 1: 153/155, đỏ 2 suite dưới đây |

Gate scoped đỏ 2 suite (run.md 4c: chạy lại trên origin/main):
- REG-SB-SETUP-BIN-01: BIN thiếu super-board-merge-cards.py. Đã đỏ trên main (thẻ #659).
- REG-SB-MERGE-TRAIN-01: `✖ F4 no worker flag: exit 13`. Chạy tests/super-board/test_merge_train.sh trên origin/main nguyên bản: cùng ✖, exit 1.
PR chỉ sửa 2 file (gate_full.py, test_gate_full_nightly.sh), không chạm các suite này.

Review mã: token regex `(?<![A-Za-z0-9_-])ID(?![A-Za-z0-9_-])` không khớp REG-X-011 với REG-X-01; lỗi gh trả rỗng; timeout 60 s giữ nguyên.
