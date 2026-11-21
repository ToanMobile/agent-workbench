# QA Summary — Issue #1401 (PR #1403)

- **Head kiểm thử:** `1c33b68048d7eeb0b786dfb98ea829d914e6c8e6` (`85729945` + merge `origin/main` `0a644f4e`)
- **Môi trường:** công cụ CLI/gate (`post-fix-gate.py`), không có UI — bỏ qua ảnh chụp màn hình.

## Kết quả chạy test
- `bash universal-agent-devkit/tests/gates/test_gate_no_tests_flaky_rerun_miss.sh` → exit `0` (27/27 mục đạt)
- `bash universal-agent-devkit/tests/gates/test_gate_run_log.sh` → exit `0` (toàn bộ đạt)
- `bash universal-agent-devkit/tests/gates/test_gate_rerun_skip.sh` → exit `0`
- `bash universal-agent-devkit/tests/gates/test_gate_rerun_skip_base.sh` → exit `0`
- `bash universal-agent-devkit/tests/gates/test_gate_rerun_skip_ttl_3d.sh` → exit `0`
- `bash universal-agent-devkit/tests/gates/test_gate_rerun_skip_unkeyed.sh` → exit `0`
- `bash universal-agent-devkit/tests/gates/test_gate_narrow_no_tests_found.sh` → exit `0`
- `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json` → exit `0` (`super-board-qa-exit2.sh` → `pass`, `4/4` suite đạt, `core-touched: universal-agent-devkit/bin/post-fix-gate.py`, lớp tĩnh 0 lỗi)

## Kiểm tra AC, Test-gap & Bảo mật
- **AC1:** Đạt — `gradle_no_tests_ran` xếp `UNTESTED` (exit 4, `no_tests_ran`) khi chạy 0 test thật; giữ `PASS` cho `UP-TO-DATE`/`FROM-CACHE` và task không chạy unit test.
- **AC2:** Đạt — `_detect_flaky_suites` ghi `flaky` vào `runs.jsonl`, báo cáo và `--json` cho cả `flaky_retry` cùng lượt lẫn 2 lượt cùng `fp`; loại trừ `infra`/`env_blocked`/kill/`exit_reason != fail`, không bị `_run_log_fit` cắt.
- **AC3:** Đạt — `_rerun_skip_miss_reason` ghi riêng vào `runs.jsonl` (`base`, `local_sha`, `force`, `pool_busy`, `unkeyed_suite`), tách khỏi `reuse_miss_reason`.
- **AC4:** Đạt — các suite gate hiện có giữ nguyên exit code và kết quả.
- **AC5:** Chờ merge và đồng bộ kit sang OfficeReader (`sb:ac` giữ chưa tick cho `ac-open`).
- **Test-gap check:** 0 High; Medium (không chặn): chưa có ca narrow (`package`/`module`) thoát 0 với `NO-SOURCE` rơi về `full_command`.
- **pr-security-review:** 0 findings (`0` lỗ hổng bảo mật mới).
