# QA v5 · issue #323 · PR #349

- Lý do chạy lại: lượt rebase (head 004fb0e3) và `origin/main` đi tiếp (#341, #320, #376); worker QA trước chết (exit=143).
- Đã gộp `origin/main` vào nhánh (không xung đột), head sau gộp có `fb96481a` + merge tiếp.
- Gate: `post-fix-gate.py --run-tests --full --force-full --diff origin/main --auto-approve-tests` exit 0, 96/96.
- Sửa ngoài code sản phẩm: không. Code PR không đổi so với head đã QA v4 (ac5efec4); chỉ có merge từ main.
- Test đã có bị sửa: `universal-agent-devkit/tests/worktree_git/test_worktree_discard_squash.sh` (siết s11 + thêm s12 cho #326) — cộng thêm, tự duyệt.
- Lượt đỏ giữa chừng: thiếu file test do nhánh chậm main (exit 127) và `test_worktree_merge_gate_trunk` đỏ do tải ~80; gộp main + chạy lại thì xanh, test đó chạy riêng cũng PASS.
- AC: #157 #234 #262 #302 #326 #327 đạt (R1–R3 từ v4 giữ nguyên); #301 tách ở #356.
