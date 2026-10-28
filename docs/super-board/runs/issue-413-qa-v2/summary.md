# QA v2 — #413 (PR #417), rebuild-1

Cây kiểm: head `50c4bfc8` + `git merge origin/main` (có f9a20221, #415 vòng cuối).

| Lệnh | Kết quả |
|---|---|
| `tests/gates/test_session_worktree_enter_lock.sh` | PASS (N1, N1b, N2, N2b, N3a–d, E9, E14–E17, R2–R8 đều XANH) |
| `tests/gates/test_worktree_merge_gate_board_kept.sh` | PASS |
| `post-fix-gate.py --run-tests --full --force-full --diff origin/main` (2 lần) | exit 1, 110/111 |

Đỏ duy nhất: REG-DK-ALL-01 → `tests/gates/test_worktree_merge_gate_vanished.sh` (1 failed) trong `run_impacted.sh`.
- Chạy riêng trên cây PR: 3/3 + 1 lần với CLAUDE_PROJECT_DIR = XANH. Chỉ đỏ khi chạy trong run_impacted dưới tải.
- QA v1 đã thấy cùng lỗi trên bản xuất `origin/main` (đỏ 1/2) → flaky có sẵn; file này không nằm trong diff PR.

AC 5 (lstart qua sleep): builder đo mẫu thay thế (pid 1120, khởi động 22/10 21:48:43; 56 lần sleep/wake, không trôi;
`is_pid_alive(1120, pid_start)` = True). Registry chưa có mẫu ghi trước lúc ngủ → AC 5 đạt một phần.

## Vòng 3 (head 50c4bfc8)

- Dựng lại worktree QA (bản cũ bị gỡ giữa lượt). test_session_worktree_enter_lock.sh PASS, test_worktree_merge_gate_board_kept.sh PASS.
- git merge origin/main (có 3315278c, #420): XUNG ĐỘT ở bin/session_lock.py (1 vùng) và hooks/session_worktree.py (3 vùng). PR #417 mergeable: CONFLICTING.
- #420 sửa cùng vùng (luật chặn khoá của phiên khách, record không pid): builder phải gộp tay, QA không sửa mã sản phẩm.
- Gate --full chưa chạy trên cây đã gộp (không gộp được).
