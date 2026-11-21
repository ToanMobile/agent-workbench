# QA Evidence — Issue #1392 / PR #1394 (v2 · rebuild R1–R5)

- Head được kiểm: `ca85cc7e680b055306e7cd83992c5cd2bab1fff0`
- Thời điểm: 2026-11-21 01:26 +0700

## Các lệnh đã chạy
1. `bash universal-agent-devkit/tests/verification/test_repo_board_and_context.sh` -> exit 0 (26/26 checks pass, gồm các ca `CLAUDE_PROJECT_DIR` và `ADB_SHIM=0`)
2. `bash universal-agent-devkit/tests/context_memory/test_context_sync.sh` -> exit 0 (all checks passed)
3. `bash universal-agent-devkit/tests/verification/test_create_task_registry.sh` -> exit 0 (all passed)
4. `bash universal-agent-devkit/tests/context_memory/test_session_context.sh` -> exit 0 (all checks passed)
5. `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh` -> exit 0 (all checks passed)
6. `bash universal-agent-devkit/tests/gates/test_adb_shim.sh` -> exit 0 (PASS: test_adb_shim)
7. `python3 universal-agent-devkit/scripts/governance/context_sync.py . --check` -> exit 0 (`context_sync --check OK`)
8. `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` -> exit 2 (`super-board-qa-exit2.sh` = `review`; 9/9 suite hồi quy pass; `REG-DK-ALL-KIT-01` `ptc=[0, 8]`; `tests_touched: ["universal-agent-devkit/bin/agent-kit"]`; `findings: []`, `uncovered: []`, `orphan_tests: []`, `static: all 0`)

## Kiểm tra thực tế trên 6 repo (chỉ đọc / bản sao tạm, đặt `CLAUDE_PROJECT_DIR` về worktree kit)
- `repo_board.py --json` và `create_task.py --dry-run` tại cả 6 repo thật: OfficeReader `#2`, Goods `#3`, GeelyEx2 `#4`, Idle `#5`, Humans `#6`, agent-workbench `#1` -> đều trỏ đúng board của CWD.
- `context_sync.py` trên bản sao tạm `AGENTS.md` + config của 5 repo app -> sinh đúng `Board của repo này: ToanMobile/projects/<2..6> (<title>)` không có ghi chú kit.
- `super-board-status.py` chạy thật tại `OfficeReader` (`#2`, 21 thẻ) và `GeelyEx2` (`#4`, 21 thẻ) -> exit 0.
- `prompt_context.sh` tại `OfficeReader` với `"xem task trên board"` -> chèn `#2`; `block-dangerous-git.sh` với `gh project item-list 1 --owner ToanMobile` -> cảnh báo `#2`, exit 0.
- `pr-security-review`: 0 lỗ hổng bảo mật mức high/medium trên 14 file diff.
- Ảnh màn hình: không cần — thay đổi CLI/script/hook không có giao diện.
