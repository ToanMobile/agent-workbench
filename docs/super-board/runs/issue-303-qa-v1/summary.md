# QA issue #303 v1 — PASS (non-visual, không có ảnh chụp)

Head đã test: 68ddba34 (đã merge origin/main: Already up to date)
- test_github_read_jq_flag.sh: exit 0 (ca --resume -q: exit 64, record halt được giữ, thông báo nêu resume)
- test_runner_ready_order.sh: exit 0, ALL PASS (R5: rc=79, thẻ #400 không được giao, log có dòng lý do HALT)
- Gate: post-fix-gate --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main: exit 0, 65/65 hồi quy

Mutation (test phải đỏ khi bỏ dòng được bảo vệ, rồi khôi phục, cây sạch):
- M1 bỏ `exit 79` trong ready_card_held: R5 đỏ (rc=0, TOP=400)
- M2 bỏ dòng log lý do: R5 đỏ (log rỗng)
- M3 bỏ nhánh `recovering` của thông báo: ca --resume đỏ ("the run continues")

Test gaps (not written): ready_card_held khi github-read trả exit khác 0 và khác 79 chỉ log rồi return 1 (không có ca riêng).
