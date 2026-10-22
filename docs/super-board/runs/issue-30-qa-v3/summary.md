# QA v3 — issue #30 (rebuild-2, head 593f1124 + merge origin/main)

Lệnh: `bash universal-agent-devkit/tests/verification/test_governance_cleanup_fold_intent.sh` → exit 0, 10/10.
Đột biến: bỏ `cap_plan` → đỏ 2 ca (8220 KB; cap thiếu); bỏ `--keep-state` → đỏ 1 ca. Khôi phục → xanh 10/10.

AC1: bản sao thư mục audit-gate thật (mtime giữ nguyên) 13648 KB → 3620 KB (du) sau
`devkit_clean --days=7 --apply --keep-state`; chạy lần 2: 0 mục, không đổi.
Dữ liệu sống: mục bị xoá chỉ là lock (mtime 29/9–14/10) và 3 backup 14/10 (>7 ngày, do age pass);
backup 17–19/10, *.json, session_worktree còn nguyên. (Cap không xoá dữ liệu sống: R1/R2/R3 đạt.)
AC2/R4: fold chạy lặp, sửa nguồn, xoá dòng → không phình AGENTS.md. AC3: intent đúng tên.

Lỗi tìm thấy: `tests/lib/test_durations.txt` thiếu test mới →
`test_run_impacted_order.sh` ĐỎ ("unlisted tests start first") sau khi merge main. Đã thêm 1 dòng → XANH.
Gate --full: REG-AUTO-ANTIGRAVITY-PM-MCP-01 flaky theo tải (gate tự ghi FLAKY), không thuộc diff.
