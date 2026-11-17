# QA #1021 v3 (PR #1239, head 42e6e87b + merge origin/main 0f15e3a1)
- test_merge_gate_unknown_and_sync_ci.sh: exit 0 (PASS); với gate của main: exit 1 (ĐỎ, 6 lỗi)
- tests/super-board/test_merge_gate_*.sh (55 file): 0 fail
- post-fix-gate --run-tests --scoped: `review` (test cũ test_merge_gate_conflicting_precheck.sh sửa 4→8 lần đọc)
