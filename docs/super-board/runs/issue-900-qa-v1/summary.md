# QA #900 v1 — PR #1111 head 60ec6609
- `python3 -m unittest discover -s tests` (mcp-servers/agent-office): exit 0, 222 tests OK, 1 skipped.
- RED trên origin/main (bản trích + test của PR): `tests.test_cc_switcher_panel` exit 1, 3 FAIL + 1 ERROR
  (test_state_needs_agent_office_header, test_non_string_values_are_400_not_dropped_connection,
  test_page_is_not_frameable, test_clients_send_header_and_phone_hides_menu_button).
- GREEN trên head PR: cùng module, 10 tests OK.
- Không có AC giao diện cần ảnh (API + HTML tĩnh, kiểm bằng test).
