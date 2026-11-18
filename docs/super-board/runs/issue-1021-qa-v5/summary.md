# QA #1021 v5 — PR #1239 @ 607aa598

- Base: origin/main đã nằm trong nhánh (merge "Already up to date").
- `test_merge_gate_unknown_and_sync_ci.sh` trên head PR: PASS, 4 ca (tự chạy).
- Cùng test trên gate của origin/main: ĐỎ ca 1, 2, 3, 4 (gate ra exit 4 thay vì 14, gọi `gh pr merge`, chỉ đọc check 1 lần) (tự chạy).
- Ca 4 (R1: MG_BASE không ghim khi UNKNOWN trong khoá) ĐỎ→XANH.
- `test_merge_gate_conflicting_precheck.sh` (test cũ bị sửa 4→8 lần đọc): PASS.
- 55 file `tests/super-board/test_merge_gate_*.sh`: 0 fail (tự chạy).
