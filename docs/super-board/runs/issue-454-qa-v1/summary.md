# QA #454 v1 (PR #508)

Nhánh đã merge origin/main trước khi chạy.

| Lệnh | Exit |
|---|---|
| bash tests/super-board/test_lane_worktree_kit.sh | 0 (XANH) |
| bash tests/super-board/test_builder_already_met_and_model_tier.sh | 0 (PASS) |
| post-fix-gate.py --run-tests --brief --auto-approve-tests | 0 |

Đột biến (AC3), đã khôi phục sau mỗi lần:
- Thêm lại `git worktree remove` vào docstring worktree.py: test 1 ĐỎ (exit 1).
- Thay `--model "$claude_model"` bằng `--effort high` ở super-board-run.sh:1297: test 2 ĐỎ (1/2).
- Xoá hẳn `--model` ở dòng 1297: test 2 vẫn PASS (dòng không còn khớp `claude --`, đếm 1/1).

Test gap (Low, không viết): đột biến thứ ba lọt qua. Có sẵn từ test gốc (cùng mẫu `nohup claude --`), PR không làm tệ hơn.
