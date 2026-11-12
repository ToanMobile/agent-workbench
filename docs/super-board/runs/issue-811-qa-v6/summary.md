# QA v6 — issue #811, PR #1086, head aab9378a (đã chứa origin/main)
Lệnh: `WORKTREE_AUTO_MERGE=0 bash universal-agent-devkit/tests/gates/<test>.sh` (không dùng `env -u`).
- AC1: `test_suite_env_auto_merge.sh` exit 0; `test_worktree_merge_gate_conflict_advice.sh` exit 0.
  RED dựng lại trên bản sao origin/main (test mới + code cũ): `suite_env_auto_merge` exit 1, 2 ca ✖ (suite_env, clean_git_env).
- AC2: `test_worktree_merge_gate.sh` + `_board_kept` `_conflict_advice` `_owner` `_subagent_live` `_trunk` `_vanished` + `test_suite_env_auto_merge.sh`: 8/8 exit 0.
- AC3: diff sản phẩm 3 file (post-fix-gate.py +3/-1, clean_git_env.sh +2, test mới); assertion `_trunk` / `_owner` không đổi (exit 0).
Gate scoped: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` in `pass` (exit 0).
Ảnh: không cần — chỉ chạm tooling/test.
