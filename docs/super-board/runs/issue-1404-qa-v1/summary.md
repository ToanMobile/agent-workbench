# QA Evidence — Issue #1404 (PR #1410)

- Head tested: `fb86345dc6f201b9b23020065ab51e8e4f98ecd0` (merged `origin/main` `0a644f4e`: already up to date)
- UI/Screenshots: không có (chỉ thay đổi shell script merge gate/train và test CLI)

## Kết quả chạy test
- `bash tests/super-board/test_merge_scratch_antigravity_hooks_1404.sh` -> exit 0 (6/6 ca PASS: 1a, 1b, 2a, 2b, 3, 4)
- `bash tests/super-board/test_merge_train.sh` -> exit 0 (19/19 ca PASS)
- `bash tests/super-board/test_merge_gate_scratch_agents_clean.sh` -> exit 0 (PASS)
- `bash tests/super-board/test_merge_gate_scratch_clean.sh` -> exit 0 (PASS)
- `bash tests/super-board/test_merge_gate_install_untracked.sh` -> exit 0 (PASS)
- `bash tests/super-board/test_merge_gate_devkit_from_main.sh` -> exit 0 (PASS)
- `bash tests/super-board/test_verify_flags_arg_span.sh` -> exit 0 (PASS)
- `bash universal-agent-devkit/tests/gates/test_matrix_real_readers.sh` -> exit 0 (PASS)
- `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` -> exit 0 (`pass`, 5/5 suite hồi quy đạt, `core-touched`: `super-board-merge-gate.sh`, `super-board-merge-train.sh`, `super-board-verify-flags.sh`)
- `python3 .agents/devkit/bin/agent-health.py -t .` -> exit 0 (PASS, 100/100, 29/29 hạng mục)
- `pr-security-review`: 0 findings (1 phát hiện ứng viên đã lọc false positive điểm 2/10: hành vi pre-existing trên `-a claude` và sau `approved-head`)

## Đối chiếu AC
- AC1 (oracle merge gate): PASS (`1a`, `2a`, `4` trong `test_merge_scratch_antigravity_hooks_1404.sh`)
- AC2 (oracle merge train): PASS (`1b`, `2b` trong `test_merge_scratch_antigravity_hooks_1404.sh` và `test_merge_train.sh`)
- AC3 (nghiệm thu thật PR #1394 qua merge queue & gỡ Blocked #1392): chưa kiểm chứng — để `[ ]` (`ac-open`) vì PR #1410 chưa merge lên `main`

## Log thô (ngoài nhánh)
- `$(git rev-parse --git-common-dir)/super-board/evidence/issue-1404/`
