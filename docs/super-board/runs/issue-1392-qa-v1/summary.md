# QA Evidence — Issue #1392 / PR #1394

- Head được kiểm: `4ca3aadeba4ad5cd9c401dec42be0577e7fadfc0`
- Thời điểm: 2026-11-20 23:39 +0700

## Các lệnh đã chạy
1. `bash universal-agent-devkit/tests/verification/test_repo_board_and_context.sh` -> exit 0 (21/21 checks pass)
2. `bash universal-agent-devkit/tests/context_memory/test_context_sync.sh` -> exit 0 (all checks passed)
3. `bash universal-agent-devkit/tests/verification/test_create_task_registry.sh` -> exit 0 (all checks passed)
4. `bash universal-agent-devkit/tests/context_memory/test_session_context.sh` -> exit 0 (all checks passed)
5. `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh` -> exit 0 (all checks passed)
6. `python3 universal-agent-devkit/scripts/governance/context_sync.py . --check` -> exit 0 (`context_sync --check OK`)
7. `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` -> exit 2 (`super-board-qa-exit2.sh` = `review`; 9/9 suite hồi quy pass; `REG-DK-ALL-KIT-01` `per_test_cache: reuse=8 ran=2`; `tests_touched: ["universal-agent-devkit/bin/agent-kit"]`; `findings: []`, `uncovered: []`, `orphan_tests: []`, `static: all 0`)

## Kiểm tra thực tế trên 6 repo (chỉ đọc / bản sao tạm)
- `repo_board.py <repo> --json` trên 6 repo thật: OfficeReader `#2`, Goods `#3`, GeelyEx2 `#4`, Idle `#5`, Humans `#6`, agent-workbench `#1` -> exit 0.
- `context_sync.py` trên bản sao tạm `AGENTS.md` + config của 5 repo app -> sinh đúng dòng `Board của repo này: ToanMobile/projects/<2..6> (<title>)` không có ghi chú kit.
- `create_task.py --dry-run` tại cả 5 repo app thật -> trỏ đúng board `#2..#6`.
- `super-board-status.py` chạy thật tại `OfficeReader` (`#2`, 20 thẻ) và `GeelyEx2` (`#4`, 7 Backlog / 7 Ready) -> exit 0.
- `prompt_context.sh` tại `OfficeReader` với `"xem task trên board"` -> chèn đúng `#2`; với `"/createTask fix x"` -> bỏ qua gợi ý; `block-dangerous-git.sh` với `gh project item-list --owner ToanMobile 1` -> cảnh báo `#2`, exit 0.
- `pr-security-review`: 0 lỗ hổng bảo mật độ tin cậy cao trên 14 file diff.
- Ảnh màn hình: không cần — thay đổi CLI/script/hook không có giao diện.
