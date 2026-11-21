# Bằng chứng QA — Issue #1392 / PR #1394 (v5 · sau vá `shims/adb` & ca `4e`)

- Head Builder bàn giao: `c3810b992424dc2f74f2458921635296e98cf6b5`
- Head thêm test 4b (`4c`, `4h`, `5b`): `6548692c411d2b7d821f17baa1c755aeca050b69`
- Thời điểm: 2026-11-21 04:20 +0700

## Các lệnh test đã chạy (QA worktree)
1. `bash universal-agent-devkit/tests/verification/test_repo_board_and_context.sh` -> exit 0 (34/34 checks pass; đã kiểm ĐỎ→XANH bằng đột biến cho `4h` `shims/adb` `pwd -L` và `5b` `repo_board.py` `if origin:`)
2. `bash universal-agent-devkit/tests/gates/test_adb_shim.sh` -> exit 0 (`PASS: test_adb_shim`)
3. `bash universal-agent-devkit/tests/context_memory/test_session_context.sh` -> exit 0 (`all checks passed`)
4. `bash universal-agent-devkit/tests/context_memory/test_session_context_gc_symlink.sh` -> exit 0 (`all passed`)
5. `bash universal-agent-devkit/tests/context_memory/test_session_context_squash_branch.sh` -> exit 0 (`PASS`)
6. `bash universal-agent-devkit/tests/context_memory/test_context_sync.sh` -> exit 0 (`all checks passed`)
7. `bash universal-agent-devkit/tests/verification/test_create_task_registry.sh` -> exit 0 (`all passed`)
8. `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh` -> exit 0 (`all checks passed`)
9. `bash universal-agent-devkit/tests/installer/test_install_idempotency.sh` -> exit 0 (`all checks passed`)
10. `python3 universal-agent-devkit/scripts/governance/context_sync.py . --check` -> exit 0
11. `post-fix-gate.py --run-tests --scoped --brief --json` trên `6548692c` -> exit 2 (`super-board-qa-exit2.sh`: `review`, 10/10 suite pass, `REG-DK-ALL-KIT-01` `ptc=[9, 2]`, `tests_touched: ["universal-agent-devkit/bin/agent-kit"]`, `static: all 0`; ghi chú: lượt chạy gate đầu bị flake timeout 1500ms tại `antigravity-pm-mcp` `agy-model.test.js:286`, chạy lại đơn lẻ PASS 375/375 và chạy lại gate PASS 10/10).

## Kiểm chứng thực tế trên 6 repo (chỉ đọc / `--dry-run`, `CLAUDE_PROJECT_DIR` trỏ worktree QA)
- `repo_board.py --json` và `create_task.py --dry-run`: `agent-workbench` `#1`, `OfficeReader` `#2`, `Goods` `#3`, `GeelyEx2` `#4`, `Idle` `#5`, `Humans` `#6` -> đúng board CWD.
- `context_sync.py` trên bản sao tạm 5 repo app -> sinh đúng dòng `ToanMobile/projects/<2..6>`.
- `super-board-status.py` tại `OfficeReader` (`#2`) và `GeelyEx2` (`#4`): exit 0, hiện đúng `#2` và `#4`.
- `prompt_context.sh` (`"check board"`) và `block-dangerous-git.sh` (`gh project item-list 1`) tại `OfficeReader`: nêu đúng `#2`.
- Kiểm thử `shims/adb` với `.agents/devkit` là symlink thật (`GH_SHIM=0`, `ADB_SHIM=1`): `FORBIDDEN_SERIAL` bị chặn exit 2, `emulator-5554` chạy thật exit 0.

## Security pass & Test-gap check
- `pr-security-review`: 0 findings (đã kiểm toàn bộ diff `origin/main...HEAD`, gồm cơ chế resolve symlink trên `BASH_SOURCE[0]` của `shims/adb` và `_shim_env_add`).
- `Test-gap check`: đã siết `4c` và bổ sung `4h` (symlink `.agents/devkit`), `5b` (multi-config `origin` + `active`) với kiểm chứng ĐỎ→XANH; các gap Medium/Low không chặn được ghi vào mục `Test gaps (not written)`.
- Ảnh màn hình: không cần — thay đổi CLI/script/hook/test không có giao diện.
