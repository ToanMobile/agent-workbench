# QA Summary — Issue #1397 (PR #1398)

- **Head kiểm thử:** `2b76c077d07f0382133aec37a2475f24c5d28813` (merged `origin/main` `cfd9197f` — already up to date)
- **Môi trường:** không có UI (`super-board-run.sh` / `super-board-github-read.py`), bỏ qua ảnh chụp màn hình.

## Kết quả chạy test
- `bash tests/super-board/test_runner_remove_assignee_no_halt_1397.sh` → exit `0` (`pass=9 fail=0`: A1, A2, A3a, A3b, B1, B2, B3, B4)
- `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` → exit `0` (`super-board-qa-exit2.sh` → `pass`, `6/6` rule đạt, lớp tĩnh 0 lỗi)
- `bash tests/super-board/test_gh_write_once_marker.sh` → exit `0` (`pass=5 fail=0`)
- `bash tests/super-board/test_card_write_fail_blocks_card.sh` → exit `0`
- `bash tests/super-board/test_github_read_reconcile.sh` → exit `0`
- `bash tests/super-board/test_github_read_auto_reconcile.sh` → exit `0`
- `bash tests/super-board/test_gh_write_retry.sh` → exit `1` (`pass=19 fail=1`, lỗi sẵn trên `origin/main` ở ca `r10`: `RC=79 attempts=3 blocked=n`; không phải hồi quy của PR #1398)

## Kiểm tra AC, Test-gap & Bảo mật
- **AC1:** Đạt — toàn bộ 13 điểm dọn `--remove-assignee` trong `super-board-run.sh` đi qua `sweep_remove_assignee` (`SB_WRITE_NO_HALT=1`), lỗi chỉ log số issue và tiếp tục, không block thẻ hay halt board.
- **AC2:** Đạt — `gh_write_once` truyền `--write-argv` sang `super-board-github-read.py --halt`, lưu `write_argv` trong `github-halt.json` tách khỏi `operation: null`, từ chối đầu vào sai dạng (exit 64).
- **AC3:** Chờ merge và đồng bộ kit sang repo con (`sb:ac` giữ chưa tick cho `ac-open`).
- **Test-gap check:** 0 High; Medium (không chặn): chưa có ca `write_argv` chứa khoảng trắng/xuống dòng hoặc `BOT_LOGIN` rỗng.
- **pr-security-review:** 0 findings (`0` lỗ hổng bảo mật mới).
