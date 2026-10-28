# QA #413 v1 — khoá devkit-kept lúc SessionStart (PR #417, head 42be7417)

Môi trường: worktree `.claude/worktrees/issue-413-qa`, đã `git merge origin/main` (Already up to date).

| AC | Kết quả | Bằng chứng |
|---|---|---|
| 1 startup git lock lỗi → NOT LOCKED | ✅ | N1, N1b XANH (N1b 6 s < 10 s) trong `test_session_worktree_enter_lock.sh` |
| 2 compact khoá worktree khởi đầu; cd sang phiên khác không khoá | ✅ | N2, N2b XANH; E9/E9b vẫn XANH |
| 3 pid_start khác / record pid cấp lại → vẫn khoá | ✅ | N3a, N3c XANH; đối chứng N3b, N3d XANH |
| 4 hai test PASS | ✅ | `test_session_worktree_enter_lock.sh` exit 0; `test_worktree_merge_gate_board_kept.sh` exit 0 |
| 5 lstart qua sleep | ❌ chưa đo được | 5 pid sống đều khớp `pid_start` (ps chạy TZ=UTC); pid sớm nhất 24/10 17:51 +07 khởi động sau lần ngủ cuối (23/10 19:42 +07) |

Gate: `post-fix-gate.py --run-tests --full --force-full --diff origin/main` exit 1 (2 lần), 110/111.
Suite đỏ duy nhất: `tests/gates/test_worktree_merge_gate_vanished.sh` ("the other worktree was not brought back": gộp nền của wt-feat4).
- Chạy riêng trên nhánh PR: xanh 1 lần, đỏ 3 lần liên tiếp (cùng lỗi).
- Chạy trên bản xuất `origin/main` (git archive): đỏ 1 lần, xanh 1 lần, cùng lỗi → flaky có sẵn trên base, không do PR (diff PR không chạm gộp nền).
- Đã nêu cho Reviewer; merge gate sẽ chạy lại verify trên cây hợp nhất.

Chưa kiểm: phép thử RED trên mã nền (hook của kit chặn lệnh khôi phục file về bản cũ), nên RED của N1/N1b/N3 dựa vào lời khai của builder.
Log thô: `.claude/audit-gate/qa-413/` (ngoài nhánh).
