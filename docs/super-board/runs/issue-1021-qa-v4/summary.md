# QA #1021 v4 — PR #1239

- Merge origin/main (b847ad45) vào nhánh PR, không xung đột, không trùng file.
- `test_merge_gate_unknown_and_sync_ci.sh`: exit 0 (PASS) trên head đã merge (tự chạy).
- 55 file `tests/super-board/test_merge_gate_*.sh`: 0 fail (tự chạy).
- Test cũ bị sửa: `test_merge_gate_conflicting_precheck.sh` (4 → 8 lần đọc), cần audit chéo.
