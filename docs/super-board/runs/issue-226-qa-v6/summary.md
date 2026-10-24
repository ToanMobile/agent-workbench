# QA v6 — PR #375 (gap 7, 4 phát hiện OCR)

Head đã gộp origin/main: nhánh issue-226-runner-merge-train-reload (head PR 948f2e9d + merge origin/main).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_merge_gate_verified_tree.sh` | 0 | tất cả xanh (khoá kit băm cả module, thiếu sha256 không biên nhận, `--record` đỏ → 11, dọn biên nhận > 14 ngày) |
| `bash tests/super-board/test_merge_gate_red_on_base.sh` | 0 | PASS |
| `bash tests/super-board/test_merge_train.sh` | 0 | tất cả xanh |
| `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | 0 | 90/90 |

Đột biến: băm riêng `post-fix-gate.py` thay vì mọi `bin/*.py` → test_merge_gate_verified_tree ĐỎ 1 ca; khôi phục → xanh.

Chưa ghi biên nhận: `super-board-verify-cmd.sh --record` thoát 65 ("needs a clean merged tree") vì worktree có `.claude/settings.json` bị DevKit đồng bộ (không thuộc PR); guard git chặn stash/checkout nên không dọn được. Merge gate sẽ verify lại một lần (vẫn đúng).
AC 7 (đo lại review lặp, PR merge/giờ) cần số liệu vận hành, chưa đo.
