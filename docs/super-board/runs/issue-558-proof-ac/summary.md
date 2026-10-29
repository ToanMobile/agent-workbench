# #558 · bằng chứng AC (PR chứng minh, code đã merge ở #583)

Lệnh: `bash tests/super-board/test_sweep_closed_cards.sh` trên `origin/main` @ 46260cf0.

| Runner | Kết quả |
|---|---|
| Bản trước #583 (`SB_RUNNER=<super-board-run.sh @ 5edb0656^>`) | ĐỎ: 4 ✖ (completed không sang Done, rc, not_planned thiếu log, ghi hỏng) |
| `origin/main` (có `sweep_closed_cards`) | XANH: 6 ✔, exit 0 |

- AC1 Blocked + CLOSED completed → Done kèm comment: `✔ Blocked + CLOSED completed: sang Done kèm comment report`
- AC2 not_planned không sang Done: `✔ đóng not_planned: giữ cột` + `✔ not_planned có log`
- AC3 lỗi ghi board không dừng board, tick sau thử lại: `✔ ghi board hỏng: không chặn thẻ/halt, không comment, rc≠0`
