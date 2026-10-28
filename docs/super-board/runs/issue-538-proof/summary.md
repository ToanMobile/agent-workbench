# Proof #538 — early-death sai với bản ghi system sau result

PR #552 đã sửa (`28170395`). PR này chỉ chứng minh lại hai AC trên `origin/main` @ `7fda00d1`.

## ĐỎ → XANH
- ĐỎ: chạy `bash tests/super-board/test_runner_claim_loop.sh` với `.claude/bin/super-board-run.sh` của `29c75f02` (trước sửa) → exit 1, dòng
  `✖ result followed by task_summary was counted as an early death (#538)`.
- XANH: cùng lệnh với runner trên main → exit 0, `✅ test_runner_claim_loop: all passed`.

## AC
- Test ĐỎ→XANH ở tầng thấp nhất: test 4d (`tests/super-board/test_runner_claim_loop.sh:165`).
- Dòng `early end` của `kitbug09c38fc46c3c` không còn sinh trong kịch bản test 4d: test khẳng định không có dòng đó.
