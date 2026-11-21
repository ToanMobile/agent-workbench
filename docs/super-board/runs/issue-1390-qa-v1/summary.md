# QA v1 — #1390 (PR #1393)

- Kết luận: **FAIL (`qa-fail`)** — phát hiện 2 lỗi mức High cần sửa mã nguồn trong `.claude/bin/super-board-run.sh`.
- An toàn mã nguồn (`pr-security-review`): 0 phát hiện có độ tin cậy cao.
- Kiểm tra trên `origin/main` (`0ba93027`): `test_runner_review_antigravity_1390.sh` FAIL (9 case), trên PR (`6033f0bd`): PASS 12/12.

## Kết quả chạy test
- `/bin/bash tests/super-board/test_runner_review_antigravity_1390.sh` → exit `0` (12/12 PASS)
- `/bin/bash tests/super-board/test_runner_review_antigravity_1390_qa_gaps.sh` → exit `1` (0/3 PASS, 3 FAIL):
  - `✖ G1: picked unrunnable script without node_modules (.../wt/mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js)`
  - `✖ G2: sweep falsely moved 🔐 re-blocked #2001 back to Review`
  - `✖ G3: sweep falsely moved 🛡 rebuild-cap #2002 back to Review`
- Các suite liên quan (`test_runner_review_slot.sh`, `test_runner_review_approved_head.sh`, `test_runner_review_merge_train.sh`, `test_claude_verify_seal.sh`) → exit `0` (4/4 PASS).

## Chi tiết lỗi cần sửa
1. `antigravity_pm_mcp_script` (`.claude/bin/super-board-run.sh:2002`): chỉ kiểm `-f "$cand"` mà không kiểm `node_modules/@modelcontextprotocol/sdk`, nên ở worktree/checkout thiếu `node_modules` sẽ chọn nhầm script hỏng thay vì profile/bản cài hợp lệ, khiến `antigravity_probe` lỗi `ERR_MODULE_NOT_FOUND` và chặn nhầm thẻ thành `Antigravity chưa mở`.
2. `sweep_antigravity_blocked` (`.claude/bin/super-board-run.sh:3662-3676`): nối 5 comment cuối (`jq -r '.[-5:][]?.body // ""'`) nên dính `sb-blocked-reason: antigravity-*` cũ khi thẻ bị chặn lại vì `🔐`/`🛡`, và dính comment thường nhắc `pm_dispatch`/`antigravity-pm` khi thẻ bị chặn vì `rebuild_cap`; cần chỉ xét comment blocker mới nhất (và comment reviewer liền trước nó nếu là thẻ cũ).
