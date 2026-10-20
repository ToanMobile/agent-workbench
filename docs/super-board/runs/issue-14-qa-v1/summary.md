# QA issue #14 (PR #136) — v1

Lệnh: `bash universal-agent-devkit/tests/worktree_git/test_worktree_automerge_staged_secret.sh` và `.../verification/test_instincts_add_concurrent.sh`

| AC | Code main (RED) | Nhánh PR (GREEN) |
|---|---|---|
| File staged chứa secret/symlink bị chặn automerge | exit 1: case 1, 2 FAIL (secret và symlink vẫn được commit và merge vào main) | exit 0: 3/3 PASS |
| `instincts.py add` seed template trong flock, 24 tiến trình đồng thời không mất bài học | exit 1: target đã dày 7283 byte khi lấy lock (copy ngoài lock) | exit 0: size lúc lock = 0, 24/24 bài học, 0 id trùng |

Gate `--run-tests --diff origin/main`: hồi quy 5/5, lớp tĩnh đạt. Exit 2 do nhánh cũ hơn main
(`tests/super-board/test_needs_you_autonomous_guard.sh` khác biệt vì main đi trước, PR không sửa file này).
Không có thay đổi UI: không cần ảnh.
