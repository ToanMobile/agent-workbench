# QA v4 · #830 · PR #1076 · head 76590761 (rebuild vòng 3)

- `bash universal-agent-devkit/tests/gates/test_hardware_issue830.sh`: rc 0 (PASS) trên head.
- Cùng test với `HW_HOOK` = hook cũ origin/main: rc 1, 42 dòng ✖ (ĐỎ).
- 22 test hook liên quan (`test_hardware_*`, `test_guard_shell_norm*`): tất cả rc 0.
- Security: diff hook không thêm eval/exec/os.system/subprocess/open mới.
- `post-fix-gate --run-tests --scoped --brief --json`: exit 2, `super-board-qa-exit2.sh` = review.
  Lý do duy nhất: `universal-agent-devkit/tests/impact_map.txt` (test đã có) bị sửa, chờ duyệt chéo.
- Ảnh: không cần (hook dòng lệnh, không có UI).
