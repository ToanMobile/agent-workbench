# QA v3 · #1107 · PR #1167 @ 29f40566 (rebuild-2)
- `bash tests/super-board/test_runner_self_reload.sh` → exit 0, "all passed" (ca 4d detached + detached-dirty).
- Mutation: chép runner của origin/main đè lên bản sửa → exit 1, `detached: exec=0 notify=1` (ĐỎ); khôi phục bản sửa → XANH.
- `bash universal-agent-devkit/tests/verification/test_essentials_budget.sh` → exit 0, 14332/14350 byte (CI đỏ cũ do #1163 đã hết).
- origin/main đã nằm trong nhánh (merge "Already up to date").
- Gate scoped: xem comment QA (chạy sau commit evidence).
