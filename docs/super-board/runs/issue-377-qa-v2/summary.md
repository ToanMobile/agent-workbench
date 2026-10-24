# QA #377 v2 · PR #382 (rebuild-1)

Nhánh đã merge origin/main, chạy trong worktree issue-377-qa.

| Lệnh | Exit | Kết quả |
|---|---|---|
| test_gate_slot_started.sh | 0 | G1–G4 xanh (G4 = R1: nhả lease trước sc.inflight) |
| test_gate_suite_cache_selection.sh | 0 | S1–S7b xanh (S7 = R3, S7b đối chứng) |
| test_gate_suite_cache_void.sh | 0 | V1–V5 xanh |
| test_gate_slot_classes.sh | 0 | xanh |
| super-board-verify-cmd.sh --record | 0 | gate --full xanh, đã ghi biên nhận cây 8437b17f… |

RED trên mã cũ (bin/post-fix-gate.py, suite_cache.py, heavy_slot.py lấy từ origin/main, đã khôi phục):
- slot_started exit 1: G1, G2, G3, G4 ĐỎ
- cache_selection exit 1: S1, S7b ĐỎ

Chưa đo (không bịa số): AC4 (tải ≥ 60), AC5 (một ngày board sau merge), AC8 (AB/BA ≥ 5 cặp).
