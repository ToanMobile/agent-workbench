# #738 · chứng minh 3 AC trên origin/main a423305b

Hai assertion đã vào main qua PR #1085 (merge a423305b). PR này chỉ thêm bằng chứng cho các AC còn thiếu (T0054), không đổi mã hay test.

## AC1 · assertion_lint.py trên 2 file trả 0 finding
- Lệnh: `python3 universal-agent-devkit/scripts/linters/assertion_lint.py mcp-servers/agent-office/tests/test_agent_workload.py mcp-servers/play-store-mcp/tests/test_integration_credentials.py; echo $?`
- Kết quả: không in finding nào, exit `0` (trước #1085: exit 1, 2 finding).

## AC2 · mỗi test có assertion ĐỎ khi hành vi sai (đột biến, đã hoàn tác sau khi chạy)
- `test_wait_for_server_survives_slow_start`: đổi `time.sleep(0.2)` thành `break` trong `_wait_for_server` (bỏ chờ cổng mở muộn).
  - Kết quả: `1 failed` — `TimeoutError: Server on 127.0.0.1:<port> not ready after 8.0s`.
- `test_non_utf8_argv_does_not_raise`: đổi `.decode("utf-8", "replace")` thành `.decode("utf-8")` ở `agent-office/server.py:1243` (bỏ xử lý argv không UTF-8).
  - Kết quả: `ERROR: test_non_utf8_argv_does_not_raise`, `FAILED (errors=1)`.
- Sau khi hoàn tác cả hai: `git status --short` rỗng.

## AC3 · bộ test agent-office và play-store-mcp xanh
- agent-office: `python3 -m unittest discover -s tests` → `Ran 217 tests ... OK (skipped=1)`.
- play-store-mcp: `uv run --with pytest --with pytest-asyncio python -m pytest tests -q` → `884 passed, 17 skipped`.
  - `python3` mặc định của máy không có pytest nên dùng `uv run --with`.
- Gate scoped trên nhánh này: xem dòng cuối của PR (exit code ghi ở phần AC của PR).
