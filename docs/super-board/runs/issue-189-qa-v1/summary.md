# QA #189 v1 — kéo thẻ Backlog lên Ready

Lệnh: `bash tests/super-board/test_runner_backlog_pull.sh` · exit 0 · ALL PASS (A, B, C, D1-D4, E, F, F2, W = 11 ca)

| AC | Ca | Kết quả |
|---|---|---|
| 1 Ready=0, 3 thẻ đủ AC + 1 needs-you → kéo đúng 3 | A | ✅ |
| 2 Thẻ thiếu AC không kéo, có comment lý do (1 lần/nội dung) | B | ✅ |
| 3 Thẻ CLOSED trong Backlog → Done, không dispatch | C | ✅ |
| 4 Không vượt worker rảnh; tải cao chỉ 1 thẻ khi lane rỗng | D1-D4, F | ✅ |
| 5 Gate --full exit 0 | xem dòng Gate cuối file | — |

Mutant: đổi `select($c | for_a_person | not)` thành `select(true)` → ca A ĐỎ (kéo cả thẻ needs-you #304); khôi phục → ALL PASS.

Ghi chú: body của chính #189 dùng AC đánh số `1)` không có gạch đầu dòng → `backlog_ticket_gaps` báo thiếu "Acceptance Criteria", cùng luật preflight (không phải lỗi mã).
