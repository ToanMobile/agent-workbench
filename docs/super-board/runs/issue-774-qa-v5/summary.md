# QA #774 v5 — head a630d61d (origin/main aa0b4d33 đã là tổ tiên, merge --no-edit: Already up to date)

- test_parity_check.sh: exit 0. AC1 drift exit 0 và giữ file chỉ có ở repo (dòng 39–48). AC2 plist + status `plist:` và lần init sau bỏ qua (dòng 51–57). AC3 hooks.json, settings.json, không hook-missing, thiếu file thì exit 2 (dòng 59–70).
- test_guard_protected_push.sh: exit 0.
- test_repo_consistency.sh: exit 0, 28 passed, 0 failed.
- test_adb_shim.sh: exit 0 (PASS). Lệnh này có trong Local tests của builder sau rebase #1112.
- Ma trận: REG-DK-INIT-PARITY-SYNC-01 tại .agents/regression_matrix.active.json:4363 chạy test_parity_check.sh (AC4).
- Không có AC giao diện. Ảnh: không cần — diff là script, hook, test và tài liệu.
- Log thô nằm ngoài nhánh: /tmp/qa-agent-workbench-774-test_parity_check.log, test_guard_protected_push.log, test_repo_consistency.log, test_adb_shim.log.
