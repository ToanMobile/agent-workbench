# QA v2 — issue #308 (PR #310)

Cây: issue-308-self-reload-diverged-main + `git merge origin/main` (sạch, không xung đột).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_runner_self_reload.sh` | 0 | 15/15 ✔, gồm 2 ca `finish` THẬT (main lệch origin; xung đột) |
| `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` | 0 | 65/65 |

Đột biến: đổi worktree tạm về `--base=origin/main` (lỗi v1) → 3 ca đỏ
(`real finish: rc=1`, `worktree left behind`, `real conflict: rc=1`); khôi phục → xanh.

AC1 ✔ main có commit cục bộ, origin đổi runner → gộp qua finish, exec code mới, giữ commit cục bộ.
AC2 ✔ xung đột → HEAD không đổi, notify một lần, không restart mù, worktree tạm được dọn.
AC3 ✔ gate --full exit 0.

Log thô giữ ngoài nhánh (không commit).
