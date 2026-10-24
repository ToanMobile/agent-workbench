# QA #320 / PR #345 — v2

- Cây kiểm: nhánh issue-320-hooks-settings-gom đã merge origin/main (gồm #362).
- Lệnh: `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main`
- Exit code: 0 — hồi quy 88/88 PASS, lớp tĩnh đạt.
- Lần chạy đầu (nhánh chưa merge #362): 84/85, đỏ duy nhất là REG-SB-GITHUB-READ-FOREIGN-HALT-01 vì thiếu file test mới của main (exit 127); không do PR. Merge main rồi chạy lại: xanh.
- Test của PR nằm trong 88/88: test_runner_watchdog.sh (#143), test_guard_kill_by_name.sh (#144), test_settings_template_read_deny.sh (#139).
- #299 tách sang #352 (builder giải thích không tái hiện / nguồn bị gitignore).
- Log đầy đủ: /tmp/qa320/gate2.log (ngoài nhánh).
- Ảnh: không cần — chỉ đổi hook/settings/test.
