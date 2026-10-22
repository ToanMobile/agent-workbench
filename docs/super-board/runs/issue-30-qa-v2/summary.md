# QA v2 — issue #30 (PR #168, fa7ef9cf)
- Lệnh: bash universal-agent-devkit/tests/verification/test_governance_cleanup_fold_intent.sh → exit 0, 6/6 kiểm tra đạt
- AC1: bản sao .claude/audit-gate thật 13312 KB → 4152 KB (du) sau `devkit_clean --days=7 --apply`; chạy lần 2 không giải phóng thêm (idempotent)
- AC2: fold chạy lặp không làm AGENTS.md lớn thêm (test đạt)
- AC3: ARCHITECTURE_REFACTOR / SECURITY / DEPRECATION_MIGRATION kích hoạt gợi ý Antigravity (test đạt)
- Đột biến: tắt cap_plan trong devkit_clean.plan → test đỏ ("1 FAILED"); khôi phục → xanh
- Nightly gọi devkit_clean.main(... --days=7 --apply) (nightly.py:180)
- Chưa đo: thư mục audit-gate thật (chỉ bản sao)
