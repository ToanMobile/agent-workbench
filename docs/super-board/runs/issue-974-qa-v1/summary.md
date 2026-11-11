# QA #974 v1 — PR #1082 (head bec9413a + merge origin/main)

| Lệnh | Exit | Kết quả |
|---|---|---|
| bash tests/super-board/test_kit_tests_devkit_fallback.sh | 0 | mọi test nạp clean_git_env.sh / super_board_all.py có fallback .agents/devkit |
| bash tests/super-board/test_runner_watchdog.sh | 0 | all passed, mục 9 stop/status chạy, không skip |
| test_batch_canary / test_qa_detached_worktree / test_tests_skip_machine_slots / test_dispatch_moves_to_building | 0 | pass |

- Quét: 0 test còn dòng nạp cứng `universal-agent-devkit/tests/lib/clean_git_env.sh` thiếu `.agents/devkit`.
- AC1 ✅, AC2 ✅, AC3 (drift 5 repo app) chỉ kiểm được sau sync kế tiếp.
- Ghi chú: PR #1081 (branch issue-974-kit-test-fallback) trùng nội dung với #1082; nên đóng #1081.
