# #678 · chứng minh 3 AC trên origin/main 55e190b9

Bản sửa đã vào main qua PR #689 (8b2fc66c). PR này chỉ thêm bằng chứng cho AC còn thiếu.

## AC1 · test_gate_impacted_cache.sh exit 0 trên main
- Lệnh: `bash universal-agent-devkit/tests/gates/test_gate_impacted_cache.sh`
- Kết quả: exit 0, dòng cuối `PASS: test_gate_impacted_cache`; ca h: `✔ h. cùng nội dung: REG-A/B/E dùng lại, runner run_impacted.sh vẫn chạy`.

## AC2 · RED trước sửa, GREEN sau sửa tại ca h
- RED: bản gốc (fe57862c) đếm `0 0 0 0 0` thay vì `0 0 0 1 1`, exit 1 (ghi ở comment [builder] của thẻ).
- GREEN: ca h trên main sau #689, xem AC1.

## AC3 · REG-DK-ALL-GATES-01 PASS khi diff không đụng tests/gates
- Lệnh của rule: `DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh`
- Cây sạch: exit 0 nhưng không chọn test nào, nên KHÔNG tính là bằng chứng.
- Sửa tạm 1 dòng cuối `universal-agent-devkit/bin/post-fix-gate.py` (không commit, đã hoàn lại, cây sạch):
  `--list` chọn các test trong tests/gates; chạy thật cho 127 test `✔`, 0 `✖`, exit 0.
- Giới hạn: chạy tay lệnh của rule trên cây có file đổi, không phải gate scoped của một PR khác. Gate scoped của chính PR này chỉ có tài liệu nên không chọn rule.
