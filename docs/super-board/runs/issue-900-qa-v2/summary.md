# QA #900 v2 — PR #1111 head 9c674bf7 (đã gộp origin/main a1b3596a)
- `python3 -m unittest discover -s tests` (mcp-servers/agent-office): exit 0, 222 tests OK, 1 skipped.
- RED trên mã production của origin/main (test của PR): exit 1, 5 FAIL + 1 ERROR
  (test_state_needs_agent_office_header, test_non_string_values_are_400_not_dropped_connection,
  test_page_is_not_frameable, test_clients_send_header_and_phone_hides_menu_button,
  test_plist_points_cc_switcher_at_repo, test_run_from_linked_worktree_points_at_main_checkout).
- GREEN trên head PR: `tests.test_cc_switcher_panel` + `tests.test_install_autostart_cc_switcher`, 12 tests OK.
- Security pass trên diff: không có phát hiện (GET state thêm guard X-Agent-Office như POST; kiểm kiểu str trước khi tra danh sách trắng; DENY frame cho trang điều khiển).
- Không có AC giao diện cần ảnh (API + HTML tĩnh, kiểm bằng test).
