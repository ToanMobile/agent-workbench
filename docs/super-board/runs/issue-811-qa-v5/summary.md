# QA v5 — issue #811, PR #1086, head 79e1b7d2 (đã chứa origin/main)
Lệnh: `WORKTREE_AUTO_MERGE=0 bash universal-agent-devkit/tests/gates/<test>.sh` (không dùng `env -u`).
- AC1: `test_suite_env_auto_merge.sh` exit 0; `test_worktree_merge_gate_conflict_advice.sh` exit 0.
  RED dựng lại: `post-fix-gate.py` + `clean_git_env.sh` của origin/main thì `suite_env_auto_merge` exit 1, `conflict_advice` exit 1.
- AC2: `test_worktree_merge_gate.sh` + `_board_kept` `_conflict_advice` `_owner` `_subagent_live` `_trunk` `_vanished` + `test_suite_env_auto_merge.sh`: 8/8 exit 0.
- AC3: diff chỉ thêm `unset` và bỏ biến khỏi suite_env; assertion `_trunk` / `_owner` không đổi (exit 0).
Gate scoped: xem comment [qa] [report].
Ảnh: không cần — chỉ chạm tooling/test.
