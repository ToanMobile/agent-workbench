# Bằng chứng QA — Issue #1392 / PR #1394 (v4 · rebuild bảo mật `_shim_env_add`)

- Head được kiểm: `d63ec98ab8bfc63ae95bca5e44488baf24bf062a`
- Thời điểm: 2026-11-21 03:24 +0700

## Các lệnh test đã chạy (QA worktree)
1. `bash universal-agent-devkit/tests/verification/test_repo_board_and_context.sh` -> exit 0 (32/32 checks pass, gồm `4f`–`4g`)
2. `bash universal-agent-devkit/tests/context_memory/test_session_context.sh` -> exit 0 (all checks passed)
3. `bash universal-agent-devkit/tests/context_memory/test_session_context_gc_symlink.sh` -> exit 0 (all passed)
4. `bash universal-agent-devkit/tests/context_memory/test_session_context_squash_branch.sh` -> exit 0 (PASS)
5. `bash universal-agent-devkit/tests/context_memory/test_context_sync.sh` -> exit 0 (all checks passed)
6. `bash universal-agent-devkit/tests/verification/test_create_task_registry.sh` -> exit 0 (all passed)
7. `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh` -> exit 0 (all checks passed)
8. `bash universal-agent-devkit/tests/gates/test_adb_shim.sh` -> exit 0 (PASS: test_adb_shim)
9. `bash universal-agent-devkit/tests/installer/test_install_idempotency.sh` -> exit 0 (all checks passed)
10. `python3 universal-agent-devkit/scripts/governance/context_sync.py . --check` -> exit 0 (`context_sync --check OK`)
11. `post-fix-gate.py --run-tests --scoped --brief --json` -> exit 2 (`super-board-qa-exit2.sh`: `review`, 9/9 suite pass, `REG-DK-ALL-KIT-01` `ptc=[0, 8]`, `tests_touched: ["universal-agent-devkit/bin/agent-kit"]`, `static: all 0`)

## Kiểm chứng thực tế trên 6 repo (chỉ đọc / `--dry-run`, đặt `CLAUDE_PROJECT_DIR` về worktree kit)
- `repo_board.py --json` và `create_task.py --dry-run`: OfficeReader `#2`, Goods `#3`, GeelyEx2 `#4`, Idle `#5`, Humans `#6`, agent-workbench `#1` -> đều trỏ đúng board của CWD.
- `context_sync.py` trên bản sao tạm 5 repo app -> sinh đúng `ToanMobile/projects/<2..6>`.
- `super-board-status.py` tại `OfficeReader` (`#2`) và `GeelyEx2` (`#4`): exit 0, hiện đúng `#2` và `#4`.
- `prompt_context.sh` tại `OfficeReader` (`"check board"`) -> `#2`; `block-dangerous-git.sh` (`gh project item-list 1`) -> cảnh báo `#2`.

## Security pass (`pr-security-review`) & Test-gap check — FAIL (1 finding giữ lại, confidence 9/10)
- `universal-agent-devkit/hooks/session_context.sh:55` + `universal-agent-devkit/shims/adb:13-15,73-76,97-100`: khi `GH_SHIM=0` và `ADB_SHIM=1`, `_shim_env_add` tạo symlink `$_iso/adb -> $_sd/adb` lên `PATH`, nhưng `shims/adb` không resolve symlink trên `BASH_SOURCE[0]` nên `root` rơi về `$_base` (`$TMPDIR`/`$HOME/.cache`) và bỏ qua hoàn toàn `<repo>/.adb-denylist` / `.adb-allowlist`. Tái hiện thực tế: `adb -s FORBIDDEN_SERIAL shell echo hi` chạy lọt `REAL_ADB_EXECUTED` (exit 0) dù `FORBIDDEN_SERIAL` nằm trong `<repo>/.adb-denylist`.
- Test gap trong `test_repo_board_and_context.sh`: `4e` gọi `enrich_context.py --compact` (không kích hoạt `board_hint()`, phải dùng `--hook`), `4d` chưa test `adb` thực thi với `.adb-denylist`.
- Ảnh màn hình: không cần — thay đổi CLI/script/hook không có giao diện.
