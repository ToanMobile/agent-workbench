# QA v3 — issue #1311, PR #1312, code head 0bba7f83

Lệnh: `bash tests/super-board/test_github_read_rate_limit_backoff.sh`
- Trên head PR: rc=0, 10/10 xanh.
- Trên origin/main (worktree riêng, chép test vào): rc=1, 9 lỗi, ví dụ
  `limit x3 then ok: rc=79 halt=yes`, `issue_is_open rc=79 (want 69)`,
  `merge-gate approval_check rc=2 (want 69)`, `preflight_gate ... dispatching without it`,
  `card.sh status rc=79 halt=yes`.
- Lỗi 401 vẫn halt ngay lần đầu (xanh cả hai bên).

Cổng: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` in `pass`, exit 0.
Base: `git merge origin/main` báo Already up to date.
Ảnh: không cần, không có UI.
