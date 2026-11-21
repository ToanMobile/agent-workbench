# Bằng chứng QA — Issue #1392 / PR #1394 (v3 · rebuild R6–R7)

- Head được kiểm: `004ec20ee821288b33c5a0e305f3659995f648b7`
- Thời điểm: 2026-11-21 02:41 +0700

## Các lệnh đã chạy
1. `bash universal-agent-devkit/tests/verification/test_repo_board_and_context.sh` -> exit 0 (30/30 checks pass, gồm 3e/3f/4d/4e cho `GH_SHIM=0` và không tạo `__pycache__`)
2. `bash universal-agent-devkit/tests/context_memory/test_context_sync.sh` -> exit 0 (all checks passed)
3. `bash universal-agent-devkit/tests/verification/test_create_task_registry.sh` -> exit 0 (all passed)
4. `bash universal-agent-devkit/tests/context_memory/test_session_context.sh` -> exit 0 (all checks passed)
5. `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh` -> exit 0 (all checks passed)
6. `bash universal-agent-devkit/tests/gates/test_adb_shim.sh` -> exit 0 (PASS: test_adb_shim)
7. `bash universal-agent-devkit/tests/installer/test_install_idempotency.sh` -> exit 0 (all checks passed)
8. `python3 universal-agent-devkit/scripts/governance/context_sync.py . --check` -> exit 0 (`context_sync --check OK`)
9. `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` -> exit 2 (`super-board-qa-exit2.sh` = `review`; 9/9 suite hồi quy pass; `REG-DK-ALL-KIT-01` `ptc=[0, 8]`; `tests_touched: ["universal-agent-devkit/bin/agent-kit"]`; `static: all 0`)

## Kiểm tra thực tế trên 6 repo (chỉ đọc / `--dry-run`, đặt `CLAUDE_PROJECT_DIR` về worktree kit)
- `repo_board.py --json` và `create_task.py --dry-run` tại cả 6 repo thật (`OfficeReader #2`, `Goods #3`, `GeelyEx2 #4`, `Idle #5`, `Humans #6`, `agent-workbench #1`): đều trỏ đúng board của CWD.
- `super-board-status.py` tại `OfficeReader` (`#2`) và `GeelyEx2` (`#4`): exit 0, hiện đúng `#2` và `#4`.
- `prompt_context.sh` tại `OfficeReader` với `"check board"` -> chèn `ToanMobile/projects/2 (OfficeReader)`; `block-dangerous-git.sh` với `gh project item-list 1 --owner ToanMobile` -> cảnh báo `#2`, exit 0.

## Security pass (`pr-security-review`) — FAIL (1 finding)
- `[builder] [issue]` `universal-agent-devkit/hooks/session_context.sh:34` (`_shim_env_add`, CWE-377 / CWE-426, mức Medium, confidence 8/10, đã qua bước lọc false-positive): dùng `_iso="${TMPDIR:-/tmp}/devkit-${_name}-shim-$(id -u)-${_sum}"` với `mkdir -p` và `ln -sf` rồi đưa `$_iso` lên đầu `$PATH` trong `$CLAUDE_ENV_FILE` mà không tránh `/tmp` dùng chung và không kiểm tra `0700` / chủ sở hữu / symlink (khác với `prompt_context.sh:94-99` và `block-dangerous-git.sh:114-125`).
- Ảnh màn hình: không cần — thay đổi CLI/script/hook không có giao diện.
