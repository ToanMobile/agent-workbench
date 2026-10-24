# QA #321 v1 — PR #342 (nhánh issue-321-gh-timeout-money-approve)

Kết quả: PASS. Đầu nhánh đã merge origin/main (Already up to date).

| AC | Lệnh | Kết quả |
|---|---|---|
| #305 test 29/30 (gh treo → ID dự phòng + cảnh báo; issue create treo → thoát ≠ 0) | `bash universal-agent-devkit/tests/verification/test_create_task_batch.sh` | exit 0, "all passed" (30/30) |
| #261 stripe.material không kích money; import/require/api.stripe.com/sk_live/pk_live/Stripe( vẫn kích | `bash tests/super-board/test_merge_policy_money_keywords.sh` | PASS |
| #236 Approve đúng head duyệt được; tin cũ báo head đã đổi, không duyệt nhầm | `node --test mcp-servers/cc-switcher-mcp/tests/super-board-approve-head.test.js .../super-board-approve.test.js` | 7 pass / 0 fail |
| Gate cùng bộ suite với merge gate | `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | exit 0, 81/81 |

## RED độc lập (đặt mã main vào, chạy lại, rồi trả mã nhánh)
- merge-policy của main: test money FAIL — `stripe.material` bị bắt nhầm, `import Stripe` / `require('stripe')` không bị bắt.
- telegram.js của main: `super-board-approve-head.test.js` pass 1 / fail 3.
- Cây làm việc sạch sau khi trả mã (git status rỗng).

## Chưa đạt / ghi chú
- #236 AC "không còn thông báo merge trùng lặp" và "ảnh chụp Telegram 18:46 làm before": không có test hay bằng chứng trong PR; không kiểm chứng được ở lượt này.
- Không có thay đổi giao diện nên không có ảnh.
