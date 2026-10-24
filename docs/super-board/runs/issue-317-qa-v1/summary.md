# QA #317 v1 (PR #339, head 1d37eef9, đã merge origin/main: Already up to date)

| AC | Bằng chứng | Kết quả |
|---|---|---|
| #138 Needs You | tests/super-board/test_status_needs_you_column.sh, exit 0; đột biến bỏ `status == NEEDS_YOU_STATUS` → ĐỎ ("waiting: ... waiting="), khôi phục → XANH | ✅ |
| #235 ⏳ chờ thẻ khác | tests/super-board/test_waiting_label.sh, exit 0 | ✅ |
| #288 merge-gate không chờ tải | tests/super-board/test_merge_gate_load_wait.sh, exit 0 | ✅ |
| #288 merge-train / ponytail | tests/super-board/test_merge_train.sh, exit 0 | ✅ |
| #288 runner lane worker | tests/super-board/test_runner_lane_workers.sh, exit 0 (43 ✔, 0 ✖) | ✅ |
| Gate --full | `super-board-verify-cmd.sh` = post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main | ✅ exit 0, 71/71 (lần 2) |

Lần 1 của gate: 69/70, REG-DK-SESSION-01 (test_multi_session_gate.sh) đỏ "expected full execution for the only session".
Chạy riêng suite đó: exit 0, 0 ✖. Lần 2 cả gate: 71/71 PASS. Diff không chạm suite đó; đỏ lần 1 do phiên khác đang chạy cùng lúc.
Không có thay đổi giao diện web: không có ảnh chụp.
